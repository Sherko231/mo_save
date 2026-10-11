import 'dart:math' as math;

import '../models/financial_event.dart';
import '../models/financial_settings.dart';
import '../models/saving_challenge.dart';
import 'challenge_storage.dart';
import 'expense_plan_storage.dart';
import 'financial_ledger_storage.dart';
import 'financial_settings_storage.dart';

enum UsdSavingAssumption { userDefined, lastReceivedSplit, unavailable }

/// Conditional month-end projections, never ledger postings or a commitment
/// that future salary, goal allocations, bills or FX trades will occur.
class ForecastMonth {
  const ForecastMonth({
    required this.month,
    required this.weeklyPaydays,
    required this.weeklyPaydayDates,
    required this.monthlyUsdPayday,
    required this.sypPlannedSavingsMicros,
    required this.sypPlannedBillsMicros,
    required this.sypSpendingEnvelopeMicros,
    required this.usdPlannedSavingsMicros,
    required this.usdPlannedBillsMicros,
    required this.netSypMicros,
    required this.netUsdMicros,
  });
  final DateTime month;
  final int weeklyPaydays;
  final List<DateTime> weeklyPaydayDates;
  final DateTime? monthlyUsdPayday;
  final int sypPlannedSavingsMicros;
  final int sypPlannedBillsMicros;
  final int sypSpendingEnvelopeMicros;
  final int? usdPlannedSavingsMicros;
  final int usdPlannedBillsMicros;
  final int netSypMicros;
  final int? netUsdMicros;
}

class GoalProjection {
  const GoalProjection({
    required this.goal,
    required this.monthlyObservedMicros,
    required this.observedMonths,
    required this.monthlyPlanAverageMicros,
    required this.planDate,
    required this.observedDate,
    required this.slowerDate,
    required this.fasterDate,
    required this.planVsObservedMicros,
  });

  final SavingChallenge goal;
  /// Average net real Savings funding, including transfers, excluding opening
  /// assets, currency/gold principal movement and price appreciation.
  final int? monthlyObservedMicros;
  final int observedMonths;
  /// Average of upcoming twelve scheduled months in the goal's unit.
  final int? monthlyPlanAverageMicros;
  final DateTime? planDate;
  final DateTime? observedDate;
  final DateTime? slowerDate;
  final DateTime? fasterDate;
  /// Positive = real pace above current plan; negative = behind current plan.
  final int? planVsObservedMicros;

  bool get isSupported => goal.isBackingVerified;
  bool get isComplete => goal.isVerifiedComplete;

  /// The date is conditional, and intentionally not a guaranteed due date.
  bool get planMissesDeadline => goal.deadline != null && !isComplete &&
      (planDate == null || _day(planDate!).isAfter(_day(goal.deadline!)));
  bool get observedMissesDeadline => goal.deadline != null && !isComplete &&
      (observedDate == null || _day(observedDate!).isAfter(_day(goal.deadline!)));

  static DateTime _day(DateTime date) =>
      DateTime(date.year, date.month, date.day);
}

class GoalForecastSnapshot {
  const GoalForecastSnapshot({
    required this.asOf,
    required this.months,
    required this.projections,
    required this.usdShare,
    required this.usdShareSource,
    required this.assumedSypPerUsd,
    required this.observedMonths,
    required this.observedNetByUnit,
  });
  final DateTime asOf;
  final List<ForecastMonth> months;
  final List<GoalProjection> projections;
  final double? usdShare;
  final UsdSavingAssumption usdShareSource;
  /// Non-null ONLY if the user explicitly chose a hypothetical SYP→USD FX.
  final double? assumedSypPerUsd;
  final int observedMonths;
  final Map<FinancialUnit, int> observedNetByUnit;

  GoalProjection? forGoal(String id) {
    for (final projection in projections) {
      if (projection.goal.id == id) return projection;
    }
    return null;
  }
}

class GoalForecastService {
  GoalForecastService({
    ChallengeStorage? goals,
    FinancialSettingsStorage? settings,
    ExpensePlanStorage? plans,
    FinancialLedgerStorage? ledger,
  }) : _goals = goals ?? ChallengeStorage(),
       _settings = settings ?? FinancialSettingsStorage(),
       _plans = plans ?? ExpensePlanStorage(),
       _ledger = ledger ?? FinancialLedgerStorage();

