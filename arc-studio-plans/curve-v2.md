## Implementation Plan: Kgiwa Launchpad v2, reversible exponential curve with reserve-backed sells

### Summary
Replace the "+1.5% per buy" pricing with one exponential curve driven by net tokens sold. Buys and sells walk the same curve in both directions. Sells are paid from real ETH reserve and revert if the reserve cannot cover them. Fees are always kept separate from the ETH backing the curve. The deployed v1 contract (0xfa64E5578704238E16672aF648889d0ce074362b) has no tokens, so v2 is a fresh deploy with nothing to migrate.

### Architecture
- **Blockchain:** GIWA Sepolia testnet (91342), native ETH.
- **Fixed parameters:**
  - Supply per launch fixed at 20,000,000 tokens (assumed from the 5 / 20,000,000 note).
  - Start price 5 / 20,000,000 = 0.00000025 ETH. The 5 ETH is virtual: it only anchors the price and is never deposited or paid out.
  - Marginal price grows exponentially to 4x at full sell-out (0.000001 ETH per token at the end).
  - Selling out the whole curve costs about 10.82 ETH of real buyer ETH.
- **Curve math:** s = net tokens sold, S = 20M.
  - Marginal price p(s) = p0 * 4^(s/S).
  - ETH backing for s tokens R(s) = A * (4^(s/S) - 1), A = p0 * S / ln 4 (about 3.61 ETH).
  - A buy of `net` ETH moves s forward so R(s1) - R(s0) <= net. A sell moves s back and pays R(s0) - R(s1). Both use the same R, so price and backing are path-independent.
  - Reserve >= R(s) always, so every sell the curve prices is fully funded by construction.
  - Rounding favours the contract: tokens out round down, buy cost rounds up, sell payout rounds down. Fixed-point exp and ln are inlined (MIT-style), keeping the contract a single Remix file.
- **Net tokens sold, not issued:** track sold = supply - curveInventory. Tokens returned by sellers go back to curveInventory and lower sold. A sell never counts as a new issuance; nothing is minted after creation. tokens(address): price = current marginal price, curveInventory = S - sold, reserveETH = real ETH backing.
- **Real reserve protection:** sell reverts with InsufficientReserve if the payout cannot be funded (the old cap-to-reserve behaviour is removed). Virtual ETH is never withdrawable or paid. Invariant: reserveETH >= R(sold).
- **Fees separate from backing:**
  - Buy: tradeFeeBps fee taken off the ETH sent; only the net goes to reserveETH.
  - Sell: reserve drops by exactly R(s0) - R(s1); the fee is deducted from the seller's proceeds and paid to the platform wallet.
  - Creation fees (0.0001 ETH) go straight to the platform wallet, never the reserve.
  - Assumption: the whole trade fee goes to platformWallet (creator share only if requested).
- **Fundraise on the same curve (assumed):** contributions buy along the curve from sold = 0 as allocations (no token yet). On target fill, deploy the token with sold = total allocated; launch price = marginal price at that point; raised ETH becomes reserveETH (reserve >= R(sold)). Contributors claim afterwards. Only the creator can cancel before fill; contributors refund after cancel. Max target 10 ETH (up from 4) so a target is always reachable before sell-out.
- **Fixes the v1 dust-pump risk:** price depends on tokens sold, not trade count, so splitting a trade cannot beat one trade.
- **Honest limit:** no bonding curve guarantees unlimited liquidity or protects traders when price falls. This design guarantees every curve-priced sell is fully funded, not a profit.
- **Unchanged:** full ABI and admin functions, 0.0001 ETH creation fee, 0.00001 ETH dust floor, no ownership renouncing, pause semantics.
- **ABI additions:** quoteBuyDetail(token, ethAmount) returning tokens out, fee, new price; quoteSellDetail(token, tokenAmount) returning ETH out, fee, new price. quoteBuy/quoteSell remain.
- Supply is fixed, so Launch and Fundraise forms drop the supply input.

### Files to Create/Modify
1. contracts/KgiwaLaunchpad.sol: exponential curve, reserve-backed sells, InsufficientReserve, detail quotes.
2. contracts/test/*.t.sol: rewrite tests (round trips, split-trade non-advantage, reserve >= R(sold) invariant, sell reverts when reserve is forced short, fundraise-to-launch continuity, fees never reduce backing).
3. remix/KgiwaLaunchpad.sol: regenerate the single-file Remix version, compile and size-check.
4. src/contracts/launchpadAbi.ts, src/contracts/launchpad.ts: new ABI, fixed 20M supply, 10 ETH max target, new address and deploy block.
5. src/lib/format.ts: launch price from fixed supply, curve info helpers.
6. src/components/TradePanel.tsx: use detail quotes, real price impact, reserve-short message.
7. src/components/TokenFields.tsx, LaunchPage.tsx, CreateFundraise.tsx: remove supply input, show fixed curve facts, raise target limit to 10 ETH.
8. src/components/FundraiseCard.tsx, MarketPage.tsx, TradePage.tsx: update labels and since-launch for the new curve.
9. scripts/deploy-giwa.ts, README.md, AGENTS.md: update docs and pricing notes.

### Build Sequence
1. Write the new contract; security review (balanced) with fixes, extra attention to fixed-point exp/ln edge cases.
2. Static analysis, then write and run tests.
3. Regenerate and compile-check the Remix single file; give the full code for pasting.
4. User deploys in Remix; wait for the new address and deploy block (deploy only on request).
5. Update ABI and frontend (forms, trade panel, labels, new address).
6. Lint, typecheck, rebuild, redeploy to Vercel.

### Done When
- [ ] Start price is 0.00000025 ETH; marginal price is 4x at full sell-out.
- [ ] Buy then sell returns the same ETH minus fees within rounding; splitting a trade never beats one trade.
- [ ] Sells return tokens to curve inventory and lower sold; no minting after creation.
- [ ] Sells revert with InsufficientReserve if the reserve cannot pay; invariant reserveETH >= R(sold) holds in tests.
- [ ] Trade and creation fees never reduce the ETH backing the curve.
- [ ] A fundraise fills at curve prices, launches at the same price, and its raised ETH is the reserve; cancel and refund still work.
- [ ] Review has no unresolved serious findings; all tests pass.
- [ ] Remix code provided, app updated and redeployed to Vercel, old contract unused.

### Open items (assumed)
- Fixed 20M supply per launch.
- Fundraises use the same curve.
- Whole trade fee goes to the platform wallet.

## Ready to build?
