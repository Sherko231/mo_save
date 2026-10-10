# Mo Save — Redesign Implementation Progress

> Progress updated: 2026-10-10. **MS-01 through MS-07 closed; MS-08 is next.** GitHub Issue states are authoritative. Source changes/tests for MS-02..MS-07 remain **runtime-unverified**; no CLI or device tests have been executed.

## Current checkpoint

- **Next task:** [MS-08 — Allow expense logging from either fund with categories](https://github.com/Sherko231/mo_save/issues/82).
- **Active implementation:** None.
- **Redesign progress:** 7 / 18 issues closed. **MS-02..MS-07 source implementations were committed but not run or verified.** Android upgrade, client backup restore, Spending UX and device acceptance remain pending.
- **Scope:** [FUNDS_REDESIGN.md](FUNDS_REDESIGN.md) defines the approved direction. [FUNDS_ACCOUNTING_CONTRACT.md](FUNDS_ACCOUNTING_CONTRACT.md) now contains the normative MS-01 accounting rules. Linked GitHub Issues contain bounded implementation work and acceptance criteria.
- **Legacy release gates:** [#28](https://github.com/Sherko231/mo_save/issues/28) (branding/direct APK) and [#29](https://github.com/Sherko231/mo_save/issues/29) (client acceptance/handoff) may contain earlier release preparation but must not be treated as redesigned-product sign-off.

## Task tracker

| Phase | Task | GitHub Issue | Dependencies | Status |
| --- | --- | --- | --- | --- |
| P1 | MS-01 — Define fund-ledger accounting invariants | [#75](https://github.com/Sherko231/mo_save/issues/75) | — | Done — documentation contract [commit](https://github.com/Sherko231/mo_save/commit/29be2562f1121dc0e474b9547b975b021cd4d10c) |
| P1 | MS-02 — Implement fund-aware ledger and persistence | [#76](https://github.com/Sherko231/mo_save/issues/76) | MS-01 | Done — code committed; runtime unverified [commit](https://github.com/Sherko231/mo_save/commit/2a71c08c74230d60bc7c70af334b2301ba89e6bd) |
| P1 | MS-03 — Safely migrate existing SQLite v9 data | [#77](https://github.com/Sherko231/mo_save/issues/77) | MS-02 | Done — v9 backup compatibility and manual reconciliation, unverified [commit](https://github.com/Sherko231/mo_save/commit/769e2fc17e168d50aa67d970a30813d9004e3b14) |
| P2 | MS-04 — Dismiss or backdate overdue salary occurrences | [#78](https://github.com/Sherko231/mo_save/issues/78) | MS-02, MS-03 | Done — ignored disposition, Undo, backdated receipt and linked historic spending; tests unrun [commit](https://github.com/Sherko231/mo_save/commit/e771e4c224b4de74cc255edfaea164577668cd92) |
| P2 | MS-05 — Record gifts, item sales, bonuses, and opening cash | [#79](https://github.com/Sherko231/mo_save/issues/79) | MS-02 | Done — one-off cash income, separate openingBalance, Home intake, corrections, tests unrun [commit](https://github.com/Sherko231/mo_save/commit/933c775afd332b472caf38d934e761fb3c664afc) |
| P2 | MS-06 — Split received amounts across Savings and Spending | [#80](https://github.com/Sherko231/mo_save/issues/80) | MS-02, MS-04, MS-05 | Done — exact per-receipt split, net historic spending, optional suggestions, manual split, tests unrun [commit](https://github.com/Sherko231/mo_save/commit/643942bffe67442ac75e5ec54b9d3ad618d6c9d3) |
| P3 | MS-07 — Build Spending fund dashboard | [#81](https://github.com/Sherko231/mo_save/issues/81) | MS-02, MS-06 | Done — live Spending, plans versus paid, source-safe expense/history, tests unrun [commit](https://github.com/Sherko231/mo_save/commit/3c68732cf896b9ac617641f45c421e37a4d8ce52) |
| P3 | MS-08 — Log expenses from either fund with categories | [#82](https://github.com/Sherko231/mo_save/issues/82) | MS-02, MS-07 | Not started |
| P3 | MS-09 — Edit future recurring expenses without rewriting history | [#83](https://github.com/Sherko231/mo_save/issues/83) | MS-07, MS-08 | Not started |
| P3 | MS-10 — Transfer money between funds safely | [#84](https://github.com/Sherko231/mo_save/issues/84) | MS-02, MS-08 | Not started |
| P3 | MS-11 — Categorized monthly spending analytics | [#85](https://github.com/Sherko231/mo_save/issues/85) | MS-08, MS-09, MS-10 | Not started |
| P4 | MS-12 — Build true Savings fund dashboard | [#86](https://github.com/Sherko231/mo_save/issues/86) | MS-02, MS-06, MS-10 | Not started |
| P4 | MS-13 — Link saving goals to real Savings assets | [#87](https://github.com/Sherko231/mo_save/issues/87) | MS-02, MS-03, MS-12 | Not started |
| P4 | MS-14 — Forecast goal completion and plan-vs-actual delays | [#88](https://github.com/Sherko231/mo_save/issues/88) | MS-05, MS-09, MS-12, MS-13 | Not started |
| P4 | MS-15 — Useful savings motivation | [#89](https://github.com/Sherko231/mo_save/issues/89) | MS-13, MS-14 | Not started |
| P5 | MS-16 — Unify audit history and corrections | [#90](https://github.com/Sherko231/mo_save/issues/90) | MS-04, MS-05, MS-08, MS-10, MS-13 | Not started |
| P5 | MS-17 — Redesign navigation around Savings and Spending | [#91](https://github.com/Sherko231/mo_save/issues/91) | MS-07, MS-11, MS-12, MS-15, MS-16 | Not started |
| P6 | MS-18 — Verify migration, accounting, backup and handoff | [#92](https://github.com/Sherko231/mo_save/issues/92) | All prior issues | Not started |

## Mandatory recovery and update procedure for implementation agents

1. Read root `AGENTS.md`, then `docs/FUNDS_REDESIGN.md`, then this tracker, then the **full body, comments, and acceptance checklist** of the next GitHub Issue. Read relevant existing code and previous docs as necessary.
2. Treat GitHub Issues as authoritative for whether a task is open/closed. Reconcile this tracker with actual GitHub issue states whenever work resumes; do not duplicate previously completed work. If a file lists a task complete but its issue is open, inspect evidence and correct the discrepancy rather than assume either side is right.
3. Select the **first unfinished, unblocked task in dependency order**. Do not work on future or unrelated issues in the same change.
4. Read the latest source files relevant to that issue. Implement the acceptance scope only; do not silently redesign unrelated workflows. Preserve current financial records and migration compatibility.
5. **Direct commits to `main` are requested. No PR, new branch or routine CLI preflight/status checks are needed for this workflow.** Code/tests may be inspected as useful; do not pretend unrun checks passed. When a specific task requires tests/Android device verification, disclose which checks were actually executed vs not executed.
6. Once work is actually complete, document the implementation and any limits in that GitHub Issue, update its checklist, close the issue, and update this file (status, progress, active/next task and relevant commit link). Commit the status update directly to `main`.
7. If you stop mid-issue, leave the issue **open** and record a concise handoff in the issue comments: completed changes, commits, files affected, remaining checklist, blockers, and next action. Keep tracker status **In progress** with the same next task; do not close prematurely.
8. If a blocker or conflict is material to ledger integrity/data preservation, stop that implementation and describe the blocker before proceeding. No fabricated financial history or fund split.

### Status vocabulary
- **Not started**: issue exists; implementation has not begun.
- **In progress**: a subset of issue requirements is underway; record the active Issue and commits.
- **Blocked**: needs prerequisite decision, data, or technical resolution.
- **Done**: GitHub Issue closed with supported acceptance evidence. Do not mark Done merely for committing code.

## Cross-issue correctness checklist

- [ ] Per-asset-unit Savings + Spending + Unallocated = real owned ledger assets
- [ ] Salary ignore never creates phantom income
- [ ] Planned bills do not decrease liquid balances until actual payment
- [ ] Direct-from-Savings expenses count once in expense analytics and reduce Savings
- [ ] Internal fund transfer does not count as income or expense
- [ ] Goal earmarks cannot fabricate assets or double-allocate funds
- [ ] FX and gold costs preserve historical quantities and reference-only valuation
- [ ] Historic SQLite v9 user data and clean backup/restore are preserved
- [ ] Forecast assumptions, real calendar dates and missing-data behavior are explicit
- [ ] Android Arabic RTL interface and direct installable APK acceptance are verified

## Change log

- **2026-10-10 — MS-07 closed (#81):** added Spending-only current-cash dashboard on Home with per-unit SYP/USD/SYP (N), separate Unallocated warning and monthly plan/actual amounts; hypothetical full-plan scenario clearly not available cash. Added Spending-only quick expense action, synchronized prior Expenses form with fund-safe debits, fund-filtered audited history and refreshed snapshots on ledger/plan edits. Added `test/spending_fund_service_test.dart` and `docs/SPENDING_FUND.md`. **No CLI, Flutter/analyzer, APK builds or device acceptance executed; source remains runtime-unverified.** Next [MS-08 / #82](https://github.com/Sherko231/mo_save/issues/82).
- **2026-10-10 — MS-06 closed (#80):** added `ReceiptFundAllocation` model, real salary income postings split among Savings/Spending/Unallocated (not separate incomes), historic-expense reserve from same receipt, optional capped weekly 540k/345k suggestions and editable monthly USD allocation, manual cash multi-fund split with full retry identity matching. Hid obsolete non-balance weekly-envelope form from Home while preserving all old ledger/audit entries; added `test/receipt_fund_allocation_test.dart` and `docs/RECEIPT_FUND_ALLOCATION.md`. **No analyzer, Flutter tests, CLI checks, APK builds or device tests executed; runtime unverified.** Next [MS-07 / #81](https://github.com/Sherko231/mo_save/issues/81).
- **2026-10-10 — MS-05 closed (#79):** added manual income categories (gift, untracked item sale, bonus, side work, other), real source/reason/date cash entry, optional initial fund classification, and new `openingBalance` event type excluded from current earned income. Stored via existing v10 ledger and history with idempotent request identity, explicit tracked-asset sale warning, audit-safe manual date/amount correction and Arabic RTL Home intake screen. Added `test/manual_inflow_service_test.dart` and `docs/MANUAL_INCOME.md`, with supporting documentation. **No analyzer, Flutter tests, CLI, device tests or APK builds executed.** Next [MS-06 / #80](https://github.com/Sherko231/mo_save/issues/80).
- **2026-10-10 — MS-04 closed (#78):** added a non-financial ignored payday disposition in `app_metadata`, month-by-scheduled-key receipt lookup, Ignore/Undo controls in Home, actual receipt/spent date dialog, optional atomic linked historical expense (so old fully spent pay is net zero), and actual-month income accounting. Added service regression tests and `docs/INCOME_OCCURRENCES.md`. **No CLI, Flutter/analyzer, device tests or builds executed; source implementation only, runtime unverified.** Next [MS-05 / #79](https://github.com/Sherko231/mo_save/issues/79).
- **2026-10-10 — MS-03 closed (#77):** implemented backward-compatible checksummed v9 `.mosave` import into v10, retained original balance-affecting events and non-balance goal progress, defaulted unknowable fund ownership to Unallocated, added atomic fund reconciliation from Settings, protected gold and fund transfer integrity, and authored v9 SQLite fixture plus backup round-trip tests. Updated `BACKUP_RESTORE.md` and `DATA_STORAGE.md`. **Not run:** Flutter tests, CLI checks, APK/device and real customer data migration. Keep independent old-app backups and complete acceptance under MS-18. Next: [MS-04 / #78](https://github.com/Sherko231/mo_save/issues/78).
- **2026-10-10 — MS-02 closed (#76):** added `FinancialFund`, fund transfer event, per-ledger-entry fund attribution, SQLite v10 `fund` column with Unallocated migration default, fund balance queries, atomic transfer checks and conservation, fund-aware transaction revisions/corrections, history labels, new unit tests and DATA_STORAGE documentation. **No CLI checks, Flutter tests, analyzer, APK builds or on-device migrations were executed**; implementation remains runtime-unverified. **Important MS-03 handoff:** schema-v9 `.mosave` backups cannot currently restore under schema v10 due to strict equality in `BackupService`; implement compatibility and real upgrade/restore validation before release. [Issue #77](https://github.com/Sherko231/mo_save/issues/77) is next.
- **2026-10-10 — MS-01 complete:** finalized [fund-ledger accounting contract](FUNDS_ACCOUNTING_CONTRACT.md), per-unit conservation/expense/income/fund transfer rules, gold and FX, goal backing, existing v9 migration constraints, audit preservation and explicit deferred decisions. Closed [Issue #75](https://github.com/Sherko231/mo_save/issues/75). No app code changed and no CLI checks/tests/builds executed. Next: [MS-02 / #76](https://github.com/Sherko231/mo_save/issues/76).
- **2026-10-10** — Redesign specification agreed from client feedback; Issues MS-01..MS-18 (#75..#92) created. No application implementation done as part of planning.
