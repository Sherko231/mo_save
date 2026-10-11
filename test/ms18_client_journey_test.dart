import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/expected_income.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/models/financial_settings.dart';
import 'package:mo_save/models/recurring_expense_item.dart';
import 'package:mo_save/models/saving_challenge.dart';
import 'package:mo_save/services/backup_service.dart';
import 'package:mo_save/services/challenge_storage.dart';
import 'package:mo_save/services/expense_plan_storage.dart';
import 'package:mo_save/services/expense_service.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/financial_settings_storage.dart';
import 'package:mo_save/services/goal_forecast_service.dart';
import 'package:mo_save/services/local_database.dart';
import 'package:mo_save/services/manual_inflow_service.dart';
import 'package:mo_save/services/notification_preferences_storage.dart';
import 'package:mo_save/services/recurring_income_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// One realistic scenario, including close/reopen and a clean restore to a
/// second SQLite file. Never tests against production user data.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MS-18 full client story balances survive restart and v12 backup',
      () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final dir = await Directory.systemTemp.createTemp('mosave_ms18_client_');
    final path = '${dir.path}${Platform.pathSeparator}live.db';
    final restoredPath = '${dir.path}${Platform.pathSeparator}recovery.db';
    var source = LocalDatabase.forTesting(path);
    final target = LocalDatabase.forTesting(restoredPath);
    addTearDown(() async {
      await source.close();
      await target.close();
      await dir.delete(recursive: true);
    });

    final settings = FinancialSettingsStorage(database: source);
    await settings.saveSettings(FinancialSettings.clientDefaults);
    // Keep the acceptance fixture focused on the client's explicit bill;
    // unrelated first-launch default commitments must not pollute it.
    await (await source.database).insert('app_metadata', <String, Object?>{
      'key': 'expense_plan_client_defaults_seeded_v1', 'value': '1',
    });
    final ledger = FinancialLedgerStorage(database: source);
    final incomes = RecurringIncomeService(
      database: source, ledgerStorage: ledger, settingsStorage: settings,
    );
    final plans = ExpensePlanStorage(database: source);
    final expenses = ExpenseService(planStorage: plans, ledgerStorage: ledger);
    final goals = ChallengeStorage(
      database: source, preferences: SharedPreferencesAsync(),
    );

    // Use a fully elapsed calendar month so the fixture never assumes
    // an as-yet-unreceived future salary or requires changing phone time.
    final now = DateTime.now();
    final salaryMonth = DateTime(now.year, now.month - 1);
    final occurrences = await incomes.loadMonth(salaryMonth);
    final weekly = occurrences.firstWhere(
      (item) => item.kind == RecurringIncomeKind.weeklySyp,
    );
    final monthly = occurrences.firstWhere(
      (item) => item.kind == RecurringIncomeKind.monthlyUsd,
    );

    await incomes.confirmReceived(
      occurrence: weekly,
      amountMicros: LedgerEntry.amountToMicros(885000),
      spendingMicros: LedgerEntry.amountToMicros(540000),
      savingsMicros: LedgerEntry.amountToMicros(345000),
    );
    await expenses.logExpense(
      amountMicros: LedgerEntry.amountToMicros(80000),
      unit: FinancialUnit.syp, occurredAt: now,
      category: 'طعام', sourceFund: FinancialFund.spending,
    );
    await incomes.confirmReceived(
      occurrence: monthly,
      amountMicros: LedgerEntry.amountToMicros(300),
      savingsMicros: LedgerEntry.amountToMicros(300),
    );
    await expenses.logExpense(
      amountMicros: LedgerEntry.amountToMicros(100),
      unit: FinancialUnit.usd, occurredAt: now,
      category: 'صحة', note: 'سحب اضطراري',
      sourceFund: FinancialFund.savings,
    );
    await ManualInflowService(ledger: ledger).record(
      kind: ManualInflowKind.gift,
      unit: FinancialUnit.usd,
      amountMicros: LedgerEntry.amountToMicros(50),
      occurredAt: now, fund: FinancialFund.savings,
      source: 'هدية',
    );

    final g = SavingChallenge(
      id: 'ms18-trip',
      name: 'سفر',
      targetAmount: 200,
      currency: ChallengeCurrency.usd,
      sequence: ChallengeSequence.ordered,
      cellCount: 2,
      cells: const <ChallengeCell>[
        ChallengeCell(value: 100),
        ChallengeCell(value: 100),
      ],
    );
    await goals.addChallenge(g);
    await goals.updateChallenge(g.copyWith(cells:
      const <ChallengeCell>[
        ChallengeCell(value: 100, isCompleted: true),
        ChallengeCell(value: 100),
      ],
    ));

    // An upcoming bill is not a paid historical expense. Raising next
    // month's price changes only future financial projections/commitments.
    final thisMonth = DateTime(now.year, now.month);
    final future = DateTime(now.year, now.month + 1);
    final bill = RecurringExpenseItem.create(
      name: 'أمبير',
      unit: FinancialUnit.syp,
      amountMicros: LedgerEntry.amountToMicros(240000),
      sortOrder: 0,
    );
    await plans.addItem(bill, effectiveFromMonth: thisMonth);
    await plans.updateItem(
      bill.copyWith(amountMicros: LedgerEntry.amountToMicros(310000)),
      effectiveFromMonth: future,
    );

    Future<void> assertBalances(FinancialLedgerStorage recorded,
        LocalDatabase testedDb) async {
      final funds = await recorded.loadFundBalancesMicros();
      expect(funds[FinancialFund.savings]![FinancialUnit.syp],
          LedgerEntry.amountToMicros(345000));
      expect(funds[FinancialFund.spending]![FinancialUnit.syp],
          LedgerEntry.amountToMicros(460000));
      expect(funds[FinancialFund.savings]![FinancialUnit.usd],
          LedgerEntry.amountToMicros(250));
      expect(funds[FinancialFund.spending]![FinancialUnit.usd], 0);
      expect(funds[FinancialFund.unallocated]![FinancialUnit.usd], 0);
      expect((await recorded.loadBalanceMicros())[FinancialUnit.syp],
          LedgerEntry.amountToMicros(805000));
      expect((await recorded.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(250));
      final posted = await recorded.loadEvents();
      expect(posted.where((e) => e.type == FinancialEventType.income),
          hasLength(3));
      expect(posted.where((e) => e.type == FinancialEventType.expense),
          hasLength(2));
      expect(posted.where((e) => e.type == FinancialEventType.fundTransfer),
          isEmpty);
      final expenseTotals = await ExpenseService(
        ledgerStorage: recorded,
        planStorage: ExpensePlanStorage(database: testedDb),
      ).loadMonth(thisMonth);
      expect(expenseTotals.actualTotalsMicros[FinancialUnit.syp],
          LedgerEntry.amountToMicros(80000));
      expect(expenseTotals.actualTotalsMicros[FinancialUnit.usd],
          LedgerEntry.amountToMicros(100));
    }

    await assertBalances(ledger, source);
    final expected = await GoalForecastService(
      goals: goals, settings: settings, plans: plans, ledger: ledger,
    ).load(asOf: now);
    expect(expected.forGoal(g.id)!.goal.verifiedSavedAmount, 100);
    expect(expected.forGoal(g.id)!.goal.isBackingVerified, isTrue);
    expect(expected.forGoal(g.id)!.goal.isVerifiedComplete, isFalse);
    expect((await plans.loadItemsForMonth(thisMonth)).single.amountMicros,
        LedgerEntry.amountToMicros(240000));
    expect((await plans.loadItemsForMonth(future)).single.amountMicros,
        LedgerEntry.amountToMicros(310000));

    final notifications = NotificationPreferencesStorage(
      preferences: SharedPreferencesAsync(),
    );
    final backup = BackupService(
      database: source, notificationPreferencesStorage: notifications,
    );
    final bytes = await backup.createBackupBytes();
    expect(backup.inspectBackupBytes(bytes).databaseSchemaVersion, 12);

    // Close the live database, then rebuild the service from the same path
    // to assert values were persisted, not cached in widget/service state.
    await source.close();
    source = LocalDatabase.forTesting(path);
    await assertBalances(FinancialLedgerStorage(database: source), source);
    final restored = BackupService(
      database: target, notificationPreferencesStorage: notifications,
    );
    await restored.restoreBackupBytes(bytes);
    await assertBalances(FinancialLedgerStorage(database: target), target);
    final backGoals = ChallengeStorage(
      database: target, preferences: SharedPreferencesAsync(),
    );
    expect((await backGoals.loadChallenges()).single.verifiedSavedAmount, 100);
    expect((await ExpensePlanStorage(database: target)
        .loadItemsForMonth(future)).single.amountMicros,
        LedgerEntry.amountToMicros(310000));
    final copy = await restored.createBackupBytes();
    expect(restored.inspectBackupBytes(copy).databaseSchemaVersion, 12);
  });
}
