import '../models/financial_event.dart';
import 'expense_service.dart';

/// One real, negative cash posting inside an actual expense event. Keeping
/// the parent event and entry index makes each drill-down auditable against
/// the original immutable ledger (including notes and paying fund).
class SpendingAnalyticsLine {
  const SpendingAnalyticsLine({
    required this.event,
    required this.entryIndex,
    required this.entry,
  });

  final FinancialEvent event;
  final int entryIndex;
  final LedgerEntry entry;

  FinancialUnit get unit => entry.unit;
  FinancialFund get fund => entry.fund;
  int get paidMicros => -entry.amountMicros;
  String get category {
    final name = event.category?.trim() ?? '';
    return name.isEmpty ? 'غير مصنف' : name;
  }

  /// Only explicit, unique linked plan payments qualify as recurring.
  /// Text/category matches cannot prove that an installment was paid.
  bool get isRecurringPayment =>
      event.recurrenceKey?.startsWith('expense-plan:') ?? false;
}

class SpendingCategoryTotal {
  SpendingCategoryTotal({
    required this.category,
    required this.amountMicros,
    required this.lines,
  });
  final String category;
  final int amountMicros;
  final List<SpendingAnalyticsLine> lines;
}

class MonthlySpendingAnalytics {
  MonthlySpendingAnalytics({
    required this.month,
    required this.previousMonth,
    required this.lines,
    required this.previousLines,
    required this.plannedMicros,
  });

  final DateTime month;
  final DateTime previousMonth;
  final List<SpendingAnalyticsLine> lines;
  final List<SpendingAnalyticsLine> previousLines;
  final Map<FinancialUnit, int> plannedMicros;

  /// Null fund or recurring means show all. These filters are applied to
  /// actual posted expense lines, never transfers, opening cash or plans.
  List<SpendingAnalyticsLine> filtered({
    FinancialUnit? unit,
    FinancialFund? fund,
    bool? recurring,
    bool previous = false,
  }) {
    final source = previous ? previousLines : lines;
    return source.where((line) =>
      (unit == null || line.unit == unit) &&
      (fund == null || line.fund == fund) &&
      (recurring == null || line.isRecurringPayment == recurring)
    ).toList(growable: false);
  }

  int actualMicros(FinancialUnit unit, {
    FinancialFund? fund,
    bool? recurring,
  }) => filtered(unit: unit, fund: fund, recurring: recurring)
      .fold<int>(0, (total, line) => total + line.paidMicros);

  int previousActualMicros(FinancialUnit unit, {
    FinancialFund? fund,
    bool? recurring,
  }) => filtered(unit: unit, fund: fund, recurring: recurring, previous: true)
      .fold<int>(0, (total, line) => total + line.paidMicros);

  int planMicros(FinancialUnit unit) => plannedMicros[unit] ?? 0;

  /// This compares the month's full active plan with every actual payment,
  /// and is not a per-bill outstanding liability calculation.
  int budgetDifferenceMicros(FinancialUnit unit) =>
      planMicros(unit) - actualMicros(unit);

  List<SpendingCategoryTotal> categories(FinancialUnit unit, {
    FinancialFund? fund,
    bool? recurring,
  }) {
    final grouped = <String, List<SpendingAnalyticsLine>>{};
    for (final line in filtered(unit: unit, fund: fund, recurring: recurring)) {
      grouped.putIfAbsent(line.category, () => <SpendingAnalyticsLine>[])
          .add(line);
    }
    final result = grouped.entries.map((entry) {
      final lines = List<SpendingAnalyticsLine>.unmodifiable(entry.value);
      return SpendingCategoryTotal(
        category: entry.key,
        amountMicros: lines.fold<int>(
          0, (total, line) => total + line.paidMicros,
        ),
        lines: lines,
      );
    }).toList();
    result.sort((a, b) {
      final byAmount = b.amountMicros.compareTo(a.amountMicros);
      return byAmount != 0 ? byAmount : a.category.compareTo(b.category);
    });
    return List<SpendingCategoryTotal>.unmodifiable(result);
  }

  /// Strict per-currency consistency with ExpenseService's actual totals.
  Map<FinancialUnit, int> allActualTotals() => <FinancialUnit, int>{
    for (final unit in FinancialUnit.values) unit: actualMicros(unit),
  };
}

class SpendingAnalyticsService {
  SpendingAnalyticsService({ExpenseService? expenses})
      : _expenses = expenses ?? ExpenseService();

  final ExpenseService _expenses;

  Future<MonthlySpendingAnalytics> loadMonth(DateTime selected) async {
    final month = DateTime(selected.year, selected.month);
    final previous = DateTime(selected.year, selected.month - 1);
    final reports = await Future.wait(<Future<ExpenseMonthSnapshot>>[
      _expenses.loadMonth(month),
      _expenses.loadMonth(previous),
    ]);
    final current = reports[0];
    return MonthlySpendingAnalytics(
      month: month,
      previousMonth: previous,
      lines: _lines(current.actualEvents),
      previousLines: _lines(reports[1].actualEvents),
      plannedMicros: Map<FinancialUnit, int>.unmodifiable(
        current.plannedTotalsMicros,
      ),
    );
  }

  static List<SpendingAnalyticsLine> _lines(List<FinancialEvent> events) {
    final result = <SpendingAnalyticsLine>[];
    for (final event in events) {
      if (event.type != FinancialEventType.expense) continue;
      for (int i = 0; i < event.entries.length; i++) {
        final entry = event.entries[i];
        if (entry.affectsBalance && entry.amountMicros < 0) {
          result.add(SpendingAnalyticsLine(
            event: event,
            entryIndex: i,
            entry: entry,
          ));
        }
      }
    }
    result.sort((a, b) {
      final byDate = b.event.occurredAt.compareTo(a.event.occurredAt);
      if (byDate != 0) return byDate;
      final byId = a.event.id.compareTo(b.event.id);
      return byId != 0 ? byId : a.entryIndex.compareTo(b.entryIndex);
    });
    return List<SpendingAnalyticsLine>.unmodifiable(result);
  }
}
