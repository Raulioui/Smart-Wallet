"use client"

import Link from "next/link"
import { usePathname } from "next/navigation"
import { ConnectWallet } from "./ConnectWallet"

const NAV_LINKS = [
  { href: "/dashboard", label: "Dashboard" },
  { href: "/settings", label: "Settings" },
]

export function Header() {
  const pathname = usePathname()

  return (
    <header className="sticky top-0 z-40 py-2 border-b border-white/5 shadow-[0_4px_32px_rgba(0,0,0,0.6)] backdrop-blur-md bg-black/30">
      <div className="max-w-6xl mx-auto px-4 h-16 flex items-center justify-between gap-10">
        <Link href="/" className="flex items-center gap-2 shrink-0">
          <div className="w-10 h-10 rounded-full bg-white text-black flex items-center justify-center text-lg font-bold">
            SW
          </div>
        </Link>

        <nav className="flex items-center gap-1">
          {NAV_LINKS.map(({ href, label }) => {
            const active = pathname === href
            return (
              <Link
                key={href}
                href={href}
                className={`px-3 py-1.5 rounded-lg text-sm transition-colors ${
                  active
                    ? "bg-gray-800 text-white"
                    : "text-gray-400 hover:text-gray-200 hover:bg-gray-800/50"
                }`}
              >
                {label}
              </Link>
            )
          })}
        </nav>

        <ConnectWallet />
      </div>
    </header>
  )
}
