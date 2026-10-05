import 'financial_event.dart';

class WeeklyEnvelopeSuggestion {
  const WeeklyEnvelopeSuggestion({
    required this.receivedMicros,
    required this.expensesMicros,
    required this.savingsMicros,
  });

  final int receivedMicros;
  final int expensesMicros;
  final int savingsMicros;

  int get allocatedMicros => expensesMicros + savingsMicros;
  int get unallocatedMicros => receivedMicros - allocatedMicros;
}

class WeeklyEnvelopeAllocation {
  const WeeklyEnvelopeAllocation({required this.event});

  final FinancialEvent event;

  int get expensesMicros => event.entries
      .where(
        (entry) =>
            entry.role == LedgerEntryRole.weeklyExpensesEnvelope &&
            entry.unit == FinancialUnit.syp,
      )
      .fold<int>(0, (sum, entry) => sum + entry.amountMicros);

  int get savingsMicros => event.entries
      .where(
        (entry) =>
            entry.role == LedgerEntryRole.weeklySavingsEnvelope &&
            entry.unit == FinancialUnit.syp,
      )
      .fold<int>(0, (sum, entry) => sum + entry.amountMicros);

  int get allocatedMicros => expensesMicros + savingsMicros;
}
