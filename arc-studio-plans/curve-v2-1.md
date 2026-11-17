## Implementation Plan: Kgiwa Launchpad v2.1 (10x reversible curve, reserve-backed)

Supersedes curve-v2.md.

### Summary
One exponential curve with k = ln 10, fixed 1B-token supply, and a 20M-token virtual pricing reserve that only sets the start price. Buys and sells use the same symmetric math. Every sell is paid from real ETH reserve and reverts if it cannot be paid. Trading fees follow 40/20/20/20 (platform, creator, holders, burn) and never come out of the ETH backing the curve. Nothing is deployed until the new contract passes all tests and a security review.

### 1. Token allocation (fixed, no minting after launch)
- Total supply: 1,000,000,000, minted once at creation to the launchpad, never again.
- Virtual pricing reserve: 20,000,000 tokens (virtual, not real supply). Only sets the start price.
- Curve allocation C (approved): 800,000,000 (80%), sold and bought back along the curve.
- Remaining supply: 200,000,000 (20%), minted at creation, locked in the launchpad forever. No function can sell, move, vest or migrate them; they count in total supply but not circulating supply and earn no holder rewards.
- No DEX migration, no vesting. After the curve sells out, trading continues only by sellers returning tokens to the curve.
- Burn is the only way supply changes (the 20% fee burn). Supply can only shrink.

### 2. Revised math (k = ln 10 ~ 2.302585093)
- Start price p0 = 5 ETH / 20,000,000 = 0.00000025 ETH (2.5e11 wei per token). 5 ETH is virtual only: never deposited, withdrawn or paid. Start FDV on 1B supply = 250 ETH.
- Marginal price at s tokens on the curve: p(s) = p0 * exp(k*s/C) = p0 * 10^(s/C); exactly 10x p0 (0.0000025 ETH) at s = C.
- ETH backing: R(s) = A * (e^(k*s/C) - 1), A = p0*C/k = 200 ETH / 2.302585 ~ 86.86 ETH. R(C) = 9A ~ 781.7 ETH.
- Buy with net ETH n from s0: e^(k*s1/C) = 1 + (R(s0)+n)/A, s1 = (C/k) * ln(1 + (R(s0)+n)/A); tokens out = s1 - s0 rounded down, re-verified so R(s1) - R(s0) <= n.
- Sell x tokens from s0: s1 = s0 - x; gross = R(s0) - R(s1) rounded down; seller fee comes out of gross.
- Examples: 1 ETH at start -> ~3.98M tokens, avg 2.514e-7 ETH, marginal 2.529e-7 ETH after. 50 ETH from start -> ~157.9M tokens, marginal 1.5757 * p0 ~ 3.94e-7 ETH.
- All rounding favours the contract. Fixed-point exp and ln inlined at 18 decimals.
- s = C - curveInventory, including tokens held by traders, unclaimed fundraise allocations, and burned tokens.
- Symmetry caveat: round trip returns ETH minus fees; the burn share moves the curve forward permanently, so it is not exactly zero-cost beyond fees.
- Exit order (honest limit): the curve pays every seller in full from real reserve, but exits are path-dependent. Example: A buys, then B buys higher, then A sells 100% of A's tokens and receives R(sA+sB) - R(sB) (more than A paid). Reserve left is R(sB), so B can still sell all of B's tokens and is paid R(sB), fully funded, but less than B paid. No profit is guaranteed to anyone.

### 3. Reserve invariant
- Per token: reserveETH >= R(s) at all times.
- Buys add net ETH to reserveETH; sells reduce it by exactly R(s0) - R(s1); fees never come out of it.
- A sell reverts with InsufficientReserve if payout > reserveETH (cap-to-reserve behaviour removed).
- Contract-level: ETH balance >= sum per token (reserveETH + holder pool + creator fees) + active fundraise contributions.
- No minting; a sell never creates tokens; returned tokens go back to curveInventory and lower s.
- Burn keeps the invariant. Burn-buy runs after the main trade state is final, using the same buy function: reserveETH += burnETH; t = tokens bought for burnETH from current s (rounded down, verified R(s+t) - R(s) <= burnETH); s += t (curveInventory -= t); the t tokens are burned from the launchpad's own balance (totalSupply -= t). Because reserveETH >= R(s) before and the added ETH covers R(s+t) - R(s), reserveETH >= R(s+t) after. If curve inventory cannot supply t, t is capped to what is left and the unspent ETH stays in the reserve. After a sell, reserve0 - gross >= R(s1) holds because gross is rounded down, so adding the burn ETH back still covers the advanced position.
- Burned tokens permanently advance s, so the curve can never retrace below the burned amount; the ETH that bought them stays in the reserve forever as extra backing.

### 4. Fee distribution (creator-selected tradeFeeBps, 1% to 3% only)
- Trade fee is chosen by the creator at launch and must be between 100 and 300 bps (1% to 3%). No 0% and no 5%. The UI offers 1%, 2% and 3%.
- Buy: fee taken from ETH sent, only net goes to reserve. Sell: fee taken from seller's gross proceeds.
- Split of every fee: 40% platformWallet (immediate); 20% creator (accrued, claimable); 20% holders; 20% burn. Any rounding remainder goes to the platform so the four parts always sum to the fee.
- Holders 20%: balance-weighted over circulating holders using dividend accounting in the token. The launchpad's own balance is excluded, which covers the 200M locked tokens, unsold curve inventory and unclaimed fundraise allocations. Burned tokens are gone. If no circulating holders exist at that moment, the holders share goes to the platform.
- Holder rewards cannot be claimed twice: each account has a withdrawn counter that is updated before ETH is paid, and claims are non-reentrant. Transfers to and from the launchpad adjust the accounting so new holders never earn past distributions.
- Burn 20% (approved): a real curve purchase, as described in the invariant section. The burn ETH is added to reserveETH, the curve position s advances, and the purchased tokens are permanently burned.
- Instant creation fee stays at 0.0001 ETH, paid to the platform wallet.
- Fundraise creation fee is restored to 0.05 ETH, paid to the platform wallet, and the owner can change it with setFundraiseCreationFee. The setter for the instant fee stays (the ABI requires it) with default 0.0001 ETH.

