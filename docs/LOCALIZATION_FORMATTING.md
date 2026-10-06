# Mo Save — Arabic localization and financial formatting

## Production language

Mo Save production UI is Arabic-only.

- `MaterialApp` is pinned to the Arabic locale (`ar`).
- Flutter Material, Widgets and Cupertino localization delegates are enabled so framework-owned UI such as date pickers is Arabic too.
- The app root enforces right-to-left layout. Individual screens should not need their own direction wrapper unless they intentionally render an isolated left-to-right value.
- Internal enum names, database values, recurrence keys and serialized field names remain stable implementation details and are not translated in persistence.

## Shared formatting

Client-visible money, asset quantities, dates and percentages should use the shared helpers instead of page-specific formatters:

- `FinancialFormat` for cash, gold, rates, dates, date/time values and percentages.
- `ChallengeFormat` for saving-goal currencies, amounts and sequence labels.

Pages should not create their own thousands-separator or currency-label implementations unless the value is an editable raw input.

## Number policy

The UI uses western decimal digits with comma thousands grouping and a dot decimal separator. Examples:

- `2,160,000 ل.س`
- `$300`
- `$1,250.50`
- `1.275 غ`
- `75٪`

Trailing zero decimals are removed when they do not add meaning. Gold supports up to three displayed decimal places; USD supports up to two; SYP and SYP (N) display whole units.

## Currency and asset labels

- USD: dollar symbol for amounts (`$300`) and Arabic prose label `الدولار الأمريكي` where a name is needed.
- SYP: `ل.س` for amounts and `الليرة السورية` in prose.
- SYP (N): `ل.س جديدة` for amounts and `الليرة السورية الجديدة` in prose.
- Gold: grams shown as `غ` and prose label `الذهب`.

Reference valuation strings are explanatory rather than raw currency-code expressions. For example, the SYP/USD reference rate is displayed as `1 دولار = 15,000 ل.س`.

## Dates and percentages

Date-only values use `d/M/yyyy`. Date/time values use `d/M/yyyy HH:mm` in device local time. Saving progress uses the Arabic percent sign (`٪`).

## Saving goals

Saving-goal sequence labels are Arabic:

- Ordered → `تصاعدي`
- Random → `عشوائي`
- Reversed → `تنازلي`

The underlying enum values remain unchanged so existing challenge data and backups remain compatible.

## Compatibility

This localization pass changes presentation only. It does not change SQLite schema, ledger amounts, historical transaction data, challenge IDs, recurrence keys or backup payload structure.