  final ChallengeStorage _goals;
  final FinancialSettingsStorage _settings;
  final ExpensePlanStorage _plans;
  final FinancialLedgerStorage _ledger;

  static const int horizonMonths = 60;

  /// usdShareOverride is an explicit 0..1 fraction of the MONTHLY USD salary.
  /// Without a user scenario we use the last ACTUAL received salary's split;
  /// if no evidence exists no USD plan forecast is shown.
  ///
  /// Currency conversion is NEVER inferred. Only an explicit optional
  /// hypothetical FX scenario may translate future SYP surplus into USD.
  Future<GoalForecastSnapshot> load({
    DateTime? asOf,
    double? usdShareOverride,
    bool includeHypotheticalSypToUsd = false,
  }) async {
    if (usdShareOverride != null &&
        (!usdShareOverride.isFinite ||
         usdShareOverride < 0 || usdShareOverride > 1)) {
      throw ArgumentError('The assumed USD savings fraction must be 0..1.');
    }
    final at = asOf ?? DateTime.now();
    final today = DateTime(at.year, at.month, at.day);
    final goals = await _goals.loadChallenges();
    final settings = await _settings.loadSettings();
    final events = await _ledger.loadEvents();

    final shareFromHistory = latestReceivedUsdSavingsShare(events);
    final share = usdShareOverride ?? shareFromHistory;
    final shareSource = usdShareOverride != null
        ? UsdSavingAssumption.userDefined
        : shareFromHistory != null
          ? UsdSavingAssumption.lastReceivedSplit
          : UsdSavingAssumption.unavailable;
    final rate = includeHypotheticalSypToUsd &&
        settings.referenceSypPerUsd.isFinite &&
        settings.referenceSypPerUsd > 0
      ? settings.referenceSypPerUsd : null;

    // At least TWO complete calendar months must follow the first real
    // balance-affecting event, else 'actual monthly pace' is unknown.
    final history = observedSavingsPace(events, today);
    final months = <ForecastMonth>[];
    for (int i = 1; i <= horizonMonths; i++) {
      final month = DateTime(today.year, today.month + i);
      final billItems = await _plans.loadItemsForMonth(month);
      final bills = <FinancialUnit, int>{};
      for (final item in billItems) {
        bills[item.unit] = (bills[item.unit] ?? 0) + item.amountMicros;
      }
      months.add(scheduleMonth(month, settings, bills, share));
    }

    int? monthly(FinancialUnit unit, ForecastMonth month) => switch(unit) {
      FinancialUnit.syp => month.netSypMicros,
      FinancialUnit.usd => month.netUsdMicros == null && rate == null
          ? null
          : (month.netUsdMicros ?? -month.usdPlannedBillsMicros) +
              (rate == null ? 0 : (month.netSypMicros / rate).floor()),
      FinancialUnit.sypNew => null,
      FinancialUnit.goldGram => null,
    };

    final projections = <GoalProjection>[];
    for (final goal in goals) {
      final unit = switch (goal.currency) {
        ChallengeCurrency.usd => FinancialUnit.usd,
        ChallengeCurrency.syp => FinancialUnit.syp,
        ChallengeCurrency.sypNew => FinancialUnit.sypNew,
      };
      final planned = months.map((m) => monthly(unit, m)).toList();
      final planKnown = planned.every((p) => p != null);
      final observed = history.netPerMonth[unit];
      final planAvg = planKnown
        ? planned.take(12).fold<int>(
            0, (sum, n) => sum + n!) ~/ 12
        : null;
      final planDate = goal.isBackingVerified && planKnown
        ? estimateDate(goal, today, planned.cast<int>())
        : null;
      final observedDate = goal.isBackingVerified && observed != null
        ? estimateDate(goal, today,
            List<int>.filled(horizonMonths, observed))
        : null;

      projections.add(GoalProjection(
        goal: goal,
        monthlyObservedMicros: history.netPerMonth[unit],
        observedMonths: history.completeMonths,
        monthlyPlanAverageMicros: planAvg,
        planDate: planDate,
        observedDate: observedDate,
        slowerDate: goal.isBackingVerified && planKnown
          ? estimateDate(goal, today, planned.cast<int>(),
              pacePercent: 75) : null,
        fasterDate: goal.isBackingVerified && planKnown
          ? estimateDate(goal, today, planned.cast<int>(),
              pacePercent: 125) : null,
        planVsObservedMicros: planAvg == null || observed == null
          ? null : observed - planAvg,
      ));
    }
    return GoalForecastSnapshot(
      asOf: today,
      months: List<ForecastMonth>.unmodifiable(months),
      projections: List<GoalProjection>.unmodifiable(projections),
      usdShare: share,
      usdShareSource: shareSource,
      assumedSypPerUsd: rate,
      observedMonths: history.completeMonths,
      observedNetByUnit: Map<FinancialUnit, int>.unmodifiable(
        history.netPerMonth,
      ),
    );
  }

