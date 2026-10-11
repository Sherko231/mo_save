# MS-17 — Fund-First Navigation and Compact Arabic Dashboard

**Issue:** [#91](https://github.com/Sherko231/mo_save/issues/91)  
**Scope:** UI/navigation only. No SQLite migration, ledger rewrite, stored goal change or backup format edit. Tests authored but not executed.

## Primary destinations

The adaptive `AppShell` uses **three** clearly named financial destinations:

1. **الادخار** (default): actual per-currency Savings, liquid Spending comparison, verified goal progress and conditional completion date, plus links to all goals, actual backed milestones, forecasts, transfers and historical audits.
2. **المصاريف**: prominent first-screen **تسجيل مصروف الآن** action, actual spendable Spending fund cash by currency, planned commitments vs actual paid amounts, categorized analytics, late-salary attention and real receipt workflows.
3. **الإعدادات**: the existing complete configuration surface, including payday/allocation settings, reference rates, reminders, reconciliation of Unallocated old money and user-controlled export/restore.

Mobile uses a 3-destination `NavigationBar`, widescreen uses `NavigationRail` at 760dp+ (extended at 1080dp+). Both retain RTL language and material touch targets. Shell tabs are retained in an `IndexedStack`, so switching does not destroy forms/scroll positions. Restoration increments a data-revision key and rebuilds both fund views from the canonical database.

## First-screen actual facts

The Savings first-screen `FundsAtGlance` gets current signed fixed-point unit balances **directly** from `FinancialLedgerStorage.loadFundBalancesMicros()`:

- `Savings` is shown as **ادخار حقيقي**.
- `Spending` is shown as **متاح للمصاريف**.
- `Unallocated` receives a separate warning and **is not silently counted as either fund**.
- USD, old SYP and SYP (N) are never mixed or converted for this strip. Gold and price-based valuation stay in the detailed Savings/asset views.

Immediately below the strip, `SavingsGoalsPreview` lists the first active goals and shows **verified** backed amounts and percentages, plus an estimated plan date only when the existing `GoalForecastService` can ground it. Legacy checked cells with no v12 earmark are shown as **unverified** progress 0, not falsely saved. The date is labelled conditional, and missing plan/history explicitly results in **no date**. The preview does not reserve, move or create money. The owner can open the full goals list, change/check the real Savings-backed cells, inspect milestones and open detailed what-if forecasts. Full balances, six-month trends and wallet/FX/gold operations remain in clearly named disclosure sections.

## Few-tap expense, without reports

The Spending destination places a filled **تسجيل مصروف الآن** button **before** the spending report and plans. It navigates straight to the existing `SpendingQuickExpensePage` with Spending preselected; the same form can explicitly choose Savings and validates reasons/backed-goal restrictions. A successful actual payment posts exactly once through the shared expense service and refreshes the relevant ledger-derived screens. The Spending fund section suppresses its now-redundant secondary Add Expense button when used underneath this primary action.

Spending shows immediately current available funds per unit; bill plan amounts are explicitly *hypothetical commitments*, not cash deductions until their actual payment is recorded. The quick analytics button opens categorized spending drill-down, not a prerequisite to recording expenses.

## All prior functions retained

- **Savings tab:** Savings details (real balances, free/reserved earmarks, trend, historic debits), backed goals list/creation/grid/reconciliation, motivational milestones, conditional forecasts, Savings history, fund transfer, manual income and received/ignored historical salary.
- **Spending tab:** quick expense, live Spending balances, transfer, Spending history, categorized analytics, effective-month recurring expense plans and settlement, received/ignored salary occurrences, gift/item-sale/bonus/manual income, general history and overview.
- **Disclosures:** advanced financial overview, SYP↔USD exchange, gold purchase, month selector and historical summaries.
- **Settings tab:** salary and distribution presets, reference-only FX/gold valuation, unallocated reconciliation, local notifications and backup/restore.
- **Goals route:** no longer displaces a major financial tab. Opened from Savings, it shows a visible back control. Opening one goal uses in-page navigation; device Back returns from detail to the list before leaving the route.

Goal metadata, historical ledger and revisions, plans, actual expenses, balances, Unallocated, goal earmarks and backup remain the same stored data. Only screens and navigation paths change.

## Source and regression specifications (NOT EXECUTED)

- `lib/main.dart`: adaptive three-tab fund-first navigation, restoration refresh and optional widget builders to test shell independently of local SQLite.
- `lib/pages/home_page.dart`: two focused Savings and Spending variants of the formerly mixed Home page; direct expense and goal routes, progressive disclosure for advanced tools.
- `lib/pages/funds_at_glance.dart`: current per-unit saved/spendable balances, explicit Unallocated distinction.
- `lib/pages/savings_goals_preview.dart`: verified Savings-backed progress and conditional date.
- `lib/pages/home_spending_fund_section.dart`: removes duplicate expense CTA when shown on its primary screen.
- `lib/pages/challenges_page.dart`: route Back handling and clear goal-list return affordance.
- `test/fund_first_navigation_test.dart`: mobile Arabic bottom destinations and wide adaptive rail, between-tab preservation.
- `test/funds_at_glance_test.dart`: disjoint Savings and Spending currencies plus Unallocated warning.
- `test/savings_goals_preview_test.dart`: verified 60% goal vs legacy unverified 100%-checked goal; conditional forecast and goal-list button.

**Not executed:** Flutter analyzer, flutter tests, APK, real device Arabic RTL/accessibility, old SQLite migration/restore or signed release. These are explicit final acceptance obligations of [MS-18 (#92)](https://github.com/Sherko231/mo_save/issues/92). Source implementation is not device acceptance.
