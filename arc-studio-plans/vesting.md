## Implementation Plan: Fundraise vesting (instant, 24 hours, 48 hours)

### Summary
When a creator publishes a fundraise they choose how contributors receive tokens after it fills: instantly, or unlocked hourly over 24 or 48 hours. This needs a new contract version (v2.2) because the vesting rules live onchain; deployed v2.1 cannot change, so the user redeploys in Remix and the app switches to the new address. Nothing is deployed until the new contract passes compilation, tests, static analysis and a security review.

### Architecture
- Chain: GIWA Sepolia (91342). v2.2 = v2.1 plus vesting. Curve, 1B supply and 200M locked, fees, burn, holder rewards, admin functions and the 0.05 ETH fundraise fee stay exactly as they are.
- Creator choice: new function createFundraiseVested(name, symbol, logoURI, supply, targetETH, tradeFeeBps, vestingHours) with vestingHours in {0, 24, 48}; anything else reverts. Existing createFundraise stays and means instant (0).
- Schedule starts when the fundraise fills and the token launches. Each contributor's full allocation is split into N equal hourly parts (N = 24 or 48). After 1 hour 1/N is claimable, after 2 hours 2/N, ... all after N hours. Instant: everything claimable at launch. Assumption: the first unlock comes 1 hour after launch, not at launch.
- claim(id) pays the vested but unclaimed amount and can be called many times; reverts NothingToReceive if nothing is available. The last step pays the remainder so total claims equal the allocation exactly (no rounding dust stranded). Claims work while paused.
- Unclaimed tokens stay in the launchpad: already counted as sold on the curve and excluded from holder rewards (launchpad balance excluded), so the reserve invariant and the 200M lock are unchanged. No new minting.
- Refunds unchanged: cancelled or expired fundraises refund exact ETH. Vesting applies only after fill.
- New views: fundraiseVesting(id) returns vesting hours and launch time; claimableOf(id, user) returns vested-but-unclaimed; fundraiseContribution keeps its shape and claimed becomes true once fully claimed.
- Contract size: v2.1 ~20.5 KB, limit 24 KB; verify after the change.

### App changes
- Create fundraise form: "Token release" selector with three cards (Instant, 24 hours, 48 hours) with a one-line explanation.
- Fundraise cards and Portfolio: show release type; for launched fundraises show claimable now, total, progress bar, countdown to next unlock; Claim claims what is available.

### Files to Create/Modify
1. contracts/KgiwaLaunchpad.sol: vesting fields, createFundraiseVested, multi-step claim, fundraiseVesting, claimableOf.
2. contracts/test/*.t.sol: update fundraise tests and add vesting tests.
3. remix/KgiwaLaunchpad.sol: regenerate single-file Remix version.
4. src/contracts/launchpadAbi.ts, src/contracts/launchpad.ts: new ABI and vesting options.
5. src/hooks/useFundraises.ts: read vesting hours, launch time, claimable.
6. src/components/CreateFundraise.tsx: three-way release selector.
7. src/components/FundraiseCard.tsx: vesting progress, countdown, claim flow.
8. src/lib/errors.ts: message for an invalid vesting choice.
9. README.md, AGENTS.md: document vesting and the new contract version.

### Build Sequence
1. Write the v2.2 contract change and compile.
2. Balanced security review with fixes, then static analysis.
3. Write and run tests: instant, 24h and 48h schedules at exact hourly boundaries; multiple claims summing to exact allocation; no double claim; invalid vesting value reverts; claim while paused; refunds and cancel unaffected; invariants (launchpad balance = 200M locked + inventory + unclaimed vesting; reserve invariant) still hold.
4. Only after everything is clean: regenerate the Remix file and hand over the full code. No deploy.
5. User deploys in Remix and sends the new address and deploy block.
6. Update the frontend; lint, typecheck, build, redeploy to Vercel.

### Done When
- [ ] A creator can choose Instant, 24 hours or 48 hours when publishing a fundraise.
- [ ] After fill, contributors can claim 1/N of their allocation each hour (N = 24 or 48), or everything immediately for Instant.
- [ ] Repeated claims sum to exactly the full allocation, with no double claims and no stranded tokens.
- [ ] Refunds, cancel and expiry work exactly as before.
- [ ] Reserve invariant, 200M lock and holder-reward exclusions still hold.
- [ ] The app shows release type, claimable now, progress and next unlock time.
- [ ] Compilation, tests, static analysis and security review complete before anything is deployed.

### Things to know
- Needs a redeploy; the new contract has a new address. v2.1 and anything created on it stay as they are but will not show in the new app.

## Ready to build?
