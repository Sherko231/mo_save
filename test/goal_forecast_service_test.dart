import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/models/financial_settings.dart';
import 'package:mo_save/models/recurring_expense_item.dart';
import 'package:mo_save/models/saving_challenge.dart';
import 'package:mo_save/services/challenge_storage.dart';
import 'package:mo_save/services/expense_plan_storage.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/financial_settings_storage.dart';
import 'package:mo_save/services/goal_forecast_service.dart';
import 'package:mo_save/services/local_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FinancialSettings settings({
    int weeklySalary = 885000,
    int savings = 345000,
    int spending = 540000,
    double monthlyUsd = 300,
    int weekday = DateTime.thursday,
    int usdDay = 1,
    double rate = 0,
  }) => FinancialSettings(
    weeklySypIncome: weeklySalary,
    weeklyPayday: weekday,
    monthlyUsdIncome: monthlyUsd,
    monthlyPayday: usdDay,
    referenceSypPerUsd: rate,
    goldUsdPerGram: 0,
    weeklyExpensesAllocation: spending,
    weeklySavingsAllocation: savings,
  );

  SavingChallenge goal({
    ChallengeCurrency unit = ChallengeCurrency.syp,
    int target = 4000000,
    int marked = 0,
    DateTime? deadline,
  }) {
    final base = SavingChallenge.create(
      id: 'goal-test',
      name: 'ادخار',
      targetAmount: target.toDouble(),
      currency: unit,
      sequence: ChallengeSequence.ordered,
      cellCount: 1,
      deadline: deadline,
    );
    return marked == 0 ? base : SavingChallenge(
      id: base.id, name: base.name, targetAmount: base.targetAmount,
      currency: base.currency, sequence: base.sequence,
      cellCount: base.cellCount, cells: base.cells,
      deadline: base.deadline,
      backedAmountMicros: LedgerEntry.amountToMicros(marked),
    );
  }

  group('MS-14 deterministic calendar forecast', () {
    test('4 vs 5 Thursdays count on actual calendar, not four per month', () {
      final five = GoalForecastService.scheduleMonth(
        DateTime(2026, 10), settings(), const {}, null,
      );
      final four = GoalForecastService.scheduleMonth(
        DateTime(2026, 11), settings(), const {}, null,
      );
      expect(five.weeklyPaydays, 5);
      expect(four.weeklyPaydays, 4);
      expect(five.netSypMicros, LedgerEntry.amountToMicros(1725000));
      expect(four.netSypMicros, LedgerEntry.amountToMicros(1380000));
      expect(four.sypSpendingEnvelopeMicros,
          LedgerEntry.amountToMicros(2160000));
    });

    test('unfunded bills reduce net Savings; never debit ledger', () {
      final good = GoalForecastService.scheduleMonth(
        DateTime(2026, 11), settings(),
        <FinancialUnit, int>{
          FinancialUnit.syp: LedgerEntry.amountToMicros(2000000),
        }, null,
      );
      final bad = GoalForecastService.scheduleMonth(
        DateTime(2026, 11), settings(),
        <FinancialUnit, int>{
          FinancialUnit.syp: LedgerEntry.amountToMicros(3000000),
        }, null,
      );
      expect(good.netSypMicros, LedgerEntry.amountToMicros(1380000));
      expect(bad.netSypMicros, LedgerEntry.amountToMicros(540000));
      expect(bad.sypPlannedBillsMicros,
          LedgerEntry.amountToMicros(3000000));
      expect(bad.usdPlannedSavingsMicros, isNull);
      expect(bad.netUsdMicros, isNull);
    });

    test('payday or salary edit changes projected budget and goal arrival', () {
      final original = GoalForecastService.scheduleMonth(
        DateTime(2026, 11), settings(), const {}, null,
      );
      final cut = GoalForecastService.scheduleMonth(
        DateTime(2026, 11),
        settings(weeklySalary: 400000, savings: 345000,
          spending: 55000),
        const {}, null,
      );
      expect(cut.netSypMicros, original.netSypMicros);
      final reduced = GoalForecastService.scheduleMonth(
        DateTime(2026, 11),
        settings(weeklySalary: 400000, savings: 200000,
          spending: 200000),
        const {}, null,
      );
      expect(reduced.netSypMicros,
          LedgerEntry.amountToMicros(800000));
      final wednesday = GoalForecastService.scheduleMonth(
        DateTime(2026, 10),
        settings(weekday: DateTime.wednesday), const {}, null,
      );
      expect(wednesday.weeklyPaydays, 4);
    });

    test('forecast date uses verified principal and conservative month end',
        () {
      final g = goal(target: 3000000, marked: 1000000);
      final future = List<int>.filled(
        60, LedgerEntry.amountToMicros(1000000),
      );
      expect(GoalForecastService.estimateDate(
        g, DateTime(2026, 10, 11), future,
      ), DateTime(2026, 12, 31));
      expect(GoalForecastService.estimateDate(
        g, DateTime(2026, 10, 11), future, pacePercent: 75,
      ), DateTime(2027, 1, 31));
      expect(GoalForecastService.estimateDate(
        g, DateTime(2026, 10, 11), future, pacePercent: 125,
      ), DateTime(2026, 12, 31));
    });

    test('zero and negative pace, legacy unverified goal have no forecast',
        () {
      final verified = goal();
      final horizon = List<int>.filled(60, 0);
      expect(GoalForecastService.estimateDate(
        verified, DateTime(2026, 10, 11), horizon), isNull);
      expect(GoalForecastService.estimateDate(
        verified, DateTime(2026, 10, 11),
        List<int>.filled(60, -LedgerEntry.amountToMicros(10))), isNull);
      final original = SavingChallenge.create(
        id: 'legacy', name: 'قديم', targetAmount: 100,
        currency: ChallengeCurrency.usd,
        sequence: ChallengeSequence.ordered, cellCount: 1,
      );
      final unverified = SavingChallenge(
        id: original.id, name: original.name,
        targetAmount: original.targetAmount,
        currency: original.currency, sequence: original.sequence,
        cellCount: original.cellCount,
        cells: <ChallengeCell>[
          original.cells.single.copyWith(isCompleted: true),
        ],
      );
      expect(GoalForecastService.estimateDate(
        unverified, DateTime(2026, 10, 11),
        List<int>.filled(60, LedgerEntry.amountToMicros(50))), isNull);
    });

    test('only real received USD salary can define default savings share',
        () {
      final now = DateTime(2026, 7, 1);
      final receipts = <FinancialEvent>[
        FinancialEvent.create(
          type: FinancialEventType.income,
          occurredAt: now,
          recurrenceKey: 'income:monthlyUsd:2026-07-01',
          entries: <LedgerEntry>[
            LedgerEntry(unit: FinancialUnit.usd,
              amountMicros: LedgerEntry.amountToMicros(200),
              fund: FinancialFund.savings),
            LedgerEntry(unit: FinancialUnit.usd,
              amountMicros: LedgerEntry.amountToMicros(100),
              fund: FinancialFund.spending),
          ],
        ),
      ];
      expect(GoalForecastService.latestReceivedUsdSavingsShare([]), isNull);
      expect(GoalForecastService.latestReceivedUsdSavingsShare(receipts),
          closeTo(2 / 3, 0.000001));
      expect(GoalForecastService.scheduleMonth(
        DateTime(2026, 11), settings(),
        <FinancialUnit, int>{
          FinancialUnit.usd: LedgerEntry.amountToMicros(50),
        }, 2 / 3,
      ).netUsdMicros,
          LedgerEntry.amountToMicros(150));
    });

    test('observed real net Savings ignores opening/FX/goal paper and month 1',
        () {
      final events = <FinancialEvent>[];
      void add(FinancialEventType type, DateTime date, int usd, {
        bool affects = true,
        FinancialFund fund = FinancialFund.savings,
      }) => events.add(FinancialEvent.create(
        type: type, occurredAt: date,
        entries: <LedgerEntry>[
          LedgerEntry(unit: FinancialUnit.usd,
            amountMicros: LedgerEntry.amountToMicros(usd),
            affectsBalance: affects, fund: fund),
        ],
      ));
      add(FinancialEventType.openingBalance, DateTime(2026, 5, 20), 1000);
      add(FinancialEventType.income, DateTime(2026, 7, 3), 300);
      add(FinancialEventType.expense, DateTime(2026, 8, 2), -100);
      add(FinancialEventType.income, DateTime(2026, 9, 10), 100);
      add(FinancialEventType.savingContribution,
          DateTime(2026, 9, 12), 900, affects: false);
      add(FinancialEventType.income, DateTime(2026, 10, 1), 5000);
      final result = GoalForecastService.observedSavingsPace(
        events, DateTime(2026, 10, 11),
      );
      expect(result.completeMonths, 3);
      expect(result.netPerMonth[FinancialUnit.usd],
          LedgerEntry.amountToMicros(100));
      expect(GoalForecastService.observedSavingsPace(
        events.where((e) => !e.occurredAt.isBefore(DateTime(2026, 9, 1)))
            .toList(), DateTime(2026, 10, 11),
      ).completeMonths, 0);
    });
  });

  group('MS-14 real storage integration', () {
    late Directory directory;
    late LocalDatabase db;
    late ChallengeStorage goals;
    late FinancialSettingsStorage settingsStore;
    late ExpensePlanStorage plans;
    late FinancialLedgerStorage ledger;
    late GoalForecastService forecasts;
    late DateTime today;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('mosave_forecast_');
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      db = LocalDatabase.forTesting(
        '${directory.path}${Platform.pathSeparator}forecast.db',
      );
      goals = ChallengeStorage(database: db,
        preferences: SharedPreferencesAsync());
      settingsStore = FinancialSettingsStorage(database: db);
      plans = ExpensePlanStorage(database: db);
      ledger = FinancialLedgerStorage(database: db);
      forecasts = GoalForecastService(
        goals: goals, settings: settingsStore,
        plans: plans, ledger: ledger,
      );
      today = DateTime.now();
      await settingsStore.saveSettings(settings());
      await (await db.database).insert('app_metadata',
        <String, Object?>{
          'key': 'expense_plan_client_defaults_seeded_v1', 'value': '1',
        });
    });

    tearDown(() async {
      await db.close();
      await directory.delete(recursive: true);
    });

    test('future plan version and weekly savings updates recalculate dates',
        () async {
      final g = SavingChallenge.create(
        id: 'syp-goal', name: 'سفر', targetAmount: 4000000,
        currency: ChallengeCurrency.syp,
        sequence: ChallengeSequence.ordered, cellCount: 4,
        deadline: DateTime(today.year + 1, 1, 31),
      );
      await goals.addChallenge(g);
      final first = await forecasts.load(asOf: today);
      final original = first.forGoal(g.id)!;
      expect(original.planDate, isNotNull);
      expect(original.observedDate, isNull);
      expect(first.observedMonths, 0);
      final bill = RecurringExpenseItem.create(
        name: 'فاتورة جديدة',
        unit: FinancialUnit.syp,
        amountMicros: LedgerEntry.amountToMicros(3700000),
        sortOrder: 0,
      );
      await plans.addItem(bill,
        effectiveFromMonth: DateTime(today.year, today.month + 1),
      );
      final expensive = await forecasts.load(asOf: today);
      expect(expensive.forGoal(g.id)!.planDate, isNull);

      await plans.updateItem(bill.copyWith(
        amountMicros: LedgerEntry.amountToMicros(500000),
      ), effectiveFromMonth: DateTime(today.year, today.month + 2));
      final reduced = await forecasts.load(asOf: today);
      expect(reduced.forGoal(g.id)!.planDate, isNotNull);
      await settingsStore.saveSettings(settings(savings: 0, spending: 885000));
      final zero = await forecasts.load(asOf: today);
      expect(zero.forGoal(g.id)!.planDate, isNull);
      expect((await ledger.loadEvents()), isEmpty);
      expect((await goals.loadChallenges()).single.verifiedSavedAmount, 0);
    });

    test('USD salary share missing until received or explicitly selected',
        () async {
      final g = SavingChallenge.create(
        id: 'usd-goal', name: 'سيارة', targetAmount: 3000,
        currency: ChallengeCurrency.usd,
        sequence: ChallengeSequence.ordered, cellCount: 3,
      );
      await goals.addChallenge(g);
      final unknown = await forecasts.load(asOf: today);
      expect(unknown.usdShareSource, UsdSavingAssumption.unavailable);
      expect(unknown.forGoal(g.id)!.planDate, isNull);
      final chosen = await forecasts.load(
        asOf: today, usdShareOverride: 0.5,
      );
      expect(chosen.usdShareSource, UsdSavingAssumption.userDefined);
      expect(chosen.forGoal(g.id)!.planDate, isNotNull);
      expect((await ledger.loadEvents()), isEmpty);
    });

    test('FX assumptions opt-in and do not write conversions or principal',
        () async {
      final g = SavingChallenge.create(
        id: 'usd-goal-fx', name: 'شراء',
        targetAmount: 1000,
        currency: ChallengeCurrency.usd,
        sequence: ChallengeSequence.ordered, cellCount: 1,
      );
      await goals.addChallenge(g);
      await settingsStore.saveSettings(settings(
        monthlyUsd: 0, rate: 15000,
      ));
      final noFx = await forecasts.load(asOf: today);
      expect(noFx.forGoal(g.id)!.planDate, isNull);
      final optional = await forecasts.load(
        asOf: today, includeHypotheticalSypToUsd: true,
      );
      expect(optional.assumedSypPerUsd, 15000);
      expect(optional.forGoal(g.id)!.planDate, isNotNull);
      expect(await ledger.loadEvents(
        type: FinancialEventType.currencyConversion), isEmpty);
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd], 0);
    });
  });
}
