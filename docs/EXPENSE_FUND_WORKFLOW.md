# MS-08 — Expenses from Savings or Spending

**Issue:** [#82](https://github.com/Sherko231/mo_save/issues/82)  
**Dependencies:** MS-02, MS-07  
**Status:** Source implementation and test scenarios committed directly on `main`. Flutter analyzer, tests, APK build and client-device verification have **not** been run.

## What the owner can record

Home → **صندوق المصاريف → إضافة مصروف من المصاريف أو الادخار**, or the expanded **المصاريف → تسجيل مصروف من الصندوق**, opens a **shared actual-payment form**. The owner chooses:

- **Paying fund:** `Spending` (the default) or `Savings`. `Unallocated` is not silently used; legacy cash remains there until explicitly reconciled.
- **Category:** Arabic categories `طعام`, `نزهة`, `فواتير`, `مواصلات`, `منزل`, `صحة`, `تسوق`, `اشتراكات`, and `أخرى` with a user-entered name. Names are stored in the canonical `financial_events.category` field. A current recurring-plan item can also be selected as an expense title/quick-fill.
- **Actual cash amount and unit:** SYP, USD (two fractional digits), or SYP (N) as *separate* units; no invented FX rate. Gold cannot be directly spent as cash.
- **Actual payment date** and optional note/reason. For **direct Savings spending**, a nonblank reason is **required**, the UI explains that it reduces savings, and an additional explicit confirmation is presented.

The screen displays the current source-fund cash balance for the selected currency. The service reads the selected fund; it checks affordability before submission, and the fund-aware ledger **rechecks within the SQLite insert transaction**. A concurrent withdrawal cannot spend cash twice or cause a new negative balance. A payment either commits one `expense` event with one negative, balance-affecting entry attributed to the selected fund, or none. Owned cash and that fund both decrease by exactly the actual amount.

### Accounting examples

| Actual expense | Before | After posting | Month's actual expenses |
| --- | --- | --- | --- |
| 80,000 SYP `نزهة`, paid from Spending | 540,000 SYP Spending, 345,000 SYP Savings | 460,000 Spending, 345,000 Savings | +80,000 SYP expense, **one event** |
| 100 USD `فواتير`, paid directly from Savings with a reason | 500 USD Savings, 0 Spending | 400 USD Savings, 0 Spending | +100 USD expense, **one event** |
| Planned 120,000 SYP utility with no payment | 540,000 SYP Spending | unchanged | +0 actual expense |

All expense totals are per unit: `ExpenseService.loadMonth` counts the actual cash-debit entries once regardless of Savings vs Spending. The Spending dashboard shows payments funded by Spending and a separate all-funds total when they differ, so a Savings expense is visible as an actual expense without being misrepresented as a Spending withdrawal.

## Plan selection, recurrence and limits

Selecting an existing recurring expense item (e.g. `أمبير`, internet) **only prefills** the name, currency and planned amount. The owner may enter the amount actually paid and choose their source fund. It does **not** create a new recurring rule, mark a specific invoice occurrence paid, modify the plan, or affect cash before confirmation.

MS-09 (#83) is responsible for effective-dated plan changes and a reliable recurring-occurrence identity. Until then, matching a generic expense category or a plan name **is not enough** to infer which installment is paid; the Spending dashboard's post-plan amount remains a clearly hypothetical scenario, not guaranteed remaining cash.

## Integrity, audit, and source attribution

- The existing `ExpenseService.logExpense` now enforces a nonempty, limited-length category, positive fixed-point cash quantity, no future date, and a mandatory nonempty reason if `sourceFund == savings`. Older programmatic clients may still default to `unallocated` for backward compatibility; both in-app entry routes **explicitly** pass the selected Savings or Spending fund.
- The UI supplies a stable one-form `requestId`. The event uses a stable ID for deduplication. An identical replay returns without posting a second debit **even when the first payment consumed the entire balance**. A conflicting replay with different details fails rather than changing the existing event.
- No new database tables or schema revision were introduced. Source fund lives on each `financial_event_entries.fund` posting; `financial_event_revisions` retains prior snapshots on correction or deletion.
- Transaction History now shows **من المصاريف / من الادخار / من غير موزّع** on the actual expense row, and each event entry's fund in details. The existing fund filter can isolate these movements, including deleted-event audit snapshots.
- A correction must retain the original unit, fund, and expense debit semantics while respecting ledger conservation; deleting an event restores that fund's amount and records a deleted snapshot.

## Regression scenarios (not executed)

The new `test/expense_fund_workflow_test.dart` covers: 80k SYP Spending example, direct 100 USD Savings example, actual expense totals across mixed source funds, insufficient Savings or Spending without fallback or partial debit, mandatory Savings reason and Other category validation, idempotent one-form expense requests with conflicting retries rejected, planned bills not debited until actual posting, historical correction/deletion with revision preservation, SYP (N) isolation, gold and future date rejection.

**Verification still due:** Run `flutter test`, analyzer, Android build and a real client database/backup acceptance pass under MS-18 (#92). No actual test success or Android runtime behavior is claimed in this source-only change.
