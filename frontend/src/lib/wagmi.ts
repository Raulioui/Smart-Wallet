import { createConfig, http } from "wagmi"
import { baseSepolia } from "wagmi/chains"
import { injected, coinbaseWallet } from "wagmi/connectors"

export const config = createConfig({
  chains: [baseSepolia],
  connectors: [
    injected(),
    coinbaseWallet({ appName: "Smart Wallet" }),
  ],
  transports: {
    [baseSepolia.id]: http(),
  },
})
