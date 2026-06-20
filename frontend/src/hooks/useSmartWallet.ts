"use client"

import { useReadContract } from "wagmi"
import { useWallet } from "./useWallet"
import { factoryAbi, smartWalletAbi, erc20Abi, orderManagerAbi, FACTORY_ADDRESS, ORDER_MANAGER_ADDRESS, USDC_ADDRESS } from "@/lib/contracts"

export function useSmartWallet() {
  const { address: eoa, isConnected } = useWallet()

  // get user adress
  const { data: walletAddress, isLoading: isLoadingAddress } = useReadContract({
    address: FACTORY_ADDRESS,
    abi: factoryAbi,
    functionName: "getAddress",
    args: eoa ? [eoa, BigInt(0)] : undefined,
    query: { enabled: !!eoa && isConnected },
  })

  // check if wallet is deployed 
  const { data: walletOwner, isLoading: isLoadingOwner } = useReadContract({
    address: walletAddress,
    abi: smartWalletAbi,
    functionName: "owner",
    query: { enabled: !!walletAddress },
  })

  const isDeployed = !!walletOwner

  // USDC balance of the user
  const { data: usdcBalance, refetch: refetchBalance } = useReadContract({
    address: USDC_ADDRESS,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: walletAddress ? [walletAddress] : undefined,
    query: { enabled: !!walletAddress && isDeployed },
  })

  // Order IDs of this wallet
  const { data: orderIds, refetch: refetchOrders } = useReadContract({
    address: ORDER_MANAGER_ADDRESS,
    abi: orderManagerAbi,
    functionName: "getUserOrders",
    args: walletAddress ? [walletAddress] : undefined,
    query: { enabled: !!walletAddress && isDeployed },
  })

  const isLoading = isLoadingAddress || isLoadingOwner

  return {
    eoa,
    walletAddress: walletAddress as `0x${string}` | undefined,
    isDeployed,
    isLoading,
    usdcBalance: usdcBalance ?? BigInt(0),
    orderIds: (orderIds ?? []) as bigint[],
    refetchBalance,
    refetchOrders,
  }
}
