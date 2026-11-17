# Kgiwa Launchpad Terminal

> Built with Arc Studio - money-powered apps in minutes

Project memory: what Arc Studio remembers about this app.

## What This App Does

Token launchpad terminal on GIWA Sepolia testnet. Tabs: Market (launched tokens + search), Trade (search + buy/sell with quotes), Launch (instant token, 0.0001 ETH creation fee, device logo), Fundraise (token launches only when target is filled; creator can cancel before), Portfolio, Staking (coming soon placeholder).

## Tech Stack

- Frontend: React 18, Vite, TypeScript, Tailwind CSS (Arc Dark tokens in `src/index.css`)
- Web3: wagmi v2, viem v2, ConnectKit (injected)
- Contracts: Solidity 0.8.28 + Foundry. `contracts/KgiwaLaunchpad.sol`, `contracts/LaunchToken.sol`, tests in `contracts/test/`. `bun run contracts:build`, `bun run contracts:test`.
- Chain: GIWA Sepolia testnet (91342), native ETH. Defined in `src/chains.ts` from docs.giwa.io (not in Arc Studio's chain registry, and not supported by the built-in deployers).
- Faucet: https://faucet.giwa.io

## Contract design decisions (v2.1)

- Fixed supply: 1,000,000,000 tokens minted once to the launchpad. 800M sold on the curve, 200M permanently locked in the launchpad (no vesting, no DEX migration, no minting after launch).
- Exponential curve, k = ln(10): price p(s) = p0 * 10^(s/800M), p0 = 5 ETH / 20M virtual tokens = 0.00000025 ETH. The 5 ETH / 20M are virtual only, never withdrawable or payable. Backing R(s) = A * (e^(k s / C) - 1), A ~ 86.86 ETH, R(C) ~ 781.7 ETH.
- One deterministic reserve function drives buys, sells, fundraise contributions and burn-buys. Invariant: reserveETH >= reserveRequired(token). Sells revert with InsufficientReserve if unpayable. Fees never reduce backing.
- Trade fee chosen by the creator, 1% to 3%. Split 40% platform / 20% creator (claimCreatorFees) / 20% holders (dividend accounting in LaunchToken, claimHolderRewards; launchpad balance excluded; below 1,000 circulating tokens the holder share goes to platform) / 20% burn (a real curve purchase: ETH added to reserve, curve position advances, tokens burned).
- Creation fees: instant 0.0001 ETH, fundraise 0.05 ETH (owner-configurable). Fundraise targets 0.01 to 50 ETH, 30-day deadline: after expiry contributors can refund without the creator. Creator can cancel before fill.
- Dust floor 0.00001 ETH on buys, contributions and sells. Renouncing ownership is disabled. Pause blocks create/buy/sell/contribute, not claims, refunds or cancel.
- Review: balanced security review (2 rounds) and Slither done; 84 Foundry tests pass.
- Exits are path dependent; the curve pays every sell in full from real reserve but guarantees no profit.

## Admin tab

- Visible only when the connected wallet equals `owner()`. Shows treasury address and balance, fee totals (from `FeesDistributed` and creation events, bounded 400k-block lookback), trader list with per-wallet volume, and forms for `setPlatformWallet` and `setFundraiseCreationFee` only.
- Platform fees are paid straight to the treasury, so there is no claim button by design.

## Deployment

- v2.1 deployed on GIWA Sepolia via Remix: 0x7953Ac57b6465665ABA819248abFf77F34592b1B at block 41413380. Owner and platform wallet: 0x27F5747b7791b28eadaA9a3f4EAD7076B0013DA4.
- The v1 contract (0xfa64E5578704238E16672aF648889d0ce074362b) is superseded and unused.
- `VITE_LAUNCHPAD_ADDRESS` and `VITE_LAUNCHPAD_DEPLOY_BLOCK` in `.env` point at v2.1. Restart the dev server and rebuild after changing them.
- Redeploying a new version: paste `remix/KgiwaLaunchpad.sol` into Remix (compiler 0.8.28, EVM cancun, optimizer 200), or `bun run deploy:giwa`.

## Key Files

- `src/App.tsx` - tab shell
- `src/components/` - pages (MarketPage, TradePage, LaunchPage, FundraisePage, PortfolioPage, StakingPage) and shared UI
- `src/hooks/` - useTokens, useFundraises, useTrades, useTx
- `src/contracts/launchpad.ts`, `src/contracts/launchpadAbi.ts` - address/env + ABI (regenerate ABI with `forge inspect KgiwaLaunchpad abi --json` after contract changes)
- `src/lib/` - formatting, image resize (logo to ~4 KB data URI), error parsing
- `scripts/deploy-giwa.ts` - GIWA deploy script

## Share links

- Starter apps already ship `getShareBase`, `buildShareLink` and `installShareSync` in `src/lib/share.ts`; import them instead of rewriting them.
- Keep shareable state in the URL path or query, not in the `#fragment`.
- Never put a secret in the URL path or query. Build every link a user copies or sends with `buildShareLink()`.
- Keep the `installShareSync()` call in `src/main.tsx` when editing it.
- Navigate inside the app with relative links.

## To Run

```bash
bun install
bun run dev
```

## Deployed contract (v2.2, fundraise vesting)

- GIWA Sepolia (91342): `0xBFF28ff8D112f206Ae1cef3C05Fdc8A7692a63E4`, deploy block 41545572, deployed via Remix. Owner and platform wallet: `0x27F5747b7791b28eadaA9a3f4EAD7076B0013DA4`.
- Fundraises can release instantly or hourly over 24 or 48 hours (`createFundraiseVested`).
- Previous v2.1 contract `0x7953Ac57b6465665ABA819248abFf77F34592b1B` is no longer used.
