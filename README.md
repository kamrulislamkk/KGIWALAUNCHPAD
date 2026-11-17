# Kgiwa Launchpad Terminal

A token launchpad terminal on GIWA Sepolia testnet. Browse launched tokens, trade them, launch a token instantly, run fundraises that launch automatically when the target is filled, and track your portfolio. Staking is shown as coming soon.

Built with [Arc Studio](https://studio.arc.io)

## What you can do

- Market: browse every launched token, search, and sort by newest, market cap or volume.
- Trade: search a token, buy or sell with live quotes and slippage, and see recent trades.
- Launch: create a token instantly (0.0001 ETH creation fee) with a logo from your device and a 1% to 3% trade fee.
- Fundraise: publish a token before it exists (0.05 ETH fee, 0.01 to 50 ETH target). It launches when the target is filled. Only the creator can cancel before then, and contributors can refund if it expires after 30 days.
- Fundraise token release: creators choose instant, 24 hours or 48 hours; with hourly release 1/24 or 1/48 of each contributor's allocation unlocks every hour after the fundraise fills, and contributors claim what has unlocked.
- Admin (contract owner wallet only): see the treasury wallet and balance, total fees collected, every trader wallet with trades and volume (copy one or all addresses, or copy as CSV), change the treasury address, and set the fundraise creation fee.
- Portfolio: see your ETH, token holdings, claimable holder rewards and creator fees, fundraise positions and tokens you launched.

## How tokens work

Every token has 1 billion supply: 800 million are sold along one price curve (start 0.00000025 ETH, up to 10x at sell-out) and 200 million stay locked forever. Sales are paid from real ETH held by the contract. Trade fees split 40% platform, 20% creator, 20% holders and 20% burned.

## Tech stack

- React 18, Vite, TypeScript, Tailwind CSS
- wagmi v2, viem, ConnectKit (injected wallets)
- Solidity 0.8.28 with Foundry and OpenZeppelin (single-file Remix version in `remix/KgiwaLaunchpad.sol`)
- Network: GIWA Sepolia testnet (chain ID 91342, native currency ETH)

## Development

Prerequisites: [Bun](https://bun.sh) and [Foundry](https://book.getfoundry.sh).

```bash
bun install
bun run dev            # start the app
bun run contracts:build
bun run contracts:test
bun run check          # lint + typecheck
```

### Deploying the contract to GIWA Sepolia

1. Create a throwaway wallet that holds testnet ETH only and fund it from https://faucet.giwa.io.
2. Add its key to `.env` as `GIWA_DEPLOYER_PRIVATE_KEY` (never commit it).
3. Run `bun run deploy:giwa --dry-run` to check, then `bun run deploy:giwa`.
4. Restart `bun run dev`. The deploy script writes the contract address and deploy block to `.env`.

### Environment variables

- `GIWA_DEPLOYER_PRIVATE_KEY`: throwaway testnet key used only by the deploy script.
- `VITE_LAUNCHPAD_ADDRESS`: deployed launchpad contract address (written by the deploy script).
- `VITE_LAUNCHPAD_DEPLOY_BLOCK`: block the contract was deployed at (written by the deploy script).
