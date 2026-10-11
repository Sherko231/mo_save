# Mo Save — UX redesign

## Goal

Keep every financial feature while making the default experience calm, obvious and quick to learn. The redesign treats complexity as something to reveal when needed rather than something to remove.

## Research principles used

- Nielsen Norman Group — Progressive Disclosure: show the small set of frequent, important choices first and move advanced/rare choices behind a clearly labelled secondary action.
- Nielsen Norman Group — EAS / cognitive-load guidance for forms: eliminate unnecessary decisions, automate defaults, simplify what remains, and make requirements predictable.
- Android / Material guidance — primary navigation should contain only the major destinations; secondary actions belong near their content or behind menus. Large screens should use a navigation rail rather than stretching phone bottom navigation.
- Android accessibility guidance — interactive targets should be at least 48dp and actions need clear labels/semantics.
- Material 3 hierarchy — use surface, typography and one prominent action to communicate priority instead of relying on many borders, dividers and competing buttons.

## Information architecture

### Primary navigation

MS-17 replaces the former Home/Goals/Settings tabs with exactly three top-level destinations:

1. Savings (`الادخار`) — current real Savings compared to spendable cash, verified goal progress and conditional forecast. Detailed goals/grid are a direct route inside Savings.
2. Spending (`المصاريف`) — actual liquid balances and a first-screen direct payment action, scheduled bills, categorized analytics and real received income.
3. Settings (`الإعدادات`) — income/expense defaults, reference estimates, reminders, Unallocated fund reconciliation and backup/restore.

On compact screens this is a bottom navigation bar. On wider windows it becomes a navigation rail.

### Savings and Spending landing screens

The default Savings landing view answers *how much is actually saved*, *how much is spendable cash*, and *when verified goals may be reached*. It uses a per-currency Savings/Spending strip and goal-backed forecast preview before collapsible detailed balances; it never silently counts Unallocated or unverified challenge checkmarks.

Spending starts with a direct Add Expense button, **before** analytics and plan sections, then shows spendable balances, actual paid amounts and hypothetical monthly commitments by currency. Income receipt, transfers, month selection, general history, asset exchange/gold and analytics remain directly linked or disclosed by need. Planned/unreceived items never post real financial transactions.

### Goals (reached from Savings)

The list emphasizes goal name, saved amount, progress and deadline. Destructive deletion moved out of the primary visual path into an overflow menu.

Creating a goal is split into two stages:

1. Essential: name, currency and target.
2. Optional/customization: grid size, sequence, deadline and note.

Defaults are automatically bounded to the chosen amount so the user does not need to understand denomination constraints before creating a basic goal.

Inside a goal, the saving grid is the primary task. Goal editing and grid ordering moved to a secondary menu so they no longer compete with checking off saved cells.

### Settings

The previous long form is now grouped into progressive-disclosure sections. Income is open first; allocation, valuation and notifications are collapsed until requested. Expense-plan and backup workflows are clear navigation rows instead of floating actions.

All groups keep their form state mounted, so collapsing a section never loses edits and save-time validation still covers every field.

## Interaction and accessibility rules

- Standard Material controls provide >=48dp touch targets.
- Destructive actions require explicit confirmation and are not visually dominant.
- Frequent or time-sensitive tasks are surfaced; advanced configuration is disclosed on demand.
- Financial history and stored values are unchanged by this redesign.
- Arabic RTL remains global.
- Large-screen navigation adapts instead of stretching the mobile navigation pattern.
- Saving-grid cells expose checked state through accessibility semantics.

## Data safety

This is a presentation and interaction redesign. It does not change SQLite schema, persisted enum names, ledger math, backup format, recurrence keys, or financial calculation rules.