  /// Exact 4/5 weekday counts, respecting configured income and envelopes.
  /// Bills beyond the Spending allowance reduce the potential Savings
  /// contribution conservatively; bills are NOT ledger payments here.
  static ForecastMonth scheduleMonth(
    DateTime month, FinancialSettings settings,
    Map<FinancialUnit, int> plannedBills, double? usdShare,
  ) {
    final first = DateTime(month.year, month.month, 1);
    final days = DateTime(first.year, first.month + 1, 0).day;
    final weeklyDates = <DateTime>[];
    for (var d = 1; d <= days; d++) {
      final date = DateTime(first.year, first.month, d);
      if (date.weekday == settings.weeklyPayday) weeklyDates.add(date);
    }
    final paydays = weeklyDates.length;
    final monthlyUsdPayday = settings.monthlyUsdIncome > 0
      ? DateTime(first.year, first.month,
          settings.monthlyPayday.clamp(1, days).toInt()) : null;
    final gross = math.max(0, settings.weeklySypIncome);
    final budgetSavings = math.max(0, settings.weeklySavingsAllocation)
        .clamp(0, gross).toInt();
    final budgetSpending = math.max(0, settings.weeklyExpensesAllocation)
        .clamp(0, gross - budgetSavings).toInt();
    final plannedSyp = paydays * budgetSavings * LedgerEntry.microsPerUnit;
    final spendingBudget = paydays * budgetSpending *
        LedgerEntry.microsPerUnit;
    final sypBills = plannedBills[FinancialUnit.syp] ?? 0;
    final usdBills = plannedBills[FinancialUnit.usd] ?? 0;
    final sypNet = plannedSyp -
        math.max(0, sypBills - spendingBudget);
    final monthlyUsdGross = settings.monthlyUsdIncome;
    final usdFunded = usdShare == null || !monthlyUsdGross.isFinite
        ? null
        : (math.max(0, monthlyUsdGross) * usdShare *
            LedgerEntry.microsPerUnit).floor();
    // No separate USD Spending allowance is configured today. To avoid an
    // optimistic forecast, deduct the entire USD plan from assumed USD
    // savings; real paid bills remain a separate accounting series.
    final usdNet = usdFunded == null ? null : usdFunded - usdBills;
    return ForecastMonth(
      month: first,
      weeklyPaydays: paydays,
      weeklyPaydayDates: List<DateTime>.unmodifiable(weeklyDates),
      monthlyUsdPayday: monthlyUsdPayday,
      sypPlannedSavingsMicros: plannedSyp,
      sypPlannedBillsMicros: sypBills,
      sypSpendingEnvelopeMicros: spendingBudget,
      usdPlannedSavingsMicros: usdFunded,
      usdPlannedBillsMicros: usdBills,
      netSypMicros: sypNet,
      netUsdMicros: usdNet,
    );
  }

