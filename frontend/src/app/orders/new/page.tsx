"use client"

import { useState } from "react"
import { useRouter } from "next/navigation"
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi"
import { encodeFunctionData, parseUnits } from "viem"
import { useSmartWallet } from "@/hooks/useSmartWallet"
import { useWallet } from "@/hooks/useWallet"
import { orderManagerAbi, smartWalletAbi, ORDER_MANAGER_ADDRESS, USDC_ADDRESS, WETH_ADDRESS, ETH_USD_FEED } from "@/lib/contracts"

type OrderType = "DCA" | "LIMIT_BUY" | "LIMIT_SELL" | "STOP_LOSS"

const TABS: { type: OrderType; label: string; desc: string }[] = [
  { type: "DCA", label: "DCA", desc: "Buy at fixed intervals" },
  { type: "LIMIT_BUY", label: "Limit Buy", desc: "Buy when price drops to target" },
  { type: "LIMIT_SELL", label: "Limit Sell", desc: "Sell when price rises to target" },
  { type: "STOP_LOSS", label: "Stop Loss", desc: "Sell when price falls to target" },
]

const INTERVAL_OPTIONS = [
  { label: "1 day", value: 86400 },
  { label: "3 days", value: 259200 },
  { label: "1 week", value: 604800 },
  { label: "2 weeks", value: 1209600 },
]

