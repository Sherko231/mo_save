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
    String? requestId,
  }) async {
    if (amountMicros <= 0) {
      throw ArgumentError('Expense amount must be greater than zero.');
    }
    if (unit == FinancialUnit.goldGram) {
      throw ArgumentError('Gold grams are not a direct expense currency.');
    }
    final String cleanCategory = category.trim();
    if (cleanCategory.isEmpty || cleanCategory.length > 80) {
      throw ArgumentError('Expense category must be 1 to 80 characters.');
    }
    final String? cleanNote = note?.trim().isNotEmpty == true
        ? note!.trim() : null;
    if (cleanNote != null && cleanNote.length > 300) {
      throw ArgumentError('Expense note must be at most 300 characters.');
    }
    if (sourceFund == FinancialFund.savings && cleanNote == null) {
      throw ArgumentError(
        'A reason is mandatory for a direct payment from Savings.',
      );
    }
    final String? cleanedRequestId = requestId?.trim();
    if (cleanedRequestId != null &&
        (cleanedRequestId.isEmpty || cleanedRequestId.length > 128)) {
      throw ArgumentError('Invalid expense request identity.');
    }

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime expenseDay =
        DateTime(occurredAt.year, occurredAt.month, occurredAt.day);
    if (expenseDay.isAfter(today)) {
      throw ArgumentError('Expense date cannot be in the future.');
    }

    final FinancialEvent event = FinancialEvent.create(
      id: cleanedRequestId == null ? null : 'expense_$cleanedRequestId',
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
      note: cleanNote,
    );

    // Recovered UI requests are checked BEFORE available cash: the original
    // payment might have spent the whole balance. Conflicting reuse fails.
    if (cleanedRequestId != null) {
      final original = await _ledgerStorage.loadEvent(event.id);
      if (original != null) {
        if (_sameExpense(original, event)) return;
        throw StateError('Expense request identity was reused for new data.');
      }
    }

    // A non-transactional early warning only. The authoritative check is
    // repeated by FinancialLedgerStorage within its SQLite write transaction.
    final int availableMicros =
        await _ledgerStorage.loadFundBalanceMicros(sourceFund, unit);
    if (availableMicros < amountMicros) {
      throw InsufficientBalanceException(
        unit: unit,
        availableMicros: availableMicros,
        requiredMicros: amountMicros,
      );
    }

    // The first write and the fund-balance validation run inside a ledger
    // transaction. A repeated UI request ID must not write a second expense.
    // Conflict re-check also covers a retry whose first result was lost.
    try {
      await _ledgerStorage.addEvent(event);
    } catch (_) {
      if (cleanedRequestId == null) rethrow;
      final existing = await _ledgerStorage.loadEvent(event.id);
      if (_sameExpense(existing, event)) return;
      rethrow;
    }
  }

  static bool _sameExpense(FinancialEvent? existing, FinancialEvent request) {
    if (existing == null) return false;
    if (existing.id != request.id ||
        existing.type != FinancialEventType.expense ||
        existing.occurredAt != request.occurredAt ||
        existing.category != request.category ||
        existing.note != request.note ||
        existing.entries.length != 1 ||
        request.entries.length != 1) {
      return false;
    }
    final previous = existing.entries.single;
    final requested = request.entries.single;
    return previous.affectsBalance &&
        previous.amountMicros == requested.amountMicros &&
        previous.unit == requested.unit &&
        previous.fund == requested.fund;
  }
}
