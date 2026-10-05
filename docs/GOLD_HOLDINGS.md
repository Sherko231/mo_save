# Gold holdings and purchase rules

Mo Save tracks physical gold as an owned asset in grams. Gold is not a second copy of the cash used to buy it: the ledger moves value from cash into grams in one atomic event.

## Purchase workflow

The Home balance section exposes a gold-purchase action. The user records:

- the cash currency actually paid (`SYP` or `USD`);
- the cash amount actually paid;
- the grams actually received;
- the operation date;
- an optional note.

The current gold reference price from Settings is shown only as context. It is not used to fabricate the purchase amount or the grams received.

## Ledger posting

One purchase is one `goldPurchase` event with exactly two balance-affecting entries:

- a negative cash entry for the amount actually paid;
- a positive `goldGram` entry for the grams actually received.

Both entries are inserted in the same SQLite transaction. Before insertion, the source cash balance is recalculated from the ledger inside that transaction. If the user no longer owns enough cash, the whole purchase is rejected and neither side is posted.

This prevents double-counting: buying gold reduces cash and increases gold rather than adding gold while leaving the same cash balance untouched.

## Gold valuation

Owned grams are part of the balance engine introduced in Issue #15. Their estimated USD value is:

`gold grams × current Settings gold USD-per-gram reference price`

The reference price is mutable valuation data. Changing it changes only the current estimate and never rewrites purchase history, cash balances, or the grams held.

The purchase UI also derives the actual cash paid per gram from the entered transaction values for immediate feedback. The exact cash and gram ledger entries remain the accounting source of truth.

## Sale foundation

`GoldService` also provides the inverse posting model for a future sale UI:

- negative `goldGram` entry;
- positive SYP or USD cash entry.

The service checks the available gold balance in the same transaction and refuses a sale that would take holdings below zero. Issue #19 does not expose the sale UI yet.

## Manual correction foundation

Gold quantity corrections use an explicit `manualAdjustment` event with category `goldCorrection` rather than pretending a correction was a purchase or sale. Negative corrections are balance-checked so they cannot take holdings below zero.

The user-facing audit/correction workflow belongs to the later transaction-history task. Keeping the correction as a normal ledger event preserves traceability and allows balances to remain fully derived from the ledger.

## Persistence

No new SQLite table or schema version is required for Issue #19. Existing financial-event and financial-entry tables already support `goldPurchase`, `goldSale`, `manualAdjustment`, and the `goldGram` unit.
