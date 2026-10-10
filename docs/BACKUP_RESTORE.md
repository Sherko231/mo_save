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

The current application uses SQLite schema **v10**. This version can restore `.mosave` backups created under schema **v9 or v10** with the existing backup envelope format version 1. Older (<v9) or newer (>v10) schemas, non-integral version values, malformed payloads and checksum failures are rejected **before replacing local data**. Restoration **replaces**, never merges, the local database.

For a verified v9 archive, the `financial_event_entries` rows lack the `fund` column. Import adds `fund = unallocated` to each such entry **after checksum verification** and before the single SQLite restore transaction. Historic income, expense and asset postings are not altered or replayed; their existing net amounts determine actual holdings. Old `weeklyAllocation` and `savingContribution` events remain non-balance-affecting historical entries and do **not** automatically constitute new Savings. Original event identities, notes, recurrence keys, exchange rates, expense plans, goal grid cells, revision JSON, app metadata and notification choices are restored. v9 revision snapshots lacking fund are interpreted as Unallocated when displayed.

For v10 archives each financial entry must carry a recognized `savings`, `spending` or `unallocated` fund designation. The import verifies per-unit fund attribution against owned balances inside the SQLite transaction, and rolls back invalid imports. This is **not** a promise to recover a corrupted or tampered backup; SHA-256 checksums validate integrity but do not encrypt or authenticate the file.

After restore, the user can open **Settings → Distribute old balances** (`توزيع أرصدتك القديمة`) to split actually owned, still-Unallocated money among Savings and Spending through explicit atomic **fund-only transfers**. Such transfers never create income or inflate asset totals. Gold may be allocated to Savings, not directly to cash spending. Negative historical holdings are surfaced for correction, not silently reset. The action remains accessible for future unallocated deposits.

Versioned on-device upgrades use SQLite's incremental `onUpgrade` from v9 → v10 (adding the new fund field with the Unallocated default). **Never uninstall or reset the user's application to perform this upgrade.** Prior challenge progress is preserved but is not promoted to goal-backed Savings until MS-13 reconciles it.

New backups exported by schema v10 carry v10 metadata, including explicit fund assignments. A subsequent v10 restore must not duplicate any receipts or internal fund transfer postings; a restore is a replacement, not an append.

The MS-03 tests (`test/local_database_migration_test.dart`, `test/legacy_backup_compatibility_test.dart`) include a v9 SQLite fixture and the v9→v10 backup conversion/round-trip, revisions, goals, budgets, checksum rejection, and no phantom income. **Tests were authored but not executed**, per the requested no-CLI-check workflow; a real device/data acceptance run remains required before final release.

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
