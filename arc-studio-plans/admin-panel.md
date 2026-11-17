## Implementation Plan: Admin panel, plain-number prices, and cleanup

### Summary
Add an owner-only Admin tab for treasury and fee management plus trader tracking, change price display from scientific notation to plain decimals like 0.00000025 ETH, remove the Arc Studio watermark, and remove the "Price at sell-out / 10x the start price" row from the info card. The deployed contract (0x7953Ac57b6465665ABA819248abFf77F34592b1B, GIWA Sepolia) is not touched: no redeploy, front-end changes plus a Vercel rebuild.

### Architecture
- Chain: GIWA Sepolia (91342). All admin actions use functions that already exist: owner, platformWallet, setPlatformWallet, fundraiseCreationFee, setFundraiseCreationFee, traderCount, traderAt, totalVolume.
- Access: the Admin tab only appears when the connected wallet equals owner(). The contract also enforces owner-only on writes, so the hidden tab is a convenience, not the security.
- Treasury address: show the current platform wallet and its live ETH balance with an explorer link; let the owner change it with setPlatformWallet after validating (valid, non-zero) and a confirm step.
- Fees collected (kept as is, no claim button, per the user's choice): platform share and creation fees are paid straight to the treasury. The panel shows totals: platform trade-fee share summed from FeesDistributed events; fundraise creation fees summed from the ETH sent in each FundraiseCreated transaction; instant launch fees counted from instant launches times the current instant fee; a grand total. It also shows what the contract still holds for others (creator fees unclaimed, holder pools, curve reserves), read live; the owner cannot claim these.
- Traders and volume: trader list from traderCount/traderAt (complete); per-wallet trades, buy volume, sell volume and total volume aggregated from Trade events scanned in block windows from the deploy block. Search, sort by volume, trades or address, a copy button per address, "Copy all addresses" (one per line, with a toast), and "Copy as CSV" (wallet, trades, buy ETH, sell ETH, total ETH). Limit: the public RPC is rate-limited, so volume scans cover a bounded lookback shown in the panel; the address list is always complete.
- Only the fundraise creation fee is editable: current value shown (default 0.05 ETH), setFundraiseCreationFee behind it, typo guard 0 to 10 ETH and a confirm step. No control for the instant fee, pause or ownership.
- Price display: fmtPrice and the small-value branch of fmtEth print fixed decimals, never exponents (e.g. 0.00000025 ETH, 0.0000002512 ETH), about 4 significant digits, trailing zeros trimmed. Applies to Market, Trade, Portfolio and Admin.
- Remove the Arc Studio mark: delete the floating watermark in src/main.tsx.
- Remove the "Price at sell-out / 10x the start price" row from the CurveFacts card (the only place it appears, on the Launch page).

### Files to Create/Modify
1. src/lib/format.ts: plain-decimal fmtPrice and fmtEth for tiny values.
2. src/main.tsx: remove the Arc Studio watermark component and its render.
3. src/components/CurveFacts.tsx: remove the "Price at sell-out" row.
4. src/components/Nav.tsx: add the owner-only Admin tab.
5. src/App.tsx: route to the Admin page.
6. src/hooks/useAdmin.ts: owner, platformWallet, treasury balance, fundraiseCreationFee, totalVolume, trader count.
7. src/hooks/useFeeTotals.ts: sum platform and creation fees from events; read held-by-contract totals.
8. src/hooks/useTraderStats.ts: trader list plus per-wallet aggregation from Trade events.
9. src/components/AdminPage.tsx: layout and owner gate (clear "Owner wallet only" message for non-owners).
10. src/components/AdminFees.tsx: totals cards.
11. src/components/AdminTraders.tsx: searchable table, per-address copy, Copy all addresses, Copy as CSV.
12. src/components/AdminSettings.tsx: treasury address and fundraise creation fee forms with confirm steps.
13. README.md, AGENTS.md: document the Admin tab.

### Build Sequence
1. Fix price formatting, remove the watermark, remove the "Price at sell-out" row.
2. Add admin hooks (owner and settings, fee totals, trader stats).
3. Build the Admin page: fee cards, traders table with copy buttons, settings forms.
4. Add the owner-only tab and route.
5. Lint, typecheck, build; verify in the preview with the owner wallet.
6. Redeploy to Vercel (no contract change).

### Done When
- [ ] Prices everywhere read like 0.00000025 ETH with no e-7.
- [ ] The Arc Studio mark is gone.
- [ ] "Price at sell-out / 10x the start price" no longer appears.
- [ ] The Admin tab shows only for the contract owner wallet.
- [ ] The panel shows the treasury address and live balance and lets the owner change the treasury address.
- [ ] It shows total fees collected (platform trade-fee share, creation fees, total) plus creator fees, holder pools and reserves still held by the contract.
- [ ] It lists all trader wallets with trades and volume; per-address copy, Copy all addresses and Copy as CSV work.
- [ ] The owner can edit only the fundraise creation fee.
- [ ] Lint, typecheck and build pass and the app is live on Vercel.

## Ready to build?