  /// Uses observed *received* salary split, never an unreceived/ignored
  /// scheduled occurrence and never global reference FX values.
  static double? latestReceivedUsdSavingsShare(List<FinancialEvent> events) {
    final receipts = events.where((e) =>
      e.type == FinancialEventType.income &&
      (e.recurrenceKey?.startsWith('income:monthlyUsd:') ?? false)
    ).toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    for (final event in receipts) {
      final usd = event.entries.where((e) =>
        e.unit == FinancialUnit.usd && e.affectsBalance &&
        e.amountMicros > 0);
      final total = usd.fold<int>(0, (n, e) => n + e.amountMicros);
      if (total <= 0) continue;
      final saved = usd.where((e) => e.fund == FinancialFund.savings)
          .fold<int>(0, (n, e) => n + e.amountMicros);
      return (saved / total).clamp(0.0, 1.0).toDouble();
    }
    return null;
  }

  /// Only complete, elapsed calendar months; excludes FX/gold principal,
  /// opening balances and non-cash goal checkmarks from 'observed funding'.
  static ObservedSavingPace observedSavingsPace(
      List<FinancialEvent> events, DateTime today) {
    final calendar = DateTime(today.year, today.month);
    DateTime? earliest;
    for (final event in events) {
      if (!event.entries.any((e) =>
          e.affectsBalance ||
          event.type == FinancialEventType.fundTransfer)) continue;
      final date = event.occurredAt.toLocal();
      final month = DateTime(date.year, date.month);
      if (earliest == null || month.isBefore(earliest)) earliest = month;
    }
    if (earliest == null) return const ObservedSavingPace(0, {});
    // Exclude the first month since it may start mid-month, and exclude
    // current month as it is not yet complete.
    final firstComplete = DateTime(earliest.year, earliest.month + 1);
    final coverage = (calendar.year - firstComplete.year) * 12 +
        calendar.month - firstComplete.month;
    if (coverage < 2) return const ObservedSavingPace(0, {});
    final count = math.min(3, coverage);
    final start = DateTime(calendar.year, calendar.month - count);
    final totals = <FinancialUnit, int>{};
    for (final event in events) {
      final date = event.occurredAt.toLocal();
      if (date.isBefore(start) || !date.isBefore(calendar)) continue;
      if (event.type == FinancialEventType.fundTransfer) {
        for (final entry in event.entries) {
          if (entry.fund != FinancialFund.savings) continue;
          totals[entry.unit] =
              (totals[entry.unit] ?? 0) + entry.amountMicros;
        }
      } else if (event.type == FinancialEventType.income ||
          event.type == FinancialEventType.expense) {
        for (final entry in event.entries) {
          if (entry.fund != FinancialFund.savings ||
              !entry.affectsBalance) continue;
          totals[entry.unit] =
              (totals[entry.unit] ?? 0) + entry.amountMicros;
        }
      }
    }
    return ObservedSavingPace(count, <FinancialUnit, int>{
      for (final unit in <FinancialUnit>[
        FinancialUnit.syp, FinancialUnit.usd, FinancialUnit.sypNew,
      ])
        unit: (totals[unit] ?? 0) ~/ count,
    });
  }

  /// Month-end conservative milestone, after all expected monthly bills.
  /// No positive total net pace -> no date. No goal verification -> no date.
  static DateTime? estimateDate(
    SavingChallenge goal,
    DateTime asOf,
    List<int> monthlyNetMicros, {
    int pacePercent = 100,
  }) {
    if (!goal.isBackingVerified) return null;
    final target = (goal.targetAmount * LedgerEntry.microsPerUnit).round();
    if (goal.backedAmountMicros! >= target) {
      return DateTime(asOf.year, asOf.month, asOf.day);
    }
    if (pacePercent <= 0 || monthlyNetMicros.isEmpty) return null;
    final horizon = math.min(monthlyNetMicros.length, horizonMonths);
    if (monthlyNetMicros.take(math.min(12, horizon))
        .fold<int>(0, (sum, n) => sum + n) <= 0) return null;
    var future = goal.backedAmountMicros!;
    for (var i = 0; i < horizon; i++) {
      future = math.max(0,
        future + monthlyNetMicros[i] * pacePercent ~/ 100);
      if (future >= target) {
        return DateTime(asOf.year, asOf.month + i + 2, 0);
      }
    }
    return null; // Not reachable within 60 months: do not invent a date.
  }
}

class ObservedSavingPace {
  const ObservedSavingPace(this.completeMonths, this.netPerMonth);
  final int completeMonths;
  final Map<FinancialUnit, int> netPerMonth;
}
