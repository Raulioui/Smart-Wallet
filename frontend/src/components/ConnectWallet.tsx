"use client"

import { useState, useRef, useEffect } from "react"
import { useWallet } from "@/hooks/useWallet"

const WALLET_ICONS: Record<string, string> = {
  MetaMask: "🦊",
  Injected: "🦊",
  "Coinbase Wallet": "🔵",
}

export function ConnectWallet() {
  const { address, isConnected, isLoading, isWrongNetwork, connectors, connect, disconnect, shortAddress } = useWallet()
  const [showModal, setShowModal] = useState(false)
  const [showDropdown, setShowDropdown] = useState(false)
  const [copied, setCopied] = useState(false)
  const dropdownRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        setShowDropdown(false)
      }
    }
    document.addEventListener("mousedown", handleClick)
    return () => document.removeEventListener("mousedown", handleClick)
  }, [])

  function copyAddress() {
    if (!address) return
    navigator.clipboard.writeText(address)
    setCopied(true)
    setTimeout(() => setCopied(false), 1500)
  }

  if (isWrongNetwork) {
    return (
      <div className="flex items-center gap-2 bg-red-500/10 border border-red-500/30 text-red-400 text-sm px-4 py-2 rounded-xl">
        <span>Switch to Base Sepolia</span>
      </div>
    )
  }

  if (isConnected && address) {
    return (
      <div className="relative" ref={dropdownRef}>
        <button
          onClick={() => setShowDropdown(!showDropdown)}
          className="flex items-center gap-2 hover:cursor-pointer hover:bg-gray-900 border border-gray-700 text-sm px-4 py-2 rounded-xl transition-colors"
        >
          <span className="w-2 h-2 rounded-full bg-green-400" />
          <span className="font-mono">{shortAddress(address)}</span>
          <span className="text-gray-400 text-xs">▾</span>
        </button>

        {showDropdown && (
          <div className="absolute right-0 mt-2 w-56 bg-gray-900 border border-gray-800 rounded-xl shadow-xl z-50 overflow-hidden">
            <div className="px-4 py-3 border-b border-gray-800">
              <p className="text-xs text-gray-500 mb-1">Connected wallet</p>
              <p className="font-mono text-xs text-gray-200 break-all">{address}</p>
            </div>
            <button
              onClick={copyAddress}
              className="w-full text-left hover:cursor-pointer px-4 py-3 text-sm hover:bg-gray-800 transition-colors flex items-center gap-2"
            >
              <span>{copied ? "✓" : "⎘"}</span>
              <span>{copied ? "Copied!" : "Copy address"}</span>
            </button>
            <button
              onClick={() => { disconnect(); setShowDropdown(false) }}
              className="w-full text-left px-4 py-3 hover:cursor-pointer text-sm text-red-400 hover:bg-gray-800 transition-colors flex items-center gap-2"
            >
              <span>⏻</span>
              <span>Disconnect</span>
            </button>
          </div>
        )}
      </div>
    )
  }

  return (
    <>
      <button
        onClick={() => setShowModal(true)}
        disabled={isLoading}
        className="bg-white hover:bg-gray-100 hover:cursor-pointer disabled:opacity-50 text-black text-sm font-medium px-5 py-2 rounded-xl transition-colors"
      >
        {isLoading ? "Connecting…" : "Connect Wallet"}
      </button>

      {showModal && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm"
          onClick={() => setShowModal(false)}
        >
          <div
            className="bg-gray-900 border border-gray-800 rounded-2xl w-full max-w-sm mx-4 overflow-hidden shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between px-6 py-4 border-b border-gray-800">
              <h2 className="font-semibold text-lg">Connect Wallet</h2>
              <button
                onClick={() => setShowModal(false)}
                className="text-gray-500 hover:cursor-pointer hover:text-gray-300 transition-colors text-xl leading-none"
              >
                ×
              </button>
            </div>

            <div className="p-4 flex flex-col gap-2">
              {connectors.map((connector) => (
                <button
                  key={connector.uid}
                  onClick={() => {
                    connect({ connector })
                    setShowModal(false)
                  }}
                  disabled={isLoading}
                  className="flex items-center hover:cursor-pointer gap-4 w-full bg-gray-800 hover:bg-gray-700 border border-gray-700 hover:border-gray-600 px-4 py-3.5 rounded-xl transition-all text-left"
                >
                  <span className="text-2xl">
                    {WALLET_ICONS[connector.name] ?? "🔌"}
                  </span>
                  <div>
                    <p className="font-medium text-sm">{connector.name}</p>
                    <p className="text-xs text-gray-500">
                      {connector.name === "Injected" || connector.name === "MetaMask"
                        ? "Browser extension"
                        : "Mobile & extension"}
                    </p>
                  </div>
                </button>
              ))}
            </div>

            <div className="px-6 pb-5 text-center">
              <p className="text-xs text-gray-600">Base Sepolia testnet</p>
            </div>
          </div>
        </div>
      )}
    </>
  )
}
