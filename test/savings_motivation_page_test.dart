import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/saving_challenge.dart';
import 'package:mo_save/pages/savings_motivation_page.dart';
import 'package:mo_save/services/goal_forecast_service.dart';
import 'package:mo_save/services/savings_motivation_service.dart';

class _FakeMotivation extends SavingsMotivationService {
  @override
  Future<SavingsMotivationSnapshot> load({DateTime? now}) async {
    final fresh = SavingChallenge.create(
      id: 'real', name: 'هدف السفر',
      targetAmount: 100, currency: ChallengeCurrency.usd,
      sequence: ChallengeSequence.ordered, cellCount: 1,
    );
    final real = SavingChallenge(
      id: fresh.id, name: fresh.name,
      targetAmount: fresh.targetAmount, currency: fresh.currency,
      sequence: fresh.sequence, cellCount: 2,
      cells: const <ChallengeCell>[
        ChallengeCell(value: 60, isCompleted: true),
        ChallengeCell(value: 40),
      ], backedAmountMicros: 60000000,
    );
    final old = SavingChallenge(
      id: 'old', name: 'تحدي قديم',
      targetAmount: 100, currency: ChallengeCurrency.usd,
      sequence: ChallengeSequence.ordered, cellCount: 1,
      cells: <ChallengeCell>[
        const ChallengeCell(value: 100, isCompleted: true),
      ],
    );
    GoalProjection projection(SavingChallenge goal,
        {DateTime? plan, DateTime? observed}) => GoalProjection(
      goal: goal,
      monthlyObservedMicros: 100000000,
      observedMonths: 3,
      monthlyPlanAverageMicros: 200000000,
      planDate: plan, observedDate: observed,
      slowerDate: null, fasterDate: null,
      planVsObservedMicros: -100000000,
    );
    final p1 = projection(real,
      plan: DateTime(2027, 1, 31),
      observed: DateTime(2027, 2, 28),
    );
    final p2 = projection(old);
    final forecasts = GoalForecastSnapshot(
      asOf: DateTime(2026, 10, 11),
      months: const <ForecastMonth>[],
      projections: <GoalProjection>[p1,p2],
      usdShare: null,
      usdShareSource: UsdSavingAssumption.unavailable,
      assumedSypPerUsd: null,
      observedMonths: 3,
      observedNetByUnit: const {},
    );
    return SavingsMotivationSnapshot(
      forecasts: forecasts,
      insights: <SavingsMotivationInsight>[
        SavingsMotivationInsight(
          projection: p1,
          achievedMilestones: const <int>[25,50],
          nextMilestone: 75, verifiedStreakMonths: 0,
        ),
        SavingsMotivationInsight(
          projection: p2,
          achievedMilestones: const <int>[],
          nextMilestone: null, verifiedStreakMonths: 0,
        ),
      ],
      streakMonthsByUnit: const {},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MS-15 Arabic goals show real badges, next threshold and no legacy rewards',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: SavingsMotivationPage(service: _FakeMotivation()),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('تقدم الادخار الحقيقي'), findsOneWidget);
    expect(find.text('إنجازات مبنية على أموال فعلية'), findsOneWidget);
    expect(find.text('هدف السفر'), findsOneWidget);
    expect(find.text('25٪ مثبّت'), findsOneWidget);
    expect(find.text('50٪ مثبّت'), findsOneWidget);
    expect(find.text('75٪ غير مكتمل'), findsOneWidget);
    expect(find.textContaining('المحطة التالية: 75٪'), findsOneWidget);
    expect(find.textContaining('لا في سلسلة'), findsNothing);
    await tester.ensureVisible(find.text('تحدي قديم'));
    await tester.pumpAndSettle();
    expect(find.textContaining('الخانات القديمة غير موثّقة'),
        findsOneWidget);
    // Old checked 100% must not earn a second 100% badge.
    expect(find.text('100٪ مثبّت'), findsNothing);
  });

  testWidgets('MS-15 single-goal filter does not show unrelated old goal',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SavingsMotivationPage(
        service: _FakeMotivation(), initialGoalId: 'real',
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('هدف السفر'), findsOneWidget);
    expect(find.text('تحدي قديم'), findsNothing);
    expect(find.textContaining('الوتيرة المرصودة ممكن تؤخر الوصول'),
        findsOneWidget);
  });
}
