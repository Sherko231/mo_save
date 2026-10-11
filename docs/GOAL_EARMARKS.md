# MS-13 — Real Savings-backed Goals

Issue: https://github.com/Sherko231/mo_save/issues/87

**Source implementation committed directly to main. Automated tests, analyzer, APK and Android/device verification NOT run.**

## Accounting contract

SQLite schema v12 adds goal_earmarks(challenge_id PRIMARY KEY referencing challenges with ON DELETE CASCADE, unit usd/syp/sypNew, amount_micros >= 0, verified_at_ms). Each verified goal reservation equals the fixed-point micro sum of its completed grid cells in the same unit. Goal earmarks reserve existing Savings. They do not create a new owned asset, income, payment, bank balance or gold. Per asset unit:

- Owned = Savings + Spending + Unallocated
- SUM(verified goal earmarks) <= Savings
- Free Savings = Savings - SUM(verified goal earmarks)

Earmark 100 USD for a goal while holding 200 USD Savings: the goal shows 100 USD backed, owned USD stays 200, Savings USD stays 200, free Savings falls to 100. Separate goals cannot reuse that pledged USD. Gold is not a supported currency for goal earmarks, and no SYP/USD or SYP (N) exchange rate is invented.

## Authorized goal edits and withdrawals

New goals start with verified zero reserved. Checking or unchecking a grid cell changes the persisted grid and verified goal amount inside one SQL transaction, enforcing enough **free Savings** after considering other goal reservations. Undoing a cell releases its amount; deleting a goal releases the reservation through the goal foreign-key cascade. Existing non-balance savingContribution events are still an audit-compatible reflection of checked cells; they never increase assets.

The shared ledger safety guard checks that all verified reservations still fit current Savings after every posted event, transfer, correction or deletion. A direct Savings expense, Savings->Spending transfer, FX conversion or gold purchase that would underfund a goal fails atomically with GoalBackingInsufficientException. The UI explains that the user must release goal cells before using that money. This is an explicit freeze-until-release policy, **not** silent mutation of old completed cells. Ordinary Spending-only payments remain independent. History revisions continue to preserve actual prior ledger events.

The live Savings dashboard displays **محجوز لأهداف موثّقة** and **حرّ من الادخار** by cash currency while retaining the full Savings and owned balances separately. Reference FX and gold prices remain presentation-only.

## Legacy goal reconciliation: never guess history

SQLite v9/v10/v11 challenge grid data and nonbalance challenge-contribution records are preserved during migration. The absence of a v12 earmark row means a goal is **unverified**, even when old cells are checked. Historic checked cells remain visible but verified backed progress is zero, not falsely complete. The owner can choose explicitly in the Arabic goal detail:

1. **تثبيت الرصيد من الادخار** — reserve the old checked-cell total from real free Savings of that exact currency; if insufficient, refuse atomically and keep all original cells.
2. **تصفير الخانات القديمة** — clear the legacy checked cells intentionally, recording a verified zero pledge without creating assets.

Successful reconciliation is idempotent and reloads the goal state. This distinguishes old savedAmount grid history from verifiedSavedAmount, verifiedProgress and isVerifiedComplete. New goals are verified from zero.

## Backups and migration

LocalDatabase v12 creates the earmark table without backfilling unverifiable old goal completions. Portable v12 backups include the new table; importing one atomically validates that goal currency matches its reservation, completed cells sum exactly to the reserved micros, and all earmarks in each unit fit the restored Savings ledger. A malformed or over-funded archive fails and keeps the target database unchanged. Verified v9/v10/v11 backups contain no v12 earmarks; their goal grids restore as preserved **unverified** data until explicit owner reconciliation. Prior financial events, expense plans, settings and history revisions are not rewritten.

## Regression cases authored — NOT EXECUTED

- test/goal_earmark_backing_test.dart covers 100 USD allocation without wealth growth, two competing goals, insufficient backed withdrawal and correct release, deleting a pledge, legacy consent with and without cash, explicit reset, historical correction freeze, v11 import as unverified, v12 verified round trip and corrupt-v12 rollback.
- test/challenge_ledger_reconciliation_test.dart now seeds real Savings before checking grid cells.
- test/local_database_migration_test.dart checks the v12 table on historical upgrades.
- test/legacy_backup_compatibility_test.dart and test/expense_plan_backup_v11_test.dart omit the new table when constructing genuine older archive fixtures.
- Savings service/widget tests inject the correct isolated database for new reserved/free fund display.

No Flutter analyzer, flutter test, build, real Android migration, backup restore, or device acceptance has run. Source commits are not proof of passing checks. Final acceptance is MS-18 (#92).

The next bounded feature is MS-14 (#88): realistic goal forecasts using verified backed progress only.
