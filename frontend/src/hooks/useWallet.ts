"use client"

import { useAccount, useConnect, useDisconnect, useChainId } from "wagmi"
import { baseSepolia } from "wagmi/chains"

export function useWallet() {
  const { address, isConnected, isConnecting, isReconnecting } = useAccount()
  const { connectors, connect, isPending: isConnectPending } = useConnect()
  const { disconnect } = useDisconnect()
  const chainId = useChainId()

  const isWrongNetwork = isConnected && chainId !== baseSepolia.id
  const isLoading = isConnecting || isReconnecting || isConnectPending

  function shortAddress(addr: string) {
    return `${addr.slice(0, 6)}…${addr.slice(-4)}`
  }

  return {
    address,
    isConnected,
    isLoading,
    isWrongNetwork,
    connectors,
    connect,
    disconnect,
    shortAddress,
  }
}
