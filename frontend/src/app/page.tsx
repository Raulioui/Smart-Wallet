"use client"

import Link from "next/link"
import Image from "next/image"
import { useWallet } from "@/hooks/useWallet"

const STEPS = [
  {
    title: "Deploy your Smart Wallet",
    desc: "Connect your wallet and create your Smart Wallet in one click. It's a personal account that lives on the blockchain, only you control it, and it never holds your private keys.",
    img: "https://images.unsplash.com/photo-1563013544-824ae1b704d3?w=800&h=500&fit=crop&q=80"
  },
  {
    title: "Create an automated order",
    desc: "Choose your strategy: dollar-cost average into ETH on a fixed interval, set a limit order triggered by a Chainlink price feed, or protect your position with a stop-loss. All orders are stored on-chain.",
    img: "https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=800&h=500&fit=crop&q=80"
  },
  {
    title: "Authorize the executor",
    desc: "Give permission to an automated executor to act on your behalf, but only up to the limits you set. You decide the max amount per trade and per day. You can remove access whenever you want.",
    img: "https://images.unsplash.com/photo-1582139329536-e7284fece509?w=800&h=500&fit=crop&q=80"
  },
  {
    title: "Executor monitors & submits",
    desc: "A background service checks your orders automatically. When the time or price condition is met, it executes the trade on your behalf, no action needed from you, and you don't pay any gas fees.",
    img: "https://images.unsplash.com/photo-1558494949-ef010cbdcc31?w=800&h=500&fit=crop&q=80"
  },
  {
    title: "Atomic swap, gasless",
    desc: "Your trade happens in a single step, either everything goes through or nothing does. Your tokens are swapped instantly at the best available price, with no risk of partial or failed executions.",
    img: "https://images.unsplash.com/photo-1605792657660-596af9009e82?w=800&h=500&fit=crop&q=80",
  },
]

export default function Home() {
  const { isConnected } = useWallet()

  return (
    <div className="max-w-6xl mx-auto px-4 py-24">

      <div className="text-center mb-40">
        <div className="inline-flex items-center gap-2 bg-white/5 border border-white/10 text-gray-500 text-xs font-medium px-3 py-1.5 rounded-full mb-10">
          Deployed on Base Sepolia 
        </div>

        <h1 className="text-6xl sm:text-8xl font-bold tracking-tight leading-none mb-8">
          DeFi Automation
          <br />
          <span className="text-gray-600">Without the Complexity</span>
        </h1>

        <p className="text-gray-500 text-lg max-w-lg mx-auto mb-12 leading-relaxed">
          EIP-4337 smart wallet protocol. DCA, limit orders and stop-losses, executed automatically, gasless, non-custodial.
        </p>

        <div className="flex items-center justify-center gap-3">
          <Link
            href={isConnected ? "/dashboard" : "#"}
            className={`bg-white hover:bg-gray-100 text-black font-semibold px-8 py-3.5 rounded-xl transition-colors text-sm ${
              !isConnected ? "opacity-30 pointer-events-none" : ""
            }`}
          >
            Launch App →
          </Link>
          <a
            href="https://github.com/Raulioui/Smart-Wallet"
            target="_blank"
            rel="noopener noreferrer"
            className="border border-gray-800 hover:border-gray-700 text-gray-500 hover:text-gray-200 font-medium px-8 py-3.5 rounded-xl transition-colors text-sm"
          >
            View Code
          </a>
        </div>

        {!isConnected && (
          <p className="text-xs text-gray-800 mt-5">Connect wallet to get started</p>
        )}
      </div>

      <div>
        <div className="flex items-center gap-4 mb-24">
          <div className="h-px flex-1 bg-gray-900" />
          <p className="text-xs font-medium text-gray-700 uppercase tracking-[0.2em]">How it works</p>
          <div className="h-px flex-1 bg-gray-900" />
        </div>

        <div className="flex flex-col">
          {STEPS.map((step, i) => (
            <div >
              <div
                className={`flex flex-col lg:flex-row items-center gap-20 py-24 ${
                  i % 2 === 1 ? "lg:flex-row-reverse" : ""
                }`}
              >
                <div className="w-full lg:w-[55%] shrink-0">
                  <div className="relative aspect-[4/3] rounded-2xl overflow-hidden ring-1 ring-white/5">
                    <Image
                      src={step.img}
                      alt={step.title}
                      fill
                      className="object-cover brightness-75"
                    />
                    <div className="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-transparent" />
                  </div>
                </div>

                <div className="flex-1">
                  <h3 className="text-4xl font-bold mb-6 leading-tight">{step.title}</h3>
                  <p className="text-gray-500 text-base leading-8">{step.desc}</p>
                </div>
              </div>

              {i < STEPS.length - 1 && (
                <div className="h-px bg-gray-900" />
              )}
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
