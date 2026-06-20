# Smart Wallet: EIP-4337 DeFi Automation

A non-custodial smart contract wallet with built-in DeFi automation on Base Sepolia. Deploy your own wallet, deposit tokens once, and create persistent orders that execute automaticaly — gasless, trustless, non-custodial.

> Deployed on Base Sepolia testnet.

---

<!-- Add screenshot of home page here -->

---

## What is this?

Most DeFi automation tools require you to trust a third party with your funds. This protocol works differently: your tokens stay in your own smart wallet at all times. An off-chain executor can only move them within the exact conditions you define on-chain, if the conditions aren't met, the transaction reverts.

Gas fees are covered by Pimlico's Paymaster. You never need ETH in your wallet to trade.

---

## How it works

```
User
  1. Deploys a SmartWallet (once, via the factory)
  2. Deposits USDC into it
  3. Creates an order: DCA / Limit Buy / Limit Sell / Stop Loss
  4. Grants a session key to the executor (spending limits + expiry)

Executor (off-chain, every 60s)
  Checks which orders are ready → builds a batch:
    [approve → swap via Uniswap V3 → recordExecution]
  Signs with the session key → sends to Pimlico Bundler → gasless tx

OrderManager (on-chain)
  recordExecution validates everything before confirming:
  - DCA: is it time yet?
  - Price orders: is Chainlink at the target price?
  If anything fails, the whole batch reverts  (including the swap).
```

---

## Contracts

### `SmartWallet.sol`

Personal wallet for each user. Implements EIP-4337  and EIP-1271. Holds all user funds and validates every UserOperation.

Session keys let the executor trade on your behalf within limits you set:

```solidity
struct SessionKeyData {
    bool isActive;
    uint48 validUntil;
    uint256 maxAmountPerTx;
    uint256 dailyLimit;
}
```

You can revoke the session key at any time. The EntryPoint auto-rejects any op signed by an expired key.

### `SmartWalletFactory.sol`

Deploys wallets with CREATE2, the address is deterministic and known before the wallet exists on-chain. Users can fund it before the first transaction (EIP-4337 counterfactual deployment).

### `OrderManager.sol`

Stores all orders and enforces execution conditions on-chain. Supported order types:

| Type | Trigger |
|---|---|
| `DCA` | `block.timestamp >= nextExecutionTime` |
| `LIMIT_BUY` | Chainlink price `<=` targetPrice |
| `LIMIT_SELL` | Chainlink price `>=` targetPrice |
| `STOP_LOSS` | Chainlink price `<=` targetPrice |

`recordExecution` is always the last call in the executor's batch. If it reverts, the swap reverts too — atomically.

---

## Executor

Node.js/TypeScript service in executor/. Polls OrderManager every 60 seconds and submits eligible orders as UserOperations via Pimlico.


## Frontend

Next.js + wagmi v3 + viem v2 + Tailwind v4.

<!-- Add screenshot of dashboard here -->

- `/` — How it works
- `/dashboard` — Deploy wallet, view balance, create and manage orders
- `/settings` — Add / renew / revoke executor session key

<!-- Add screenshot of settings here -->

Supports MetaMask and Coinbase Wallet on Base Sepolia.

---

## Deployed contracts (Base Sepolia)

| Contract | Address |
|---|---|
| SmartWalletFactory | `0xE097784c26fCf1b3A5D737DF5ef48dcBae325939` |
| OrderManager | `0x1e29B2021541Fafd759C781508868FD5dc97a3f6` |
| Executor key | `0xD5B95747CcCEa0E0115623e05d8067a666cfF9c8` |
| USDC | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` |
| WETH | `0x4200000000000000000000000000000000000006` |
| ETH/USD feed | `0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1` |

---
