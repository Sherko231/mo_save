# Mo Save — Local Data Storage

## Storage policy

Mo Save is offline-first. Financial records and saving challenges are stored locally on the device. There is no backend or cloud dependency in the agreed scope.

SQLite is the primary durable data store. `SharedPreferences` is not used as the primary store for financial records; it remains available only for tiny preferences and for the one-time migration of legacy challenge data.

## Database

- File: `mo_save.db`
- Engine: SQLite through `sqflite` on Android/iOS and `sqflite_common_ffi` on Windows/Linux development builds.
- Current schema version: `10`
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

`FinancialLedgerStorage` owns ordinary event persistence and balance queries. Balance reads sum only entries where `affects_balance = 1`; therefore screens derive owned balances from the ledger instead of maintaining separate cached totals.

Normal workflows append financial events. Issue #21 adds explicit user-authorized correction/delete flows through `TransactionHistoryService`; every pre-edit/pre-delete snapshot is first copied to schema-v9 revision storage before the current ledger event is changed.

## Schema v4 — Recurring occurrence identity

Schema v4 adds nullable `recurrence_key` to `financial_events` plus a partial unique index for non-null values.

Recurring income schedules are derived from the current financial settings and the real calendar instead of assuming four weeks per month. Each generated occurrence receives a stable key such as:

`income:weeklySyp:2026-10-08`

or:

`income:monthlyUsd:2026-10-01`

When the user confirms receipt, the resulting income event stores that key. The unique index prevents one scheduled occurrence from being confirmed twice. The actual amount entered by the user is stored in the ledger entry; later changes to salary defaults do not rewrite that historical transaction.

A configured monthly payday that does not exist in a shorter month is clamped to that month's final calendar day. Weekly occurrences are enumerated from actual dates, so months with five Thursdays naturally contain five weekly salary occurrences.

### MS-06 — Actual receipt split within the existing ledger (no schema change)

A single balance-affecting `income` event may have several positive entries
in the **same unit**, one each for `savings`, `spending`, and
`unallocated`. The sum equals the actual receipt amount in fixed integer
micros. No second receipt, fund-transfer event or cash balance cache is
created. If a linked historic expense is recorded, its amount is reserved
inside the receipt's Unallocated positive posting and then deducted by a
separate linked actual expense within the **same SQLite transaction**.
Consequently only the net **still owned** money is distributed between
Savings and Spending, and fund totals equal the owned asset total.

The manual one-off inflow and opening-balance workflow may also assign
the receipt across several funds through the same postings, retaining its
`manual-cash:` duplicate-request identity. Prior weekly
`weeklyAllocation` non-balance events remain historical planning data and
are **not** interpreted as true fund assignments. Old history and v9 backup
compatibility remain unchanged. Details and concrete 885k/300 USD examples:
[RECEIPT_FUND_ALLOCATION.md](RECEIPT_FUND_ALLOCATION.md).

### MS-05 — One-off income and opening assets (no new schema version)

Manual cash entries reuse the canonical v10 `financial_events` and
`financial_event_entries` tables. A real non-salary receipt uses event type
`income` and a category such as `هدية`, `مكافأة`, `عمل جانبي`, or
`بيع غرض غير مسجل كأصل`. A previously owned cash amount not yet recorded
uses the separate `openingBalance` event type, so it increases owned cash
once without being counted as earned income. Both have **one positive
balance-affecting posting** in USD/SYP/SYP (N), attributed to exactly one
`FinancialFund` (including the Unallocated option).

The optional source and detail are saved as labelled human-readable lines in
the existing event `note` (no new column); category and actual date use
existing fields. Each form uses one unique `manual-cash:<request-id>`
recurrence key for duplicate protection, **not** a recurring income schedule.
The key remains stable during a permitted manual date correction and is
included in ordinary backup/restore. Item sale income requires an explicit
confirmation that the sold item was **not** a tracked asset; actual conversion
or gold-sale ledger postings must be used for tracked holdings.

History retains its normal pre-update/delete revision snapshots, and the
manual opening type appears separately from earned income. See
[MANUAL_INCOME.md](MANUAL_INCOME.md) and [TRANSACTION_HISTORY.md](TRANSACTION_HISTORY.md).
No new SQLite migration or backup format version was introduced under MS-05.

### MS-04 — Ignored recurring paydays (no new schema version)

An expected income occurrence may be intentionally **ignored** using existing
`app_metadata` with key `ignored_income_occurrence:<recurrence-key>` and
value `1`. This is a **non-financial occurrence disposition**, not a
`financial_events` entry, income, expense, or balance-affecting posting. It
is retained in the existing `.mosave` backup because `app_metadata` is
already exported/restored.

Ignore and receipt confirmation use serialized SQLite transactions so a
single occurrence cannot be both ignored and received. Removing the metadata
key cancels Ignore and restores the option to register the receipt.

