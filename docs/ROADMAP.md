# Mo Save — Client-Ready Roadmap

This roadmap is the ordered implementation plan from the repository's current state to a client-ready Android build.

Work should proceed one bounded GitHub Issue at a time. Do not skip dependencies unless the owner explicitly authorizes it.

## Phase 0 — Existing foundation

Already implemented on `main`:

- bottom navigation: Home / Challenges / Settings;
- no global top app header;
- Android safe-area handling;
- local challenge create/delete;
- saving challenge grid with exact target sum;
- challenge progress and progress on challenge cards;
- currencies: USD, SYP and SYP (N);
- denomination rules for SYP and SYP (N);
- Ordered / Random / Reversed sequence modes;
- sequence editable inside challenge details;
- challenge detail remains inside the Challenges tab so bottom navigation stays visible.

These features are foundation only. Goal and asset workflows are introduced by later roadmap phases.

---

## Phase 1 — Lock scope and data foundation

### #8 — P1-T01 — Resolve remaining product decisions — COMPLETED
Client decisions are locked and documented in `docs/PRODUCT.md`.

### #9 — P1-T02 — Introduce robust local database and migrate current challenges — COMPLETED
Challenge persistence now uses a versioned SQLite database. Existing SharedPreferences challenge JSON is migrated transactionally on first database access, and the schema/migration policy is documented in `docs/DATA_STORAGE.md`.

**Phase exit:** product assumptions are explicit and existing user challenge data is safe in the new persistence layer.

---

## Phase 2 — Core financial model

### #10 — P2-T01 — Add editable financial settings — COMPLETED
The Settings tab now persists editable weekly/monthly income defaults, paydays, reference exchange rate, USD-per-gram gold price and weekly envelope defaults in SQLite schema v2.

### #11 — P2-T02 — Add transaction ledger and financial event model — COMPLETED
SQLite schema v3 now provides a financial-event ledger with signed fixed-point entries for USD, SYP, SYP (N) and gold grams. Income, expenses, saving contributions, conversions, gold operations and manual adjustments share one event model, and owned balances are derived from ledger entries instead of cached totals.

**Phase exit:** the app has a durable model for future money movements and editable defaults.

---

## Phase 3 — Income, expenses and weekly plan

### #12 — P3-T01 — Implement recurring income and receipt confirmation — COMPLETED
The Home tab now derives weekly and monthly income occurrences from the real calendar, naturally handles four- and five-Thursday months, shows upcoming/expected income, and lets the user edit the actual received amount before recording it as a uniquely identified income ledger event.

### #13 — P3-T02 — Add recurring expense plan and actual expense logging — COMPLETED
SQLite schema v5 now stores an editable recurring monthly expense plan seeded once from the client's approved SYP items. Home shows planned versus actual spending for the selected month, supports SYP/USD/SYP (N), lets the user add/edit/delete plan items, and records one-off or recurring actual spending as dated expense ledger transactions with category and optional note.

### #14 — P3-T03 — Implement weekly envelope allocation — COMPLETED
Confirmed weekly SYP income can now be allocated from Home into expenses/commitments and savings using the current Settings defaults as an editable proposal. The allocation is stored as a uniquely linked, non-balance-affecting ledger event, can leave an explicit unallocated remainder, and never consumes USD savings automatically.

**Phase exit:** the user can record incoming money, actual spending and the weekly allocation plan without manual calculations.

---

## Phase 4 — Balances, goals, conversions and gold

### #15 — P4-T01 — Build multi-currency balance and valuation engine — COMPLETED
Home now derives separate USD, SYP, SYP (N) and gold balances directly from balance-affecting ledger entries and shows a clearly labelled estimated USD total when all non-zero assets have a defined valuation. SYP uses the current Settings reference exchange rate and gold uses the current USD-per-gram reference price; changing either reference changes the estimate only, never history or owned balances. SYP (N) remains separate and is not guessed into the USD estimate until a trustworthy reference conversion is defined.

### #16 — P4-T02 — Integrate saving goals with challenges — COMPLETED
The existing challenge is now the saving-goal record: it keeps its target, currency, grid and sequence while adding an optional deadline and note. Goal details can be edited inside the challenge, deadline state is shown on challenge cards, and the detail screen derives required weekly/monthly saving pace from the remaining amount without storing duplicate progress data.

