import 'financial_event.dart';

enum RecurringIncomeKind {
  weeklySyp,
  monthlyUsd,
}

class ExpectedIncome {
  const ExpectedIncome({
    required this.recurrenceKey,
    required this.kind,
    required this.scheduledDate,
    required this.unit,
    required this.expectedAmountMicros,
    this.receivedEvent,
  });

  final String recurrenceKey;
  final RecurringIncomeKind kind;
  final DateTime scheduledDate;
  final FinancialUnit unit;
  final int expectedAmountMicros;
  final FinancialEvent? receivedEvent;

  bool get isReceived => receivedEvent != null;

  int? get receivedAmountMicros {
    final FinancialEvent? event = receivedEvent;
    if (event == null) {
      return null;
    }
    return event.entries
        .where((entry) => entry.unit == unit && entry.affectsBalance)
        .fold<int>(0, (sum, entry) => sum + entry.amountMicros);
  }

  ExpectedIncome copyWithReceived(FinancialEvent event) {
    return ExpectedIncome(
      recurrenceKey: recurrenceKey,
      kind: kind,
      scheduledDate: scheduledDate,
      unit: unit,
      expectedAmountMicros: expectedAmountMicros,
      receivedEvent: event,
    );
  }
}
