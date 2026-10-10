# Mo Save — Savings and Spending Redesign Specification

Status: **PLANNED, NOT IMPLEMENTED**. Created 2026-10-10 after client feedback. This is the product specification for GitHub issues MS-01 through MS-18, indexed in [FUNDS_REDESIGN_PROGRESS.md](FUNDS_REDESIGN_PROGRESS.md).

## The real product goal

When opening Mo Save, the owner must immediately answer three questions:

1. **How much have I actually accumulated in savings?** Show real, dedicated Savings assets, distinct from all owned cash or a paper savings challenge.
2. **How much liquid money can I spend now, and where did it go?** Show the Spending fund, categorized recorded expenses, and the difference between spendable cash and expected commitments.
3. **When am I likely to reach my savings target?** Show a scenario-based projected date, the actual pace vs the current plan, and whether the owner is ahead or behind. Never promise an exact future outcome.

A secondary objective is motivating saving through honest, useful progress and reminders linked to real balances, not a disconnected piggy bank.

## Navigation and client journeys

Two prominent financial destinations:
- **Savings**: Savings fund balances by currency and gold, optional reference-based estimated combined valuation, goal earmarks and progress, trend, forecast, milestone reminders, and withdrawal history.
- **Spending**: immediately spendable balances by currency, Add Expense, expected commitments, planned vs actual spending, monthly category summaries and drill-down.

Income receipt, fund allocation, internal transfers, transaction history, initial setup, reference prices, notification preferences, and backup/restore remain accessible without overloading either dashboard. Arabic-only and correct RTL in the shipped UI; these documents and Issues are in English.

### Common workflows

- **Overdue salary**: Dismiss/ignore one past occurrence persistently, or record an actual historical receipt (and, separately, historical expenses if already spent). Ignore is neither income nor a balance adjustment.
- **Recurring salaries**: record received amount, NOT merely the expected amount; then allocate any part to Savings, Spending or explicitly Unallocated. The current Thursday/SYP and start-of-month/USD examples are editable presets only.
- **Other inflows**: gift, sale, bonus, side income, other, with note, actual date, currency. Opening/previously owned funds are initialization rather than newly earned income. Selling an already tracked owned asset must avoid recognizing its value twice.
- **One-off expense**: record date, category, amount, unit, reason/note and paying fund (Spending or Savings). Deduct the chosen fund immediately and count one actual expense. Prevent overdrafts.
- **Planned recurring expense**: edit a bill's expected amount effective in future periods; it is a plan, not a cash debit until payment is recorded. Historic actual spending never changes when a future gas/ampere price changes.
- **Internal fund transfer**: Savings ↔ Spending in the same asset unit, with amount, date and note. Move fund ownership; do not classify as earnings or spending. FX conversion across units is separate, with historical executed rate.
- **Goal**: designate part of already-owned Savings for a goal. Goal progress and optional challenge grid must reconcile to designated Savings and cannot create a second asset. Releasing/withdrawing these funds must reconcile earmarks.
- **Forecast**: adapt to changed salaries, expenses, Thursday counts, goal targets, actual saving pace, and reference FX assumptions.

## Account model and invariants (MS-01 must finalize)

**Owned asset**: a separate unit such as USD, SYP, SYP (N), or gold grams.
**Fund**: Savings, Spending, or Unallocated (temporary intake/migration bucket; never silently label this as saved).
**Balance**: owned quantity resulting from balance-affecting financial ledger entries.
**Earmark**: a portion of an existing Savings asset reserved for one goal; it does not add a new balance.
**Spending expense**: an actual outflow from the explicitly selected fund, recorded by category and date.
**Expected commitment**: a future budget item, not an actual expense.
**Valuation**: a clearly labelled estimate from editable reference FX/gold prices, not historical cost or new money.

Required invariants:

1. For each asset unit, the sum of Savings + Spending + Unallocated holdings equals the ledger-owned balance. Never add unvalued different currencies together.
2. A single receipt creates assets once; fund allocation only assigns those assets, not new income.
3. A transfer inside the app does not increase income or actual expenses or net owned assets.
4. Payment from Savings or Spending decreases the selected fund and owned assets exactly once, and records an expense exactly once.
5. Goal commitments/checked cells cannot collectively exceed eligible real Savings holdings; assigning to a goal is NOT saving new money.
6. FX trades and gold purchases/sales preserve historical executed amounts while reference-rate changes only affect estimates; preserve asset-specific postings.
7. Updates and deletions preserve ledger integrity, uniqueness, event-linked audit trails and no-invalid-negative-holdings constraints.
8. Historic unpaid/ignored salary occurrences and estimated future paydays must never automatically inflate cash or Savings.
9. Old app data for which there is no knowable fund ownership remains visible as Unallocated pending explicit reconciliation; do not fabricate past fund splits.
10. User-adjustable configuration affects the future, not completed financial events.

