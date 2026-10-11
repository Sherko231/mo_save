import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/models/saving_challenge.dart';
import 'package:mo_save/pages/savings_goals_preview.dart';
import 'package:mo_save/services/challenge_storage.dart';
import 'package:mo_save/services/goal_forecast_service.dart';

class _TestGoals extends ChallengeStorage {
  _TestGoals(this.goals);
  final List<SavingChallenge> goals;

  @override
  Future<List<SavingChallenge>> loadChallenges() async => goals;
}

class _TestForecast extends GoalForecastService {
  _TestForecast(this.goals);
  final List<SavingChallenge> goals;
  @override
  Future<GoalForecastSnapshot> load({
    DateTime? asOf,
    double? usdShareOverride,
    bool includeHypotheticalSypToUsd = false,
  }) async {
    return GoalForecastSnapshot(
      asOf: DateTime(2026, 10, 11),
      months: const <ForecastMonth>[],
      projections: <GoalProjection>[
        for (final g in goals)
          GoalProjection(
            goal: g,
            monthlyObservedMicros: null,
            observedMonths: 0,
            monthlyPlanAverageMicros: LedgerEntry.amountToMicros(40),
            planDate: g.isBackingVerified
              ? DateTime(2027, 2, 28) : null,
            observedDate: null,
            slowerDate: null,
            fasterDate: null,
            planVsObservedMicros: null,
          ),
      ],
      usdShare: null,
      usdShareSource: UsdSavingAssumption.unavailable,
      assumedSypPerUsd: null,
      observedMonths: 0,
      observedNetByUnit: const <FinancialUnit, int>{},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MS-17 preview shows verified goal amount/date, never old checked cells',
      (tester) async {
    final verified = SavingChallenge(
      id: 'real', name: 'هدف السفر', targetAmount: 100,
      currency: ChallengeCurrency.usd,
      sequence: ChallengeSequence.ordered, cellCount: 2,
      cells: const <ChallengeCell>[
        ChallengeCell(value: 60, isCompleted: true),
        ChallengeCell(value: 40),
      ],
      backedAmountMicros: LedgerEntry.amountToMicros(60),
    );
    final legacy = SavingChallenge(
      id: 'old', name: 'هدف قديم', targetAmount: 100,
      currency: ChallengeCurrency.usd,
      sequence: ChallengeSequence.ordered, cellCount: 1,
      cells: const <ChallengeCell>[
        ChallengeCell(value: 100, isCompleted: true),
      ],
    );
    final all = <SavingChallenge>[verified, legacy];
    var goalOpens = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: ListView(children: <Widget>[
            SavingsGoalsPreview(
              goalStorage: _TestGoals(all),
              forecastService: _TestForecast(all),
              onOpenGoals: () => goalOpens++,
            ),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('الأهداف وتوقع الوصول'), findsOneWidget);
    expect(find.text('هدف السفر'), findsOneWidget);
    expect(find.text('60٪ موثّق'), findsOneWidget);
    expect(find.textContaining('المبلغ المحجوز: '), findsOneWidget);
    expect(find.textContaining('الوصول حسب الخطة:'), findsOneWidget);
    expect(find.text('هدف قديم'), findsOneWidget);
    expect(find.text('0٪ موثّق'), findsOneWidget);
    expect(find.textContaining('خانات قديمة غير موثّقة'), findsOneWidget);
    expect(find.textContaining('لا يمكن تقدير وصول هدف'), findsOneWidget);
    await tester.ensureVisible(find.text('إدارة كل أهداف الادخار'));
    await tester.tap(find.text('إدارة كل أهداف الادخار'));
    await tester.pumpAndSettle();
    expect(goalOpens, 1);
  });
}
