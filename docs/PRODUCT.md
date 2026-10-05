# Mo Save — Product Scope

## Product goal

Mo Save is a single-user, offline-first Android personal finance and savings app. It combines day-to-day cash-flow tracking with gamified saving challenges.

The product is intentionally not an AI financial adviser. It should calculate, record and present the user's real financial plan clearly and consistently.

## Main navigation

The app keeps three primary tabs:

1. **Home** — financial overview and upcoming actions.
2. **Challenges** — saving goals represented as interactive saving grids.
3. **Settings** — editable financial assumptions and app preferences.

The bottom navigation must remain clear of Android system navigation insets and remain visible while browsing challenge details.

## Supported financial model

### Income

The initial client workflow contains two recurring income sources:

- A weekly SYP income received every Thursday.
- A monthly USD income received on a configurable monthly payday.

Both default amounts must be editable. Confirming an income receipt records the actual received amount; changing a future default must not rewrite historical transactions.

The recurrence engine must use real calendar dates, including months with five Thursdays.

### Expenses

The user maintains an editable recurring expense plan, primarily in SYP, and can also record unexpected one-off expenses.

The app must distinguish:

- planned expenses;
- actual recorded expenses.

Monthly totals are calculated from the expense items rather than stored as a manually duplicated total.

### Weekly envelope allocation

A confirmed Thursday income can be divided between:

- expenses/commitments;
- surplus/savings.

The default split is editable and can also be adjusted before confirming a specific week's allocation.

USD savings must never be consumed automatically to cover SYP expenses. Any use of saved USD is an explicit user action.

### Saving goals and challenges

A challenge is the gamified interface for a saving goal.

A goal can contain:

- name;
- target amount;
- currency;
- optional deadline;
- cell count;
- sequence mode: Ordered, Random or Reversed;
- progress.

Completing challenge cells must ultimately reconcile with the financial transaction ledger so savings are not double-counted.

### Currencies

Supported currencies/assets:

- USD;
- SYP;
- SYP (N);
- Gold holdings measured in grams.

Challenge cell denomination rules:

- USD: whole units;
- SYP: multiples of 1,000;
- SYP (N): multiples of 10.

The sum of all challenge cells must equal the target exactly.

### Exchange-rate valuation

The user manually configures a USD/SYP reference rate in Settings.

This rate is used only for estimated combined valuation. Changing it must not change:

- historical transactions;
- actual currency balances;
- challenge progress.

Real currency conversions are explicit transactions and use the actual source/destination amounts.

### Gold

Gold is a separate savings asset measured in grams.

The user can convert accumulated cash into gold through an explicit purchase transaction. The source cash balance decreases and gold grams increase, preventing the same money from being counted twice.

A configurable gold price per gram is used for estimated valuation.

### Financial history

All meaningful money movements should be represented in a transaction ledger, including:

- income;
- expenses;
- saving contributions;
- currency conversions;
- gold purchases/sales;
- manual corrections.

Displayed balances must be explainable from this history.

## Home dashboard target

Home should eventually show, at minimum:

- expected vs received income for the current month;
- planned vs actual expenses;
- available SYP;
- USD savings;
- gold grams and estimated value;
- estimated combined USD value;
- next expected income;
- saving-goal progress.

## Notifications

Local Android notifications may remind the user about:

- Thursday income;
- monthly USD income;
- optional goal deadlines/saving reminders.

No backend is required for notifications.

## Persistence and backup

The app is local/offline. Financial records must use a proper local database with schema versioning and migration support.

A user-controlled backup/export and restore flow is required before client handoff.

## Explicitly out of scope for the agreed version

- AI financial adviser/chatbot;
- bank-account integrations;
- automatic online exchange-rate feeds;
- automatic gold-price feeds;
- multi-user accounts;
- cloud backend/sync unless separately approved later.

## Remaining client decisions

Tracked in Issue #8. The main unresolved items are:

- final gold-price input currency;
- whether every currency conversion must store an explicit executed exchange rate in addition to source/destination amounts;
- final UI language strategy;
- whether first-install values are prefilled for this specific client or entered through setup;
- corrected default weekly envelope values after confirming the expense totals.
