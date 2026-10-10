# MS-05 — Manual Income and Opening Cash

**Issue:** [#79](https://github.com/Sherko231/mo_save/issues/79)  
**Dependency:** MS-02 (#76)  
**Implementation:** source changes committed directly to `main`. Automated tests have been authored but **not run**.

## Product behavior

Use **Home → إضافة دخل أو رصيد سابق** to record a one-off real cash receipt.

| Source selected by the user | Persisted event type | History classification | Monthly earned-income report? |
| --- | --- | --- | --- |
| Gift | `income` | `هدية` | Yes |
| Sale of an item **not previously tracked as an app asset** | `income` | `بيع غرض غير مسجل كأصل` | Yes |
| Bonus | `income` | `مكافأة` | Yes |
| Side work | `income` | `عمل جانبي` | Yes |
| Other real inflow | `income` | `دخل إضافي` | Yes |
| Cash owned before it was entered into Mo Save | `openingBalance` | `رصيد افتتاحي سابق` | **No** |

All six types credit an owned **cash asset** exactly once. Supported cash units are USD, SYP and SYP (N), stored as integer micros. Gold grams are excluded; real gold purchases/sales must use the existing asset-trade workflow and its historical executed values.

An optional **source** field and a separate user **note** field are saved as readable labelled text within the existing event `note` field:

```text
المصدر: Birthday present from a friend
التفاصيل: Received on 10 October
```

The event `category` preserves the chosen inflow classification. The cash input stores the user's actual date, unit, amount, chosen fund, source and note. The selected fund is a classification of the **same receipt**: `savings`, `spending`, or `unallocated`. It is **not** a fund-transfer event and does not create a second deposit. More granular split allocation on a recurring salary is MS-06.

## Opening cash and duplicate safeguards

Opening balances exist to represent **previously owned cash never entered before**, without displaying it as new income. Users are explicitly warned not to post money already included in owned balances. Previously recorded legacy money in `Unallocated` must be moved by **Settings → توزيع أرصدتك القديمة**; it must not be entered as a second opening balance.

Item sales are appropriate only for goods **not represented as owned app assets**; the user must confirm that distinction. Tracked USD/SYP/gold holdings must instead use an actual conversion or gold sale. The service rejects an item-sale receipt unless `untrackedAssetSaleConfirmed = true`.

Every form opening generates a stable request ID. The service inserts an event with that ID and a uniquely indexed `manual-cash:<request-id>` recurrence key. Repeated requests with the same identity and **identical** details return the existing event, never add another receipt. Reuse with changed values fails. A disabled Save button prevents accidental repeat submissions during an in-flight request. Users must still avoid manually recording the same transaction again using a different form/request.

The dates cannot be in the future; the amount must be positive; the form parses cash amounts into integer micros without floating-point rounding (whole SYP and SYP (N); USD to two decimal places). The event remains in the canonical `financial_events` and `financial_event_entries` tables, with the existing atomic conservation checks and fund attribution; **no schema migration** is required beyond existing SQLite v10.

## Corrections, audit, and reporting

- The new `openingBalance` event type is displayed explicitly as **رصيد افتتاحي (ليس دخلاً)** in transaction history.
- Corrections/deletions use `TransactionHistoryService` and retain `financial_event_revisions` snapshots. Corrections preserve the entry's unit, fund, event type, category/notes (unless separately edited), and positive direction; they may not break fund balances.
- The history's edit-date restriction remains for generated recurring paydays. Manual cash events with `manual-cash:` identities are allowed to have their actual date corrected while preserving retry identity.
- Actual income aggregates use only `FinancialEventType.income`. `openingBalance` is **excluded** from earned-income reports. Internal `fundTransfer` is neither income nor expense.
- History shows the selected category and readable source/note; the full note appears in transaction detail.

## Reconciliation examples

**A gift:** one 50 USD gift allocated to Savings → owned USD +50, Savings USD +50, monthly income USD +50, no expense.

**Existing money:** 200 USD cash held before using the app, newly recorded in Unallocated → owned USD +200, Unallocated USD +200, **monthly income +0**.

**An already-owned asset sale:** selling tracked gold for USD cannot be recorded as `itemSale` income, because that would count the proceeds without debiting gold. Use the gold-sale transaction instead.

## Testing and delivery limits

`test/manual_inflow_service_test.dart` contains test cases for: gift posted once, opening cash excluded from income, repeated request versus conflicting reuse, source/category persistence, physical gold rejection, invalid amounts/dates, explicit untracked-item confirmation, safe amount correction, and retained revision snapshots.

**The tests have not been executed**. No Flutter analyzer, CLI checks, Android install, backup import, or client acceptance run was carried out. The full redesigned Savings/Spending workflow and allocation UI is still incomplete until MS-06 and downstream issues.
