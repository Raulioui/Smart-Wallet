import { getActiveOrders } from "./poller.js"
import { isReadyToExecute, executeOrder } from "./executor.js"
import { sessionKeyAccount } from "./config.js"

const POLL_INTERVAL_MS = 60_000 // 1 minute

async function runOnce(): Promise<void> {
  console.log(`\n[${new Date().toISOString()}] polling...`)

  let orders
  try {
    orders = await getActiveOrders()
  } catch (err) {
    console.error("failed to fetch orders:", err)
    return
  }

  if (orders.length === 0) {
    console.log("no active orders")
    return
  }

  console.log(`${orders.length} active order(s)`)

  for (const order of orders) {
    const typeLabel = ["DCA", "LIMIT_BUY", "LIMIT_SELL", "STOP_LOSS"][order.orderType]
    console.log(`order ${order.id} (${typeLabel}) wallet=${order.wallet}`)

    try {
      const ready = await isReadyToExecute(order)
      if (!ready) continue

      console.log(`  executing...`)
      const txHash = await executeOrder(order)
      console.log(`  done: ${txHash}`)
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      console.error(`  failed: ${msg}`)
    }
  }
}

async function main(): Promise<void> {
  console.log("smart wallet executor")
  console.log(`session key: ${sessionKeyAccount.address}`)
  console.log(`poll interval: ${POLL_INTERVAL_MS / 1000}s`)

  while (true) {
    await runOnce()
    await new Promise<void>((resolve) => setTimeout(resolve, POLL_INTERVAL_MS))
  }
}

main().catch((err) => {
  console.error("fatal:", err)
  process.exit(1)
})
