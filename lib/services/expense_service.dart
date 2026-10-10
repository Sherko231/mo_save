import '../models/financial_event.dart';
import '../models/recurring_expense_item.dart';
import 'expense_plan_storage.dart';
import 'financial_ledger_storage.dart';

class ExpenseMonthSnapshot {
  const ExpenseMonthSnapshot({
    required this.planItems,
    required this.actualEvents,
    required this.plannedTotalsMicros,
    required this.actualTotalsMicros,
  });

  final List<RecurringExpenseItem> planItems;
  final List<FinancialEvent> actualEvents;
  final Map<FinancialUnit, int> plannedTotalsMicros;
  final Map<FinancialUnit, int> actualTotalsMicros;
}

class ExpenseService {
  ExpenseService({
    ExpensePlanStorage? planStorage,
    FinancialLedgerStorage? ledgerStorage,
  })  : _planStorage = planStorage ?? ExpensePlanStorage(),
        _ledgerStorage = ledgerStorage ?? FinancialLedgerStorage();

  final ExpensePlanStorage _planStorage;
  final FinancialLedgerStorage _ledgerStorage;

  Future<ExpenseMonthSnapshot> loadMonth(DateTime month) async {
    final DateTime start = DateTime(month.year, month.month, 1);
    final DateTime end = DateTime(month.year, month.month + 1, 1);
    final List<RecurringExpenseItem> planItems = await _planStorage.loadItems();
    final List<FinancialEvent> events = await _ledgerStorage.loadEvents(
      from: start,
      to: end,
      type: FinancialEventType.expense,
    );

    final Map<FinancialUnit, int> planned = <FinancialUnit, int>{
      for (final FinancialUnit unit in FinancialUnit.values) unit: 0,
    };
    for (final RecurringExpenseItem item in planItems) {
      planned[item.unit] = (planned[item.unit] ?? 0) + item.amountMicros;
    }

    final Map<FinancialUnit, int> actual = <FinancialUnit, int>{
      for (final FinancialUnit unit in FinancialUnit.values) unit: 0,
    };
    for (final FinancialEvent event in events) {
      for (final LedgerEntry entry in event.entries) {
        if (!entry.affectsBalance || entry.amountMicros >= 0) {
          continue;
        }
        actual[entry.unit] = (actual[entry.unit] ?? 0) - entry.amountMicros;
      }
    }

    return ExpenseMonthSnapshot(
      planItems: planItems,
      actualEvents: events,
      plannedTotalsMicros: planned,
      actualTotalsMicros: actual,
    );
  }

  Future<void> logExpense({
    required int amountMicros,
    required FinancialUnit unit,
    required DateTime occurredAt,
    required String category,
    String? note,
    FinancialFund sourceFund = FinancialFund.unallocated,
  }) async {
    if (amountMicros <= 0) {
      throw ArgumentError('Expense amount must be greater than zero.');
    }
    if (unit == FinancialUnit.goldGram) {
      throw ArgumentError('Gold grams are not a direct expense currency.');
    }
    final String cleanCategory = category.trim();
    if (cleanCategory.isEmpty) {
      throw ArgumentError('Expense category must not be empty.');
    }

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime expenseDay =
        DateTime(occurredAt.year, occurredAt.month, occurredAt.day);
    if (expenseDay.isAfter(today)) {
      throw ArgumentError('Expense date cannot be in the future.');
    }

    // Legacy callers remain Unallocated; Spending's primary action debits
    // only Spending. The ledger repeats the safety check transactionally.
    final int availableMicros =
        await _ledgerStorage.loadFundBalanceMicros(sourceFund, unit);
    if (availableMicros < amountMicros) {
      throw InsufficientBalanceException(
        unit: unit,
        availableMicros: availableMicros,
        requiredMicros: amountMicros,
      );
    }

    final FinancialEvent event = FinancialEvent.create(
      type: FinancialEventType.expense,
      occurredAt: DateTime(
        expenseDay.year,
        expenseDay.month,
        expenseDay.day,
        12,
      ),
      entries: <LedgerEntry>[
        LedgerEntry(
          unit: unit,
          amountMicros: -amountMicros,
          fund: sourceFund,
        ),
      ],
      category: cleanCategory,
      note: note,
    );

    await _ledgerStorage.addEvent(event);
  }
}
