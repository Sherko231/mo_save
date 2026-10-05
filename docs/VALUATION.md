# Balance and valuation rules

Mo Save treats owned assets and estimated value as two different concepts.

## Owned balances

The source of truth is the financial ledger. Current balances are derived only from `financial_event_entries` where `affects_balance = 1`.

Separate balances are maintained for:

- USD;
- SYP;
- SYP (N);
- gold grams.

Envelope allocations and saving earmarks do not create extra owned money because their tracking entries are non-balance-affecting.

## Estimated USD value

The estimated combined USD value is derived at display time and is never stored as a historical balance.

- USD contributes its current USD balance directly.
- SYP is divided by the current `reference_syp_per_usd` Settings value.
- Gold grams are multiplied by the current `gold_usd_per_gram` Settings value.
- SYP (N) remains a separate balance because the product does not currently define a trustworthy SYP (N) ↔ USD reference conversion. A non-zero SYP (N) balance therefore makes the combined estimate explicitly incomplete rather than being guessed.

If a non-zero SYP balance has no configured exchange rate, or a non-zero gold balance has no configured gold price, the UI reports that the full estimate is unavailable and explains which setting is missing.

Changing a reference exchange rate or gold price changes only the current estimate. It never rewrites ledger events, owned balances, or challenge progress.

## Display precision

Balance cards use these deterministic display rules:

- USD: 2 decimal places;
- SYP: whole units;
- SYP (N): whole units;
- gold: 3 decimal places;
- estimated USD values: 2 decimal places.

Thousands separators are used for readability. Ledger storage remains fixed-point micros, so display rounding never changes stored values.

## Refresh behavior

Ledger mutations publish an in-process change event. Balance views subscribe to that event and recalculate from the ledger after successful income, expense, correction, conversion, gold, or other future ledger writes. Returning to Home also reloads the current Settings references so valuation changes are reflected without rewriting history.
