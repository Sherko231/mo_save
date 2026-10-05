# Mo Save — Local Data Storage

## Storage policy

Mo Save is offline-first. Financial records and saving challenges are stored locally on the device. There is no backend or cloud dependency in the agreed scope.

SQLite is the primary durable data store. `SharedPreferences` is not used as the primary store for financial records; it remains available only for tiny preferences and for the one-time migration of legacy challenge data.

## Database

- File: `mo_save.db`
- Engine: SQLite through `sqflite` on Android/iOS and `sqflite_common_ffi` on Windows/Linux development builds.
- Current schema version: `2`
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

Changing these settings affects future defaults only. Historical financial transactions, once introduced, must preserve the values actually used at the time and must never be rewritten by later settings changes.

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

Income, expense, transaction, conversion and gold-operation tables belong to later bounded roadmap Issues. They must be introduced through numbered SQLite migrations so existing client data survives application upgrades.

## Backup

SQLite is local-only in this phase. User-controlled export/restore is planned separately in Issue #24 and must operate through a version-aware backup format rather than exposing the live database file directly.
