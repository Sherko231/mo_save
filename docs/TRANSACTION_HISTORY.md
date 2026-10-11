# Transaction history and correction rules

Issue #21 adds a user-visible audit trail over the existing financial ledger.

## History surface

Home exposes **سجل الحركات والتصحيحات**. The history is chronological and can be filtered by:

- calendar month;
- financial event type;
- currency/asset unit.

The history includes income, **distinct non-income opening balances**, expenses, challenge saving contributions, weekly allocations, SYP/USD conversions, gold purchases/sales and manual adjustments. Manual gift/bonus/side-work/item-sale receipts are income events identified by their category; their readable source and reason are kept in the note and visible in history. Opening one record shows every ledger entry, metadata, executed conversion rate when present, creation/update timestamps and prior revisions.

## Corrections do not edit balances directly

Balances remain derived from `financial_event_entries`. The correction UI edits the underlying event and its entries atomically, then all balance/dashboard views recalculate from the ledger. No cached balance is patched by the history screen.

For amount corrections, the event keeps its original id, units, entry directions and workflow links. Currency-conversion corrections derive a new historical SYP-per-USD executed rate from the corrected source/destination amounts.

## Safety rules

A correction or deletion is rejected when it would:

- make an owned unit more negative than its current balance;
- remove or change an event that still has a dependent `source_event_id` event;
- break a weekly envelope so its allocation exceeds the linked Thursday income;
- directly change a challenge saving-contribution event that is owned by the challenge grid.

Challenge saving contributions are therefore read-only in History. Their amount must be changed by changing the challenge cells, preserving the challenge/ledger reconciliation contract.

Generated recurring payday event dates remain attached to their generated occurrence and cannot be moved to another day from History. **Manual cash entries with `manual-cash:` identities may have their true date corrected**, since their identity is only an idempotent request key rather than a scheduled payday. Categories/notes and amounts can still be corrected with audit snapshots.

## Deletion and audit retention

Schema v9 adds `financial_event_revisions`. Before an explicit edit or delete, the current complete event snapshot is stored as JSON together with the action and timestamp.

Deleting an event removes it from the active ledger so derived balances and recurring workflows recalculate correctly, but the pre-delete snapshot stays in `financial_event_revisions`. Deleted records continue to appear in the history for their original transaction month with a **محذوفة** marker.

Updated active records expose their revision count and detail view shows prior snapshots, so the user can see that a transaction was corrected instead of silently losing the previous value.

## Source of truth

`financial_events` + `financial_event_entries` remain the current accounting source of truth. `financial_event_revisions` is audit-only and never contributes to balances, goals, expense totals or valuation.


## MS-16 — Unified fund-aware transaction history (Issue #90)

The canonical Arabic transaction history now provides **one chronological
source of truth** for current and cancelled transactions in the selected
calendar month. Filters include event type, asset unit, paying/receiving fund,
linked goal, and free-text search across category, note, original IDs,
recurrence/source IDs and linked goal IDs. Current goal names appear in a
dropdown; a deleted goal's historical ID remains selectable and searchable.

The read-only **المخطط والمتوقع — ليس مالاً منفذاً** section is separate
from recorded movements. It shows that month's time-effective recurring bill
plan plus expected/received/ignored income occurrences. Plan rows and
unconfirmed income **never** become ledger income, expenses or available
fund balances merely because they are displayed. Historical expected salaries
are based on current scheduled defaults and are labelled as such; old confirmed
receipts remain intact regardless of later edits to paydays or amounts.

Current-event details explicitly show every original signed entry and its
Savings/Spending/Unallocated attribution. Transfers show **source and
destination** separately and do not increase owned wealth. Details also expose
category, reason/note, event/source/recurrence IDs, related goal, event date,
created/updated times and, for real SYP/USD exchanges, the **executed historic
rate**, never today's reference valuation rate.

All amount/date/description edits and cancellation requests go through
`TransactionHistoryService` and its existing **single-transaction**
validation: keep event ID, unit, direction, ledger type, fund and related
identities; preserve exchange/conversion and equal-opposite fund-transfer
semantics; refuse invalid negative fund balances, unbacked goals or dependent
receipts; and write a previous full event snapshot before a permitted
mutation. An unchanged metadata form no longer creates a fictitious revision.
Cancellation removes the active event's balance effect **only if safe** and
retains the pre-cancelled event inside `financial_event_revisions`. Cancelled
records are visible for audit, not counted as new expenses or income. The UI
calls this `إلغاء أثر الحركة مع حفظ نسخة التدقيق`, not an irreversible
loss of history. It is a cancellation via audited removal, **not** a newly
posted opposite-direction income or expense.

Goal-grid reservation changes remain workflow-owned: they can be edited or
released **only on the goal screen**, where the real Savings backing rule is
checked atomically. History intentionally blocks direct edits to
`savingContribution` events. MS-16 additionally saves the *previous
non-balance goal-progress event* as an audit revision during edits, releases,
goal deletion and bulk replacement. Those snapshots record earlier checked
amounts and goal links without minting Savings or cash. Recreated goal-grid
postings with the same stable ID show one current event; older tombstones
remain accessible inside revisions, not counted as duplicate transactions.
Goal-creation/name-only edits with **zero posted progress** have no financial
ledger event to revise; they remain nonfinancial goal metadata. Existing old
grid history prior to MS-16 cannot be reconstructed and is not invented.

Audit revision rows have no parent-event FK, so they survive the cancellation
of the active event. The existing v12 portable backup includes these rows.
This feature introduces **no new schema, shadow balance, exchange rate, or
synthetic future event**; ledger and goal backing remain unchanged.

### Regression additions (authored, NOT executed)

- `test/unified_transaction_audit_test.dart`: direct 100 USD Savings expense
  appears once, correct to 80 and inspect old 100/note, safely cancel to
  restore the original Savings balance, retain all revisions; same-unit
  transfers preserve total assets, reject unequal legs, correct and cancel;
  old FX execution rate survives corrections; planned-only bills never debit;
  goal-grid release preserves old noncash state; a correction cannot underfund
  Savings already earmarked to a goal; unchanged metadata is revision-free.
- `test/unified_transaction_history_page_test.dart`: Arabic actual-vs-planned
  surface, income/bill section, original expense detail and expandible
  previous snapshots.

No Flutter analyzer, flutter tests, APK build, real-client v12 migration,
backup restore or Android RTL device test was performed for MS-16. All tests
above were written but are not known to pass. MS-18 is the mandatory client
verification and delivery gate.
