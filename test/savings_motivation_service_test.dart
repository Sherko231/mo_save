import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/models/saving_challenge.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/goal_forecast_service.dart';
import 'package:mo_save/services/goal_reminder_copy.dart';
import 'package:mo_save/services/local_database.dart';
import 'package:mo_save/services/savings_motivation_service.dart';

SavingChallenge _goal({
  required String id,
  required int backed,
  int target = 100,
  bool verified = true,
}) {
  final fresh = SavingChallenge.create(
    id: id, name: 'هدف $id',
    targetAmount: target.toDouble(),
    currency: ChallengeCurrency.usd,
    sequence: ChallengeSequence.ordered,
    cellCount: 1,
  );
  return SavingChallenge(
    id: fresh.id, name: fresh.name, targetAmount: fresh.targetAmount,
    currency: fresh.currency, sequence: fresh.sequence,
    cellCount: fresh.cellCount,
    cells: <ChallengeCell>[
      fresh.cells.single.copyWith(isCompleted: backed == target),
    ],
    backedAmountMicros: verified ? LedgerEntry.amountToMicros(backed) : null,
  );
}

GoalProjection _projection(SavingChallenge goal, {
  int? planned = 200,
  int? observed = 150,
  DateTime? planDate,
  DateTime? observedDate,
}) => GoalProjection(
  goal: goal,
  monthlyObservedMicros: observed == null ? null :
      LedgerEntry.amountToMicros(observed),
  observedMonths: observed == null ? 0 : 3,
  monthlyPlanAverageMicros: planned == null ? null :
      LedgerEntry.amountToMicros(planned),
  planDate: planDate,
  observedDate: observedDate,
  slowerDate: null, fasterDate: null,
  planVsObservedMicros: planned == null || observed == null
      ? null : LedgerEntry.amountToMicros(observed - planned),
);

class _ForecastStub extends GoalForecastService {
  _ForecastStub(this.snapshot);
  final GoalForecastSnapshot snapshot;

  @override
  Future<GoalForecastSnapshot> load({
    DateTime? asOf,
    double? usdShareOverride,
    bool includeHypotheticalSypToUsd = false,
  }) async => snapshot;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MS-15 verified-only milestone and supportive messaging', () {
    test('unverified full old grid earns no milestone or financial progress',
        () {
      final goal = _goal(id: 'old', backed: 100, verified: false);
      final insight = SavingsMotivationInsight(
        projection: _projection(goal),
        achievedMilestones: const <int>[],
        nextMilestone: null,
        verifiedStreakMonths: 0,
      );
      expect(goal.savedAmount, 100);
      expect(insight.currentPercent, 0);
      expect(insight.achievedMilestones, isEmpty);
      expect(insight.guidance, contains('غير موثّقة'));
      expect(GoalReminderCopy.weekBefore(goal), contains('غير مثبتة'));
      expect(GoalReminderCopy.onDeadline(goal), contains('غير موثّقة'));
      expect(GoalReminderCopy.weekBefore(goal), isNot(contains('المتبقي')));
    });

    test('real backed progress awards exactly its attained thresholds', () {
      final goal = _goal(id: 'real', backed: 60);
      final insight = SavingsMotivationInsight(
        projection: _projection(goal),
        achievedMilestones: const <int>[25, 50],
        nextMilestone: 75, verifiedStreakMonths: 0,
      );
      expect(insight.currentPercent, 60);
      expect(insight.achievedMilestones, <int>[25, 50]);
      expect(insight.nextMilestone, 75);
      expect(insight.guidance, contains('أقل من الخطة'));
      expect(GoalReminderCopy.weekBefore(goal), contains('40'));
      expect(GoalReminderCopy.onDeadline(goal), contains('تعديل الخطة'));
    });

    test('conditional comparison is measured between plan and observed dates',
        () {
      final insight = SavingsMotivationInsight(
        projection: _projection(
          _goal(id: 'pace', backed: 25),
          planDate: DateTime(2026, 12, 31),
          observedDate: DateTime(2027, 1, 31),
        ),
        achievedMilestones: const <int>[25],
        nextMilestone: 50, verifiedStreakMonths: 0,
      );
      expect(insight.observedVsPlanDays, 31);
      expect(SavingsMotivationInsight(
        projection: _projection(
          _goal(id: 'missing', backed: 25),
          observed: null, planDate: DateTime(2026, 12, 31),
        ),
        achievedMilestones: const <int>[25],
        nextMilestone: 50, verifiedStreakMonths: 0,
      ).observedVsPlanDays, isNull);
    });

