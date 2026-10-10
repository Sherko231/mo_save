import '../models/financial_event.dart';
import 'expense_service.dart';
import 'financial_ledger_storage.dart';

/// A current, per-currency picture of Spending. Forecasts are explicitly
/// hypothetical: the recurring plan has no payment-occurrence links yet.
class SpendingFundSnapshot {
  SpendingFundSnapshot({
    required this.month,
    required Map<FinancialUnit, int> spendingMicros,
    required Map<FinancialUnit, int> unallocatedMicros,
    required Map<FinancialUnit, int> plannedMicros,
    required Map<FinancialUnit, int> actualSpentFromFundMicros,
    required Map<FinancialUnit, int> totalActualExpenseMicros,
  })  : spendingMicros = Map<FinancialUnit, int>.unmodifiable(spendingMicros),
        unallocatedMicros = Map<FinancialUnit, int>.unmodifiable(unallocatedMicros),
        plannedMicros = Map<FinancialUnit, int>.unmodifiable(plannedMicros),
        actualSpentFromFundMicros =
            Map<FinancialUnit, int>.unmodifiable(actualSpentFromFundMicros),
        totalActualExpenseMicros =
            Map<FinancialUnit, int>.unmodifiable(totalActualExpenseMicros);

  static const List<FinancialUnit> cashUnits = <FinancialUnit>[
    FinancialUnit.syp,
    FinancialUnit.usd,
    FinancialUnit.sypNew,
  ];

  final DateTime month;
  final Map<FinancialUnit, int> spendingMicros;
  final Map<FinancialUnit, int> unallocatedMicros;
  final Map<FinancialUnit, int> plannedMicros;
  final Map<FinancialUnit, int> actualSpentFromFundMicros;
  final Map<FinancialUnit, int> totalActualExpenseMicros;

  int spendableMicros(FinancialUnit unit) => spendingMicros[unit] ?? 0;
  int unallocatedBalanceMicros(FinancialUnit unit) =>
      unallocatedMicros[unit] ?? 0;
  int plannedCommitmentsMicros(FinancialUnit unit) =>
      plannedMicros[unit] ?? 0;
  int paidFromSpendingMicros(FinancialUnit unit) =>
      actualSpentFromFundMicros[unit] ?? 0;
  int actualPaidAcrossAllFundsMicros(FinancialUnit unit) =>
      totalActualExpenseMicros[unit] ?? 0;

  /// What cash would remain if ALL listed monthly budget items were paid
  /// now. This intentionally does not pretend to know which planned items
  /// were already paid: a category match is not a settled bill. It can be
  /// negative and is never used as the real spendable balance.
  int hypotheticalAfterFullPlanMicros(FinancialUnit unit) =>
      spendableMicros(unit) - plannedCommitmentsMicros(unit);
}

class SpendingFundService {
  SpendingFundService({
    FinancialLedgerStorage? ledger,
    ExpenseService? expenses,
  })  : _ledger = ledger ?? FinancialLedgerStorage(),
        _expenses = expenses ?? ExpenseService();

  final FinancialLedgerStorage _ledger;
  final ExpenseService _expenses;

  Future<SpendingFundSnapshot> loadCurrentMonth({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final month = DateTime(today.year, today.month);
    final funds = await _ledger.loadFundBalancesMicros();
    final expenseMonth = await _expenses.loadMonth(month);
    final spendingOutflow = <FinancialUnit, int>{
      for (final unit in FinancialUnit.values) unit: 0,
    };
    for (final event in expenseMonth.actualEvents) {
      for (final entry in event.entries) {
        if (entry.affectsBalance &&
            entry.amountMicros < 0 &&
            entry.fund == FinancialFund.spending) {
          spendingOutflow[entry.unit] =
              spendingOutflow[entry.unit]! - entry.amountMicros;
        }
      }
    }
    return SpendingFundSnapshot(
      month: month,
      spendingMicros: funds[FinancialFund.spending]!,
      unallocatedMicros: funds[FinancialFund.unallocated]!,
      plannedMicros: expenseMonth.plannedTotalsMicros,
      actualSpentFromFundMicros: spendingOutflow,
      totalActualExpenseMicros: expenseMonth.actualTotalsMicros,
    );
  }
}
