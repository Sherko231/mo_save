# Transaction history and correction rules

Issue #21 adds a user-visible audit trail over the existing financial ledger.

## History surface

Home exposes **سجل الحركات والتصحيحات**. The history is chronological and can be filtered by:

- calendar month;
- financial event type;
- currency/asset unit.

The history includes income, expenses, challenge saving contributions, weekly allocations, SYP/USD conversions, gold purchases/sales and manual adjustments. Opening one record shows every ledger entry, metadata, executed conversion rate when present, creation/update timestamps and prior revisions.

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

Recurring event dates remain attached to their generated occurrence and cannot be moved to another day from History. Notes/categories can still be corrected.

## Deletion and audit retention

Schema v9 adds `financial_event_revisions`. Before an explicit edit or delete, the current complete event snapshot is stored as JSON together with the action and timestamp.

Deleting an event removes it from the active ledger so derived balances and recurring workflows recalculate correctly, but the pre-delete snapshot stays in `financial_event_revisions`. Deleted records continue to appear in the history for their original transaction month with a **محذوفة** marker.

Updated active records expose their revision count and detail view shows prior snapshots, so the user can see that a transaction was corrected instead of silently losing the previous value.

## Source of truth

`financial_events` + `financial_event_entries` remain the current accounting source of truth. `financial_event_revisions` is audit-only and never contributes to balances, goals, expense totals or valuation.
