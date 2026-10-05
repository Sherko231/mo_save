# Mo Save — Local Data Storage

## Storage policy

Mo Save is offline-first. Financial records and saving challenges are stored locally on the device. There is no backend or cloud dependency in the agreed scope.

SQLite is the primary durable data store. `SharedPreferences` is not used as the primary store for financial records; it remains available only for tiny preferences and for the one-time migration of legacy challenge data.

## Database

- File: `mo_save.db`
- Engine: SQLite through `sqflite` on Android/iOS and `sqflite_common_ffi` on Windows/Linux development builds.
- Current schema version: `8`
- Foreign keys are enabled for every opened connection.

The desktop SQLite factory is initialized automatically before the first database path/open call, so Windows/Linux development builds require no manual setup.

Schema versioning is controlled by `LocalDatabase.schemaVersion`. Future schema changes must increment that value and add an explicit migration step instead of silently recreating the database.

## Schema v1

### `app_metadata`

Small internal migration/state flags.

- `key` — primary key
- `value` — string value

### `challenges`

One row per saving challenge.

- `id` — challenge identifier, primary key
- `name`
- `target_amount`
- `currency`
- `sequence`
- `cell_count`
- `sort_order` — preserves the user's challenge-list order

### `challenge_cells`

One row per challenge grid cell.

- `challenge_id` — foreign key to `challenges.id`
- `position` — cell order within the challenge
- `value`
- `is_completed` — `0` or `1`

The composite primary key is `(challenge_id, position)`. Deleting a challenge cascades to its cells.

## Schema v2

### `financial_settings`

A single editable row (`id = 1`) stores the user's current defaults for future financial operations:

- `weekly_syp_income` — default weekly SYP income amount;
- `weekly_payday` — ISO weekday number, Thursday by default;
- `monthly_usd_income` — default monthly USD income amount;
- `monthly_payday` — day of month, day 1 by default;
- `reference_syp_per_usd` — optional reference exchange rate used only for estimates;
- `gold_usd_per_gram` — optional reference gold price in USD per gram;
- `weekly_expenses_allocation` — default weekly expenses/commitments envelope;
- `weekly_savings_allocation` — default weekly surplus/savings envelope;
- `updated_at` — local update timestamp.

The first load seeds the approved client defaults (885,000 SYP weekly income, Thursday payday, 300 USD monthly income, day 1 payday, 540,000 SYP expenses envelope, 345,000 SYP savings envelope). Exchange rate and gold price begin unset (`0`) until the user enters them.

Changing these settings affects future defaults only. Historical financial transactions preserve the values actually used at the time and are not rewritten by later settings changes.

## Schema v3 — Financial ledger

The ledger is the source of truth for money and asset movements. No duplicate running totals are stored.

### `financial_events`

One row represents one user-visible financial event.

- `id` — stable event id, primary key;
- `event_type` — income, expense, saving contribution, weekly allocation, currency conversion, gold purchase, gold sale or manual adjustment;
- `occurred_at_ms` — when the event actually happened;
- `note` — optional free-text note;
- `category` — optional category;
- `related_challenge_id` — optional link to an existing challenge; deleting the challenge clears this link but does not delete the financial history;
- `related_goal_id` — reserved link for future goal/history compatibility;
- `created_at_ms` and `updated_at_ms` — audit timestamps.

### `financial_event_entries`

Each event has one or more signed ledger entries.

- `event_id` — parent financial event;
- `position` — stable order inside the event;
- `unit` — `usd`, `syp`, `sypNew` or `goldGram`;
- `amount_micros` — signed fixed-point quantity where one unit equals 1,000,000 micros;
- `affects_balance` — whether this entry changes the owned-asset balance.

Positive entries add to a balance and negative entries subtract from it. Fixed-point micros are used instead of SQLite floating-point money values so later calculations do not accumulate binary rounding errors.

Examples of the posting model:

- income: positive balance-affecting cash entry;
- expense: negative balance-affecting cash entry;
- SYP → USD conversion: negative SYP entry plus positive USD entry in the same event;
- gold purchase: negative cash entry plus positive `goldGram` entry;
- gold sale: negative `goldGram` entry plus positive cash entry;
- saving contribution: may use a non-balance-affecting entry to track goal progress without counting the same cash twice;
- weekly envelope allocation: non-balance-affecting SYP entries earmark already-owned cash into weekly buckets;
- manual adjustment: explicit signed correction entry.

`FinancialLedgerStorage` owns event CRUD and balance queries. Balance reads sum only entries where `affects_balance = 1`; therefore future screens must derive owned balances from the ledger instead of maintaining separate cached totals.

Historical events are append-only by normal workflows. Corrections require the explicit `updateEvent` or `deleteEvent` paths; updates keep the original event id and creation timestamp and replace the event entries atomically.

## Schema v4 — Recurring occurrence identity

Schema v4 adds nullable `recurrence_key` to `financial_events` plus a partial unique index for non-null values.

Recurring income schedules are derived from the current financial settings and the real calendar instead of assuming four weeks per month. Each generated occurrence receives a stable key such as:

`income:weeklySyp:2026-10-08`

or:

`income:monthlyUsd:2026-10-01`

When the user confirms receipt, the resulting income event stores that key. The unique index prevents one scheduled occurrence from being confirmed twice. The actual amount entered by the user is stored in the ledger entry; later changes to salary defaults do not rewrite that historical transaction.

A configured monthly payday that does not exist in a shorter month is clamped to that month's final calendar day. Weekly occurrences are enumerated from actual dates, so months with five Thursdays naturally contain five weekly salary occurrences.