export default function NewOrder() {
  const router = useRouter()
  const { isConnected } = useWallet()
  const { walletAddress, isDeployed } = useSmartWallet()

  const [tab, setTab] = useState<OrderType>("DCA")

  // DCA fields
  const [dcaAmount, setDcaAmount] = useState("")
  const [dcaInterval, setDcaInterval] = useState(86400)
  const [dcaExecutions, setDcaExecutions] = useState("")

  // Price-based fields
  const [priceAmount, setPriceAmount] = useState("")
  const [priceTarget, setPriceTarget] = useState("")
  const [priceMinOut, setPriceMinOut] = useState("")

  const { writeContract, data: txHash, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash })

  if (isSuccess) router.push("/dashboard")

  function buildCalldata() {
    if (tab === "DCA") {
      return encodeFunctionData({
        abi: orderManagerAbi,
        functionName: "createDCAOrder",
        args: [
          USDC_ADDRESS,
          WETH_ADDRESS,
          parseUnits(dcaAmount || "0", 6),
          BigInt(dcaInterval),
          BigInt(dcaExecutions || "1"),
          BigInt(0),
        ],
      })
    }

    const fnMap = {
      LIMIT_BUY: "createLimitBuyOrder",
      LIMIT_SELL: "createLimitSellOrder",
      STOP_LOSS: "createStopLossOrder",
    } as const

    return encodeFunctionData({
      abi: orderManagerAbi,
      functionName: fnMap[tab as keyof typeof fnMap],
      args: [
        USDC_ADDRESS,
        WETH_ADDRESS,
        parseUnits(priceAmount || "0", 6),
        parseUnits(priceMinOut || "0", 18),
        BigInt(Math.floor(parseFloat(priceTarget || "0") * 1e8)),
        ETH_USD_FEED,
        BigInt(0),
      ],
    })
  }

  function submit() {
    if (!walletAddress) return
    writeContract({
      address: walletAddress,
      abi: smartWalletAbi,
      functionName: "execute",
      args: [ORDER_MANAGER_ADDRESS, BigInt(0), buildCalldata()],
    })
  }

  const isSubmitting = isPending || isConfirming

  if (!isConnected) {
    return (
      <div className="max-w-xl mx-auto px-4 py-20 text-center">
        <p className="text-gray-400">Connect your wallet first.</p>
      </div>
    )
  }

  if (!isDeployed) {
    return (
      <div className="max-w-xl mx-auto px-4 py-20 text-center">
        <p className="text-gray-400 mb-4">You need to deploy your Smart Wallet first.</p>
        <a href="/dashboard" className="text-gray-400 hover:text-white underline text-sm">Go to Dashboard →</a>
      </div>
    )
  }

  const isDca = tab === "DCA"

  return (
    <div className="max-w-xl mx-auto px-4 py-10">
      <h1 className="text-2xl font-bold mb-8">New Order</h1>

      {/* Type tabs */}
      <div className="grid grid-cols-2 gap-2 mb-8">
        {TABS.map(({ type, label, desc }) => (
          <button
            key={type}
            onClick={() => setTab(type)}
            className={`text-left p-4 rounded-xl border transition-all ${
              tab === type
                ? "bg-white/10 border-white/20 text-white"
                : "bg-gray-900 border-gray-800 hover:border-gray-700 text-gray-400"
            }`}
          >
            <p className="font-medium text-sm mb-0.5">{label}</p>
            <p className="text-xs opacity-70">{desc}</p>
          </button>
        ))}
      </div>

      {/* Form */}
      <div className="bg-gray-900 border border-gray-800 rounded-2xl p-6 space-y-5">

        {isDca ? (
          <>
            <div>
              <label className="text-xs text-gray-500 mb-1.5 block">Amount per execution (USDC)</label>
              <input
                type="number"
                placeholder="10"
                value={dcaAmount}
                onChange={(e) => setDcaAmount(e.target.value)}
                className="w-full bg-gray-800 border border-gray-700 focus:border-white/40 outline-none text-sm px-4 py-3 rounded-xl transition-colors"
              />
            </div>

            <div>
              <label className="text-xs text-gray-500 mb-1.5 block">Interval</label>
              <div className="grid grid-cols-2 gap-2">
                {INTERVAL_OPTIONS.map(({ label, value }) => (
                  <button
                    key={value}
                    onClick={() => setDcaInterval(value)}
                    className={`py-2.5 text-sm rounded-xl border transition-all ${
                      dcaInterval === value
                        ? "bg-white/10 border-white/20 text-white"
                        : "bg-gray-800 border-gray-700 hover:border-gray-600 text-gray-400"
                    }`}
                  >
                    {label}
                  </button>
                ))}
              </div>
            </div>

            <div>
              <label className="text-xs text-gray-500 mb-1.5 block">Number of executions</label>
              <input
                type="number"
                placeholder="4"
                value={dcaExecutions}
                onChange={(e) => setDcaExecutions(e.target.value)}
                className="w-full bg-gray-800 border border-gray-700 focus:border-white/40 outline-none text-sm px-4 py-3 rounded-xl transition-colors"
              />
            </div>

            {dcaAmount && dcaExecutions && (
              <div className="bg-gray-800 rounded-xl p-3 text-xs text-gray-400">
                Total: <span className="text-white font-medium">{(parseFloat(dcaAmount) * parseInt(dcaExecutions)).toFixed(2)} USDC</span>
                {" "}over <span className="text-white font-medium">{INTERVAL_OPTIONS.find(o => o.value === dcaInterval)?.label}</span> intervals
              </div>
            )}
          </>
        ) : (
          <>
            <div>
              <label className="text-xs text-gray-500 mb-1.5 block">
                Amount in (USDC)
              </label>
              <input
                type="number"
                placeholder="100"
                value={priceAmount}
                onChange={(e) => setPriceAmount(e.target.value)}
                className="w-full bg-gray-800 border border-gray-700 focus:border-white/40 outline-none text-sm px-4 py-3 rounded-xl transition-colors"
              />
            </div>

            <div>
              <label className="text-xs text-gray-500 mb-1.5 block">
                {tab === "LIMIT_BUY" ? "Buy when ETH price drops to ($)" : "Trigger price ($)"}
              </label>
              <input
                type="number"
                placeholder={tab === "LIMIT_BUY" ? "2500" : "2000"}
                value={priceTarget}
                onChange={(e) => setPriceTarget(e.target.value)}
                className="w-full bg-gray-800 border border-gray-700 focus:border-white/40 outline-none text-sm px-4 py-3 rounded-xl transition-colors"
              />
            </div>

            <div>
              <label className="text-xs text-gray-500 mb-1.5 block">Min ETH received (slippage floor)</label>
              <input
                type="number"
                placeholder="0.03"
                value={priceMinOut}
                onChange={(e) => setPriceMinOut(e.target.value)}
                className="w-full bg-gray-800 border border-gray-700 focus:border-white/40 outline-none text-sm px-4 py-3 rounded-xl transition-colors"
              />
            </div>
          </>
        )}

        <button
          onClick={submit}
          disabled={isSubmitting}
          className="w-full bg-white hover:bg-gray-100 disabled:opacity-50 text-black font-medium py-3.5 rounded-xl transition-colors mt-2"
        >
          {isSubmitting ? "Confirming…" : "Create Order"}
        </button>
      </div>
    </div>
  )
}
