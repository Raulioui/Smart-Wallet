"use client"

import { useState } from "react"
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi"
import { useSmartWallet } from "@/hooks/useSmartWallet"
import { useWallet } from "@/hooks/useWallet"
import { factoryAbi, FACTORY_ADDRESS } from "@/lib/contracts"
import { OrderCard } from "@/components/OrderCard"
import { CreateOrderForm } from "@/components/CreateOrderForm"

type View = "orders" | "new"

function formatUsdc(val: bigint) {
  return (Number(val) / 1e6).toFixed(2)
}

function shortAddr(addr: string) {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`
}

export default function Dashboard() {
  const { isConnected } = useWallet()
  const { eoa, walletAddress, isDeployed, isLoading, usdcBalance, orderIds, refetchOrders } = useSmartWallet()
  const [view, setView] = useState<View>("orders")

  const { writeContract, data: deployTxHash, isPending: isDeploying } = useWriteContract()
  const { isLoading: isDeployConfirming } = useWaitForTransactionReceipt({ hash: deployTxHash })

  function deployWallet() {
    if (!eoa) return
    writeContract({
      address: FACTORY_ADDRESS,
      abi: factoryAbi,
      functionName: "createWallet",
      args: [eoa, BigInt(0)],
    })
  }

  if (!isConnected) {
    return (
      <div className="max-w-6xl mx-auto px-4 py-20 text-center">
        <p className="text-gray-500">Connect your wallet to view the dashboard.</p>
      </div>
    )
  }

  if (isLoading) {
    return (
      <div className="max-w-6xl mx-auto px-4 py-20 text-center">
        <p className="text-gray-600 animate-pulse">Loading…</p>
      </div>
    )
  }

  return (
    <div className="max-w-6xl mx-auto px-4 py-10">

      <div className="flex items-start justify-between gap-4 mb-10">
        <div>
          <h1 className="text-2xl font-bold mb-1">Dashboard</h1>
          <p className="text-sm text-gray-600">
            {isDeployed
              ? "Manage your automated DeFi orders."
              : "Deploy your Smart Wallet to start automating."}
          </p>
        </div>

        {isDeployed && (
          <div className="flex items-center gap-2">
            <button
              onClick={() => setView("orders")}
              className={`text-sm hover:cursor-pointer px-4 py-2 rounded-xl border transition-colors ${
                view === "orders"
                  ? "bg-white text-black border-white font-medium"
                  : "border-gray-800 text-gray-500 hover:text-white hover:border-gray-600"
              }`}
            >
              Orders
            </button>
            <button
              onClick={() => setView("new")}
              className={`text-sm hover:cursor-pointer px-4 py-2 rounded-xl border transition-colors ${
                view === "new"
                  ? "bg-white text-black border-white font-medium"
                  : "border-gray-800 text-gray-500 hover:text-white hover:border-gray-600"
              }`}
            >
              + New Order
            </button>
          </div>
        )}
      </div>

      <div className="bg-white/[0.03] border border-white/[0.07] rounded-2xl px-6 py-4 mb-8 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <span className={`w-2 h-2 rounded-full ${isDeployed ? "bg-green-400" : "bg-gray-600"}`} />
          <div>
            <p className="text-xs text-gray-500 mb-0.5">Smart Wallet</p>
            <p className="font-mono text-xs text-gray-300">
              {walletAddress ? shortAddr(walletAddress) : "—"}
            </p>
          </div>
        </div>

        {isDeployed ? (
          <div className="text-right">
            <p className="text-xs text-gray-500 mb-0.5">USDC Balance</p>
            <p className="text-xl font-bold">{formatUsdc(usdcBalance)} <span className="text-sm text-gray-500 font-normal">USDC</span></p>
          </div>
        ) : (
          <button
            onClick={deployWallet}
            disabled={isDeploying || isDeployConfirming}
            className="bg-white hover:cursor-pointer hover:bg-gray-100 disabled:opacity-50 text-black text-sm font-medium px-5 py-2.5 rounded-xl transition-colors"
          >
            {isDeploying || isDeployConfirming ? "Deploying…" : "Deploy Smart Wallet"}
          </button>
        )}
      </div>

      {isDeployed && usdcBalance === BigInt(0) && view === "orders" && (
        <div className="bg-white/[0.02] border border-white/[0.07] rounded-2xl p-5 mb-6 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
          <div>
            <p className="text-sm font-medium mb-1">Deposit USDC to get started</p>
            <p className="text-xs text-gray-500 leading-relaxed">
              Send USDC to your Smart Wallet address below. Orders will spend from this balance automatically.
            </p>
          </div>
          <button
            onClick={() => { if (walletAddress) navigator.clipboard.writeText(walletAddress) }}
            className="shrink-0 hover:cursor-pointer flex items-center gap-2 bg-white/[0.04] hover:bg-white/[0.07] border border-white/10 hover:border-white/20 text-xs text-gray-400 hover:text-white px-4 py-2.5 rounded-xl transition-all font-mono"
          >
            <span>{walletAddress ? `${walletAddress.slice(0, 10)}…${walletAddress.slice(-8)}` : "—"}</span>
            <span className="text-gray-600">⎘</span>
          </button>
        </div>
      )}

      {isDeployed && (
        <>
          {view === "new" ? (
            <div>
              <button
                onClick={() => setView("orders")}
                className="text-xs hover:cursor-pointer text-gray-600 hover:text-gray-400 mb-6 flex items-center gap-1 transition-colors"
              >
                ← Back to orders
              </button>
              <CreateOrderForm onSuccess={() => { refetchOrders(); setView("orders") }} />
            </div>
          ) : (
            <>
              {orderIds.length === 0 ? (
                <div className="text-center py-20 border border-white/[0.06] border-dashed rounded-2xl">
                  <p className="text-gray-600 mb-1">No orders yet</p>
                  <p className="text-xs text-gray-700 mb-6">Create your first order to start automating your DeFi strategy.</p>
                  <button
                    onClick={() => setView("new")}
                    className="bg-white hover:cursor-pointer hover:bg-gray-100 text-black text-sm font-medium px-6 py-2.5 rounded-xl transition-colors"
                  >
                    Create first order
                  </button>
                </div>
              ) : (
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                  {orderIds.map((id) => (
                    <OrderCard
                      key={id.toString()}
                      orderId={id}
                      walletAddress={walletAddress!}
                      onCancelled={refetchOrders}
                    />
                  ))}
                </div>
              )}
            </>
          )}
        </>
      )}
    </div>
  )
}
