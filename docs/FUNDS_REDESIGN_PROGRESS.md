# Mo Save — Redesign Implementation Progress

> Initial tracking snapshot: 2026-10-10. **All 18 redesign issues are OPEN and NOT STARTED at creation.** This file is a human/AI-readable navigation index, not a replacement for GitHub issue states. Never infer implementation from a document or checkbox alone.

## Current checkpoint

- **Next task:** [MS-01 — Define fund-ledger accounting invariants](https://github.com/Sherko231/mo_save/issues/75).
- **Active implementation:** None.
- **Redesign progress:** 0 / 18 complete.
- **Scope:** [FUNDS_REDESIGN.md](FUNDS_REDESIGN.md) defines the approved direction; linked GitHub Issues contain bounded work and acceptance criteria.
- **Legacy release gates:** [#28](https://github.com/Sherko231/mo_save/issues/28) (branding/direct APK) and [#29](https://github.com/Sherko231/mo_save/issues/29) (client acceptance/handoff) may contain earlier release preparation but must not be treated as redesigned-product sign-off.

## Task tracker

| Phase | Task | GitHub Issue | Dependencies | Status |
| --- | --- | --- | --- | --- |
| P1 | MS-01 — Define fund-ledger accounting invariants | [#75](https://github.com/Sherko231/mo_save/issues/75) | — | Not started |
| P1 | MS-02 — Implement fund-aware ledger and persistence | [#76](https://github.com/Sherko231/mo_save/issues/76) | MS-01 | Not started |
| P1 | MS-03 — Safely migrate existing SQLite v9 data | [#77](https://github.com/Sherko231/mo_save/issues/77) | MS-02 | Not started |
| P2 | MS-04 — Dismiss or backdate overdue salary occurrences | [#78](https://github.com/Sherko231/mo_save/issues/78) | MS-02, MS-03 | Not started |
| P2 | MS-05 — Record gifts, item sales, bonuses, and opening cash | [#79](https://github.com/Sherko231/mo_save/issues/79) | MS-02 | Not started |
| P2 | MS-06 — Split received amounts across Savings and Spending | [#80](https://github.com/Sherko231/mo_save/issues/80) | MS-02, MS-04, MS-05 | Not started |
| P3 | MS-07 — Build Spending fund dashboard | [#81](https://github.com/Sherko231/mo_save/issues/81) | MS-02, MS-06 | Not started |
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

- **2026-10-10** — Redesign specification agreed from client feedback; Issues MS-01..MS-18 (#75..#92) created. No application implementation done as part of planning.
