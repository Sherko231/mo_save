# Mo Save — Local Data Storage

## Storage policy

Mo Save is offline-first. Financial records and saving challenges are stored locally on the device. There is no backend or cloud dependency in the agreed scope.

SQLite is the primary durable data store. `SharedPreferences` is not used as the primary store for financial records; it remains available only for tiny preferences and for the one-time migration of legacy challenge data.

## Database

- File: `mo_save.db`
- Engine: SQLite through `sqflite`
- Current schema version: `1`
- Foreign keys are enabled for every opened connection.

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

## Legacy SharedPreferences migration

Previous versions stored the full challenge list as JSON under:

` saving_challenges_v1 `

On the first database access after upgrade:

1. Open/create schema v1.
2. Check the `legacy_shared_preferences_challenges_v1_migrated` metadata flag.
3. If migration has not run, read and decode the legacy JSON.
4. Insert each missing challenge and all of its cell values/completion state inside one SQLite transaction.
5. Write the migration-complete metadata flag in the same transaction.
6. Only after the SQLite transaction succeeds, remove the old SharedPreferences payload.

If decoding or database insertion fails, the completion flag is not written and the legacy payload is not removed, so the migration can be retried without intentionally discarding the original data.

## Challenge writes

Challenge create/update/delete/progress persistence now resolves to SQLite transactions. Existing screen code may submit the full current challenge list through the compatibility repository method, but persistence is no longer written to SharedPreferences.

Dedicated repository methods also exist for add/update/delete operations so later financial-ledger work can move to narrower writes without another storage migration.

## Future financial tables

Income, expense, transaction, settings, conversion and gold tables are intentionally not created in schema v1 because they belong to later bounded roadmap Issues. They must be introduced through numbered SQLite migrations so existing client data survives application upgrades.

## Backup

SQLite is local-only in this phase. User-controlled export/restore is planned separately in Issue #24 and must operate through a version-aware backup format rather than exposing the live database file directly.
