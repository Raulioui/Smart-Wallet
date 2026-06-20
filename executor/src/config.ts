import { createPublicClient, http } from "viem"
import { createBundlerClient } from "viem/account-abstraction"
import { privateKeyToAccount } from "viem/accounts"
import { baseSepolia } from "viem/chains"
import { createPimlicoClient } from "permissionless/clients/pimlico"
import "dotenv/config"

function requireEnv(key: string): string {
  const val = process.env[key]
  if (!val) throw new Error(`Missing env var: ${key}`)
  return val
}

// Contract addresses 
export const ENTRY_POINT = "0x0000000071727De22E5E9d8BAf0edAc6f37da032" as const
export const ORDER_MANAGER = requireEnv("ORDER_MANAGER") as `0x${string}`

// Uniswap V3 SwapRouter02 on Base Sepolia.
export const SWAP_ROUTER = "0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4" as const

// Fee tier for the swap pool (500 = 0.05%, 3000 = 0.3%, 10000 = 1%)
export const UNISWAP_POOL_FEE = 500

const PIMLICO_API_KEY = requireEnv("PIMLICO_API_KEY")
const PIMLICO_URL = `https://api.pimlico.io/v2/base-sepolia/rpc?apikey=${PIMLICO_API_KEY}`
const RPC_URL = process.env.RPC_URL ?? "https://sepolia.base.org"

export const sessionKeyAccount = privateKeyToAccount(
  requireEnv("PRIVATE_KEY") as `0x${string}`
)

export const publicClient = createPublicClient({
  chain: baseSepolia,
  transport: http(RPC_URL),
})

// Used to sponsor UserOps 
export const pimlicoClient = createPimlicoClient({
  chain: baseSepolia,
  transport: http(PIMLICO_URL),
  entryPoint: {
    address: ENTRY_POINT,
    version: "0.7",
  },
})

// Used to submit and wait for UserOps (viem/account-abstraction bundler client)
export const bundlerClient = createBundlerClient({
  chain: baseSepolia,
  transport: http(PIMLICO_URL),
})
