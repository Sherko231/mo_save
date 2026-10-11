# Challenge progress and ledger reconciliation

Challenge-grid progress is a **historical bookkeeping signal**, not proof of real Savings. Under MS-13, only an explicit verified goal_earmarks row backed by an existing Savings asset unit is an earmark. Both remain non-balance-affecting.

## Canonical contribution record

Each saving goal/challenge owns at most one grid-generated `savingContribution` ledger event with recurrence key:

`challenge-progress:<challenge-id>`

The event is linked through both `related_challenge_id` and `related_goal_id` because the challenge itself is the saving-goal record.

Its single ledger entry:

- uses the challenge currency;
- equals the exact sum of all completed challenge cells;
- uses fixed-point micros;
- has `affects_balance = 0`.

The entry is deliberately non-balance-affecting. For a verified goal, checking a saving cell also changes its real Savings-backed earmark in the same transaction, subject to free Savings and competing-goal constraints. For older unverified goals, checked cells remain historical marks until the owner explicitly pledges them or resets them. A checkmark alone **never** creates or proves owned cash.

## Toggle behavior

Challenge state and the canonical saving contribution are written inside the same SQLite transaction.

- First completed cell creates the contribution event.
- Completing more cells updates the same event to the new completed-cell total.
- Undoing a cell reduces the same event.
- Undoing the final completed cell removes the contribution event.
- Repeated toggles cannot create duplicate contributions because one stable recurrence key is used per challenge.
- Sequence, deadline or note edits do not change the contribution timestamp when the saved amount is unchanged.

This makes persisted grid progress and ledger contribution totals identical after restart.

## Existing progress backfill

Issue #17 adds a one-time data backfill tracked by `app_metadata` key:

`challenge_grid_contributions_v1_backfilled`

For each existing challenge, the backfill sums cells where `is_completed = 1` and creates the same canonical non-balance-affecting contribution event. The metadata flag is written only after the transaction succeeds, so a failed backfill can be retried safely.

No database schema bump is required because the existing challenge, ledger and metadata tables already contain everything needed for this relationship.

## Verified backing and legacy choice (MS-13)

Verified earmarks live in SQLite v12 goal_earmarks and equal the completed grid micros. The ledger rejects expenses, transfers and corrections that underfund a verified goal. Unchecking releases a pledge without changing funds; deleting releases the FK-backed reservation. Existing v9-v11 challenge grid marks stay unverified. The user must explicitly confirm backing old completed cells against available real Savings, or reset their checkmarks. This keeps old history without fabricated progress. See [GOAL_EARMARKS.md](GOAL_EARMARKS.md).

## Deletion

Deleting a goal also removes its grid-generated contribution event before deleting the challenge. The contribution does not affect owned balances, so removing a deleted goal cannot create or destroy cash.
