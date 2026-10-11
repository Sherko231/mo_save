# MS-14 — Conditional Goal Completion Forecasts

**Issue:** [#88](https://github.com/Sherko231/mo_save/issues/88)  
**Status:** Source and regression tests committed directly to `main`. **No Flutter analyzer, test suite, APK or user-device validation has run.**

## No invented savings, salary or goal payments

This is a **read-only scenario model**, not a booked transaction, a promised payday, a bank account or a guaranteed milestone. The only starting principal for each individual goal is `SavingChallenge.backedAmountMicros` (verified, real Savings-backed reservation from MS-13), never old unverified challenge checkmarks or hypothetical Savings that have not been earmarked. A currently free Savings balance is **not** auto-assigned to every goal.

Every future contribution is a conditional **potential allocation**. Independent goal predictions **must not be added together**: different goals cannot all receive the entire same future surplus. The UI explicitly states this.

All USD, old SYP and SYP (N) amounts remain separate fixed-point units. There is **no automatic asset conversion**. SYP-to-USD is possible only as a **separately opted-in hypothetical scenario**, using a strictly positive reference SYP/USD setting, with an explicit warning that no conversion is executed. No SYP (N) reference conversion is assumed; absent an appropriate future income schedule, SYP (N) plan projections have **no date** (historical observed net Savings can still be shown separately if sufficient evidence exists).

## Plan pace: real calendar paydays and effective bill amounts

The plan source reads current `FinancialSettings` and **every future month's** active recurring expense plan version (MS-09); both are reloaded on each scenario computation. It projects only **next full month onward**, avoiding double-counting potentially already received/spent transactions in the current partial month. It uses real calendar weekday dates, so a month with five configured Thursdays has five weekly payday *assumptions*, not four. The configured monthly USD salary payday is preserved as an actual day of each calendar month (clamped to the last real day when a configured payday exceeds that month's length). Projected milestones are conservatively placed **at the month's end**, after expected bill commitments, rather than claimed precise payday arrival times.

For each coming month:

```text
SYP scheduled potential saving = count(configured weekly payday)
                                 × bounded weekly savings allocation

SYP scheduled spending envelope = count(weekly payday)
                                  × bounded weekly spending allocation

SYP plan net = potential saving -
               max(0, monthly planned SYP bills - spending envelope)

USD proposed salary saving = monthly USD salary × selected saved share
USD plan net = proposed salary saving - all planned USD bills
```

Weekly allocations are bounded to the configured weekly salary, and **all assumptions remain prospective**. There is no separate confirmed USD Spending allowance in settings, so the model conservatively deducts all expected USD bills from the assumed salary Savings amount rather than silently treating them as fully funded by another wallet. Future bill versions, scheduled stops, USD salary edits, weekday changes and allocation edits therefore change the projected net pace and goal dates. Planned expenses are **not** actual debit events. Real income received late is recorded under its actual date; missed/ignored **past** occurrences are never retroactively counted as future Savings.

**USD allocation:** Without a manually chosen percentage, the model uses the proportion allocated to Savings in the **latest actually recorded monthly USD salary receipt**. Scheduled-but-unreceived salary cannot establish a Savings split. If no such receipt exists, the USD planned allocation is **unknown** and there is **no USD plan date** unless the owner explicitly chooses a scenario (or opts in to hypothetical SYP→USD surplus conversion). This prevents assuming that a 300 USD expected salary is all available for savings.

## Actual observed pace (not future income)

For the observed comparator, a minimum of **two complete calendar months** after the first active balance-affecting event is required. The first event month is excluded as potentially partial; the current month is excluded as incomplete; then up to the last three complete months are averaged using **real signed Savings entries**:

- actual `income` entries credited to Savings;
- real `expense` entries debited directly from Savings;
- actual `fundTransfer` entries to/from Savings (explicitly **not newly earned income**).

Opening balances, FX conversions, gold principal movements, technical/manual adjustments, gold price appreciation, reference FX movements and non-balance `savingContribution` grid markers **do not count** as repeatable saving pace. Transferring old accumulated Spending cash to Savings can change observed funding, but this is not earned income: users must judge whether it can sustainably recur. Deleting or correcting an original ledger event naturally updates the observation when recalculated. The model does **not** invent goal-specific deposit histories: observed Savings fund pace is a clearly labeled **portfolio-wide proxy**, conditionally assigned to each goal separately.

No actual observed estimate is shown with too little history or if observed pace is zero/negative.

## Dates and sensitivity

For each backed, unfinished goal and original asset unit, the next **60 complete calendar months** are simulated. The goal's already verified/earmarked amount is the initial amount. Each future month advances from its plan net (or observed average). A hypothetical slower or faster scenario uses **75%** or **125%** of planned net pace. Negative month movement cannot produce a negative funded balance; it also cannot silently remove already verified goal earmarks (no ledger writes occur).

A date exists only when a **positive net pace** can reach the target within the horizon. If progress is unverified, income allocation is unknown, reference rates are unavailable for opted-in FX, future pace does not sustain growth, or the horizon ends before the target, show **no estimated date**, not a fabricated one.

The result shows:
- estimated plan date, observed-pace date and slower/faster dates, independently;
- average monthly **future plan** net vs historical **actual** net by matching currency, with ahead/behind difference;
- user-selected goal deadline (if any) with conditional schedule risk;
- first projected month count of configured weekly salary dates, planned Savings and planned bills;
- disclosed USD share assumption (latest received salary vs manual override), and optional reference FX.

Recomputing with a different salary, recurring bill, confirmed deposit, Savings transfer/expense, goal amount/checkmark, manual USD share or FX assumption re-reads the inputs; none of those forecast operations modify the canonical ledger or existing old records. Assumption overrides are **in-page what-if controls**, not changed permanent salary settings.

## Navigation and tests

The dedicated RTL `GoalForecastPage` is reachable from Home's Savings dashboard, the Savings-goals list and the individual goal detail. Each goal is independently forecast and its unverified historical checkmarks clearly do **not** count as financial progress.

- `lib/services/goal_forecast_service.dart`: calendar-accurate future plan and historical observed Savings comparator, conditional horizon and sensitivity engine, USD receipt split inference.
- `lib/pages/goal_forecast_page.dart`: Arabic scenario controls, explicit caveats, monthly schedule and per-goal forecasts/deadlines.
- `test/goal_forecast_service_test.dart`: 4/5 weekly paydays, monthly bills overrunning envelope, salary/weekday/plan edits, marked principal and variable pace date, no-date cases, real salary USD split, observed month coverage, ledger isolation and FX what-if.
- `test/goal_forecast_page_test.dart`: RTL view, unavailable-history messaging and explicit USD share scenario.

**NO TESTS EXECUTED.** Flutter analyzer, tests, target build, saved backup migration and Android acceptance remain MS-18 (#92) obligations. No SQLite migration, balance cache, new event or background scheduling is introduced by MS-14. Future reminders/motivation belong to MS-15 (#89).
