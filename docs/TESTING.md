# Mo Save — Automated testing and migration QA

## Test command

Run the local automated suite from the repository root:

```bash
flutter test
```

The suite uses isolated temporary SQLite databases through `LocalDatabase.forTesting(...)`. Test databases are created with `sqflite_common_ffi`, closed after each test, and never reuse the production `mo_save.db` file.

## Covered financial rules

- Challenge cell generation always sums exactly to the target.
- USD, SYP, and SYP (N) challenge cells respect their denomination step.
- Ordered/reversed sequencing remains monotonic, and resequencing preserves completed savings.
- Goal pace calculations round up to the active denomination step.
- Separate USD/SYP/SYP (N)/gold balances and reference-only valuation rules.
- Missing SYP/gold reference values make an estimate incomplete instead of guessing.
- Non-zero SYP (N) remains excluded from the combined USD estimate until a defined valuation rule exists.
- Real-calendar recurring income with both four- and five-Thursday months.
- Monthly payday 29–31 clamps to the real last day in shorter months.
- An actual 885,000 SYP salary can be split 540,000 Spending / 345,000 Savings, with one income event and exact per-fund totals after reload.
- Actual 300 USD monthly receipts support a user-edited split with nonzero Unallocated remainder, not mandatory all-Savings classification.
- Prior spending reduces distributable cash before savings/spending allocations; 885k received minus 80k historic expense may produce 345k Savings + 460k Spending with zero Unallocated, preserving exactly one expense.
- Invalid allocations fail before any partial receipt is written; manual split retries are idempotent for identical postings, and conflicting reuse fails.
- MS-07 Spending dashboard shows exactly the per-unit Spending holdings; Savings USD, unallocated SYP and physical gold cannot inflate available liquidity.
- Monthly recurring planned bills do not debit actual Spending cash; the after-full-plan figure is explicitly a hypothetical scenario, not an unpaid-bills calculation.
- Actual spending is counted once from the paying fund; Spending-funded monthly expense is distinguished from total expenses across all funds.
- A Spending-only quick expense rejects insufficient Spending funds even when overall assets or Savings would cover it; ledger and fund totals do not change.
- Fund-filtered history includes actual receipts/expenses involving Spending and retains deleted-event revisions and amount corrections.
- A 50 USD manual gift is a single real-income receipt; Savings and owned-asset totals increase exactly once.
- Opening pre-existing cash records an owned asset but is **not income** in period aggregates; Unallocated remains a separate bucket.
- Stable manual entry request keys prevent duplicate receipts while rejecting changed-payload retries.
- One-off cash receipts reject tracked gold, future dates, non-positive values and item-sale income without explicit untracked-item confirmation.
- Correcting manually entered income preserves event type/fund and the original revision snapshot; manual dates may be corrected without relaxing recurring-payday date rules.
- Ignoring a specific old payday persists after database restart and can be undone without writing income or balances.
- A confirmed ignored payday is rejected; the receipt and ignore disposition cannot coexist.
- Actual historical salary receipt and its already-spent amount are two linked atomic events, and the net balance is zero when the salary was spent in full.
- Receipt uniqueness survives repeated confirmation; changed salary defaults do not hide already-recorded historical occurrences.
- Weekly envelope defaults clamp to the actual received salary.
- Weekly envelope allocation remains non-balance-affecting and cannot be duplicated.
- Actual expenses cannot exceed the designated paying fund's balance; quick Spending payments never spend Savings or Unallocated cash.
- SYP↔USD conversions reconcile source/destination balances and persist the executed rate.
- Gold purchases reconcile cash-out and gram-in postings without double counting.
- Insufficient cash prevents conversion/gold purchase mutations.
- Challenge-grid progress keeps one canonical non-balance saving contribution and removes it when progress returns to zero.

## Current verification status

The MS-02 through MS-07 regression cases have been committed, but the owner requested **no CLI checks**, so these cases have **not been executed**. No successful runtime, analyzer, Android build, real-client database upgrade or device acceptance is claimed. They remain verification obligations before client delivery (MS-18).

## Migration QA

The migration suite covers two upgrade paths that contain client data:

1. A real schema-v1 SQLite file is created, populated with a challenge and cells, then opened through the current `LocalDatabase`. The test verifies upgrade to schema v10, preservation of challenge data, and presence of the later ledger/settings/expense/revision schema.
2. Legacy `saving_challenges_v1` SharedPreferences JSON is loaded through `ChallengeStorage`, migrated once into SQLite, removed from the legacy store, and reconciled into the canonical challenge-progress ledger event when completed cells already exist.

These tests are intended to catch accidental missing migrations, destructive schema changes, duplicate legacy imports, and challenge/ledger divergence before release.

## Widget smoke coverage

`expense_plan_widget_test.dart` exercises one complete persisted create → edit → delete flow against an isolated SQLite database, including the destructive-delete confirmation dialog and the resulting empty state.

## Known boundaries

The automated suite intentionally does not treat mutable reference prices as historical accounting data. It also does not attempt OS-level verification of Android notifications, file-picker UI, app signing, or installation/update behavior; those remain release/acceptance checks in Issues #28 and #29.

The suite does not invent a SYP (N) exchange rate. Any future product decision that defines such a rate must add valuation tests before enabling it in the combined total.