## Schema v5 — Recurring expense plan

### `recurring_expense_items`

The current monthly expense plan is stored as editable items rather than as one duplicated total.

Each item stores:

- `id` — stable item id;
- `name` — Arabic user-visible category/name;
- `unit` — cash unit (`syp`, `usd` or `sypNew`);
- `amount_micros` — positive planned monthly amount using the same fixed-point representation as the ledger;
- `sort_order` — display order;
- `created_at_ms` and `updated_at_ms`.

The first expense-plan load seeds the approved client defaults exactly once through an `app_metadata` flag. The seeded SYP items are: Amper 240,000; Internet 200,000; Electricity 150,000; Gas 100,000; Telephone 30,000; services 140,000; family 200,000; side expenses 100,000; personal spending 1,000,000. Their calculated SYP total is 2,160,000.

The seed marker remains even if the user deletes every item, so an intentionally cleared plan is not silently recreated on the next launch. Items can be added, edited or deleted later and monthly planned totals are always recalculated from the current item rows.

Actual spending is not stored in the plan table. Every actual expense is a normal `expense` financial event with a negative balance-affecting ledger entry plus its date, category and optional note. The selected-month UI compares totals derived from the plan rows against totals derived from expense ledger events.

## Schema v6 — Weekly envelope allocation metadata

Schema v6 keeps weekly allocation inside the financial ledger rather than creating a second balance system.

It adds:

- `source_event_id` to `financial_events`, allowing a weekly allocation event to point directly to the confirmed Thursday income event that produced it;
- `entry_role` to `financial_event_entries`, allowing SYP entries in one allocation event to be identified as `weeklyExpensesEnvelope` or `weeklySavingsEnvelope`.

A confirmed weekly SYP income can be allocated once through an event with recurrence key:

`allocation:income:weeklySyp:YYYY-MM-DD`

The existing unique recurrence-key index prevents duplicate allocation of the same salary occurrence.

Allocation entries use `affects_balance = 0`. The cash already entered the SYP balance when the income was confirmed, so splitting it into an expenses envelope and a savings envelope must not create or destroy money. Any unallocated remainder stays ordinary available SYP. The workflow only operates on SYP weekly income and never consumes USD savings automatically.

The default proposed allocation comes from the current Settings values, but the user can change both envelope amounts before confirming that week's allocation. If the received salary is smaller than the configured defaults, the proposal is capped to the amount actually received. Historical allocation records remain unchanged when Settings defaults are edited later.

## Schema v7 — Saving-goal metadata

Schema v7 upgrades the existing challenge row so the challenge itself is the financial saving goal instead of introducing a duplicate goal table.

It adds nullable columns to `challenges`:

- `deadline_ms` — optional date-only goal deadline stored as a UTC timestamp;
- `goal_note` — optional user-entered purpose/context for the goal.

Existing challenges migrate with both values null, so their grid, progress, currency, sequence and completion state remain unchanged.

Required pace is calculated from the current remaining challenge amount and the deadline at display time. Weekly and monthly pace are rounded upward to the challenge currency denomination step. Pace is not stored as a second value, so changing progress or the deadline cannot leave stale calculations behind.

The challenge target remains the goal target. Challenge-grid completion is reconciled with canonical non-balance-affecting saving-contribution events as documented in `docs/CHALLENGE_LEDGER.md`.

## Schema v8 — Executed SYP/USD conversion metadata

Schema v8 adds nullable `executed_syp_per_usd` to `financial_events`.

The field stores the historical rate actually used by a real SYP↔USD conversion, always using the convention `SYP per 1 USD` regardless of conversion direction. Application validation requires the value for `currencyConversion` events and rejects it on other event types.

The source and destination amounts remain fixed-point signed rows in `financial_event_entries`. One conversion therefore contains exactly one negative source entry and one positive destination entry. Both are inserted in the same SQLite transaction, and the source balance is checked inside that transaction before the event is committed.

The Settings `reference_syp_per_usd` value remains estimate-only and is never copied into a real conversion automatically. See `docs/CURRENCY_CONVERSIONS.md` for the complete conversion and audit rules.

## Legacy SharedPreferences migration

Previous versions stored the full challenge list as JSON under:

` saving_challenges_v1 `

On the first database access after upgrade:

1. Open/create the current schema.
2. Check the `legacy_shared_preferences_challenges_v1_migrated` metadata flag.
3. If migration has not run, read and decode the legacy JSON.
4. Insert each missing challenge and all of its cell values/completion state inside one SQLite transaction.
5. Write the migration-complete metadata flag in the same transaction.
6. Only after the SQLite transaction succeeds, remove the old SharedPreferences payload.

If decoding or database insertion fails, the completion flag is not written and the legacy payload is not removed, so the migration can be retried without intentionally discarding the original data.

## Challenge writes

Challenge create/update/delete/progress persistence resolves to SQLite transactions. Existing screen code may submit the full current challenge list through the compatibility repository method, but persistence is no longer written to SharedPreferences.

Dedicated repository methods also exist for add/update/delete operations so later financial-ledger work can move to narrower writes without another storage migration.

## Future financial tables

Gold and other bounded roadmap work must continue to use numbered SQLite migrations when persistent schema changes are required. Actual money movements must post into the ledger rather than maintaining independent balances.

## Backup

SQLite is local-only in this phase. User-controlled export/restore is planned separately in Issue #24 and must operate through a version-aware backup format rather than exposing the live database file directly.