### 5. Fundraise mechanics
- Target range 0.01 to 50 ETH, with capacity and reserve checks.
- Creation costs the fundraise creation fee (0.05 ETH by default, owner-configurable). It is not refunded on cancel.
- At creation: require target <= R(C) and allocation fits curve inventory (50 ETH uses ~19.7% of the curve).
- Contributions buy along the same curve from s = 0 as allocations (no token yet); capped to remaining target with excess refunded; no trade fee on contributions; each contribution checked against curve capacity before acceptance.
- On fill: deploy token, set s = total allocated, launch price = marginal price at that s, raised ETH becomes reserveETH (>= R(s) by construction); contributors claim.
- Cancel: only the creator, only before fill; contributors refund exactly their contribution.

### Files to Create/Modify
1. contracts/KgiwaLaunchpad.sol: curve, reserve-backed sells, fee split, fundraise validation, fixed supply, new views and claim functions.
2. contracts/LaunchToken.sol: fixed 1B supply, launchpad-only burn, holder-reward accounting excluding the launchpad.
3. contracts/test/*.t.sol: rewrite tests:
   - curve reversibility: buy then sell returns ETH minus fees within a few wei; buys split in pieces never beat one buy
   - reserve invariant reserveETH >= R(s) after every buy, sell, burn-buy and fundraise launch (fuzz and invariant tests)
   - sell reverts with InsufficientReserve when the reserve is forced short
   - first buyer sells 100% of their tokens while later buyers can still sell all theirs, each paid in full from reserve
   - fee accounting: the four parts sum to the fee, platform paid, creator accrues and claims, holders share, remainder to platform
   - burn accounting: reserve increases by the burn ETH, s advances, totalSupply drops by the burned tokens, supply never rises, tokens bought on the curve and burned
   - holder rewards: cannot be claimed twice, excluded launchpad balance, locked 200M, unclaimed allocations and burned tokens earn nothing, new holders do not earn past distributions
   - fee limits: trade fee 1% to 3% only; instant creation fee 0.0001 ETH; fundraise creation fee 0.05 ETH and owner-configurable
   - fundraise: capacity checks at 0.01 and 50 ETH, targets outside the range revert, contributions that exceed capacity revert, launch price continuity, reserve backing, cancel and refund exactly returns contributions, only creator can cancel before fill
   - no minting after launch (total supply never increases)
4. remix/KgiwaLaunchpad.sol: regenerate the single Remix file.
5. src/contracts/launchpadAbi.ts, src/contracts/launchpad.ts: new ABI, fixed supply, target range 0.01-50 ETH, new address and deploy block.
6. src/components/TradePanel.tsx: real price impact, fee breakdown, reserve-short message.
7. src/components/TokenFields.tsx, LaunchPage.tsx, CreateFundraise.tsx: remove supply input, show curve facts, update target limits.
8. src/components/PortfolioPage.tsx: show and claim holder rewards and creator fees.
9. src/components/MarketPage.tsx, TradePage.tsx, FundraiseCard.tsx: update labels.
10. README.md, AGENTS.md: update docs.

### Build Sequence
1. Write contract and token; compile.
2. Balanced security review with fixes (fixed-point math, fee accounting, burn-buy, holder rewards).
3. Static analysis; write and run all tests.
4. Nothing is deployed, and no Remix code is handed out, until compilation, tests, static analysis and the security review are all complete and clean. Then regenerate and compile-check the Remix file and give the full code.
5. User deploys in Remix and sends the address and deploy block.
6. Update the frontend; lint, typecheck, build, redeploy to Vercel.

### Done When
- [ ] Price is 0.00000025 ETH at the start and exactly 10x at the end of the curve allocation (k = ln 10).
- [ ] Supply is 1B at creation, 200M permanently locked, nothing minted afterwards.
- [ ] The 5 ETH virtual liquidity is never withdrawable or payable.
- [ ] Buy and sell use the same R(s); sells revert when the reserve cannot pay; reserveETH >= R(s) holds in tests.
- [ ] Fee splits 40/20/20/20, every part works, and fees never reduce curve backing. Creator trade fee is limited to 1%-3%.
- [ ] Burn is a real curve purchase: its ETH is added to the reserve, s advances, the tokens are burned, and the reserve invariant still holds.
- [ ] Holder rewards cannot be claimed twice, and the launchpad balance (including the locked 200M) and burned tokens are excluded.
- [ ] The first buyer can sell 100% of their tokens and later buyers can still sell, each paid in full from available reserve.
- [ ] Instant creation costs 0.0001 ETH; fundraise creation costs 0.05 ETH and is owner-configurable.
- [ ] Fundraises accept only 0.01-50 ETH targets that fit the curve and launch at the last fundraise price with raised ETH as the real reserve; cancel and refund return contributions exactly.
- [ ] All tests pass, review has no unresolved serious findings, and nothing is deployed before that.

## Ready to build?
