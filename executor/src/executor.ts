import { getUserOperationHash, waitForUserOperationReceipt } from "viem/account-abstraction"
import { numberToHex } from "viem"
import { baseSepolia } from "viem/chains"
import type { UserOperation } from "viem/account-abstraction"
import {
  publicClient,
  pimlicoClient,
  bundlerClient,
  sessionKeyAccount,
  ENTRY_POINT,
} from "./config.js"
import { chainlinkAbi, entryPointAbi, OrderType, type Order } from "./contracts.js"
import { buildExecuteBatchCalldata } from "./builder.js"
import { getFeeConfig } from "./poller.js"

const STALE_THRESHOLD_SECS = 3600n

// Structurally valid 65-byte ECDSA signature used only for gas estimation.
// validateUserOp returns SIG_VALIDATION_FAILED for unknown signers, which
// Pimlico's simulation phase tolerates — it only needs gas measurements.
const DUMMY_SIG =
  "0xfffffffffffffffffffffffffffffff0000000000000000000000000000000007aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1c" as `0x${string}`

// ─── Conditions ──────────────────────────────────────────────────────────────

// Returns true if the order should be executed right now.
// Mirrors the on-chain checks in recordExecution to avoid wasting gas on ops
// that would revert.
export async function isReadyToExecute(order: Order): Promise<boolean> {
  const now = BigInt(Math.floor(Date.now() / 1000))

  if (order.validUntil !== 0n && now > order.validUntil) {
    console.log(`  [${order.id}] skip: expired`)
    return false
  }

  if (order.orderType === OrderType.DCA) {
    if (now < order.nextExecutionTime) {
      const wait = order.nextExecutionTime - now
      console.log(`  [${order.id}] DCA: next in ${formatSeconds(wait)}`)
      return false
    }
    return true
  }

  return checkPriceCondition(order, now)
}

async function checkPriceCondition(order: Order, now: bigint): Promise<boolean> {
  const [, answer, , updatedAt] = await publicClient.readContract({
    address: order.priceFeed,
    abi: chainlinkAbi,
    functionName: "latestRoundData",
  })

  if (now - updatedAt > STALE_THRESHOLD_SECS) {
    console.log(`  [${order.id}] skip: stale price feed (last updated ${now - updatedAt}s ago)`)
    return false
  }

  const currentPrice = answer < 0n ? 0n : answer

  if (order.orderType === OrderType.LIMIT_BUY || order.orderType === OrderType.STOP_LOSS) {
    const ready = currentPrice <= order.targetPrice
    if (!ready) console.log(`  [${order.id}] skip: price ${currentPrice} > target ${order.targetPrice}`)
    return ready
  }

  // LIMIT_SELL: execute when price >= target
  const ready = currentPrice >= order.targetPrice
  if (!ready) console.log(`  [${order.id}] skip: price ${currentPrice} < target ${order.targetPrice}`)
  return ready
}

function formatSeconds(secs: bigint): string {
  if (secs < 60n) return `${secs}s`
  if (secs < 3600n) return `${secs / 60n}m`
  if (secs < 86400n) return `${secs / 3600n}h`
  return `${secs / 86400n}d`
}

// ─── Execution ───────────────────────────────────────────────────────────────

export async function executeOrder(order: Order): Promise<`0x${string}`> {
  const fee = await getFeeConfig()
  const callData = buildExecuteBatchCalldata(order, 0n, fee)

  const [nonce, fees] = await Promise.all([
    publicClient.readContract({
      address: ENTRY_POINT,
      abi: entryPointAbi,
      functionName: "getNonce",
      args: [order.wallet, 0n],
    }),
    publicClient.estimateFeesPerGas(),
  ])


  // The viem return type is a discriminated union (EIP-1559 | legacy) so we assert.
  const maxFeePerGas = fees.maxFeePerGas as bigint
  const maxPriorityFeePerGas = (fees.maxPriorityFeePerGas ?? fees.maxFeePerGas) as bigint

  // Step 1: Pimlico sponsorsand fills gas limits and paymaster fields.

  const sponsored = await pimlicoClient.sponsorUserOperation({
    userOperation: {
      sender: order.wallet,
      nonce,
      callData,
      maxFeePerGas,
      maxPriorityFeePerGas,
      signature: DUMMY_SIG,
    },
  })

  // Step 2: Compute the UserOp hash and sign with the session key.

  const userOperation = {
    sender: order.wallet,
    nonce,
    callData,
    maxFeePerGas,
    maxPriorityFeePerGas,
    ...sponsored,
    signature: DUMMY_SIG,
  } as UserOperation<"0.7">

  const userOpHash = getUserOperationHash({
    userOperation,
    entryPointAddress: ENTRY_POINT,
    entryPointVersion: "0.7",
    chainId: baseSepolia.id,
  })

  const signature = await sessionKeyAccount.signMessage({
    message: { raw: userOpHash },
  })

  // Step 3: Submit via raw RPC.

  const bundlerHash = await sendRpc(bundlerClient, "eth_sendUserOperation", [
    toWireUserOp({ ...userOperation, signature }),
    ENTRY_POINT,
  ])

  console.log(`  submitted: ${bundlerHash}`)

  // Step 4: Wait for inclusion in a block.
  const receipt = await waitForUserOperationReceipt(bundlerClient, {
    hash: bundlerHash as `0x${string}`,
    timeout: 60_000,
  })

  if (!receipt.success) {
    throw new Error(`UserOp reverted (tx: ${receipt.receipt.transactionHash})`)
  }

  return receipt.receipt.transactionHash
}

// Calls an arbitrary RPC method via a viem client's transport.

async function sendRpc(client: any, method: string, params: unknown[]): Promise<string> {
  return client.request({ method, params })
}

// Converts UserOperation<"0.7"> bigint fields to hex strings for the JSON-RPC wire format.
function toWireUserOp(op: UserOperation<"0.7">): Record<string, unknown> {
  return {
    sender: op.sender,
    nonce: numberToHex(op.nonce),
    ...(op.factory && { factory: op.factory }),
    ...(op.factoryData && { factoryData: op.factoryData }),
    callData: op.callData,
    callGasLimit: numberToHex(op.callGasLimit),
    verificationGasLimit: numberToHex(op.verificationGasLimit),
    preVerificationGas: numberToHex(op.preVerificationGas),
    maxFeePerGas: numberToHex(op.maxFeePerGas),
    maxPriorityFeePerGas: numberToHex(op.maxPriorityFeePerGas),
    ...(op.paymaster && { paymaster: op.paymaster }),
    ...(op.paymasterVerificationGasLimit && {
      paymasterVerificationGasLimit: numberToHex(op.paymasterVerificationGasLimit),
    }),
    ...(op.paymasterPostOpGasLimit && {
      paymasterPostOpGasLimit: numberToHex(op.paymasterPostOpGasLimit),
    }),
    ...(op.paymasterData && { paymasterData: op.paymasterData }),
    signature: op.signature,
  }
}
