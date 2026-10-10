# MS-04 — Recurring Income Occurrence Dispositions

**Status:** Implementation committed to `main` for Issue [#78](https://github.com/Sherko231/mo_save/issues/78); runtime verification not executed at the owner's request. This documentation concerns only recurring expected income and does not implement the later full fund-allocation workflow (MS-06).

## Purpose

Old expected salaries must never force the owner to confirm receipt and inflate cash they no longer possess. Every due payday has three choices:

1. **Ignore this occurrence** (`تجاهل هذه الدفعة`). Dismisses exactly one scheduled payday. It does **not** create a `financial_events` row, income, expense, Savings allocation, or balance change. It no longer appears in the overdue attention section. In the monthly Income section it is marked **تم تجاهل الدفعة**, with an **إلغاء التجاهل** option.
2. **Record actual receipt** (`تسجيل الاستلام`). Enter the real received amount and calendar date, not necessarily the preset amount or scheduled date. The financial event stores the original scheduled recurrence key so the UI will continue to recognize it after a salary settings change. The credited balance stays Unallocated until the user chooses its destination under MS-06.
3. **Record a historic receipt with already-spent money**. The same form accepts the amount already spent, its actual date, expense category and optional reason. It creates **one real income** and **one linked actual expense** together in one SQLite transaction. If an old 885,000 SYP receipt was fully spent, +885,000 and -885,000 yield no phantom remaining cash. If spending was previously registered in the app, the user should **not** record it again. Choosing Ignore is appropriate when there is no need to reconstruct a receipt.

## Identity and persistence

The existing `financial_events.recurrence_key` is the canonical scheduled identity, e.g. `income:weeklySyp:2026-10-08` and `income:monthlyUsd:2026-10-01`. A confirmed receipt uses exactly this key even if actually received on an earlier date.

No new SQLite version is needed. The disposition is kept in existing `app_metadata`:

```text
key   = ignored_income_occurrence:<existing recurrence_key>
value = 1
```

This is included in `.mosave` exports/restores automatically because `app_metadata` is already backed up. Ignored keys are unchanged by future edits of recurring payday, salary amount, or budget settings. Revisiting a month after reopening the app restores the status without recreating a balance event.

Ignoring and recording are mutually exclusive:
- Ignore checks for an existing receipt and inserts the disposition inside one SQLite transaction; repeated Ignore is idempotent.
- Confirm checks for the Ignore disposition inside the **same transaction** used to insert the receipt (and any linked expense); a race between both operations cannot leave both committed.
- Income recurrence keys have an existing unique index, preventing receipt duplication.
- Undo Ignore removes the metadata key; this action **does not** confirm income or move funds.
- Old receipts are fetched by their **scheduled identity** rather than by the actual receipt month. They remain visible if the user later changes recurring settings or confirms income with an earlier actual date.
- Future paydays cannot be dismissed or confirmed through the implemented flow.
- A linked historic expense carries `source_event_id` referring to the income event, preserving both the audit trail and dependent-event safety on later corrections/deletions.
- The monthly projected-income total excludes ignored occurrences; actual income analytics only count real posted receipt events.

## Recording examples

| Action | New income event | New actual expense event | Owned balance delta | Overdue reminder |
| --- | --- | --- | --- | --- |
| Ignore already-spent 885,000 SYP payday | None | None | 0 | Removed |
| Record 885,000 SYP receipt, already spent 885,000 | +885,000 | -885,000 | 0 | Marked received |
| Record 885,000 SYP receipt, already spent 200,000 | +885,000 | -200,000 | +685,000 SYP Unallocated | Marked received |
| Record 300 USD, spent none | +300 USD | None | +300 USD Unallocated | Marked received |
| Undo Ignore | None | None | 0 | Appears again if due |

Expense reporting should include the historic expense once in its actual expense month; planned bills and old weekly envelope non-balance entries remain separate. The future MS-08 categorization UI provides a fuller expense workflow.

## Regression cases authored

- Ignore an old Thursday occurrence twice, verify zero finance entries, restart database, verify persistent Ignore, then undo and verify it becomes actionable again.
- Confirming an ignored occurrence throws without posting money.
- A fully spent backdated 885,000 SYP salary creates exactly one receipt plus one expense linked to it; no remaining owned or fund balance.
- Retrying a confirmed occurrence fails rather than posting a second receipt/expense.
- Changing salary defaults/payday after recording a backdated USD receipt preserves its original recurrence identity and amount.

Tests have been added in `test/recurring_income_service_test.dart`, but **not executed**. Flutter analyzer, CLI test commands, Android build and device interaction remain unverified. Preserve independent backups until MS-18 completes acceptance.
