import { publicClient, ORDER_MANAGER } from "./config.js"
import { orderManagerAbi } from "./contracts.js"
import type { Order, FeeConfig } from "./contracts.js"

/// Returns active orders and the fee of the OrderManager.
export async function getActiveOrders(): Promise<Order[]> {
  const activeIds = await publicClient.readContract({
    address: ORDER_MANAGER,
    abi: orderManagerAbi,
    functionName: "getActiveOrderIds",
  })

  if (activeIds.length === 0) return []

  const orders = await Promise.all(
    activeIds.map((id) =>
      publicClient.readContract({
        address: ORDER_MANAGER,
        abi: orderManagerAbi,
        functionName: "getOrder",
        args: [id],
      })
    )
  )

  return orders as unknown as Order[]
}

export async function getFeeConfig(): Promise<FeeConfig> {
  const [collector, bps] = await publicClient.readContract({
    address: ORDER_MANAGER,
    abi: orderManagerAbi,
    functionName: "getFeeConfig",
  })
  return { collector, bps }
}
