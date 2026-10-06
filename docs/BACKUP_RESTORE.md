# Mo Save — Backup and restore

## Scope

Issue #24 adds a user-controlled portable backup file for the complete local financial state.

The backup contains:

- financial Settings and initial-setup metadata;
- recurring expense-plan items;
- saving challenges/goals and every challenge cell;
- all financial ledger events and entries, including gold holdings derived from them;
- transaction revision/audit snapshots;
- local notification preferences.

Gold is not exported as a duplicated balance. It is restored from the same ledger entries that produce the owned gold-gram balance in normal app operation.

## File format

Backups use the `.mosave` extension. The file is JSON with an outer envelope containing:

- a stable format identifier;
- backup-format version;
- SQLite schema version;
- UTC creation timestamp;
- SHA-256 checksum;
- the complete payload as a JSON string.

The checksum is verified before any current data is changed. The payload contains table snapshots plus notification preferences.

The current implementation deliberately requires the backup SQLite schema version to match the app's current `LocalDatabase.schemaVersion`. An incompatible backup is rejected before restore. Future schema migrations must explicitly define compatible backup migration behavior rather than silently guessing at older/newer structures.

## Export

Settings exposes a backup action that opens the operating-system save picker. The user chooses where the `.mosave` file is stored, so it can be kept outside the app sandbox, including a Files location, cloud drive or a location later copied to a computer.

No storage-wide Android permission is required; the native document picker is used.

## Restore safety

The app first reads and validates the selected file, verifies its checksum and schema, then shows a summary and an explicit replacement warning.

Restore replaces the current local state; it does not merge two financial histories.

All SQLite rows are replaced inside one database transaction. Child rows are deleted before parent rows. Financial events are inserted before their entries, and `source_event_id` self-references are restored only after all event identities exist.

If any row violates the live schema, foreign keys, uniqueness constraints or another database rule, SQLite rolls the entire restore back. The app therefore never commits a half-restored financial database.

Notification preferences are restored with compensating rollback if the database transaction fails. Local reminders are rescheduled after a successful restore.

## Clean-install recovery

The backup action is available during the one-time fresh-install setup flow as well as normal Settings. Restoring a valid backup on a clean install restores the previous app state and completes initial setup, allowing the user to continue with the recovered data instead of recreating the plan manually.

After restore, Home, Challenges and Settings are rebuilt so cached screen state cannot keep showing values from before the replacement.

## Operational recommendation

A backup only protects against device loss or reinstall if the exported `.mosave` file is stored outside the device/app sandbox. The UI therefore tells the user to keep copies in an external location such as cloud storage or a computer.
