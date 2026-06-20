export const orderManagerAbi = [
  {
    name: "getActiveOrderIds",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256[]" }],
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
    name: "recordExecution",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "orderId", type: "uint256" },
      { name: "amountIn", type: "uint256" },
      { name: "amountOut", type: "uint256" },
    ],
    outputs: [],
  },
  {
    name: "getFeeConfig",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { name: "feeCollector", type: "address" },
      { name: "feeBps", type: "uint256" },
    ],
  },
] as const

export const smartWalletAbi = [
  {
    name: "executeBatch",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "dests", type: "address[]" },
      { name: "values", type: "uint256[]" },
      { name: "functionDatas", type: "bytes[]" },
    ],
    outputs: [],
  },
] as const

export const erc20Abi = [
  {
    name: "approve",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "transfer",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "balanceOf",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const

export const swapRouterAbi = [
  {
    name: "exactInputSingle",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "params",
        type: "tuple",
        components: [
          { name: "tokenIn", type: "address" },
          { name: "tokenOut", type: "address" },
          { name: "fee", type: "uint24" },
          { name: "recipient", type: "address" },
          { name: "amountIn", type: "uint256" },
          { name: "amountOutMinimum", type: "uint256" },
          { name: "sqrtPriceLimitX96", type: "uint160" },
        ],
      },
    ],
    outputs: [{ name: "amountOut", type: "uint256" }],
  },
] as const

export const chainlinkAbi = [
  {
    name: "latestRoundData",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { name: "roundId", type: "uint80" },
      { name: "answer", type: "int256" },
      { name: "startedAt", type: "uint256" },
      { name: "updatedAt", type: "uint256" },
      { name: "answeredInRound", type: "uint80" },
    ],
  },
] as const

export const entryPointAbi = [
  {
    name: "getNonce",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "sender", type: "address" },
      { name: "key", type: "uint192" },
    ],
    outputs: [{ name: "nonce", type: "uint256" }],
  },
] as const

// ─── Types ───────────────────────────────────────────────────────────────────

export const OrderType = {
  DCA: 0,
  LIMIT_BUY: 1,
  LIMIT_SELL: 2,
  STOP_LOSS: 3,
} as const

export const OrderStatus = {
  ACTIVE: 0,
  COMPLETED: 1,
  CANCELLED: 2,
  EXPIRED: 3,
} as const

export type OrderTypeValue = (typeof OrderType)[keyof typeof OrderType]
export type OrderStatusValue = (typeof OrderStatus)[keyof typeof OrderStatus]

export interface Order {
  id: bigint
  wallet: `0x${string}`
  orderType: OrderTypeValue
  status: OrderStatusValue
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
  validUntil: bigint         // 0 = no expiry
  createdAt: bigint
}

export interface FeeConfig {
  collector: `0x${string}`
  bps: bigint
}
