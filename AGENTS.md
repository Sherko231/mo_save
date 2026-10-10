# AGENTS.md — Mo Save implementation contract

This file is for coding agents working in `Sherko231/mo_save`.

## Product and sources of truth

This is an offline-first, single-user Arabic/RTL Flutter financial app using a versioned SQLite financial ledger. **The savings/spending fund redesign is planned, not yet implemented.** Never claim a requirement works merely because it appears in a roadmap.

Read, in this order:

1. `README.md` — project overview and existing documentation links.
2. `docs/FUNDS_REDESIGN.md` — product goals, financial invariants and end-to-end acceptance story.
3. `docs/FUNDS_REDESIGN_PROGRESS.md` — task IDs, live Issue links, dependency order and resumable checkpoint.
4. The **full GitHub Issue and comments** for the next available redesign task.
5. Relevant source and current docs, especially `docs/PRODUCT.md`, `docs/DATA_STORAGE.md`, `docs/VALUATION.md`, `docs/CHALLENGE_LEDGER.md`, `docs/ROADMAP.md`, `docs/BACKUP_RESTORE.md` and `docs/TESTING.md` when applicable.

GitHub Issue state and acceptance evidence are authoritative for completion. The progress file is a synchronised summary and should be corrected if stale.

## Resuming work

- Identify the earliest incomplete redesign Issue from **MS-01 through MS-18** (#75–#92) whose dependencies are done.
- If an Issue is already in progress, **continue it** rather than starting a second Issue. Read its latest comments/commits to recover the exact checkpoint.
- Implement one bounded Issue at a time. Do not jump ahead or duplicate completed implementation.
- At a mid-task interruption, leave the Issue open and add a brief checkpoint comment with what changed, what remains, commit links and any blockers. Update the tracker to In progress.
- Finish by satisfying the issue's acceptance criteria, documenting changes and verification limits, updating its checkboxes/status and `docs/FUNDS_REDESIGN_PROGRESS.md`, and closing the GitHub Issue. Then move to the next dependency-unblocked issue.

## Authorized GitHub workflow

**Owner preference for this redesign:** commit changes **directly to `main`**, with **no PR, feature branch, or routine CLI preflight/status checks**. GitHub connector/API reads for relevant files, issue status, and dependencies are sufficient for work coordination. Do not insert unrelated CLI checks as a gate to saving progress.

This preference does not mean the application is automatically verified. Where a task explicitly requires automated tests, data migration checks, APK/device acceptance or other validation, perform only what is available and accurately state which checks were run and which remain unverified. Never claim a test/build/install passed without executing it.

Avoid unrelated changes, force pushes, destructive rewriting or losing user data. Prefer small commits and an explicit issue-to-commit trail.

## Non-negotiable financial rules

- Owned assets are not the same as savings. Assets remain separated by unit (USD, SYP, SYP (N), gold grams) and assigned to Savings, Spending, or explicitly Unallocated.
- Every real inflow/outflow is posted once. Internal fund transfers and saving-goal earmarks never create new owned assets, income or actual expenses.
- Actual payments, including those taken directly from Savings, must decrease the correct fund and be counted once in expense analytics.
- A planned bill is never a cash debit until paid. Ignored old salary reminders never add income or cash.
- Goal progress is backed by real Savings earmarks, never a parallel fictional piggy bank balance.
- Future savings and goal dates are forecasts, not guarantees; manual FX/gold reference prices only affect labelled estimates.
- Preserve historic ledger/audit records and safely migrate existing SQLite v9 and backup data; ambiguous old fund splits must not be invented.
- Production UI stays Arabic-only and RTL.

## Release gates

Current older Issues #28 and #29 concern the prior APK/release handoff. Any existing build/signing work may remain, but **final client acceptance must wait until MS-01..MS-18 are done and the redesign is verified on the target device**.

Do not treat updating this document, the task tracker, or a GitHub Issue as implementing application features.