Historical income may use a different actual receipt date from its scheduled
payday, without losing the original `recurrence_key`. The Income screen
resolves receipts by scheduled identity, while monthly **actual** receipts
are grouped by the `occurred_at_ms` month. An optional already-spent amount
creates a separate `expense` event with `source_event_id` referencing the
receipt, in the same transaction, so fully spent old salaries do not increase
current cash. Such an expense counts once and must not duplicate expenses
previously recorded by the user. Legacy v9 data and old income events are
unchanged. See [INCOME_OCCURRENCES.md](INCOME_OCCURRENCES.md).

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

## Schema v9 — Financial event revision audit

Schema v9 adds `financial_event_revisions` so explicit corrections and deletions do not erase the previous user-visible transaction state.

Each revision stores:

- `id` — local autoincrement revision id;
- `event_id` — stable id of the financial event being changed;
- `action` — `update` or `delete`;
- `snapshot_json` — complete pre-mutation event snapshot, including all ledger entries and workflow metadata;
- `changed_at_ms` — when the correction/delete was confirmed.

The revision table deliberately has no foreign key to the current event row because a deleted event must keep its audit snapshot after the active ledger row is removed. Revision rows are audit-only and never participate in balance, expense, goal or valuation calculations.

The transaction-history UI merges active ledger events with final delete snapshots so deleted transactions remain visible in their original transaction month. Active corrected events show their revision count and detail view can show earlier snapshots.

Before replacing amounts, the correction flow checks resulting balances from the same SQLite transaction and rejects a mutation that would worsen an owned unit into a negative value. Deletion performs the equivalent check. Events with dependent `source_event_id` rows cannot be amount-corrected or deleted until the dependent event is handled, and challenge-owned saving contributions stay read-only in History so challenge progress cannot diverge from its canonical ledger contribution.

See `docs/TRANSACTION_HISTORY.md` for the user-facing correction rules.

## Schema v10 — Fund classification and zero-asset transfers (MS-02)

Schema v10 adds one field to `financial_event_entries`:

- `fund TEXT NOT NULL DEFAULT 'unallocated'` with allowed values `savings`, `spending`, and `unallocated`; indexed together with `unit`.

It does not rewrite a single older `financial_events` row or create new income. Existing v9 entries receive the SQLite default `unallocated`. Thus every old known owned balance is classified as **unallocated** until the user explicitly reconciles it (MS-03). Historical weekly envelopes and challenge completion cannot establish a verified Savings fund amount.

Each balance-affecting ledger entry now represents both an owned-asset delta and a delta to the selected fund. A new `fundTransfer` event represents an **equal and opposite pair of non-balance-affecting entries**, in the **same unit**, with different funds and equal absolute amounts. The entries adjust fund quantities only. The canonical owned-asset balance query continues to sum only `affects_balance = 1`. The fund query groups (1) balance-affecting entries and (2) `fundTransfer` entries; it ignores other non-balance entries such as `savingContribution` and `weeklyAllocation`.

Conservation, **for each** asset unit:

```text
Owned(unit) = Savings(unit) + Spending(unit) + Unallocated(unit)
```

`FinancialLedgerStorage` exposes `loadFundBalancesMicros()`, `loadFundBalanceMicros(fund, unit)`, `transferFunds(...)`, and `addFundTransfer(event)`. New fund-only transfers can be retried with the same stable event ID or recurrence key without double posting. The service checks source-fund availability and per-unit conservation inside the same SQLite transaction, rejecting operations that would worsen a negative fund balance. Gold grams cannot enter the immediately spendable `spending` fund. Conversion and gold purchase/sale postings preserve their pre-existing historic amounts and executed rates.

`TransactionHistoryService` now round-trips fund attribution in event revisions and blocks fund-invalid corrections/deletions in the existing atomic correction transaction. Existing event revision history is retained unchanged. This phase **does not** rewire the Home/Spending/Savings UI: ordinary old-screen events still default to `unallocated` until downstream issues implement explicit fund selection and salary distribution.

**MS-03 compatibility update:** versioned on-device SQLite v9→v10 upgrades classify legacy entries as Unallocated. The backup importer now accepts checksummed `.mosave` backups from schema v9 and v10, adds Unallocated classification to old entry rows, and transactionally checks per-unit fund conservation and fund transfer shape. The original v9 financial events, audit snapshots, expense plans, and goal cells remain intact. Manual classification is available from Settings → **توزيع أرصدتك القديمة**; it does not create any new income. See [BACKUP_RESTORE.md](BACKUP_RESTORE.md). These paths have test cases but have not been executed on-device; keep a verified independent backup until release acceptance.

Implementation tests have been added in `test/fund_ledger_test.dart` but have **not** been run (CLI checks explicitly omitted at owner request). See the issue and progress tracker for verification status.

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
