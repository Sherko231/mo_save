# MS-01 — Fund-Ledger Accounting Contract

**Status:** Design contract approved for implementation; **no code or database migration is implemented by MS-01**.  
**Issue:** [#75 — MS-01](https://github.com/Sherko231/mo_save/issues/75)  
**Next dependency:** [#76 — MS-02](https://github.com/Sherko231/mo_save/issues/76)  
**Product source:** [FUNDS_REDESIGN.md](FUNDS_REDESIGN.md)

This document defines the mandatory accounting semantics for the upcoming Savings/Spending redesign. If a later implementation violates an invariant below, that implementation is incorrect even if the UI looks plausible.

## 1. Financial concepts and what they do *not* mean

| Concept | Formal meaning | Not interchangeable with |
| --- | --- | --- |
| Owned balance | Net quantity of a specific owned asset from active balance-affecting ledger postings. | Income, all-time savings contributions, planned budgets, goal progress. |
| Asset unit | One of `usd`, `syp`, `sypNew`, or `goldGram`. Quantities of different units must not be summed directly. | Reference USD valuation. |
| Savings fund | Portion of *currently owned* assets intentionally reserved for saving. Has a per-unit balance. | Total wealth, all earnings ever received, unchecked/checked challenge cells. |
| Spending fund | Portion of currently owned **cash** available to pay expenses. Has per-unit balances; it must not implicitly contain Savings or unvalued gold. | Expected net-of-bills remainder, all current assets. |
| Unallocated fund | Explicit holding bucket for newly received assets not yet split, and for legacy assets whose historical fund assignment is unknowable. | Income category, an expense or a hidden default Savings fund. |
| Goal earmark | Reservation of a portion of Savings for one goal, in a defined asset unit. | Additional owned assets or additional Savings. |
| Actual expense | A completed payment/outflow from a chosen fund, with amount, unit, date, category and optional reason. | Planned recurring bill, internal transfer or conversion principal. |
| Planned commitment | Forecast/plan for an expected bill. No impact on owned or fund balances until a real payment is posted. | A settled expense. |
| Receipt | Real external income or other cash inflow recognized once, tied to a date/source. | A proposed recurring salary, an internal transfer or a preexisting opening balance. |
| Opening balance | Previously owned money recorded to initialize the app; increases initially recorded assets but **not** current-period earned income. | A new salary, gift or sale receipt. |
| Reference valuation | Optional estimate computed from current user-entered FX and gold reference prices. | An executable conversion, historical transaction amount or asset itself. |

Gold is a **non-spendable physical holding**, initially allocated to Savings or Unallocated. It may be liquidated through a genuine sale into cash assigned to a chosen fund. It must never appear as spendable Spending cash without a sale. `sypNew` is distinct from `syp`; no automatic FX relationship is assumed.

### Four financial views that must not be confused

1. **Savings now:** present Savings-fund balances per asset unit. For multi-asset view, optionally show *estimated* USD value **only if every nonzero unit is valuably convertible**; otherwise mark incomplete and list missing reference inputs.
2. **Spendable now:** current Spending cash balances per cash unit, without subtracting bills that have not been paid yet.
3. **Projected post-commitment room:** optional spending-fund cash minus upcoming planned commitments in matching units, explicitly labelled as a projection, never presented as the available balance.
4. **This month's actual expenses:** sum of completed expense events by occurred-at month, unit, category and source fund. Transfers and unpaid planned items are not expenses.

`Total assets` (Savings + Spending + Unallocated per asset) is distinct from `Savings now`. `Net savings added this period` means **real net movement into Savings** after withdrawals/transfers and excludes market reference-value changes; distinguish this from current total Savings.

## 2. Exact conservation and validation invariants

All accounting quantities are signed integer *microunits* (`1 unit = 1,000,000 micros`), consistent with existing `LedgerEntry.amountMicros`. Do not use floating-point sums for persisted quantities.

Let `B[u]` be the sum of **active** `financial_event_entries` with `affects_balance = 1`, grouped by unit `u`. Let `F[u,f]` be the active fund-owned quantity in unit `u` and fund `f` (`Savings`, `Spending`, `Unallocated`).

For **every** unit (USD, SYP, SYP (N), goldGram) and every committed state:

```text
B[u] = F[u,Savings] + F[u,Spending] + F[u,Unallocated]

For each new/edited financial event E and unit u:
SUM_f(deltaFund(E,u,f)) = deltaOwned(E,u)

For a pure same-unit internal fund transfer T:
SUM_f(deltaFund(T,u,f)) = 0
deltaOwned(T,u) = 0

For each goal G and asset unit u:
0 <= earmarked(G,u) <= eligible unassigned Savings for G,u
SUM_goals earmarked(G,u) <= F[u,Savings]
```

Additional constraints:

- Validate **available source-fund balance** and total owned balance in the **same SQLite transaction** before posting a debit. No silently negative fund quantities or uncontrolled overdrafts.
- Financial event, its owned-asset entries (if any), fund deltas, goal effects, occurrence link, and relevant revision metadata commit **atomically**, or none do.
- No double booking: a salary receipt creates a *single external inflow*; assigning 540k/345k between funds is a classification of that same inflow, not another 885k credit.
- No phantom deposits from Savings-goal checkboxes, forecasts, weekly-envelope allocations, or ignored overdue salaries.
- Identical client actions retried after UI/navigation/crash must be idempotent using stable identifiers/recurrence keys where applicable.
- Preserve active-event audit/revision history on correction or deletion; aggregate current balances must use **only active** entries, never revision snapshots.
- Fund-level historical backdating/corrections must not invalidate a dependent allocation or goal earmark. Reject or explicitly unwind linked operations atomically.
- For historical data with an already-invalid balance, **flag for reconciliation rather than manufacturing offsetting money**. MS-02/MS-03 must specify how restrictions apply without changing old rows.

> Implementation recommendation for MS-02: attach fund delta records to each canonical event and derive fund balances from them; maintain a migration-opening allocation checkpoint for existing v9 assets. Do **not** store an independently editable running-total cache or duplicate the owned-asset ledger as income. Schema/table names are deliberately left to MS-02.

## 3. Canonical event and fund-posting matrix

All amounts below are illustrative; each row describes the **effect on the active ledgers**, not a second balance store.

| Event | Owned asset delta | Savings fund delta | Spending fund delta | Unallocated delta | Income? | Actual expense? |
| --- | --- | --- | --- | --- | --- | --- |
| Received 885,000 SYP Thursday pay, allocated 345k/540k | +885,000 SYP | +345,000 SYP | +540,000 SYP | 0 | +885,000 SYP | No |
| Received 300 USD pay, allocated all to Savings | +300 USD | +300 USD | 0 | 0 | +300 USD | No |
| Received 50 USD gift, allocation postponed | +50 USD | 0 | 0 | +50 USD | +50 USD | No |
| Reallocate 50 USD existing Unallocated → Savings | 0 | +50 USD | 0 | -50 USD | No | No |
| Record historic opening 200 USD to Unallocated | +200 USD | 0 | 0 | +200 USD | **No** | No |
| Ignore one old unpaid-looking salary occurrence | 0 | 0 | 0 | 0 | No | No |
| Transfer 100 USD Savings → Spending | 0 | -100 USD | +100 USD | 0 | No | No |
| Pay 80,000 SYP outing from Spending | -80,000 SYP | 0 | -80,000 SYP | 0 | No | +80,000 SYP |
| Pay 100 USD directly from Savings | -100 USD | -100 USD | 0 | 0 | No | +100 USD |
| Earmark 100 USD of existing Savings to a goal | 0 | 0 | 0 | 0 | No | No |
| Set next month's ampere bill to 250k SYP | 0 | 0 | 0 | 0 | No | No |
| Real conversion: 1,300,000 SYP Spending → 100 USD Savings | -1,300,000 SYP; +100 USD | +100 USD | -1,300,000 SYP | 0 | No | No |
| Buy 2 g gold using 200 USD Savings | -200 USD; +2 goldGram | -200 USD; +2 goldGram | 0 | 0 | No | No |
| Sell 2 g gold from Savings for 210 USD deposited to Spending | -2 goldGram; +210 USD | -2 goldGram | +210 USD | 0 | No | No |
| Reverse a 100 USD Savings expense | +100 USD | +100 USD | 0 | 0 | No | -100 USD net of reversal (linked adjustment) |

The FX/gold examples use **actual entered amounts and historical executed rates**, not changing Settings reference values. Mixed-unit transfers are **not** ordinary internal fund transfers; they are explicit asset conversion or sale/purchase events.

A linked refund/void must reverse or adjust original expenditure with correct category and date attribution; it is **not** earned income. The exact reporting UI for partial refunds is scheduled beyond MS-01; enforce conservation regardless.

### Worked examples: no double counting

**Example A — direct Spending expense**

```text
Receipt                885,000 SYP owned
Funds                  345,000 Savings + 540,000 Spending
Pay outing             -80,000 Spending and -80,000 owned
After                  345,000 Savings + 460,000 Spending = 805,000 owned
This month's expenses  80,000 SYP (one event, classified as outing)
```

**Example B — expense funded by Savings**

```text
Initial                500 USD Savings; 0 Spending; 500 USD owned
Direct expense         100 USD from Savings (reason + category required)
After                  400 USD Savings; 0 Spending; 400 USD owned
Actual expense         100 USD exactly once
```

**Example C — transfer followed by payment**

```text
Initial                500 USD Savings
Fund transfer          Savings -100; Spending +100; assets unchanged; expenses 0
Actual payment         Spending -100; owned USD -100; expenses +100
Final                  400 USD Savings; 0 Spending; actual expense 100
```

**Example D — goal assignment is not income**

```text
Current Savings        300 USD
Goal A earmark         100 USD (reserved WITHIN existing 300)
Goal B free maximum    200 USD
Owned assets            300 USD, not 400
If an earmarked sum must be spent, first release/reduce the earmark
in the same confirmed workflow, or explicitly reject the payment.
Never leave 100 USD "completed" when insufficient backing remains.
```

## 4. Expense and income semantics

1. A recurring salary schedule is **expected income only** until user confirmation of actual receipt. Use real calendar occurrences: Thursday may occur four or five times in a month. A receipt is an income event with actual amount/date and stable occurrence identity.
2. An ignored occurrence is a **separate occurrence disposition** (ignored/dismissed), not a synthetic zero-valued receipt. It is persistent, non-financial, and should support later correction/restoration of the decision without creating duplicate income. Historical receipt and earlier actual spending can instead be posted with explicit dates.
3. Manual inflows require real receipt category/source/amount/date/unit. **Selling an item that was not represented as an owned asset** can be categorized as sale income; liquidating already-tracked gold/currency is a conversion/sale, **not** a second income event.
4. A historical opening balance represents preexisting holdings, not the period's income. Distinguish when/why it was initialized, and never silently use it as an actual-salary substitute.
5. Expense records require positive amount, cash unit, actual date, categorized reason (or a user-supplied Other category) and an **explicit paying fund**. Expenses from Savings appear in monthly reports exactly as expenses from Spending do.
6. A planned recurring bill is a time-effective budget record; editing future utility/gas prices must not rewrite past actual expenses. Prevent duplicate actual payments for one linked planned occurrence while allowing extra one-off spending.
7. Expense and income totals stay **per currency**, with optional clearly estimated aggregated USD representations. Budget projections and goal forecasts must not silently write ledger entries.

## 5. Valuation, currency, gold, and goal boundaries

- USD, SYP, SYP (N) and gold grams are distinct units with micros storage. Whole SYP/SYP (N) input policies and gold display precision must not change persisted quantities.
- Current reference SYP/USD is for display-only estimates. **Actual** conversion stores paid SYP, received USD and historic SYP-per-USD (or inverse amounts with same convention).
- Current reference gold USD/gram is display-only. A physical purchase/sale uses actual cash and gram amounts, with explicit source/destination fund ownership.
- Nonzero SYP (N) does not have a defined USD conversion. Never quietly include it in an estimated combined USD total or treat it as old SYP.
- Spendable liquidity excludes gold, goal earmarks and Savings unless explicitly transferred/spent. Asset value changes due to reference rates cannot count as new saved contributions.
- Each goal has a denomination/currency. **Real earmark backing must be in that same unit**; cross-unit goal estimates may be displayed, but must not create virtual USD ownership. If a product requirement later allows multi-asset goals, implement a separate explicit valuation-backed specification before enabling it.
- Existing checked challenge cells and their `affects_balance = 0` events express prior self-reported progress. They are **not proof** that matching Savings assets exist or are uncommitted. Preserve their historical record during migration; do not automatically consider it a real earmark or silently discard it. MS-03 and MS-13 should introduce a transparent reconciliation path.
- Goal withdrawal should release/reallocate backing as part of the operation and update displayed progress in the same transaction. The user must not see a completed 100 USD grid backed by only 40 USD eligible Savings.

## 6. Migration and revision contract

The current repository is at schema v9 and uses:
- `financial_events`, `financial_event_entries` with `affects_balance`, `recurrence_key`, `source_event_id`, and executed SYP/USD rate.
- `financial_event_revisions` containing pre-edit/delete snapshots.
- `recurring_expense_items` for editable expense plans.
- `challenges`/`challenge_cells` and a one-per-goal `savingContribution` ledger record that does not affect balances.
- `weeklyAllocation` events with non-balance SYP roles.
- A `.mosave` JSON backup with integrity SHA-256 and a strict matching database schema version.

**Migration rules:**

- Keep every historical financial event, revision, note, linked salary, goal cell, recurring expense item, setup marker and reference setting. No destructive re-seeding or recreation.
- Old `weeklyAllocation` entries are **not evidence** of durable fund ownership and cannot automatically be transformed into new Savings fund deposits.
- At migration, snapshot each **actual owned unit balance** into Unallocated in the new fund classification without adding a new balance-affecting event. The legacy history still explains the asset balance; the migration checkpoint explains the initial fund classification.
- Offer a one-time explicit user split of Unallocated among Savings and Spending; this is a fund-only reclassification, **not income**.
- If a legacy unit's historical net position is inconsistent/negative, flag it, preserve original data, and block unsafe new allocations until reconciliation. Never silently reset an invalid balance to zero.
- Existing backup schema versions may differ from the new live schema. MS-03 must define version-aware validated restore/migration before release; checksum validation checks integrity, **not confidentiality or authenticity**. Restore must remain transactional and safe against partial replacement.
- Correction/deletion of event-linked fund postings, salary decisions and earmarks must keep their references valid. Historical audit snapshots remain visible but are excluded from current balances.
- A restored database must reproduce the exact same active per-unit owned/fund balances and goal allocations; don't append another migration/opening credit on restart.

## 7. Delivery acceptance test vectors for MS-02 onward

| Vector | Expected result |
| --- | --- |
| Cash receipt 885,000 SYP, split 345,000/540,000 | Owned = 885,000 SYP; Savings = 345,000; Spending = 540,000; 1 income occurrence |
| Spend 80,000 SYP from Spending | Owned = 805,000; Spending = 460,000; Savings = 345,000; monthly expense = 80,000 |
| 300 USD received into Savings and 100 USD spent directly from Savings | USD owned/Savings = 200; Spending = 0; expense = 100 USD |
| 100 USD fund transfer then 100 USD payment from Spending | Exactly one 100 USD expense; not two; final Savings reduced 100 |
| 50 USD gift held in Unallocated then assigned to Savings | Only 1 x 50 USD income; no second credit on assignment |
| Ignore historical salary and restart | Still dismissed; zero income and balance impact |
| Goal earmark 100 USD while Savings = 300 USD | Savings remains 300; free eligible = 200; goal shows 100 assigned |
| Convert 1,300,000 SYP → 100 USD with explicit execution | SYP down 1,300,000; USD up 100, respective fund deltas equal owned deltas; no income/expense |
| Buy gold with 200 USD savings | Cash down 200 USD; gold up entered grams, no phantom extra cash |
| Edit next month's electricity/ampere plan | Past posted expense totals unchanged; cash balances unchanged |
| Migrate v9 with unknown fund ownership | Asset balances preserved; all unverified balances in Unallocated; historical challenge cells visible but not fabricated as goal-backed Savings |
| Restore + repeat migration | No duplicate fund opening, receipts, contributions or missing audit history |

These are **specified test vectors**, not executed tests. MS-18 owns end-to-end verification; MS-02/MS-03 must add focused tests with the implementation.

## 8. Explicitly deferred product decisions (not blockers to MS-01)

The baseline contract is fixed above. These require deliberate follow-up if requested, not assumptions by an implementation agent:

1. **Liabilities, borrowed funds and overdrafts:** out of scope; no negative fund balances permitted for new operations. Legacy anomalies must be surfaced for reconciliation.
2. **Partial refunds/reimbursements and expense category reversal UX:** preserve accounting equivalence and linkage now; exact UI/report representation belongs to later expense/history issues.
3. **Spending allocation of physical gold:** unsupported as direct spendable liquidity. Gold remains saved/unallocated until an explicit sale creates cash.
4. **Multi-currency *real* goal backing:** initially same-unit earmarks only. Estimated cross-unit progress may be shown separately but does not count as confirmed funding.
5. **Automatic priority when spending goal-earmarked Savings:** no silent goal depletion. Require explicit release/reassignment confirmation in MS-13.
6. **Unusual backdated correction with a historically negative intermediate balance:** do not overwrite data; expose and resolve under MS-02/MS-03 policy, preserving audit history.
7. **Large changes in a recurring budget item:** use effective-from-date semantics in MS-09; the treatment of non-monthly recurrence patterns requires separate product approval.

## 9. Evidence from existing implementation (read-only review)

- `lib/models/financial_event.dart`: currently enumerates event types and asset units but has no fund dimension. `LedgerEntry.affectsBalance` differentiates real holdings from non-balance goal/envelope tracking.
- `lib/services/financial_ledger_storage.dart`: `loadBalanceMicros()` sums balance-affecting postings grouped by **unit**, not by fund; conversion/gold operations are existing atomic two-sided postings.
- `lib/services/local_database.dart`: `schemaVersion = 9`, existing event/entry tables have no fund columns, and revision snapshots are separate from active balances.
- `docs/CHALLENGE_LEDGER.md` and `lib/services/challenge_storage.dart`: completed cells are mirrored in an `affects_balance = 0` saving-contribution event, including legacy backfill.
- `docs/VALUATION.md`, `docs/CURRENCY_CONVERSIONS.md`, `docs/GOLD_HOLDINGS.md`: cash and gold ownership, reference-only valuation and historic executed amounts are already distinguished.
- `docs/BACKUP_RESTORE.md`: restore is transactional but currently requires a matching schema version. Account migration cannot rely on old backups automatically opening in a new schema.

**MS-01 is documentation-only.** No application source, SQLite schema, current user data, APK or tests are changed by this Issue.
