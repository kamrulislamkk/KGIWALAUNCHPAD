## Implementation Plan: Kgiwa Launchpad Terminal

### Summary
A token launchpad terminal on GIWA Sepolia testnet. Users browse launched tokens, trade them, launch a token instantly for a fixed 0.0001 ETH fee, run fundraises that auto-launch when the target is met, and track a portfolio. Staking shows as "Coming soon".

### Architecture
- **Blockchain:** GIWA Sepolia testnet (chain ID 91342, native currency ETH, RPC https://sepolia-rpc.giwa.io, explorer https://sepolia-explorer.giwa.io, faucet https://faucet.giwa.io). Testnet only, never mainnet.
- **Deployment caveat:** Arc Studio's built-in deployers only support Circle-supported testnets, and GIWA Sepolia is not one of them.
  - Primary: add `scripts/deploy-giwa.ts` (viem). It deploys with a throwaway testnet-only key the user pastes into `.env` themselves (never in chat).
  - Fallback: deploy to Arc Testnet and switch the UI chain. The contract is chain-agnostic.
  - Deploy only after the user explicitly says "deploy".
- **Fees at a glance:** creation fee = fixed 0.0001 ETH (instant launch; fundraise creation assumed the same). Trade fee = per-token `tradeFeeBps`, set by the creator. No fee is charged because of the 0.0001 figure on buys.
- **Contract (new, Solidity):** `KgiwaLaunchpad` matches the user's ABI exactly plus additive functions their rules require. Uses OpenZeppelin Ownable, ReentrancyGuard, ERC20. Each launched token is a small fixed-supply ERC-20 (`LaunchToken`, 18 decimals).
  - Instant launch: `createInstant` takes `instantCreationFee` (0.0001 ETH). Extra ETH sent becomes the creator's optional first buy. Full supply goes on the curve. Initial price set so full supply = 5 ETH virtual liquidity (price0 = 5 ETH / supply).
  - Buy: buyer pays current price, then price rises 1.5% per buy regardless of size. Tokens out = (ETH minus trade fee) / current price. `reserveETH` holds real ETH.
  - Sell: payout limited to real ETH in `reserveETH` (available liquidity). `minimumETHOut` protects the seller.
  - Fundraise: `createFundraise` stores name, symbol, logo, supply, target, fee. No token exists yet. Each `contribute` buys at the stepping price (+1.5% per contribution, starting at the 5 ETH virtual price). Overshoot above target is refunded in the same tx. When target is hit, the token is deployed and launched in that tx; raised ETH becomes `reserveETH` (the first buy) and the launch price is the last fundraise price, so market cap continues. Contributors `claim` allocated tokens.
  - Cancel/refund: only the creator can cancel, only before target is reached. Contributors then `refund`.
  - Admin/analytics: `paused` blocks creates, buys, sells, contributions. `traderCount`/`traderAt`, `totalVolume`, and events as in the ABI.
- **Additions to the ABI:** `cancelFundraise(uint256)`, `fundraiseCount()`, `fundraises(uint256)` (creator, name, symbol, logo, supply, target, raised, price, status, token), `fundraiseContribution(uint256,address)` (ETH, tokens allocated, claimed), events `TokenLaunched`, `FundraiseCompleted`, `FundraiseCancelled`, `Claimed`, `Refunded`.
- **Assumptions (to confirm with user):**
  - Sell pays at one 1.5% step below the current price and drops the price one step, so buy then sell nets to about the fee (otherwise a guaranteed 1.5% round-trip profit exists).
  - Trade fee goes to `platformWallet`, capped at 5%. `fundraiseCreationFee` defaults to 0.0001 ETH. Platform wallet and owner default to the deployer.
  - Supply range 1M to 1T tokens (UI default 1B). 100% of supply on the curve, no creator allocation.
  - The 0.0001 ETH is only the one-time token creation fee, charged at launch. It is not a buy fee and not a minimum buy. A buy costs only what the buyer sends, minus the per-token `tradeFeeBps` (set by the creator at launch, per the ABI; the UI can default it to 0).
  - Buys and contributions have a tiny dust floor of 0.00001 ETH, separate from the creation fee. Without a floor, zero-value buys would still bump the price 1.5% each.
- **Known design risk:** fixed +1.5% per buy regardless of size lets someone pump the price with many tiny buys, then sell a large position into others' ETH. The dust floor makes it only slightly costly and does not remove it. Acceptable for testing. Before real use, consider a larger minimum buy or a step that scales with size.
- **Logo upload:** contract stores `logoURI` as a string. UI resizes the device image to about 96x96 WebP in-browser and stores a data URI (capped around 4 KB). No backend. IPFS is a later alternative.
- **Frontend:** React, Tailwind, wagmi + viem, ConnectKit. Multicall for lists and balances; `getLogs` from the deploy block for trade history. Public RPC is rate-limited, so batch requests.
- **Wallet:** ConnectKit (injected) with GIWA Sepolia as the primary chain and a prompt to switch or add the network.

### Files to Create/Modify
1. `contracts/LaunchToken.sol`: fixed-supply ERC-20 minted to the launchpad at creation.
2. `contracts/KgiwaLaunchpad.sol`: the launchpad with the full ABI plus additions.
3. `contracts/test/KgiwaLaunchpad.t.sol`: Foundry tests (price steps, round-trip break-even, reserve cap, fundraise launch, overshoot refund, cancel/refund, pause).
4. `scripts/deploy-giwa.ts`: viem deploy script for GIWA Sepolia; writes address and deploy block to `contracts/contract-metadata/KgiwaLaunchpad.json`.
5. `src/config.ts`: replace template chains with `giwaSepolia` (defineChain) as primary; drop mainnet.
6. `src/contracts/launchpad.ts`: address, deploy block, ABI from artifact, ERC-20 ABI helpers.
7. `src/lib/format.ts`: ETH, token amount, market cap formatting; address shortening.
8. `src/lib/image.ts`: client-side logo resize/compress to data URI with size checks.
9. `src/hooks/useTokens.ts`: `tokenCount`/`tokenAt`/`tokens()` via multicall with name, symbol, logo.
10. `src/hooks/useTrades.ts`: `Trade` event history per token and global.
11. `src/hooks/useFundraises.ts`: `fundraiseCount`/`fundraises(i)` and the user's contributions.
12. `src/components/Nav.tsx`: six tabs (Market, Trade, Launch, Fundraise, Portfolio, Staking), connect button, network and faucet hint.
13. `src/components/TokenLogo.tsx`: logo with initials fallback.
14. `src/components/SearchInput.tsx`: shared search by name, symbol or address.
15. `src/components/MarketPage.tsx`: grid of launched tokens only, with search, price, market cap, volume, trade button.
16. `src/components/TradePage.tsx`: token search/select, buy/sell panel with live quotes and slippage, balance, market cap, recent trades.
17. `src/components/LaunchPage.tsx`: instant launch form (name, symbol, logo upload, supply, trade fee, optional first buy, fixed 0.0001 ETH fee).
18. `src/components/FundraisePage.tsx`: create form and fundraise list with progress; contribute, creator cancel, claim, refund; completed ones link to Trade.
19. `src/components/PortfolioPage.tsx`: ETH balance, holdings with value (via `quoteSell`), total value, created tokens, fundraise positions with claim/refund.
20. `src/components/StakingPage.tsx`: "Coming soon" placeholder.
21. `src/App.tsx`: tab state, layout, shared selected-token state.
22. `.env`: user adds `GIWA_DEPLOYER_PRIVATE_KEY` (testnet-only throwaway) if using the script.

### Build Sequence
1. Write `LaunchToken.sol` and `KgiwaLaunchpad.sol`, compile, run a security review and fixes.
2. Write and run the Foundry tests.
3. Wait for the user to say "deploy". Add `scripts/deploy-giwa.ts`, dry run, deploy to GIWA Sepolia (or Arc Testnet if the fallback is chosen). Record address and deploy block in metadata and `src/contracts/launchpad.ts`.
4. Update `src/config.ts` for GIWA Sepolia; add `format.ts`, `image.ts` and contract config.
5. Build data hooks (tokens, trades, fundraises).
6. Build Nav, App shell, Market and Trade pages.
7. Build Launch page with logo upload and 0.0001 ETH fee.
8. Build Fundraise page (create, contribute, cancel, claim, refund).
9. Build Portfolio page and Staking placeholder.
10. Typecheck and lint, then test end to end in the preview with GIWA test ETH: launch, buy, sell, fundraise to target, cancel and refund.

### Done When
- [ ] Contract matches the user's ABI and includes the listed additions.
- [ ] Contract compiles, tests pass, security review has no unresolved serious findings.
- [ ] Deployed on GIWA Sepolia (or Arc Testnet if fallback chosen); address in metadata and frontend config.
- [ ] Market tab lists only launched tokens, with search.
- [ ] Trade searches a token and buys/sells with quotes and slippage; each buy raises price 1.5%; sells paid from available reserve.
- [ ] Launch creates a token for 0.0001 ETH with a device logo, and it appears in Market.
- [ ] A fundraise shows no token until target is met; reaching target auto-launches with the last price and market cap; only the creator can cancel before target; contributors can refund after cancel or claim after launch.
- [ ] Portfolio shows holdings and value, created tokens, fundraise positions.
- [ ] Staking shows "Coming soon".
- [ ] Typecheck and lint pass.

## Ready to build?