### #17 — P4-T03 — Sync challenge progress with savings transactions — COMPLETED
Challenge-cell completion is now reconciled atomically with one canonical non-balance-affecting saving-contribution ledger event per goal. Its amount always equals the sum of completed cells; undoing cells reduces or removes that event, repeated toggles cannot create duplicates, and a one-time backfill creates matching contribution records for progress that existed before this workflow.

### #18 — P4-T04 — Add explicit currency conversion transactions — COMPLETED
Home now records real SYP↔USD conversions as one atomic two-entry ledger event: the actual source amount is deducted and the actual destination amount is added. Each event stores the historical executed rate in SYP per USD, independent of the mutable Settings reference rate, and the workflow rejects conversions that exceed the current source balance.

### #19 — P4-T05 — Add gold holdings and purchase workflow — COMPLETED
Home now records gold purchases from SYP or USD as one atomic ledger event that deducts the actual cash paid and adds the actual grams received. Purchases are rejected if the source cash balance is insufficient, gold remains a separate owned asset valued only by the current Settings reference price, and service-level sale/manual-correction foundations preserve the same no-double-counting ledger model.

**Phase exit:** all savings assets and goals reconcile to the transaction ledger.

---

## Phase 5 — Main user experience

### #20 — P5-T01 — Build the Home financial dashboard — COMPLETED
Home now opens with one at-a-glance dashboard for the selected month: expected and received income by currency, planned versus actual expenses, current SYP/USD balances, gold grams and estimated value, combined estimated USD value, the next expected income, and compact saving-goal progress. The dashboard aggregates the existing ledger/settings/challenge sources without introducing cached financial totals, while the existing detailed income, allocation, expense and asset workflows remain available below it.

### #21 — P5-T02 — Add transaction history and correction flows
Provide an auditable timeline with filters and safe corrections.

**Phase exit:** the user can understand current status and trace how every balance was produced.

---

## Phase 6 — Automation and configuration

### #22 — P6-T01 — Add local payday and goal notifications
Add Android reminders for Thursday income, monthly income and optional goals.

### #23 — P6-T02 — Complete Settings and initial setup UX
Make a fresh install configurable without code changes and clearly separate future defaults from historical records.

**Phase exit:** the daily workflow is configurable and reminders operate locally.

---

## Phase 7 — Data safety and production UX

### #24 — P7-T01 — Add local backup, export and restore
Protect local financial history against reinstall/device loss.

### #25 — P7-T02 — Finalize localization, RTL and financial number formatting
Apply the approved language strategy and consistent financial formatting.

### #26 — P7-T03 — Harden validation, empty states and destructive actions
Handle invalid amounts, impossible operations, errors and destructive actions safely.

**Phase exit:** the app is understandable, recoverable and resilient enough for real client data.

---

## Phase 8 — Verification and delivery

### #27 — P8-T01 — Add automated tests and migration QA
Cover critical financial calculations, reconciliation and persistence migrations.

### #28 — P8-T02 — Prepare branding and Android release build
Finalize app identity, signing and a production Android build.

### #29 — P8-T03 — Client acceptance test and final handoff
Run the client's real workflow, fix release blockers and deliver the final signed build plus usage notes.

**Phase exit:** client-approved production release.

---

## Client-ready definition

The application is considered ready for delivery only when all of the following are true:

- all Issues #8–#29 are completed or explicitly removed from scope by the owner;
- current financial balances reconcile with the transaction history;
- challenge progress reconciles with saving contributions;
- exchange-rate changes affect estimates only;
- gold purchases do not double-count cash and gold;
- four- and five-Thursday months behave correctly;
- existing data survives supported migrations;
- backup and restore are verified on a clean install;
- Android system navigation does not overlap app controls;
- the final signed release build installs and runs on the client's target device;
- the client completes acceptance testing and approves the agreed scope.

## Execution order

Use the Issue numbers above as the default implementation order. Each implementation task should:

1. start from the latest verified `main`;
2. change only the bounded Issue scope;
3. preserve unrelated work and existing client data;
4. update documentation when product behavior changes;
5. be merged before starting the next dependent task.
