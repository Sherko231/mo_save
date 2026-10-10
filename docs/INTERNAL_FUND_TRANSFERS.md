# MS-10 — Internal Savings ↔ Spending Transfers

**GitHub Issue:** [#84](https://github.com/Sherko231/mo_save/issues/84)  
**Source implementation:** committed directly to `main`. **Neither automated tests nor an Android device run have been executed.**

## User interaction

Home → **نقل بين الادخار والمصاريف**, or Spending dashboard →
**نقل من الادخار للمصاريف أو بالعكس**, opens a dedicated Arabic fund-transfer
screen. The user explicitly chooses the paying fund (`Savings` or
`Spending`), the other fund becomes the destination, and the user enters
an exact positive amount, SYP/USD/SYP (N) cash unit, date and optional note.

The screen shows actual per-currency source and destination balances and a
preview of each fund's post-transfer balance. The source cannot supply more
than its available cash; all cash balance enforcement is repeated **inside**
the ledger's SQLite transaction, so stale displayed balances cannot authorize
an overdraft. A confirmation dialog explicitly states that it is **not new
income or spending**, and not a currency conversion. One form opening uses
one stable request identity, so retrying an identical submitted transfer will
not create a second posting, even after it fully drains the source.

A dated transfer is an actual classification movement posted on that date.
The validation checks fund balances at the time of writing; it does **not**
currently reconstruct every historical point-in-time fund balance for a
backdated transfer. The historic replay/audit enhancements are part of the
later MS-16 work. Future-dated transfers are rejected.

The older **توزيع الأرصدة القديمة** screen continues to transfer money out
of `Unallocated` to the chosen cash fund, and also handles physically held
gold going to Savings. This MS-10 screen is intentionally **only Savings ↔
Spending cash**. Gold grams cannot be put in the Spending fund.

## Accounting contract

A fund reclassification uses the existing `fundTransfer` event with
exactly two postings of equal size in the **same** unit:

```text
Savings → Spending, 100 USD:

fund=savings,  unit=usd, amount_micros=-100000000, affects_balance=false
fund=spending, unit=usd, amount_micros=+100000000, affects_balance=false

Net owned USD = 0 from this event.
Net current income = 0. Net actual expense = 0.
```

The source and destination must differ. Entries have opposite signs, equal
absolute micros and `affects_balance=false`. A transfer has no FX rate,
no foreign-currency or gold change, no hidden source of new assets and no
monthly income/expense posting.

| Step | Owned USD | Savings USD | Spending USD | Actual expense USD |
| --- | ---: | ---: | ---: | ---: |
| Start with 500 USD saved | 500 | 500 | 0 | 0 |
| Move 100 USD from Savings to Spending | **500** | **400** | **100** | **0** |
| Pay 100 USD from Spending | **400** | **400** | **0** | **100** |

If a 100 USD transfer is undone **after** that cash has already been spent
from Spending, the delete/correction must fail unless there is enough
remaining Spending money to support the reversal. The audited
`TransactionHistoryService` already prevents net-negative funds and keeps
pre-change `financial_event_revisions` snapshots when a modification is
permitted.

SYP, USD and SYP (N) are separate units and no automatic conversion occurs
here. **Home → الأرصدة والتحويلات → تحويل عملة** remains the distinct
real SYP↔USD conversion workflow, with two actual asset entries and the
stored `executed_syp_per_usd` from the executed transaction. It must not
be represented by one same-unit fund transfer or inferred from a mutable
reference rate.

## Ledger and audit compatibility

- Existing canonical v11 `financial_events`, `financial_event_entries`
  and their `fund` attribution are reused. No new schema or balance cache.
- `FundTransferService.move` validates source/destination, cash-only unit,
  amount, date, note length and stable request identity, then calls the
  existing `FinancialLedgerStorage.transferFunds` API.
- `addFundTransfer` performs its duplicate identity check and fund
  conservation in one SQLite transaction. An identical retry is a no-op;
  conflicting reuse rejects.
- Transaction History displays the transfer direction, amount, date and
  optional note; fund-specific filters include both sides. Permitted edits
  and deletes retain revisions and respect fund balance conservation.
- Existing v9/v10 migration, v11 backup, old Unallocated classifications,
  goal/challenge progress and actual expense records are untouched. Portable
  backups already serialize canonical financial events/entries/revisions.

## Authored regression coverage — NOT RUN

`test/fund_transfer_page_test.dart` also defines a widget scenario for opening the Arabic form, entering 100,000 SYP, confirming the transfer and checking both fund balances without changing owned assets.

`test/fund_transfer_workflow_test.dart` includes 500→400+100 USD fund
conservation followed by a real 100 USD Spending expense; reverse transfer;
insufficient source balance; full-source duplicate retry with payload
conflict; same-fund, Unallocated, gold, zero, future-date and missing-identity
rejections; SYP/SYP (N) isolation; fund-filtered transaction history and
audited corrections, deletion, and refusal to undo a transfer backing cash
that has already been spent.

**Unverified:** Flutter analyzer, `flutter test`, APK, real Android UX,
customer database v11 upgrade, or client backup/restore. Do not treat the
committed tests as passing. Final integration and release acceptance remain
MS-18 (#92).
