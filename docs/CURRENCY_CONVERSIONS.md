# Currency conversion rules

Mo Save distinguishes a real currency conversion from reference-rate valuation.

## Supported workflow

Issue #18 supports explicit conversions between SYP and USD in either direction.

The user records:

- the source currency and amount actually paid;
- the destination currency and amount actually received;
- the operation date;
- an optional note.

The executed rate is derived from those real amounts and stored historically using one convention regardless of direction:

`SYP per 1 USD`

For example, paying 1,300,000 SYP and receiving 100 USD stores an executed rate of 13,000 SYP/USD. Paying 100 USD and receiving 1,300,000 SYP stores the same rate.

## Ledger posting

One conversion is one `currencyConversion` financial event with exactly two balance-affecting entries:

- one negative source entry;
- one positive destination entry.

Both entries are inserted inside the same SQLite transaction, so a conversion cannot deduct one currency without also adding the other.

Before insertion, the current source balance is calculated from the ledger inside that transaction. The conversion is rejected if the source amount exceeds the owned balance.

## Historical executed rate

SQLite schema v8 adds nullable `executed_syp_per_usd` to `financial_events`.

The field is required by the application model for `currencyConversion` events and is not used by other event types. The stored rate must match the exact source/destination ledger amounts.

The exact amounts remain the accounting source of truth. The stored executed rate is audit metadata describing the historical deal that was actually performed.

## Reference rate remains estimate-only

`financial_settings.reference_syp_per_usd` is never used to fabricate conversion entries. It remains a mutable reference used only for current estimated valuation.

Changing the Settings reference rate after a conversion therefore changes current estimates only. It does not rewrite:

- the source amount;
- the destination amount;
- the historical executed rate;
- any current balance derived from the ledger.

## Scope boundary

SYP (N) conversion is intentionally not guessed into this workflow because the product has not defined a trustworthy conversion rule for it. Gold purchases and sales are handled separately by Issue #19.
