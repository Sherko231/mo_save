# MS-06 — Allocating a Real Receipt to Savings and Spending

**Issue:** [#80](https://github.com/Sherko231/mo_save/issues/80)  
**Product contract:** [FUNDS_ACCOUNTING_CONTRACT.md](FUNDS_ACCOUNTING_CONTRACT.md)  
**Implementation status:** source and tests committed to `main`, **not executed or device-verified**.

## 1. What changes money

Every actual receipt has **one** `financial_events` income event, identified by its existing stable payday recurrence key (for a scheduled salary) or a manual cash request identity (for gifts, bonuses, other one-off income). Its positive `financial_event_entries` are grouped by asset unit and assigned to funds:

```text
Actual receipt = Savings + Spending + Unallocated
```

These are multiple postings inside **one event**, not multiple income events or internal fund transfers. They affect both asset ownership and the fund classification in the same SQLite transaction. Zero-amount fund components are omitted because ledger entries must be nonzero. Actual income reports aggregate all positive entries for the event exactly once.

### Concrete examples

| Receipt | Savings | Spending | Unallocated | Actual income events |
| --- | ---: | ---: | ---: | ---: |
| Thursday 885,000 SYP | 345,000 | 540,000 | 0 | One +885,000 SYP |
| Monthly 300 USD | 300 | 0 | 0 | One +300 USD |
| Monthly 300 USD, user-edited | 200 | 75 | 25 | One +300 USD |
| 50 USD gift | 30 | 15 | 5 | One +50 USD |

At any point, `owned[unit] = savings[unit] + spending[unit] + unallocated[unit]`. A confirmed Savings allocation changes current Savings **and** owned assets, but it does not make the monthly income artificially larger.

## 2. Historical receipts that were partly spent

The existing MS-04 receipt form lets the owner enter money **previously spent** from an old salary. To avoid allocating cash that is gone, the owner can only distribute the **net remainder**:

```text
amount to allocate = actual receipt - already-spent amount

Savings + Spending <= amount to allocate

Income's Unallocated positive posting =
    already-spent amount + still-unallocated remainder

Linked actual expense's Unallocated negative posting =
    -already-spent amount

Unallocated after linked expense = still-unallocated remainder
```

Example: an actual **885,000 SYP** receipt, **80,000 SYP** already paid, **345,000 SYP** to Savings, and **460,000 SYP** to Spending yields:

- One +885,000 SYP income event with `345k savings + 460k spending + 80k unallocated` positive postings.
- One -80,000 SYP linked *actual expense* from Unallocated in the **same** transaction, not a fund transfer.
- Final balances: owned **805,000 SYP**, Savings **345,000**, Spending **460,000**, Unallocated **0**; actual expense **80,000 SYP** exactly once.
- Editing/removing the source receipt later is subject to the existing dependent-event and fund-conservation safeguards.

Over-allocation or attempting to debit an amount of historical expense not reserved from **that receipt's** Unallocated posting is rejected. A concurrent attempt to ignore a confirmed receipt cannot create contradictory states.

## 3. UI and defaults

**Scheduled weekly/monthly salary:** On Home, choose **تسجيل الاستلام**. The receipt dialog exposes actual amount/date, optional already-spent amount/date, Savings amount and Spending amount. The live Unallocated remainder is shown. The two allocation fields default to zero, leaving all unallocated until an explicit user choice.

**Optional, editable suggestions:** The **تطبيق التقسيم المقترح (اختياري)** button suggests the current configured Thursday envelope values (normally **540,000 SYP Spending / 345,000 SYP Savings**) capped to the **net amount still owned**. For USD monthly salary it suggests putting available USD in Savings, but **does not force this**. Users may adjust either value or leave some/all Unallocated; preset values are not evidence of actual cash.

**Manual income and opening cash:** Home → **إضافة دخل أو رصيد سابق** retains the simple choose-one-fund flow and adds a **تقسيم المبلغ على أكثر من صندوق** toggle. When switched on, Savings/Spending fields split the same receipt or opening cash once; the remainder remains Unallocated. A manual opening balance is still **not** reportable income.

**Legacy weekly envelope UI:** The old standalone Thursday `weeklyAllocation` form was removed from Home to prevent users mistaking its **non-balance-affecting planning record** for an actual transfer to Savings. Existing `weeklyAllocation` events and their history remain intact, can still appear in transaction audit, and do not enter fund balances. The current settings values remain as **optional suggestions** only; no automatic posting occurs.

**Post-confirmation changes:** This issue implements **initial allocation at receipt**. Subsequent intentional fund reclassification can use the explicit Unallocated reconciliation tool from MS-03; the general Savings↔Spending transfer UI belongs to MS-10. Corrections are currently available through the existing audited transaction-history workflow, preserving the per-entry original fund and its revision history; a fully redesigned correction flow is MS-16.

## 4. Persistence and acceptance boundaries

- The existing SQLite v10 entry-level `fund` column supports all splits; no new schema version or backup format is necessary.
- A schedule recurrence key uniquely identifies each real payday; repeated confirmations cannot make duplicate receipts.
- The `manual-cash:` request key prevents repeated manual saving of an identical action, including a multi-posting receipt; a different split under the same request identity is rejected.
- Funds and asset balances are recalculated from active event postings; there is no second mutable balance cache.
- The historic expense stays linked through `source_event_id`, and the combined commit is atomic.
- The **new** `test/receipt_fund_allocation_test.dart` covers: exact 885k split, arbitrary 300 USD split, nonzero Unallocated remainder, net-of-historic-spending allocations, oversplit rejection without partial events, idempotent manual gift split, and zero/invalid allocation model.
- No `flutter test`, analyzer, CLI preflight, APK build, simulated device, or client backup migration test has been run. The source and tests are **not runtime-verified**. MS-18 remains the release and real-device acceptance gate.
