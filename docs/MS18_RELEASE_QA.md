# MS-18 — Redesign Release Evidence & Client Acceptance

**Issue:** [#92](https://github.com/Sherko231/mo_save/issues/92)  
**Status:** VERIFICATION IN PROGRESS — **not signed off**, no device acceptance.  
**Date:** 2026-10-11. **No full customer data file is included in the repository.**

## Validation scope and trustworthy evidence

The previously closed MS-02..MS-17 issues primarily committed source code and unexecuted tests. During MS-18 the project added the automated [Flutter CI workflow](../.github/workflows/flutter-verify.yml), pinned to Flutter 3.38.7 (Dart 3.10.7), which runs:

1. `flutter pub get`.
2. `flutter analyze --no-fatal-infos` (errors and warnings still fail; informational migration/style lints are reported but not release-blocking).
3. `flutter test --reporter expanded` across ALL `test/` unit/widget/migration and finance integration tests. The test step runs even if analysis fails to reveal all blockers.
4. `flutter build apk --release` independently in an Ubuntu runner. A successful build uploads `mo-save-android-release-apk` for limited-time manual device installation/testing. A compiled APK alone does not establish usability or client approval.

The [initial CI run](https://github.com/Sherko231/mo_save/actions/runs/38156395342) **failed** at compilation and analyzer, revealing genuine longstanding syntax/type and test-source errors: fund-transfer error statement, missing recurring-plan import, typed forecast arithmetic, and unescaped dollar literals in test names/expectations. Corrections were committed under MS-18. This earlier failed run is not evidence of a successful app. Check the latest **`main`** CI run after the corrections rather than reading earlier cancelled superseded runs.

An independent [focused finance smoke workflow](../.github/workflows/flutter-smoke.yml) additionally runs the client story and v9/v10/v12 migration and archive scenarios. Its first [run #38157382031](https://github.com/Sherko231/mo_save/actions/runs/38157382031) **passed** analyzer without warnings/errors (40 info-only style/deprecation findings remain) and **passed all 20 migration/backup/goal validation tests**. The added client journey test **failed** because its synthetic just-created goal was mistakenly marked as a legacy *unverified* goal; the sample fixture was corrected to start with verified zero-backed state (consistent with SavingChallenge.create and real new goals). A fresh [smoke run #38157529226](https://github.com/Sherko231/mo_save/actions/runs/38157529226) was triggered on the corrected commit and is **not yet evidenced as passing** at this checkpoint. These facts are NOT a full release sign-off.

The original main workflow also has superseded long-running full-suite jobs; its latest corrected run requires an explicit green result. The action workflow uses `concurrency.cancel-in-progress` for new pushes and path filtering, so documentation-only changes do not trigger duplicate APK builds.

## Reproducible automated end-to-end scenario

[MS-18 regression fixture](../test/ms18_client_journey_test.dart) exercises this realistic, fully isolated SQLite scenario using a completed previous calendar month for actual salary dates:

| Event | Savings SYP | Spending SYP | Savings USD | Owned SYP | Owned USD |
| --- | ---: | ---: | ---: | ---: | ---: |
| Start | 0 | 0 | 0 | 0 | 0 |
| Receive 885,000 SYP, allocate 345k Savings + 540k Spending | 345,000 | 540,000 | 0 | 885,000 | 0 |
| Pay 80,000 SYP from Spending | 345,000 | 460,000 | 0 | 805,000 | 0 |
| Receive and allocate all 300 USD to Savings | 345,000 | 460,000 | 300 | 805,000 | 300 |
| Pay one actual 100 USD expense from Savings | 345,000 | 460,000 | 200 | 805,000 | 200 |
| Receive one new 50 USD gift in Savings | 345,000 | 460,000 | 250 | 805,000 | 250 |
| Reserve 100 USD of existing Savings for one 200 USD goal | 345,000 | 460,000 | 250 | 805,000 | 250 |

Expected: only **three income events** (two salaries + gift) and **two actual expenses**, 80,000 SYP and 100 USD respectively; Savings goal earmark 100 USD is NOT additional assets. Unallocated remains zero in these two cash units. One scheduled SYP bill is 240,000 in the present month and 310,000 effective next month; neither price/change is a cash debit until the user actually pays.

The suite closes the original SQLite database and reopens the same file, checks balances/expenses, performs a checksummed v12 `.mosave` export to a **second clean SQLite database**, and rechecks event counts, both money units, verified goal and future-effective bill price after restore. This test proves only synthetic fixtures, **not that a particular customer's real backup was successfully migrated**.

Additional committed tests cover direct on-disk schema v9→v12 and v1→v12 migration, legacy SharedPreferences, v9/v10/v11 backup import into v12, v12 goal pledges and corrupt archive rollback, fund transfers, edited/deleted expenses with audit revisions, reminder dismissal, date correctness, projections and adaptive RTL widgets.

## Mandatory manual client/device gates (NOT EXECUTED by CI)

1. **Preserve real source files.** Export a `.mosave` backup from the installed customer app and store a copy outside the phone. Keep the original SQLite/app installation until validation. Do **not** uninstall, clear storage, overwrite the only backup, or test restore against irreplaceable live data.
2. **On-device upgrade.** On the actual client's Android handset, test upgrade-in-place under the SAME package ID `com.samo.mosave`, preserving records, versioned planned expenses, original event IDs/revisions, actual receipt dates, ignored occurrences, goal checkmarks and existing Unallocated old money. `com.example.mo_save` is a different package and requires backup-restore rather than in-place upgrade.
3. **Backup and restore dry-run.** Use a second/test install or disposable device profile, restore an untouched exported customer backup, and compare event counts, each financial unit/fund balance, special currencies and grams, salary edits/ignored reminders, older planned bill revisions, goal pledges and scheduled local reminder preferences. Confirm corrupted/archive-future-version rejection leaves the current test data unchanged. Re-export and inspect the recovered file.
4. **Everyday path.** From **الادخار** confirm separately Savings, Spending, Unallocated, noncash physical gold, verified goal progress, and an explicitly conditional forecast. In **المصاريف**, record a categorized 80,000 SYP expense via the prominent first-screen button without opening analytics; verify just one posted expense. Check 100 USD Savings expense with reason/confirmation, 50 USD gift, internal fund transfer conservation, negative-balance/earmark blocking and archived transaction corrections.
5. **Adaptive Arabic accessibility.** Check compact phone with large text, system dark mode, keyboard, Android Back from nested goal, small and wide layouts, touch targets ≥48dp and TalkBack/RTL reading order. Check notification permission behavior, optional reminders, document-picker export/import and app reopening after process death.
6. **APK release evidence.** Verify the latest GitHub Action produced a build artifact, download it from the GitHub Actions run, install/update using `adb install -r`, check launch and `adb shell dumpsys package com.samo.mosave` identity. The current direct/private APK uses debug-managed signing for distribution. Record device Android version, exact APK commit SHA, install/update result and customer acceptance after use.
7. **Owner acceptance.** Record user-observed expected-versus-actual balances and a passed signed-off migration, recovery and Arabic UI checklist. Only then close MS-18 and unblock the older client handoff Issues #28/#29.

## Release decision

**Not releasable from repository source alone.** A green CI (if achieved) demonstrates isolated automated coverage and successful APK compilation, not real device installation, customer data recovery or user acceptance. Any failing CI job requires correction and a fresh successful run on the final commit. Keep MS-18 open until both automated and device/customer checks are evidenced.
