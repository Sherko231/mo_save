import 'dart:math';

import '../models/expected_income.dart';
import '../models/financial_event.dart';
import '../models/weekly_envelope_allocation.dart';
import 'financial_ledger_storage.dart';
import 'financial_settings_storage.dart';

class WeeklyEnvelopeService {
  WeeklyEnvelopeService({
    FinancialSettingsStorage? settingsStorage,
    FinancialLedgerStorage? ledgerStorage,
  })  : _settingsStorage = settingsStorage ?? FinancialSettingsStorage(),
        _ledgerStorage = ledgerStorage ?? FinancialLedgerStorage();

  final FinancialSettingsStorage _settingsStorage;
  final FinancialLedgerStorage _ledgerStorage;

  Future<WeeklyEnvelopeSuggestion> suggestedSplit(
    ExpectedIncome occurrence,
  ) async {
    _validateWeeklyReceivedOccurrence(occurrence);

    final settings = await _settingsStorage.loadSettings();
    final int receivedMicros = occurrence.receivedAmountMicros!;
    final int configuredExpenses = LedgerEntry.amountToMicros(
      settings.weeklyExpensesAllocation,
    );
    final int configuredSavings = LedgerEntry.amountToMicros(
      settings.weeklySavingsAllocation,
    );

    final int expensesMicros = min(configuredExpenses, receivedMicros);
    final int afterExpenses = receivedMicros - expensesMicros;
    final int savingsMicros = min(configuredSavings, afterExpenses);

    return WeeklyEnvelopeSuggestion(
      receivedMicros: receivedMicros,
      expensesMicros: expensesMicros,
      savingsMicros: savingsMicros,
    );
  }

  Future<WeeklyEnvelopeAllocation?> loadAllocation(
    ExpectedIncome occurrence,
  ) async {
    if (occurrence.kind != RecurringIncomeKind.weeklySyp ||
        !occurrence.isReceived) {
      return null;
    }

    final FinancialEvent? event = await _ledgerStorage.loadEventByRecurrenceKey(
      _allocationRecurrenceKey(occurrence.recurrenceKey),
    );
    if (event == null) {
      return null;
    }
    if (event.type != FinancialEventType.weeklyAllocation) {
      throw StateError('Unexpected event stored for weekly allocation key.');
    }
    return WeeklyEnvelopeAllocation(event: event);
  }

  Future<WeeklyEnvelopeAllocation> allocate({
    required ExpectedIncome occurrence,
    required int expensesMicros,
    required int savingsMicros,
  }) async {
    _validateWeeklyReceivedOccurrence(occurrence);

    if (expensesMicros < 0 || savingsMicros < 0) {
      throw ArgumentError('Envelope amounts cannot be negative.');
    }
    if (expensesMicros == 0 && savingsMicros == 0) {
      throw ArgumentError('At least one envelope must receive an amount.');
    }

    final int receivedMicros = occurrence.receivedAmountMicros!;
    if (expensesMicros + savingsMicros > receivedMicros) {
      throw ArgumentError('Envelope allocation cannot exceed received income.');
    }

    final String allocationKey =
        _allocationRecurrenceKey(occurrence.recurrenceKey);
    final FinancialEvent? existing =
        await _ledgerStorage.loadEventByRecurrenceKey(allocationKey);
    if (existing != null) {
      throw StateError('This weekly income has already been allocated.');
    }

    final FinancialEvent sourceIncome = occurrence.receivedEvent!;
    final List<LedgerEntry> entries = <LedgerEntry>[];
    if (expensesMicros > 0) {
      entries.add(
        LedgerEntry(
          unit: FinancialUnit.syp,
          amountMicros: expensesMicros,
          affectsBalance: false,
          role: LedgerEntryRole.weeklyExpensesEnvelope,
        ),
      );
    }
    if (savingsMicros > 0) {
      entries.add(
        LedgerEntry(
          unit: FinancialUnit.syp,
          amountMicros: savingsMicros,
          affectsBalance: false,
          role: LedgerEntryRole.weeklySavingsEnvelope,
        ),
      );
    }

    final FinancialEvent allocation = FinancialEvent.create(
      type: FinancialEventType.weeklyAllocation,
      occurredAt: sourceIncome.occurredAt,
      entries: entries,
      category: 'تقسيم راتب الخميس',
      note: 'توزيع الراتب بين المصاريف والادخار',
      recurrenceKey: allocationKey,
      sourceEventId: sourceIncome.id,
    );

    await _ledgerStorage.addEvent(allocation);
    return WeeklyEnvelopeAllocation(event: allocation);
  }

  static void _validateWeeklyReceivedOccurrence(ExpectedIncome occurrence) {
    if (occurrence.kind != RecurringIncomeKind.weeklySyp ||
        occurrence.unit != FinancialUnit.syp) {
      throw ArgumentError('Only weekly SYP income can use envelope allocation.');
    }
    if (!occurrence.isReceived || occurrence.receivedAmountMicros == null) {
      throw StateError('Income must be confirmed before it can be allocated.');
    }
  }

  static String _allocationRecurrenceKey(String incomeRecurrenceKey) {
    return 'allocation:$incomeRecurrenceKey';
  }
}
