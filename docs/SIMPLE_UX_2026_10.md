# Mo Save — Simple UX, October 2026

## What changed

This pass prioritizes first-time comprehension over exposing accounting terminology.
The first screen answers **"What can I spend?"** and **"What have I saved?"**
It uses actual per-currency ledger balances; it never turns an expected paycheck
or a forecast into owned cash. Currency units remain distinct.

Three bottom/rail destinations replace the previous Savings/Spending/Settings tabs:

1. **الرئيسية (Home):** current per-currency saved/spendable money and three high-frequency actions: expense, income, and internal transfer. Quick links lead to goals, received salary, and history.
2. **السجل (History):** a directly accessible auditable record with filters, corrections and expected commitments. Its back button is hidden in tab mode; standalone history retains its normal back button.
3. **المزيد (More):** settings/backup plus three collapsed groups for advanced money management, goals/forecasts, and reports. Each advanced tool loads only when opened.

Income receipts are given a focused screen with overdue actions and monthly
received/ignored/future occurrences, rather than requiring a user to locate
the salary block on a long Spending dashboard.

Expense entry asks where the money came from, its currency and **amount
before category**, then accepts optional date/note; savings-funded payments
still require a reason and confirmation. Manual intake hides optional
date/source/note behind an explicit disclosure while retaining existing
allocation, splitting and source-safety rules.

## Retained feature map

| Existing capability | Simple UX route |
| --- | --- |
| Actual Spending and Savings balances in SYP, USD, SYP (N) | Home |
| Gold holdings, other assets and historical reference estimates | More → Money management → Savings detail → Other assets |
| One-off expense including Savings-funded payment | Home → Record expense |
| Actual one-off cash, gift, extra pay, prior opening balance and sales | Home → Add money |
| Fund allocation / split / unallocated reconciliation | Add money, or More → Money management → Unallocated |
| Savings–Spending transfers | Home → Transfer money |
| Overdue recurring salary ignore/undo and dated actual receipts | Home → Salary |
| Recurring salary defaults and allocation settings | More → Settings |
| Planned recurring bills and future-effective updates | More → Settings; also Spending detail |
| Category analytics, plan-versus-paid comparison | More → Reports → Spending analytics |
| Chronological history, audit corrections, history filters | History tab |
| Savings-backed goals and contribution grid | Home → Goals |
| Forecasts, conditional target dates, motivation/milestones | More → Goals and forecasts |
| Savings trend, Spending forecast and all prior advanced dashboard details | More → Money management |
| FX conversion, gold purchases/sales and valuation references | More → Savings detail / Settings |
| Reminders, currency reference prices and preferences | More → Settings |
| Backup/restore and data restoration callback | More → Settings and backup |

## Safety and implementation boundaries

This redesign changes the navigation and presentation only, plus plain-language
form labels and optional-field disclosure. It does not change SQL migrations,
accounting rules, event writes, historical entries, backup schemas or currency
math. All prior advanced dashboards remain navigable rather than deleted.

No GitHub Actions workflows are enabled; the owner requested local testing.
Client/device acceptance is **not** claimed until a local build and actual
first-time-user walkthrough succeed.

## Local walkthrough checklist

- Open and navigate Home, History, More without a blank scroll/crash.
- Confirm Home amounts match full Savings and Spending details for every
  currency; Unallocated must never be included in the saved/spendable columns.
- Record an ordinary payment, then verify balance and history update.
- Record a payment from Savings with reason and explicit confirmation.
- Add a gift, a prior opening balance, and a split allocation without double counting.
- Receive a current/backdated salary, ignore and undo an old occurrence.
- Check goals, forecasts, transfers, expense plan editing, conversions and analytics.
- Export a backup, restore on a test installation, and verify navigation refresh.
- Show the customer the app **without explaining its internals first**.
  Ask them to find current spending cash, add a payment and locate their goal.

If a step fails, leave the active verification issue open and fix that path
before treating the redesign as accepted.
