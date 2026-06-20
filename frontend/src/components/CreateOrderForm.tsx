"use client"

import { useState } from "react"
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi"
import { encodeFunctionData, parseUnits } from "viem"
import { useSmartWallet } from "@/hooks/useSmartWallet"
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

export function CreateOrderForm({ onSuccess }: { onSuccess: () => void }) {
  const { walletAddress } = useSmartWallet()

  const [tab, setTab] = useState<OrderType>("DCA")
  const [dcaAmount, setDcaAmount] = useState("")
  const [dcaInterval, setDcaInterval] = useState(86400)
  const [dcaExecutions, setDcaExecutions] = useState("")
  const [priceAmount, setPriceAmount] = useState("")
  const [priceTarget, setPriceTarget] = useState("")
  const [priceMinOut, setPriceMinOut] = useState("")

  const { writeContract, data: txHash, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash })

  if (isSuccess) onSuccess()

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
  const isDca = tab === "DCA"

  return (
    <div className="max-w-lg">

      <div className="grid grid-cols-2 gap-2 mb-6">
        {TABS.map(({ type, label, desc }) => (
          <button
            key={type}
            onClick={() => setTab(type)}
            className={`text-left hover:cursor-pointer p-4 rounded-xl border transition-all ${
              tab === type
                ? "bg-white/10 border-white/20 text-white"
                : "bg-white/[0.03] border-white/[0.06] hover:border-white/[0.12] hover:bg-white/[0.05] text-gray-400"
            }`}
          >
            <p className="font-medium text-sm mb-0.5">{label}</p>
            <p className="text-xs opacity-70">{desc}</p>
          </button>
        ))}
      </div>

      <div className="bg-white/[0.03] border border-white/[0.07] rounded-2xl p-6 space-y-5">
        {isDca ? (
          <>
            <div>
              <label className="text-xs text-gray-500 mb-1.5 block">Amount per execution (USDC)</label>
              <input
                type="number"
                placeholder="10"
                value={dcaAmount}
                onChange={(e) => setDcaAmount(e.target.value)}
                className="w-full bg-white/[0.05] border border-white/[0.08] focus:border-white/30 outline-none text-sm px-4 py-3 rounded-xl transition-colors"
              />
            </div>
            <div>
              <label className="text-xs text-gray-500 mb-1.5 block">Interval</label>
              <div className="grid grid-cols-2 gap-2">
                {INTERVAL_OPTIONS.map(({ label, value }) => (
                  <button
                    key={value}
                    onClick={() => setDcaInterval(value)}
                    className={`py-2.5 hover:cursor-pointer text-sm rounded-xl border transition-all ${
                      dcaInterval === value
                        ? "bg-white/10 border-white/20 text-white"
                        : "bg-white/[0.05] border-white/[0.08] hover:border-white/20 text-gray-400"
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
                className="w-full bg-white/[0.05] border border-white/[0.08] focus:border-white/30 outline-none text-sm px-4 py-3 rounded-xl transition-colors"
              />
            </div>
            {dcaAmount && dcaExecutions && (
              <div className="bg-white/[0.05] border border-white/[0.06] rounded-xl p-3 text-xs text-gray-400">
                Total: <span className="text-white font-medium">{(parseFloat(dcaAmount) * parseInt(dcaExecutions)).toFixed(2)} USDC</span>
                {" "}over <span className="text-white font-medium">{INTERVAL_OPTIONS.find(o => o.value === dcaInterval)?.label}</span> intervals
              </div>
            )}
          </>
        ) : (
          <>
            <div>
              <label className="text-xs text-gray-500 mb-1.5 block">Amount in (USDC)</label>
              <input
                type="number"
                placeholder="100"
                value={priceAmount}
                onChange={(e) => setPriceAmount(e.target.value)}
                className="w-full bg-white/[0.05] border border-white/[0.08] focus:border-white/30 outline-none text-sm px-4 py-3 rounded-xl transition-colors"
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
                className="w-full bg-white/[0.05] border border-white/[0.08] focus:border-white/30 outline-none text-sm px-4 py-3 rounded-xl transition-colors"
              />
            </div>
            <div>
              <label className="text-xs text-gray-500 mb-1.5 block">Min ETH received (slippage floor)</label>
              <input
                type="number"
                placeholder="0.03"
                value={priceMinOut}
                onChange={(e) => setPriceMinOut(e.target.value)}
                className="w-full bg-white/[0.05] border border-white/[0.08] focus:border-white/30 outline-none text-sm px-4 py-3 rounded-xl transition-colors"
              />
            </div>
          </>
        )}

        <button
          onClick={submit}
          disabled={isSubmitting}
          className="w-full hover:cursor-pointer bg-white hover:bg-gray-100 disabled:opacity-50 text-black font-medium py-3.5 rounded-xl transition-colors mt-2"
        >
          {isSubmitting ? "Confirming…" : "Create Order"}
        </button>
      </div>
    </div>
  )
}