    test('a completed backed goal is acknowledged without new cash', () {
      final goal = _goal(id: 'done', backed: 100);
      final insight = SavingsMotivationInsight(
        projection: _projection(goal),
        achievedMilestones: const <int>[25,50,75,100],
        nextMilestone: null,
        verifiedStreakMonths: 0,
      );
      expect(insight.complete, isTrue);
      expect(insight.guidance, contains('لا توجد أموال إضافية'));
    });

    test('streak requires two or more real complete positive months; '
        'old opening, FX, transfers and grid marks cannot create it', () {
      final events = <FinancialEvent>[];
      void add(FinancialEventType type, DateTime at, int amount, {
        FinancialFund fund = FinancialFund.savings,
        bool affects = true,
      }) => events.add(FinancialEvent.create(
        type: type,
        occurredAt: at,
        entries: <LedgerEntry>[
          LedgerEntry(unit: FinancialUnit.usd,
            amountMicros: LedgerEntry.amountToMicros(amount),
            fund: fund, affectsBalance: affects),
        ],
      ));
      add(FinancialEventType.openingBalance, DateTime(2026, 5, 18), 1000);
      add(FinancialEventType.income, DateTime(2026, 7, 7), 100);
      add(FinancialEventType.income, DateTime(2026, 8, 7), 100);
      add(FinancialEventType.expense, DateTime(2026, 8, 15), -40);
      add(FinancialEventType.income, DateTime(2026, 9, 7), 100);
      add(FinancialEventType.savingContribution,
          DateTime(2026, 9, 8), 500, affects: false);
      add(FinancialEventType.openingBalance, DateTime(2026, 9, 8), 1000);
      add(FinancialEventType.income, DateTime(2026, 10, 10), 5000);
      final streaks = SavingsMotivationService.evidencedStreaks(
        events, DateTime(2026, 10, 11),
      );
      expect(streaks[FinancialUnit.usd], 3);
      expect(streaks.containsKey(FinancialUnit.syp), isFalse);
      add(FinancialEventType.expense, DateTime(2026, 9, 12), -150);
      expect(SavingsMotivationService.evidencedStreaks(
        events, DateTime(2026, 10, 11),
      ), isEmpty);
      expect(SavingsMotivationService.evidencedStreaks(
        events, DateTime(2026, 7, 12),
      ), isEmpty);
    });

    test('no actual history never fabricates a streak', () {
      expect(SavingsMotivationService.evidencedStreaks(
        const <FinancialEvent>[], DateTime(2026, 10, 11),
      ), isEmpty);
    });
  });

  test('MS-15 derives earned thresholds without ledger/owned mutations',
      () async {
    final dir = await Directory.systemTemp.createTemp('mosave_motivation_');
    final db = LocalDatabase.forTesting(
      '${dir.path}${Platform.pathSeparator}motivation.db',
    );
    addTearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });
    final ledger = FinancialLedgerStorage(database: db);
    await ledger.addEvent(FinancialEvent.create(
      type: FinancialEventType.openingBalance,
      occurredAt: DateTime(2026, 5, 4),
      entries: <LedgerEntry>[
        LedgerEntry(
          unit: FinancialUnit.usd, fund: FinancialFund.savings,
          amountMicros: LedgerEntry.amountToMicros(200),
        ),
      ],
    ));
    final g1 = _goal(id: 'first', backed: 60);
    final g2 = _goal(id: 'legacy', backed: 100, verified: false);
    final asOf = DateTime(2026, 10, 11);
    final snapshot = GoalForecastSnapshot(
      asOf: asOf,
      months: const <ForecastMonth>[],
      projections: <GoalProjection>[
        _projection(g1, planned: 200, observed: 100),
        _projection(g2, planned: 200, observed: 100),
      ],
      usdShare: null,
      usdShareSource: UsdSavingAssumption.unavailable,
      assumedSypPerUsd: null, observedMonths: 0,
      observedNetByUnit: const <FinancialUnit, int>{},
    );
    final motivation = SavingsMotivationService(
      forecasts: _ForecastStub(snapshot), ledger: ledger,
    );
    final before = await ledger.loadBalanceMicros();
    final loaded = await motivation.load(now: asOf);
    expect(loaded.forGoal('first')!.achievedMilestones, <int>[25,50]);
    expect(loaded.forGoal('first')!.nextMilestone, 75);
    expect(loaded.forGoal('legacy')!.achievedMilestones, isEmpty);
    expect(loaded.forGoal('legacy')!.nextMilestone, isNull);
    expect(await ledger.loadBalanceMicros(), before);
    expect(await ledger.loadEvents(type: FinancialEventType.income), isEmpty);
  });
}
