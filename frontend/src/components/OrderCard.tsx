"use client"

import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi"
import { encodeFunctionData } from "viem"
import { orderManagerAbi, smartWalletAbi, ORDER_MANAGER_ADDRESS, ORDER_TYPE_LABELS, ORDER_STATUS_LABELS, ORDER_STATUS_COLORS } from "@/lib/contracts"
import type { OnchainOrder } from "@/lib/contracts"

function formatUsdc(val: bigint) {
  return (Number(val) / 1e6).toFixed(2)
}

function formatDate(ts: bigint) {
  if (ts === BigInt(0)) return "—"
  return new Date(Number(ts) * 1000).toLocaleString()
}

export function OrderCard({ orderId, walletAddress, onCancelled }: {
  orderId: bigint
  walletAddress: `0x${string}`
  onCancelled: () => void
}) {
  // get user active and cancelled orders
  const { data: order, isLoading } = useReadContract({
    address: ORDER_MANAGER_ADDRESS,
    abi: orderManagerAbi,
    functionName: "getOrder",
    args: [orderId],
  })

  const { writeContract, data: txHash, isPending } = useWriteContract()

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash })

  if (isSuccess) onCancelled()

  if (isLoading || !order) {
    return (
      <div className="bg-white/[0.03] border border-white/[0.07] rounded-2xl p-5 animate-pulse h-36" />
    )
  }

  const o = order as unknown as OnchainOrder
  const statusLabel = ORDER_STATUS_LABELS[o.status] ?? "Unknown"
  const statusColor = ORDER_STATUS_COLORS[o.status] ?? "text-gray-400"
  const typeLabel = ORDER_TYPE_LABELS[o.orderType] ?? "Unknown"
  const isActive = o.status === 0
  const isDca = o.orderType === 0

  function cancel() {
    const data = encodeFunctionData({
      abi: orderManagerAbi,
      functionName: "cancelOrder",
      args: [o.id],
    })
    writeContract({
      address: walletAddress,
      abi: smartWalletAbi,
      functionName: "execute",
      args: [ORDER_MANAGER_ADDRESS, BigInt(0), data],
    })
  }

  return (
    <div className="bg-white/[0.03] border border-white/[0.07] hover:border-white/[0.14] rounded-2xl p-5 transition-all">
      <div className="flex items-start justify-between mb-4">
        <div className="flex items-center gap-2">
          <span className="text-xs font-medium bg-white/[0.07] px-2 py-0.5 rounded-full">{typeLabel}</span>
          <span className="text-xs text-gray-500">#{o.id.toString()}</span>
        </div>
        <span className={`text-xs font-medium ${statusColor}`}>{statusLabel}</span>
      </div>

      <div className="grid grid-cols-2 gap-3 text-sm mb-4">
        {isDca ? (
          <>
            <div>
              <p className="text-xs text-gray-500 mb-0.5">Per execution</p>
              <p className="font-medium">{formatUsdc(o.amountPerExecution)} USDC</p>
            </div>
            <div>
              <p className="text-xs text-gray-500 mb-0.5">Executions left</p>
              <p className="font-medium">{o.executionsLeft.toString()}</p>
            </div>
            <div className="col-span-2">
              <p className="text-xs text-gray-500 mb-0.5">Next execution</p>
              <p className="font-medium">{formatDate(o.nextExecutionTime)}</p>
            </div>
          </>
        ) : (
          <>
            <div>
              <p className="text-xs text-gray-500 mb-0.5">Amount in</p>
              <p className="font-medium">{formatUsdc(o.amountIn)} USDC</p>
            </div>
            <div>
              <p className="text-xs text-gray-500 mb-0.5">Target price</p>
              <p className="font-medium">${(Number(o.targetPrice) / 1e8).toFixed(0)}</p>
            </div>
          </>
        )}
      </div>

      {isActive && (
        <button
          onClick={cancel}
          disabled={isPending || isConfirming}
          className="w-full hover:cursor-pointer text-sm text-red-400 hover:text-red-300 border border-red-900/40 hover:border-red-800 py-2 rounded-xl transition-colors disabled:opacity-50"
        >
          {isPending || isConfirming ? "Cancelling…" : "Cancel Order"}
        </button>
      )}
    </div>
  )
}
