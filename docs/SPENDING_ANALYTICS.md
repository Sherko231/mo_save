# MS-11 — Categorized Monthly Actual Spending Analytics

**Issue:** [#85](https://github.com/Sherko231/mo_save/issues/85)  
**Status:** Source and regression cases committed directly to `main`. **No analyzer, Flutter tests, APK or client-device verification have run.**

## Read-only, auditable inputs

The analytics service reads `ExpenseService.loadMonth` for the selected month and the preceding calendar month. That service in turn uses the existing, active `financial_events` and `financial_event_entries` ledger and the month-effective recurring expense plan (SQLite v11). For an actual payment, analytics counts **each negative, balance-affecting posting inside an `expense` event once**. It preserves the event ID, individual entry index, `occurredAt`, original category, payment-fund attribution, currency and note.

These are **not** expense analytics: `fundTransfer` (Savings↔Spending or Unallocated reconciliation), `openingBalance`, actual/expected income, `weeklyAllocation`, `savingContribution`, currency conversion, gold purchase/sale, and an unconfirmed recurring bill. Deleting an expense removes it from active totals but keeps history revisions. A permitted amount correction recalculates the report using the corrected active posting; prior note and amount remain auditable in Transaction History.

No new balance cache, tables, event types, funds or schema migrations are introduced.

## Reporting and user controls

Home → **تحليلات المصاريف الشهرية** (or Expenses disclosure → **التحليلات**) opens a dedicated Arabic RTL analytics page for the month currently selected on Home. Users may navigate calendar months and choose one cash currency at a time:

- **SYP, USD, SYP (N)**: separate totals, without hidden FX conversion or a false sum of incompatible assets.
- **Full monthly plan vs all actual payments**: reports both separately and shows the signed difference. Planned bills do not debit cash or appear as actual payments. The plan is valid for that historical month, including future-effective changes from MS-09.
- **Paying fund**: Spending, Savings and Unallocated are reported independently. A 100 USD actual expense paid directly from Savings contributes 100 USD to current month's **actual expenses**, and 0 to Spending-funded expense; there is only one parent payment. Internal Savings→Spending transfers never inflate either expense subtotal.
- **Linked recurring vs one-off/unlinked**: only actual expenses whose `recurrenceKey` begins `expense-plan:` count as confirmed recurring-plan payments. Older, unlinked or category-only expenses count in **unlinked/one-off**, not a fabricated settled installment. A plan with no linked payment remains a plan, not a debit.
- **Previous-month comparison**: compares the same selected unit, source-fund filter and recurring/unlinked filter in the previous *calendar month*, with an absolute (not percent) change to avoid dividing by zero.
- **Category breakdown**: descending actual outflow, then alphabetically, for the current filters. Each category total equals the sum of its real expense ledger postings. The simple category bars are visual shares of the highest category, **not** actual-to-budget percentages.
- **Drill-down**: tapping a category lists every original payment posting with its amount, source fund, true recorded date, note, parent event ID and ledger entry index. There is a shortcut to the normal **audited transaction history**, opened with the analyzed month, unit, expense-type and fund filters so users can inspect corrections/deletions.

The **plan-vs-actual comparison is per currency across all payment funds**, independently of the source/kind filter, and is explicitly labeled that way. Source/type filters apply to the categorization and prior-month comparison. This avoids silently comparing a whole-budget number with a Savings-only subtotal. A plan/category text match alone does not establish a paid installment; the full-plan minus actual number is a *difference between totals*, **not a bill-by-bill amount still owed**.

## Examples

| Operation in selected month | USD actual expense | USD Savings-funded | USD Spending-funded |
| --- | ---: | ---: | ---: |
| Open 500 USD Savings | 0 | 0 | 0 |
| Transfer 100 USD Savings→Spending | **0** | 0 | 0 |
| Pay 100 USD bill directly from Savings | **100** | **100** | 0 |
| Pay 100 USD bill later from Spending | **200** | 100 | 100 |

Both payments decrease owned USD; the internal transfer does not. The category drill-down exposes a source fund and original ledger event for each payment.

For SYP: 80,000 outing + 20,000 food + 120,000 *explicitly confirmed linked* internet installment = **220,000 actual** in three categories. Only the 120,000 internet payment appears as linked recurring; an old unlinked `إنترنت` payment does not count as an automatically settled monthly installment.

## Implementation

- `lib/services/spending_analytics_service.dart`: pure reporting snapshot, per-posting detail, category/fund/recurrence grouping, historical comparison and per-unit plan/actual values. All sums use **integer micros** until formatted for display.
- `lib/pages/spending_analytics_page.dart`: Arabic/RTL month switcher, cash-unit selector, budget-vs-actual, fund breakdown, linked-recurring breakdown, filtered monthly comparison, ranked category bars, editable filters and original-entry drill-down.
- `lib/pages/home_page.dart`, `lib/pages/home_expenses_section.dart`: shortcut on Home and within expanded Expenses section.
- `lib/pages/transaction_history_page.dart`: optional initial month/unit/event-type filters (in addition to previously supported initial fund), so analytics can navigate into the canonical audit history for that period.
- `test/spending_analytics_service_test.dart`: Savings expense exactly once, transfers/opening ignored, mixed category/linked installment, unlinked same-name bill, month/source/kind comparison, correction/delete with revisions, currency separation and future-effective plan prices.
- `test/spending_analytics_page_test.dart`: RTL category drill-down exposing the original note, paying fund and event identity.

**Verification:** All tests above were *authored but not run*. No Flutter analyzer, Android build, real-device data migration/restore or client sign-off was performed. Preserve independent user backups. Final acceptance and build handoff remain MS-18 (#92).

## Next

[MS-12 — Build true Savings fund dashboard (#86)](https://github.com/Sherko231/mo_save/issues/86) should build on the same canonical fund balances and transfers, not copy analytics totals into another wallet.
