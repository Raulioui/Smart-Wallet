// ─── Deployed addresses (Base Sepolia) ───────────────────────────────────────

export const FACTORY_ADDRESS       = "0xE097784c26fCf1b3A5D737DF5ef48dcBae325939" as const
export const ORDER_MANAGER_ADDRESS = "0x1e29B2021541Fafd759C781508868FD5dc97a3f6" as const
export const EXECUTOR_KEY          = "0xD5B95747CcCEa0E0115623e05d8067a666cfF9c8" as const

export const USDC_ADDRESS = "0x036CbD53842c5426634e7929541eC2318f3dCF7e" as const
export const WETH_ADDRESS = "0x4200000000000000000000000000000000000006" as const
export const ETH_USD_FEED = "0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1" as const

// ─── ABIs ────────────────────────────────────────────────────────────────────

export const factoryAbi = [
  {
    name: "createWallet",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "owner", type: "address" },
      { name: "salt", type: "uint256" },
    ],
    outputs: [{ name: "", type: "address" }],
  },
  {
    name: "getAddress",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "salt", type: "uint256" },
    ],
    outputs: [{ name: "", type: "address" }],
  },
] as const

export const smartWalletAbi = [
  {
    name: "owner",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
  {
    name: "execute",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "dest", type: "address" },
      { name: "value", type: "uint256" },
      { name: "functionData", type: "bytes" },
    ],
    outputs: [],
  },
  {
    name: "addSessionKey",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "key", type: "address" },
      {
        name: "data",
        type: "tuple",
        components: [
          { name: "isActive", type: "bool" },
          { name: "validUntil", type: "uint48" },
          { name: "maxAmountPerTx", type: "uint256" },
          { name: "dailyLimit", type: "uint256" },
        ],
      },
    ],
    outputs: [],
  },
  {
    name: "getSessionKey",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "key", type: "address" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "isActive", type: "bool" },
          { name: "validUntil", type: "uint48" },
          { name: "maxAmountPerTx", type: "uint256" },
          { name: "dailyLimit", type: "uint256" },
        ],
      },
    ],
  },
] as const

export const orderManagerAbi = [
  {
    name: "createDCAOrder",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "tokenIn", type: "address" },
      { name: "tokenOut", type: "address" },
      { name: "amountPerExecution", type: "uint256" },
      { name: "intervalSeconds", type: "uint256" },
      { name: "executions", type: "uint256" },
      { name: "validUntil", type: "uint256" },
    ],
    outputs: [{ name: "orderId", type: "uint256" }],
  },
  {
    name: "createLimitBuyOrder",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "tokenIn", type: "address" },
      { name: "tokenOut", type: "address" },
      { name: "amountIn", type: "uint256" },
      { name: "minAmountOut", type: "uint256" },
      { name: "targetPrice", type: "uint256" },
      { name: "priceFeed", type: "address" },
      { name: "validUntil", type: "uint256" },
    ],
    outputs: [{ name: "orderId", type: "uint256" }],
  },
  {
    name: "createLimitSellOrder",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "tokenIn", type: "address" },
      { name: "tokenOut", type: "address" },
      { name: "amountIn", type: "uint256" },
      { name: "minAmountOut", type: "uint256" },
      { name: "targetPrice", type: "uint256" },
      { name: "priceFeed", type: "address" },
      { name: "validUntil", type: "uint256" },
    ],
    outputs: [{ name: "orderId", type: "uint256" }],
  },
  {
    name: "createStopLossOrder",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "tokenIn", type: "address" },
      { name: "tokenOut", type: "address" },
      { name: "amountIn", type: "uint256" },
      { name: "minAmountOut", type: "uint256" },
      { name: "targetPrice", type: "uint256" },
      { name: "priceFeed", type: "address" },
      { name: "validUntil", type: "uint256" },
    ],
    outputs: [{ name: "orderId", type: "uint256" }],
  },
  {
    name: "cancelOrder",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "orderId", type: "uint256" }],
    outputs: [],
  },
  {
    name: "getOrder",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "orderId", type: "uint256" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "id", type: "uint256" },
          { name: "wallet", type: "address" },
          { name: "orderType", type: "uint8" },
          { name: "status", type: "uint8" },
          { name: "tokenIn", type: "address" },
          { name: "tokenOut", type: "address" },
          { name: "amountPerExecution", type: "uint256" },
          { name: "intervalSeconds", type: "uint256" },
          { name: "nextExecutionTime", type: "uint256" },
          { name: "executionsLeft", type: "uint256" },
          { name: "amountIn", type: "uint256" },
          { name: "minAmountOut", type: "uint256" },
          { name: "targetPrice", type: "uint256" },
          { name: "priceFeed", type: "address" },
          { name: "validUntil", type: "uint256" },
          { name: "createdAt", type: "uint256" },
        ],
      },
    ],
  },
  {
    name: "getActiveOrderIds",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256[]" }],
  },
  {
    name: "getUserOrders",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "wallet", type: "address" }],
    outputs: [{ name: "", type: "uint256[]" }],
  },
] as const

export const erc20Abi = [
  {
    name: "balanceOf",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "decimals",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    name: "symbol",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "string" }],
  },
] as const

// ─── Types ────────────────────────────────────────────────────────────────────

export const ORDER_TYPE_LABELS = ["DCA", "Limit Buy", "Limit Sell", "Stop Loss"] as const
export const ORDER_STATUS_LABELS = ["Active", "Completed", "Cancelled", "Expired"] as const
export const ORDER_STATUS_COLORS = ["text-green-400", "text-white", "text-gray-400", "text-red-400"] as const

export type OnchainOrder = {
  id: bigint
  wallet: `0x${string}`
  orderType: number
  status: number
  tokenIn: `0x${string}`
  tokenOut: `0x${string}`
  amountPerExecution: bigint
  intervalSeconds: bigint
  nextExecutionTime: bigint
  executionsLeft: bigint
  amountIn: bigint
  minAmountOut: bigint
  targetPrice: bigint
  priceFeed: `0x${string}`
  validUntil: bigint
  createdAt: bigint
}
