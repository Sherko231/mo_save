# MS-07 — Spending Fund Dashboard

**Issue:** [#81](https://github.com/Sherko231/mo_save/issues/81)  
**Product contract:** [FUNDS_ACCOUNTING_CONTRACT.md](FUNDS_ACCOUNTING_CONTRACT.md)  
**Delivery state:** Code and regression cases saved on `main`; no Flutter tests, analyzer, APK builds, or target-device verification performed.

## Actual spendable cash — not projected net worth

The new **صندوق المصاريف** section appears directly below Home's existing overview. It always shows the **current** monthly Spending picture, not a balance reconstructed for a different month selected in Home's historic overview. It labels itself **المتاح للصرف الآن**.

Amounts are derived from active ledger entries using `FinancialLedgerStorage.loadFundBalancesMicros()`; there is no independent balance table or wallet cache. It displays:

1. **SYP Spending cash** per ledger unit, always visible.
2. **USD Spending cash**, always visible (Savings USD must **not** be summed).
3. **SYP (N) Spending cash**, displayed separately if any current cash, plan, actual payment or unallocated holding exists. No automatic SYP (N)↔SYP/USD conversion is assumed.
4. **Unallocated cash**, if any, visibly labelled **not spendable from the Spending fund**. An action opens the existing Settings reconciliation page. Gold grams never appear in Spending liquidity.

Any current balance is independent of the recurring expense plan. Opening a dashboard, adding/editing a plan or viewing a forecast **never writes financial entries**.

## Plan vs actual and conservative scenario

For **the current month**, each currency card shows four distinct quantities:

| Label | Source | Affects actual Spending now? |
| --- | --- | --- |
| متاح للصرف الآن | Current `FinancialFund.spending` holdings in this exact cash unit | This **is** the actual spendable balance |
| التزامات الخطة الشهرية | Current sum of `recurring_expense_items` per currency | **No**, planned only |
| دُفع من صندوق المصاريف هذا الشهر | Net negative cash postings in actual `expense` events whose entry fund is Spending | Already debited once by the actual event |
| إجمالي المصروف الفعلي من كل الصناديق (when different) | All actual `expense` postings in the month, regardless of original fund | For reporting only; **not** an extra debit |
| تقدير افتراضي بعد دفع كامل الخطة من الآن | `current Spending cash - full monthly plan` | **No**, hypothetical only |

**Important limitation:** Existing recurring expense plan items are not yet linked to paid bill occurrences. We therefore cannot reliably know how much of an individual recurring commitment is still unpaid. The projection explicitly assumes **all** planned items were to be paid *again from now*. It may double-count a bill that was in fact already paid, so it is a **conservative what-if scenario**, not a promised disposable remainder or confirmed outstanding balance. Negative hypothetical results are shown as an estimated shortfall, **never a negative real wallet**. True plan-versus-paid matching and effective-dated commitments are future MS-08/MS-09 work.

Home's separate historic month picker continues to control historic overview and expense-detail sections. This new section has **its own live current-month label** and must not silently present a historic month's plan as money due right now. Home refreshes and edits to the existing monthly expense-plan sheet invalidate the Spending dashboard and reload the snapshot, so a new plan amount is reflected without inventing any paid expense.

## Primary actions

**إضافة مصروف من الصندوق** opens the lightweight quick expense form, with category, actual date, amount, unit and optional reason. It explicitly uses `ExpenseService.logExpense(sourceFund: FinancialFund.spending)`, so the canonical event decreases **owned cash and Spending in the same unit**, and adds **one** actual expense. No automatic cash is drawn from Savings or Unallocated; if Spending lacks enough cash, the operation fails without posting any entries. The existing expanded Expenses section also posts from Spending now for consistency. The broader fund chooser and advanced category/expense workflow remain assigned to MS-08 (#82).

**سجل حركات صندوق المصاريف** opens the existing `TransactionHistoryPage` with `initialFund: FinancialFund.spending`. The standard history now exposes a **صندوق** filter; a Spending receipt split, direct Spending expense, or transfer involving Spending appears, while unrelated Savings-only or Unallocated-only entries are excluded by default. Users can switch back to **كل الصناديق**. The history retains corrections, deletion snapshots and existing audit details.

### Example

1. Receive 885,000 SYP once, allocated **540,000 SYP Spending** and **345,000 SYP Savings**.
2. Spending shows **540,000 SYP available**; Savings never included. Add a **120,000 SYP monthly internet plan**: Spending **still shows 540,000**, not 420,000.
3. Actually pay **80,000 SYP from Spending**. Spending shows **460,000 SYP available**, monthly Spending-paid **80,000 SYP**, Savings stays 345,000. Total owned assets equal 805,000 SYP.
4. The hypothetical scenario after paying the *entire* 120,000 SYP plan from now shows **340,000 SYP**, not as a new cash balance. It might be overly cautious if the 80,000 payment already partially covers that planned internet item.

## Technical boundaries and regression coverage

- `lib/services/spending_fund_service.dart`: `SpendingFundSnapshot` and `SpendingFundService` derive strictly per-unit live amounts, planned totals and month actuals, no balance writes or FX assumptions.
- `lib/pages/home_spending_fund_section.dart`: Arabic RTL dashboard and primary actions on Home. Refreshes from ledger change stream and after navigation; ignores stale in-flight refreshes.
- `lib/pages/spending_quick_expense_page.dart`: category, amount, date, note and cash unit; source fund is fixed to Spending.
- `lib/services/expense_service.dart`: adds optional `sourceFund`; legacy service default is Unallocated to keep existing non-UI callers backward compatible. Dashboard's and old Home Expenses' user-visible actions explicitly select Spending.
- `lib/services/transaction_history_service.dart` and `lib/pages/transaction_history_page.dart`: fund-participation filter across active events and deleted-event revision snapshots; standard history still offers all funds.
- `test/spending_fund_service_test.dart`: authored tests for per-currency spendable balance excluding Savings/Unallocated, planned bill non-debit, separate Spending-only/total actual expense, source-fund insufficiency rejecting without mutation, full Spending fund history, corrected/deleted expense audit, SYP (N) separation.
- No schema or backup format changes. Existing event identities, linked receipts, audit history and legacy unallocated holdings are unchanged.

**Tests were added but NOT EXECUTED**, following the requested no-CLI workflow. No analyzer/build/runtime or real client device acceptance claims are made. MS-18 remains the eventual release gate.
