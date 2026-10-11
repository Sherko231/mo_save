import '../models/financial_event.dart';
import '../models/saving_challenge.dart';
import 'financial_ledger_storage.dart';
import 'goal_forecast_service.dart';

/// Derived encouragement; has NO persistence and creates NO financial event.
/// It is never a second goal wallet or an achievement ledger.
class SavingsMotivationInsight {
  const SavingsMotivationInsight({
    required this.projection,
    required this.achievedMilestones,
    required this.nextMilestone,
    required this.verifiedStreakMonths,
  });

  final GoalProjection projection;
  final List<int> achievedMilestones;
  final int? nextMilestone;
  /// Complete, consecutive calendar months with actual positive net
  /// Savings salary/income less direct Savings expenses. No transfers or
  /// nonbalance challenge checkmarks; zero means no justified streak.
  final int verifiedStreakMonths;

  SavingChallenge get goal => projection.goal;
  bool get verified => goal.isBackingVerified;
  bool get complete => goal.isVerifiedComplete;

  int get currentPercent {
    if (!verified) return 0;
    return (goal.verifiedProgress * 100).floor().clamp(0, 100).toInt();
  }

  /// Signed difference of CONDITIONAL dates; it is NOT measured historic
  /// movement of a stored forecast or a guaranteed improvement.
  int? get observedVsPlanDays {
    final plan = projection.planDate;
    final actual = projection.observedDate;
    if (!verified || plan == null || actual == null) return null;
    return DateTime.utc(actual.year, actual.month, actual.day).difference(
      DateTime.utc(plan.year, plan.month, plan.day),
    ).inDays;
  }

  /// Conditions are attached to the forecast, not invented from deadlines.
  String get guidance {
    if (!verified) {
      return 'الخانات القديمة غير موثّقة. ثبّت رصيد الهدف من الادخار '
          'الحقيقي أو صفّر الخانات قبل حساب إنجازات مالية.';
    }
    if (complete) {
      return 'الهدف مكتمل بمبلغ محجوز فعلياً من صندوق الادخار. '
          'لا توجد أموال إضافية من هذه الشارة.';
    }
    final observed = projection.monthlyObservedMicros;
    final plan = projection.monthlyPlanAverageMicros;
    if (observed == null) {
      return 'للمقارنة مع الواقع بدنا شهرين مكتملين على الأقل من '
          'حركات الادخار. موعد الخطة تقديري وليس ضماناً.';
    }
    if (plan == null || plan <= 0) {
      return 'ما في خطة ادخار موجبة واضحة بنفس العملة. '
          'راجع توزيع الراتب والفواتير أو افتراضات التوقع.';
    }
    if (observed <= 0) {
      return 'صافي حركة الادخار الفعلية غير موجب. '
          'تعديل الخطة أو تخفيف المصاريف قد يساعد؛ ما في موعد مضمون.';
    }
    final difference = observed - plan;
    if (difference > 0) {
      return 'وتيرة الادخار الفعلية أعلى من الخطة الحالية. '
          'الفرق تقديري للصندوق كله، وليس إيداعاً إضافياً لهذا الهدف.';
    }
    if (difference < 0) {
      return 'وتيرة الادخار الفعلية أقل من الخطة الحالية. '
          'راجع الفواتير والاستلامات الفعلية بدون لوم أو وعود.';
    }
    return 'وتيرة الادخار الفعلية قريبة من الخطة الحالية. '
        'أعد الحساب عند تغيّر الدخل أو المصاريف.';
  }
}

class SavingsMotivationSnapshot {
  const SavingsMotivationSnapshot({
    required this.forecasts,
    required this.insights,
    required this.streakMonthsByUnit,
  });
  final GoalForecastSnapshot forecasts;
  final List<SavingsMotivationInsight> insights;
  final Map<FinancialUnit, int> streakMonthsByUnit;

  SavingsMotivationInsight? forGoal(String id) {
    for (final insight in insights) {
      if (insight.goal.id == id) return insight;
    }
    return null;
  }
}

class SavingsMotivationService {
  SavingsMotivationService({
    GoalForecastService? forecasts,
    FinancialLedgerStorage? ledger,
  }) : _forecasts = forecasts ?? GoalForecastService(),
       _ledger = ledger ?? FinancialLedgerStorage();

  final GoalForecastService _forecasts;
  final FinancialLedgerStorage _ledger;

  static const List<int> milestones = <int>[25, 50, 75, 100];

