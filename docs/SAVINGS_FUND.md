# MS-12 — True Savings Fund Dashboard

**Issue:** [#86](https://github.com/Sherko231/mo_save/issues/86)  
**Status:** Implementation and regression tests committed directly to `main`. **No Flutter tests, analyzer, APK, migration or device QA executed.**

## What counts as Savings

The new Arabic Home section **صندوق الادخار الحقيقي** sits above the Spending dashboard. Its current amount is **only** `FinancialFund.savings` for every asset unit, as calculated by the canonical, active SQLite fund ledger:

```text
Owned[unit] =
  Savings[unit] + Spending[unit] + Unallocated[unit]
```

It shows USD, SYP, SYP (N), and physical gold **separately** and clearly distinguishes each saved quantity from all owned assets of the same unit. Spending cash, Unallocated/migrated assets, a paper challenge grid, expected salaries, unpaid bills and future plans **do not increase Savings**.

Gold grams are **physical non-spendable Savings**, not ready-to-spend cash. The existing Unallocated reconciliation link allows a user to explicitly classify previously owned assets into Savings, without recording new income; it never auto-promotes old ambiguous balances. The MS-10 Savings↔Spending transfer action and history shortcut are available beside this live summary.

### Exact real-world sequence

| Event | Real USD Savings | USD Spending | USD Unallocated | Total owned USD |
| --- | ---: | ---: | ---: | ---: |
| Receive 300 USD into Savings | 300 | 0 | 0 | 300 |
| Transfer 100 USD Savings→Spending | 200 | 100 | 0 | 300 |
| Pay 20 USD **directly from Savings** | **180** | **100** | 0 | **280** |
| Register 50 USD previously owned, Unallocated | 180 | 100 | 50 | 330 |

An old `savingContribution` checkmark with `affects_balance=false` does **not** increase Savings. Neither a goal challenge's target nor its completed checkmarks are converted into new assets.

## Monthly additions, withdrawals and honest trends

Current month and the preceding **five** calendar months are derived from active ledger events by their actual `occurredAt` calendar month, using fixed-point integer micro-units. A user-selectable unit controls this display (including gold, separately).

- **Received into Savings**: positive balance-affecting receipts with `type=income` and Savings fund.
- **Transferred in**: positive side of a `fundTransfer` into Savings, including explicit Unallocated reconciliation. This is *funding/reclassification*, **not newly earned income**.
- **Withdrawn from Savings**: negative Savings entries of actual `expense` events, and outbound Savings `fundTransfer` postings; direct-from-Savings spending is counted once.
- **Opening Savings**: opening-balance quantities displayed separately (not earned income or an ordinary contribution).
- **Conversions and gold trades**: signed movement in unit quantities from `currencyConversion`, `goldPurchase`, `goldSale`. These are a reshuffling of assets, not new saving contributions.
- **Other adjustments**: explicit/manual adjustments or other balance-affecting legacy entries; not automatically treated as earned savings. Non-balance goal/grid entries are ignored.

```text
net funding[unit] = received + transferred in
                   - actually paid from Savings - transferred out

net monthly fund movement[unit] = net funding
                   + opening + conversions + other adjustments
```

The six-month list shows the **signed actual net fund movement** of each month, not historic market prices or forecast growth. It does not infer a total net worth from mixed units; a displayed current balance is always **now**, not the balance of a selected historical month. Ledger corrections and deletions update the derived movement when refreshed while keeping their earlier snapshots accessible through Transaction History.

## Reference-only valuation

The combined card uses the **existing `FinancialBalanceSnapshot` rules**, but creates the snapshot from **Savings entries only**, not all owned balances. Estimates are calculated at view time:

```text
estimated Savings USD =
  saved USD
  + (saved SYP / user-entered reference SYP-per-USD)
  + (saved gold grams × user-entered reference gold USD-per-gram)
```

The card labels this **قيمة تقريبية للادخار فقط**, not earned income, new principal or a realizable sale value. If a nonzero SYP balance has no reference FX rate, gold has no reference gram price, or SYP (N) is nonzero (there is **no approved rate**), the complete combined estimate is **unavailable** and actionable warnings are shown. Partial estimates are never labeled as total. Editing reference rates changes **only this estimate**: it does not change `financial_event_entries`, any historical executed FX/gold quantity, the number of saved units, or monthly net-funding flows.

**Example:** 100 USD Savings + 1,500,000 SYP Savings + 2 saved gold grams, using 15,000 SYP/USD and 100 USD/g, gives a reference-only 400 USD valuation. Changing only reference values to 30,000 SYP/USD and 150 USD/g yields **450 USD estimated**; actual USD/SYP/gram quantities remain exactly the same.

## Explicit goal boundary

MS-12 introduced current Savings totals; **MS-13 now also exposes verified goal reservations and free/unreserved Savings per currency**. Goal checked cells count as actual progress only after an explicit backing record covered by real Savings. Old unverified goals require a user choice; see [GOAL_EARMARKS.md](GOAL_EARMARKS.md). Forecast dates and motivation remain MS-14/15.

## Implementation and unverified tests

- `lib/services/savings_fund_service.dart`: current canonical fund/owned balance reconciliation, isolated Savings reference valuation, categorized monthly real movement and 6-month per-unit trend. No new persistent tables, mutation or balance cache.
- `lib/pages/home_savings_fund_section.dart`: Arabic/RTL live Savings section, all four asset holdings, reference-only valuation and incomplete-reference warnings, net movement breakdown, six-month trend, legacy Unallocated prompt, history/fund transfer actions; refreshes on ledger events and Home refresh.
- `lib/pages/home_page.dart`: renders Savings section next to Spending, above the original overview of other account-owned assets.
- `test/savings_fund_service_test.dart`: income split, Spending/Unallocated isolation, incoming/outgoing fund reclassification, direct Savings expense, paper challenge exclusion, gold transaction classification and reference price changes, unknown SYP (N) value, month boundaries, audited expense correction/deletion.
- `test/savings_fund_page_test.dart`: RTL Savings balance UI and recalculation after an internal transfer, while total owned assets stay unchanged.

**None of these tests were run.** Flutter analyzer, APK build, target Android installation and real client SQLite v11 restore/migration checks remain release obligations under MS-18 (#92). No new schema/backup migration is needed for this source-only MS-12 feature.
