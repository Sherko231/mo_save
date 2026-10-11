import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/models/financial_settings.dart';
import 'package:mo_save/models/saving_challenge.dart';
import 'package:mo_save/pages/goal_forecast_page.dart';
import 'package:mo_save/services/goal_forecast_service.dart';

class _FakeForecasts extends GoalForecastService {
  int calls = 0;
  double? lastUsdShare;
  bool lastFx = false;

  @override
  Future<GoalForecastSnapshot> load({
    DateTime? asOf,
    double? usdShareOverride,
    bool includeHypotheticalSypToUsd = false,
  }) async {
    calls++;
    lastUsdShare = usdShareOverride;
    lastFx = includeHypotheticalSypToUsd;
    final now = DateTime(2026, 10, 11);
    final goal = SavingChallenge.create(
      id: 'goal', name: 'السفر',
      targetAmount: 3000, currency: ChallengeCurrency.usd,
      sequence: ChallengeSequence.ordered, cellCount: 3,
      deadline: DateTime(2027, 2, 1),
    );
    final month = GoalForecastService.scheduleMonth(
      DateTime(2026, 11),
      const FinancialSettings(
        weeklySypIncome: 885000,
        weeklyPayday: DateTime.thursday,
        monthlyUsdIncome: 300,
        monthlyPayday: 12,
        referenceSypPerUsd: 15000,
        goldUsdPerGram: 0,
        weeklyExpensesAllocation: 540000,
        weeklySavingsAllocation: 345000,
      ), const {}, usdShareOverride,
    );
    final projection = GoalProjection(
      goal: goal,
      monthlyObservedMicros: null, observedMonths: 0,
      monthlyPlanAverageMicros: usdShareOverride == null
          ? null : LedgerEntry.amountToMicros(150),
      planDate: usdShareOverride == null
          ? null : DateTime(2028, 11, 30),
      observedDate: null,
      slowerDate: null, fasterDate: null,
      planVsObservedMicros: null,
    );
    return GoalForecastSnapshot(
      asOf: now,
      months: <ForecastMonth>[month],
      projections: <GoalProjection>[projection],
      usdShare: usdShareOverride,
      usdShareSource: usdShareOverride == null
        ? UsdSavingAssumption.unavailable
        : UsdSavingAssumption.userDefined,
      assumedSypPerUsd: includeHypotheticalSypToUsd ? 15000 : null,
      observedMonths: 0,
      observedNetByUnit: const <FinancialUnit, int>{},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('MS-14 RTL forecast labels unavailable dates and updates assumptions',
      (tester) async {
    final service = _FakeForecasts();
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: GoalForecastPage(
          service: service, initialGoalId: 'goal',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('توقعات أهداف الادخار'), findsOneWidget);
    expect(find.textContaining('تقديرات مشروطة'), findsOneWidget);
    expect(find.text('السفر'), findsOneWidget);
    expect(find.textContaining('غياب توزيع راتب مستلم'), findsOneWidget);
    expect(find.textContaining('لا توجد بيانات كافية لتحديد تاريخ'),
        findsNothing);
    final sliderSwitch = find.widgetWithText(
        SwitchListTile, 'افتراض نسبة ادخار بالدولار');
    await tester.ensureVisible(sliderSwitch);
    await tester.tap(sliderSwitch);
    await tester.pumpAndSettle();
    expect(service.lastUsdShare, closeTo(0.5, 0.000001));
    expect(find.byType(Slider), findsOneWidget);
    expect(find.textContaining('50٪'), findsWidgets);
    await tester.ensureVisible(find.text('السفر'));
    await tester.pumpAndSettle();
    expect(find.text('وصول حسب الخطة'), findsOneWidget);
    expect(find.textContaining('حسب الخطة الحالية ممكن نتأخر'),
      findsOneWidget);
    expect(service.calls, greaterThanOrEqualTo(2));
  });
}
