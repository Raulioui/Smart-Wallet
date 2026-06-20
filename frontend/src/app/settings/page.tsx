"use client"

import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi"
import { useSmartWallet } from "@/hooks/useSmartWallet"
import { useWallet } from "@/hooks/useWallet"
import { smartWalletAbi, EXECUTOR_KEY } from "@/lib/contracts"

function formatDate(ts: bigint) {
  return new Date(Number(ts) * 1000).toLocaleDateString()
}

function formatUsdc(val: bigint) {
  return (Number(val) / 1e6).toLocaleString()
}

export default function Settings() {
  const { isConnected } = useWallet()
  const { walletAddress, isDeployed, isLoading } = useSmartWallet()

  const { data: sessionKey, refetch: refetchKey } = useReadContract({
    address: walletAddress,
    abi: smartWalletAbi,
    functionName: "getSessionKey",
    args: [EXECUTOR_KEY],
    query: { enabled: !!walletAddress && isDeployed },
  })

  const { writeContract, data: txHash, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash })

  if (isSuccess) refetchKey()

  function addSessionKey() {
    if (!walletAddress) return
    const oneYear = BigInt(Math.floor(Date.now() / 1000) + 365 * 24 * 3600)
    writeContract({
      address: walletAddress,
      abi: smartWalletAbi,
      functionName: "addSessionKey",
      args: [
        EXECUTOR_KEY,
        {
          isActive: true,
          validUntil: Number(oneYear),
          maxAmountPerTx: BigInt(1000e6),
          dailyLimit: BigInt(5000e6),
        },
      ],
    })
  }

  if (!isConnected) {
    return (
      <div className="max-w-3xl mx-auto px-4 py-20 text-center">
        <p className="text-gray-400">Connect your wallet to view settings.</p>
      </div>
    )
  }

  if (isLoading) {
    return (
      <div className="max-w-3xl mx-auto px-4 py-20 text-center">
        <p className="text-gray-500 animate-pulse">Loading…</p>
      </div>
    )
  }

  const isActive = sessionKey?.isActive === true
  const validUntil = sessionKey?.validUntil ? BigInt(sessionKey.validUntil) : BigInt(0)
  const maxAmountPerTx = sessionKey?.maxAmountPerTx ?? BigInt(0)
  const dailyLimit = sessionKey?.dailyLimit ?? BigInt(0)

  return (
    <div className="max-w-3xl mx-auto px-4 py-10">
      <h1 className="text-2xl font-bold mb-8">Settings</h1>

      <section className="bg-white/[0.03] border border-white/[0.07] rounded-2xl p-6 mb-6">
        <h2 className="font-semibold mb-4">Smart Wallet</h2>
        <div className="space-y-2">
          <div className="flex justify-between text-sm">
            <span className="text-gray-500">Address</span>
            <span className="font-mono text-gray-200">
              {walletAddress ?? "Not deployed"}
            </span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-gray-500">Network</span>
            <span>Base Sepolia</span>
          </div>
        </div>
      </section>

      {/* How session keys work */}
      <section className="bg-white/[0.03] border border-white/[0.07] rounded-2xl p-6 mb-6">
        <h2 className="font-semibold mb-4">How session keys work</h2>
        <div className="space-y-4">
          <div className="flex gap-4">
            <div className="shrink-0 w-8 h-8 rounded-full bg-white/[0.06] border border-white/[0.08] flex items-center justify-center text-xs text-gray-400 font-medium">1</div>
            <div>
              <p className="text-sm font-medium mb-0.5">Limited permission, not full access</p>
              <p className="text-xs text-gray-500 leading-relaxed">The session key only allows the executor to trigger trades within the limits you set. It cannot withdraw funds, transfer tokens, or do anything outside the order flow.</p>
            </div>
          </div>
          <div className="flex gap-4">
            <div className="shrink-0 w-8 h-8 rounded-full bg-white/[0.06] border border-white/[0.08] flex items-center justify-center text-xs text-gray-400 font-medium">2</div>
            <div>
              <p className="text-sm font-medium mb-0.5">You stay in control</p>
              <p className="text-xs text-gray-500 leading-relaxed">You set the max amount per transaction and the daily spending limit. The executor cannot exceed these thresholds no matter what. You can revoke access at any time.</p>
            </div>
          </div>
          <div className="flex gap-4">
            <div className="shrink-0 w-8 h-8 rounded-full bg-white/[0.06] border border-white/[0.08] flex items-center justify-center text-xs text-gray-400 font-medium">3</div>
            <div>
              <p className="text-sm font-medium mb-0.5">Expires automatically</p>
              <p className="text-xs text-gray-500 leading-relaxed">The key is valid for one year. After that date, the executor loses access automatically and orders will stop executing until you renew it.</p>
            </div>
          </div>
        </div>
      </section>

      {isDeployed && (
        <section className="bg-white/[0.03] border border-white/[0.07] rounded-2xl p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="font-semibold">Executor Session Key</h2>
            <span
              className={`text-xs font-medium px-2 py-0.5 rounded-full ${
                isActive
                  ? "bg-green-500/10 text-green-400 border border-green-500/20"
                  : "bg-white/[0.05] text-gray-500 border border-white/[0.08]"
              }`}
            >
              {isActive ? "Active" : "Not configured"}
            </span>
          </div>

          <div className="space-y-2 mb-6">
            <div className="flex justify-between text-sm">
              <span className="text-gray-500">Executor address</span>
              <span className="font-mono text-xs text-gray-300">
                {EXECUTOR_KEY.slice(0, 10)}…{EXECUTOR_KEY.slice(-8)}
              </span>
            </div>
            {isActive && (
              <>
                <div className="flex justify-between text-sm">
                  <span className="text-gray-500">Valid until</span>
                  <span>{formatDate(validUntil)}</span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-gray-500">Max per tx</span>
                  <span>{formatUsdc(maxAmountPerTx)} USDC</span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-gray-500">Daily limit</span>
                  <span>{formatUsdc(dailyLimit)} USDC</span>
                </div>
              </>
            )}
          </div>

          {!isActive && (
            <div className="bg-white/5 border border-white/10 rounded-xl p-4 mb-4 text-sm text-gray-400">
              The executor needs a session key to run your orders automatically without
              requiring your signature each time.
            </div>
          )}

          <button
            onClick={addSessionKey}
            disabled={isPending || isConfirming}
            className={`w-full hover:cursor-pointer py-3 rounded-xl text-sm font-medium transition-colors disabled:opacity-50 ${
              isActive
                ? "border border-white/[0.1] hover:border-white/20 text-gray-400 hover:text-white"
                : "bg-white hover:bg-gray-100 text-black"
            }`}
          >
            {isPending || isConfirming
              ? "Confirming…"
              : isActive
              ? "Renew Session Key (1 year)"
              : "Add Session Key"}
          </button>
        </section>
      )}
    </div>
  )
}
