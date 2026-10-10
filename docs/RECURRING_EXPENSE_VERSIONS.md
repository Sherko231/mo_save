# MS-09 — Time-Effective Recurring Expense Plans

**GitHub Issue:** [#83](https://github.com/Sherko231/mo_save/issues/83)  
**Implementation:** SQLite v11 with source and regression tests committed to `main`. **Not tested or run on the user's client/Android device.**

## Behavior

Recurring bills such as `أمبير`, internet, electricity, gas, telephone, and household payments are **budgets/plans**, not actual cash outflows. The user can create a new recurring item effective this month or a future month, edit its name, price or currency effective **next month or later**, or schedule its discontinuation beginning next month or later. Past/current months cannot be retroactively edited by the plan-management screen. Edits to a future effective month replace only that **future plan version**, never a past version or payment.

**Example:** 240,000 SYP ampere plan in October, revised to 310,000 SYP **effective November**:

| Month | Planned ampere | Actual cash debit from revision |
| --- | ---: | ---: |
| October | 240,000 SYP | 0 |
| November | 310,000 SYP | 0 |
| December, if canceled effective December | No plan | 0 |

Any 240,000 SYP actual payment in October remains **240,000 SYP** in October's historical expense report after changing November's future plan. Planned totals and real expenses are two independent series; no forecast or schedule update writes any `financial_events`.

## Data model and migration

SQLite schema **v11** adds the additive, versioned `recurring_expense_plan_versions` table:

```text
(item_id, effective_month YYYYMM)    composite primary key
name, unit, amount_micros             one expected value at that month
is_active                             1 for a live plan, 0 for scheduled stop
recorded_at_ms                        when the version was saved
```

The existing `recurring_expense_items` table keeps stable identities, creation timestamps and order. A plan is read for a month by selecting its **latest version whose effective month is not after the requested month**. A scheduled stop hides the plan in that month and later months, unless a later active version intentionally restarts it. The plan sheet displays upcoming scheduled edits/stops rather than silently changing the current amount. New plans that start in a future month appear in plan management but not yet in current-month budgets.

### Known legacy baseline, not fabricated price history

When a v10 app database is upgraded, each existing recurring expense item gets exactly **one known baseline** effective from its original `created_at_ms` calendar month. There is no reliable historical series of earlier edited prices in v9/v10; the migration does **not** invent any earlier historical versions. Consequently planned amounts for months before the known baseline may be unavailable. This is intentional and independent of historic *actual* expenses, which are fully preserved.

The schema v11 migration and v9/v10-to-v11 backup conversion **do not alter** any financial ledger posting, history revision, category, old completed goal, fund classification or recurring income. `ExpenseService.loadMonth(month)` now explicitly requests the month-appropriate plan; the actual amount still comes only from balance-affecting expense events for that occurred-at month. SYP, SYP (N), USD remain different quantities; physical gold cannot be a directly spendable cash-plan currency.

## Matching a paid installment

In the actual-expense form, the user can choose a plan item from the month of the selected payment date. Selecting it suggests the correct unit and planned amount. When the owner confirms a real payment, the event is a normal categorized **actual expense** from the explicitly selected Savings or Spending fund and records this stable recurrence key:

```text
expense-plan:<item-id>:<YYYYMM>
```

Only **one paid planned occurrence per item per month** can be linked through that key. Retrying an identical action is idempotent; trying to pay the same linked installment again with different details is rejected. The UI marks linked installments as **مدفوع**. For a separate extra or partial one-off charge, the user can choose an ordinary category rather than the plan item. A category-name match alone never proves a planned invoice was paid.

**Limitations:** This is a simple **monthly** budget plan, not a billing-provider synchronization or an arbitrary weekly/quarterly schedule. A planned payment is recorded as settled for that month by explicit user action, **not** automatically when a similarly named expense appears. Refunds/partial planned payments beyond one explicitly confirmed linked installment and more advanced settlement/reversal editing belong to later finance/history tasks; no second hidden debit is generated.

## Backup / restore

Portable `.mosave` exports now record schema **v11** and include the complete versions table. A v11 restore replaces existing plan items and versions atomically with the incoming snapshot, and rejects a missing/orphaned plan version. Older verified v9/v10 backups remain supported: the new versions table must be absent in those payloads; the known single legacy plan baseline is reconstructed inside the restore transaction. Unsupported newer schemas are rejected before mutation. The SHA-256 checksum detects accidental changes but does not encrypt/authenticate backups.

Keep an independent client backup before upgrading; the owner has not performed a real Android migration test.

## Tests authored — NOT executed

- `test/expense_plan_versions_test.dart`: new plan, future amount/currency/name change, scheduled cancellation, current and historical projections, actual expense immutability, forbidden backdating, restart persistence, future-only management list, unique linked planned installment and one-off extra.
- `test/expense_plan_backup_v11_test.dart`: v11 backup round-trip, v10 import baseline without invented revisions, invalid v11 version history atomic rollback.
- `test/local_database_migration_test.dart`: v1/v9 schema migrations now check v11 plan version table and preserved prior balances/audit.
- `test/legacy_backup_compatibility_test.dart`: verified downgrade fixtures omit the new v11 table and re-export into the current schema version.
- `test/expense_plan_widget_test.dart`: updated to expect effective-future edit/stop status rather than destructive replacement of current plan.

No analyzer, `flutter test`, Android build, runtime acceptance or client's phone backup restore was run. Treat this as source-level completion only pending MS-18 (#92).
