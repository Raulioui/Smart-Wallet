import { encodeFunctionData } from "viem"
import { smartWalletAbi, erc20Abi, swapRouterAbi, orderManagerAbi } from "./contracts.js"
import { OrderType, type Order, type FeeConfig } from "./contracts.js"
import { ORDER_MANAGER, SWAP_ROUTER, UNISWAP_POOL_FEE } from "./config.js"

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as const

// Returns the encoded calldata for SmartWallet.executeBatch.
// The batch is: approve → swap → (fee transfer) → recordExecution


export function buildExecuteBatchCalldata(
  order: Order,
  estimatedAmountOut: bigint,
  fee: FeeConfig
): `0x${string}` {
  const amountIn =
    order.orderType === OrderType.DCA ? order.amountPerExecution : order.amountIn

  const minAmountOut =
    order.orderType === OrderType.DCA
      ? 0n 
      : order.minAmountOut

  const dests: `0x${string}`[] = []
  const values: bigint[] = []
  const datas: `0x${string}`[] = []

  // 1. Approve SwapRouter to pull tokenIn from the wallet
  dests.push(order.tokenIn)
  values.push(0n)
  datas.push(
    encodeFunctionData({
      abi: erc20Abi,
      functionName: "approve",
      args: [SWAP_ROUTER, amountIn],
    })
  )

  // 2. Swap tokenIn → tokenOut via Uniswap V3 exactInputSingle
  dests.push(SWAP_ROUTER)
  values.push(0n)
  datas.push(
    encodeFunctionData({
      abi: swapRouterAbi,
      functionName: "exactInputSingle",
      args: [
        {
          tokenIn: order.tokenIn,
          tokenOut: order.tokenOut,
          fee: UNISWAP_POOL_FEE,
          recipient: order.wallet,
          amountIn,
          amountOutMinimum: minAmountOut,
          sqrtPriceLimitX96: 0n,
        },
      ],
    })
  )

  // 3. Optional fee transfer (tokenOut → feeCollector)
  if (fee.bps > 0n && fee.collector !== ZERO_ADDRESS) {
    const feeAmount = (estimatedAmountOut * fee.bps) / 10_000n
    if (feeAmount > 0n) {
      dests.push(order.tokenOut)
      values.push(0n)
      datas.push(
        encodeFunctionData({
          abi: erc20Abi,
          functionName: "transfer",
          args: [fee.collector, feeAmount],
        })
      )
    }
  }

  // 4. recordExecution — validates timing/price and updates order state on-chain.
  //    Must be last: if it reverts, the whole batch (including the swap) is rolled back.
  dests.push(ORDER_MANAGER)
  values.push(0n)
  datas.push(
    encodeFunctionData({
      abi: orderManagerAbi,
      functionName: "recordExecution",
      args: [order.id, amountIn, estimatedAmountOut],
    })
  )

  return encodeFunctionData({
    abi: smartWalletAbi,
    functionName: "executeBatch",
    args: [dests, values, datas],
  })
}