  Future<SavingsMotivationSnapshot> load({DateTime? now}) async {
    final asOf = now ?? DateTime.now();
    final forecasts = await _forecasts.load(asOf: asOf);
    final events = await _ledger.loadEvents();
    final streaks = evidencedStreaks(events, asOf);
    final insights = <SavingsMotivationInsight>[];
    for (final projection in forecasts.projections) {
      final goal = projection.goal;
      final progress = goal.isBackingVerified
          ? (goal.verifiedProgress * 100).floor().clamp(0, 100).toInt()
          : 0;
      final achieved = goal.isBackingVerified
          ? milestones.where((v) => v <= progress).toList(growable: false)
          : <int>[];
      final upcoming = goal.isBackingVerified && !goal.isVerifiedComplete
          ? milestones.where((v) => v > progress).first
          : null;
      final unit = switch (goal.currency) {
        ChallengeCurrency.usd => FinancialUnit.usd,
        ChallengeCurrency.syp => FinancialUnit.syp,
        ChallengeCurrency.sypNew => FinancialUnit.sypNew,
      };
      insights.add(SavingsMotivationInsight(
        projection: projection,
        achievedMilestones: List<int>.unmodifiable(achieved),
        nextMilestone: upcoming,
        verifiedStreakMonths: streaks[unit] ?? 0,
      ));
    }
    return SavingsMotivationSnapshot(
      forecasts: forecasts,
      insights: List<SavingsMotivationInsight>.unmodifiable(insights),
      streakMonthsByUnit: Map<FinancialUnit, int>.unmodifiable(streaks),
    );
  }

  /// For each currency independently, count consecutive COMPLETE elapsed
  /// months with positive balance-affecting new income minus true direct
  /// Savings expenses. Do not mistake internal transfers of old principal,
  /// opening balances, gold/FX trades, or goal checkmarks for a streak.
  ///
  /// The first ever recorded asset month might be partial; omit it. Require
  /// at least two complete months after it, and the most recent completed
  /// month itself must be net-positive. The result is an asset-fund streak,
  /// not proof that any particular goal received new earmarks in those months.
  static Map<FinancialUnit, int> evidencedStreaks(
    List<FinancialEvent> events, DateTime asOf,
  ) {
    final currentMonth = DateTime(asOf.year, asOf.month);
    DateTime? firstAssetMonth;
    for (final event in events) {
      if (!event.entries.any((e) => e.affectsBalance)) continue;
      final date = event.occurredAt.toLocal();
      final month = DateTime(date.year, date.month);
      if (firstAssetMonth == null || month.isBefore(firstAssetMonth)) {
        firstAssetMonth = month;
      }
    }
    if (firstAssetMonth == null) return const <FinancialUnit, int>{};
    final firstWhole = DateTime(
      firstAssetMonth.year, firstAssetMonth.month + 1,
    );
    final elapsed = (currentMonth.year - firstWhole.year) * 12 +
        currentMonth.month - firstWhole.month;
    if (elapsed < 2) return const <FinancialUnit, int>{};
    final totals = <int, Map<FinancialUnit, int>>{};
    for (final event in events) {
      if (event.type != FinancialEventType.income &&
          event.type != FinancialEventType.expense) continue;
      final date = event.occurredAt.toLocal();
      final month = DateTime(date.year, date.month);
      if (month.isBefore(firstWhole) || !month.isBefore(currentMonth)) continue;
      final key = month.year * 100 + month.month;
      final amounts = totals.putIfAbsent(key, () => <FinancialUnit, int>{});
      for (final entry in event.entries) {
        if (!entry.affectsBalance || entry.fund != FinancialFund.savings ||
            entry.unit == FinancialUnit.goldGram) continue;
        amounts[entry.unit] = (amounts[entry.unit] ?? 0) +
            entry.amountMicros;
      }
    }
    final result = <FinancialUnit, int>{};
    for (final unit in <FinancialUnit>[
      FinancialUnit.usd, FinancialUnit.syp, FinancialUnit.sypNew,
    ]) {
      var streak = 0;
      for (int offset = 1; offset <= elapsed; offset++) {
        final m = DateTime(currentMonth.year, currentMonth.month - offset);
        final key = m.year * 100 + m.month;
        if ((totals[key]?[unit] ?? 0) <= 0) break;
        streak++;
      }
      if (streak >= 2) result[unit] = streak;
    }
    return result;
  }
}
