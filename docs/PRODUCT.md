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

## Language and user model

- The production UI is **Arabic-only**.
- The app is designed for **one user only**.
- No account system or multi-user profile switcher is required.
- All client-facing production screens must follow RTL layout and Arabic financial labels.

## Initial client profile

A fresh install should start with the client's current plan prefilled so the app is immediately useful. These values are defaults only: the user must be able to edit them, delete them, or remove everything and recreate the plan from scratch.

Initial defaults:

- Weekly SYP income: **885,000 SYP every Thursday**.
- Monthly USD income: **300 USD at the start of each month**.
- Weekly envelope default from the Thursday income:
  - expenses/commitments: **540,000 SYP**;
  - surplus/savings: **345,000 SYP**.
- Current recurring monthly expense items are prefilled from the client's supplied list and calculate to **2,160,000 SYP** in total.
- The university goal and main USD savings goal may also be prefilled as editable saving goals.

None of these values may be hardcoded into financial business logic. Changing or deleting a default must not require an app update.

## Supported financial model

### Income

The initial client workflow contains two recurring income sources:

- A weekly SYP income received every Thursday.
- A monthly USD income received at the start of the month by default.

Both default amounts and paydays must be editable. Confirming an income receipt records the actual received amount; changing a future default must not rewrite historical transactions.

The recurrence engine must use real calendar dates, including months with five Thursdays.

### Expenses

The user maintains an editable recurring expense plan, primarily in SYP, and can also record unexpected one-off expenses.

The app must distinguish:

- planned expenses;
- actual recorded expenses.

Monthly totals are calculated from the expense items rather than stored as a manually duplicated total.

USD savings must not be consumed automatically for SYP expenses. Unexpected SYP expenses should normally reduce available SYP/surplus unless the user explicitly records another source.

### Weekly envelope allocation

A confirmed Thursday income can be divided between:

- expenses/commitments;
- surplus/savings.

The initial default split is **540,000 SYP for expenses/commitments and 345,000 SYP for surplus/savings** from an 885,000 SYP weekly income.

The split remains editable globally and can also be adjusted before confirming a specific week's allocation.

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

The client's main savings behavior is that the monthly 300 USD income and surplus from the SYP income both contribute toward savings goals as the user records or allocates them.

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

Real currency conversions are explicit transactions. Every SYP↔USD conversion must store:

- source amount and currency;
- destination amount and currency;
- the **actual executed exchange rate used for that conversion**;
- date/time and optional note.

The actual executed rate is historical transaction data and is separate from the Settings reference rate.

### Gold

Gold is a separate savings asset measured in grams.

The user can convert accumulated cash into gold through an explicit purchase transaction. The source cash balance decreases and gold grams increase, preventing the same money from being counted twice.

Gold valuation in Settings is defined as **USD per gram**. The user manually enters the reference USD price per gram, which is used only for estimated valuation.

Gold purchases should preserve the actual cash amount spent and grams acquired so historical operations remain auditable even after the reference gold price changes.

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

The estimated combined value uses the manually configured exchange rate and USD-per-gram gold price. It must be clearly presented as an estimate, while the real asset balances remain visible separately.

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

## Locked client decisions — Issue #8

The product decisions required before the financial data model are now locked:

1. Gold reference price is entered as **USD per gram**.
2. Every real SYP↔USD conversion stores the **actual executed exchange rate**.
3. Production UI language is **Arabic only**.
4. The client's initial financial plan is **prefilled on first install**, while every item remains editable/deletable and the user can recreate the plan from zero.
5. The default Thursday allocation is **540,000 SYP expenses/commitments + 345,000 SYP surplus/savings** from the default 885,000 SYP weekly income.

Future changes to these defaults are user configuration changes and must not rewrite historical transactions.