| Event | Owned assets | Funds | Income report | Actual expense report |
| --- | --- | --- | --- | --- |
| Record salary/gift received | Increases once | Assigned/Unallocated | Increases once | No |
| Record prior opening cash | Increases once | Assigned/Unallocated | No current-earned income | No |
| Ignore overdue payday | Unchanged | Unchanged | No | No |
| Allocate existing receipt | Unchanged | Move Unallocated to selected funds | No | No |
| Move Savings to Spending | Unchanged | Savings decreases; Spending increases | No | No |
| Pay an 80,000 SYP bill from Spending | Decreases 80,000 SYP | Spending decreases | No | +80,000 SYP |
| Pay 100 USD directly from Savings | Decreases 100 USD | Savings decreases | No | +100 USD |
| Assign 100 USD of Savings to goal | Unchanged | Unchanged | No | No |
| Plan next month's utility bill | Unchanged | Unchanged | No | No |
| SYP↔USD conversion / gold purchase | Changes component holdings | Explicitly funded per posting | No | No ordinary expense |

Never silently treat portfolio market appreciation as amount saved, and never add USD/SYP/SYP (N)/gold into one unqualified total. SYP (N) valuation remains undefined until an explicit trusted rule is added.

## Presets and forecasts

All financial presets are user-editable:
- Example Thursday pay: 885,000 SYP; suggested allocation: 540,000 SYP Spending and 345,000 SYP Savings.
- Example monthly USD pay: 300 USD, which can be spent, saved, or split.
- Example planning months: 4 Thursdays → 1,380,000 SYP suggested saving; 5 Thursdays → 1,725,000 SYP suggested saving, plus independently planned USD saving.
- Recurring bills, prices, currencies, paydays, fund split, gold reference and USD/SYP reference rates may change.

The forecast needs both **plan-based pace** and **observed actual pace**, with clear labels, period coverage and assumptions. Future savings are not guaranteed or capped by old example values. Show an ahead/behind comparison only against an explicit baseline plan; for invalid/zero pace show insufficient data, not an invented arrival date. Use real calendar dates. If estimating a multi-currency goal, state valuation assumptions.

## Legacy migration and data safety

Current app starts from SQLite schema v9 and includes challenge contributions that are intentionally non-balance-affecting. The redesign must not mistake those challenge checkmarks for proven physical Savings funds. Preserve all financial events, entries, expense plans, challenge data, user settings, transaction revisions and notifications. Introduce versioned, repeatable migrations and one-time user reconciliation of ambiguous fund assignments. No destructive reset, automatic past-income confirmation, or fake initial deposits.

Backups currently use portable `.mosave` JSON and a strict schema-version match. Before migrating schema, define compatible backup/restore behavior and validation; test upgrade and clean restore. Do not claim SHA-256 checksum alone provides encryption. User data is local and financial, so preserve privacy and accurate balances.

## Critical end-to-end client scenario

1. Dismiss an old already-spent Thursday salary: no balance changes, no repeated overdue prompt.
2. Record an actual 885,000 SYP salary and allocate 540,000 Spending + 345,000 Savings.
3. Log an unplanned 80,000 SYP outing from Spending: 460,000 SYP Spendable; 80,000 in actual expense analytics.
4. Record 300 USD and allocate it to Savings; earmark part of that real balance toward a 3,000 USD goal without adding assets.
5. Spend 100 USD directly from Savings: Savings decreases by 100, month expenses increase by 100 once, goal earmark adjusts if affected.
6. Record an unexpected 50 USD gift with a reason and assign its fund.
7. Change next month's ampere/utility bill only prospectively.
8. Restart and restore backup; verify fund balances, actual expense reports, savings allocations, overdue salary dismissals and realistic forecast still reconcile.

## Delivery and non-goals

- No cloud backend, bank integration, multi-user system, automatic exchange price feed, or AI adviser is requested.
- Existing docs such as PRODUCT, ROADMAP and UX_REDESIGN describe the currently shipped/earlier scope; this new spec supersedes contradictory **future design intentions**, not currently deployed features. Update them as issues land.
- Existing release Issues #28 (APK branding) and #29 (client acceptance/handoff) stay blocked for final sign-off until redesign Issues MS-01..MS-18 meet their acceptance criteria.
- Plan and tracking live in GitHub Issues and [FUNDS_REDESIGN_PROGRESS.md](FUNDS_REDESIGN_PROGRESS.md); code is not implemented merely because a task is documented.
