# MS-15 — Savings Motivation Grounded in Real Assets

Issue: https://github.com/Sherko231/mo_save/issues/89

Implementation committed directly to main. New tests are authored but have NOT been run.

## Earning progress
The Arabic Savings motivation page shows verified 25/50/75/100 percent milestones only when the goal has a real backed amount in goal_earmarks. A checked old grid without a verified earmark earns no milestone, even if all cells are checked. The next milestone shows how much more of existing Savings must actually be reserved. Milestone labels never create income, expenses, goals, assets or transfers; unpledging cash may appropriately remove earned milestones.

## Plan versus evidence
The page reads the existing GoalForecastService: a conditionally estimated arrival date based on editable plans versus observed complete calendar months of Savings. Where both plan and observed hypothetical dates exist, the difference is shown in calendar days, explicitly as scenario comparison rather than a historical change in a persisted forecast. Messages distinguish above-plan, below-plan, missing-plan and insufficient-history cases without promises or blame. Every goal is an independent conditional scenario; one salary cannot be fully assigned to all goals simultaneously.

## Genuine streaks only
A streak appears only when there are at least two complete preceding calendar months, following the first (possibly partial) month of asset history. It counts consecutive complete months with positive actual income credited to Savings less actual expenses debited from Savings in the same unit. Missing/zero/negative months break it. Opening assets, internal transfers, currency/gold trades, reference-value changes, checked goal-grid cells and forecast income cannot earn it. It is a currency-wide Savings-fund streak, not evidence of contributions earmarked to a particular goal.

## Optional reminders
Existing Settings goal-deadline switch remains independently optional, off by default. If enabled, local reminders at one week before and on the user's goal deadline report verified remaining allocations, gently suggest reviewing plans and do not invent progress for legacy unverified cells. Fully backed goals are skipped. No extra push type, permission, shadow balance or SQLite schema is introduced.

## Files
- lib/services/savings_motivation_service.dart: read-only milestone, guidance, streak and date comparison.
- lib/pages/savings_motivation_page.dart: Arabic RTL visible milestones, next threshold, grounded guidance, date delta and evidence-only streak, plus link to detailed forecasts.
- Home Savings, goals list and goal detail link to this page.
- lib/services/goal_reminder_copy.dart and notification_service.dart: accurate opted-in deadline text; Settings clarifies purpose.
- test/savings_motivation_service_test.dart and test/savings_motivation_page_test.dart: evidence-only milestone and streak, no phantom assets, old goal exclusion and RTL messaging.

None of these tests or Flutter analyzer, APK, device upgrade, Android notification delivery and backup restore verification were run. Final integration acceptance belongs to MS-18 (#92). Next bounded task: MS-16 (#90), unified financial history and audit.
