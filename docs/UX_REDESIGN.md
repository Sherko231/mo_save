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

Only three top-level destinations remain:

1. Home (`الرئيسية`) — status, attention items and financial actions.
2. Saving goals (`الأهداف`) — goal progress and saving grids.
3. Settings (`الإعدادات`) — future defaults, reminders and data tools.

On compact screens this is a bottom navigation bar. On wider windows it becomes a navigation rail.

### Home

The default view now answers three questions in order:

1. What is my current financial position?
2. Is anything due or requiring action now?
3. Where do I go for details?

Detailed balance tools, recurring income, weekly allocation and expenses are preserved behind clearly named expandable sections. Transaction history remains a direct shortcut because it is a high-value audit path.

### Goals

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
