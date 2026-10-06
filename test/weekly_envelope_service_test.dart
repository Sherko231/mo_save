import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/expected_income.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/models/financial_settings.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/financial_settings_storage.dart';
import 'package:mo_save/services/local_database.dart';
import 'package:mo_save/services/weekly_envelope_service.dart';

void main() {
  group('WeeklyEnvelopeService', () {
    late Directory tempDirectory;
    late LocalDatabase database;
    late FinancialLedgerStorage ledger;
    late FinancialSettingsStorage settingsStorage;
    late WeeklyEnvelopeService service;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('mo_save_envelope_');
      database = LocalDatabase.forTesting(
        '${tempDirectory.path}${Platform.pathSeparator}envelope.db',
      );
      ledger = FinancialLedgerStorage(database: database);
      settingsStorage = FinancialSettingsStorage(database: database);
      service = WeeklyEnvelopeService(
        settingsStorage: settingsStorage,
        ledgerStorage: ledger,
      );

      await settingsStorage.saveSettings(const FinancialSettings(
        weeklySypIncome: 885000,
        weeklyPayday: DateTime.thursday,
        monthlyUsdIncome: 300,
        monthlyPayday: 1,
        referenceSypPerUsd: 0,
        goldUsdPerGram: 0,
        weeklyExpensesAllocation: 540000,
        weeklySavingsAllocation: 345000,
      ));
    });

    tearDown(() async {
      await database.close();
      await tempDirectory.delete(recursive: true);
    });

    test('suggested split clamps envelopes to actual received amount', () async {
      final occurrence = await _receivedOccurrence(
        ledger,
        amount: 600000,
        key: 'income:weeklySyp:2026-10-01',
      );

      final suggestion = await service.suggestedSplit(occurrence);

      expect(suggestion.receivedMicros, LedgerEntry.amountToMicros(600000));
      expect(suggestion.expensesMicros, LedgerEntry.amountToMicros(540000));
      expect(suggestion.savingsMicros, LedgerEntry.amountToMicros(60000));
      expect(suggestion.unallocatedMicros, 0);
    });

    test('allocation is non-balance-affecting and linked to source income', () async {
      final occurrence = await _receivedOccurrence(
        ledger,
        amount: 885000,
        key: 'income:weeklySyp:2026-10-08',
      );

      final allocation = await service.allocate(
        occurrence: occurrence,
        expensesMicros: LedgerEntry.amountToMicros(540000),
        savingsMicros: LedgerEntry.amountToMicros(300000),
      );
      final balances = await ledger.loadBalanceMicros();
      final loaded = await service.loadAllocation(occurrence);

      expect(allocation.expensesMicros, LedgerEntry.amountToMicros(540000));
      expect(allocation.savingsMicros, LedgerEntry.amountToMicros(300000));
      expect(allocation.event.sourceEventId, occurrence.receivedEvent!.id);
      expect(allocation.event.entries.every((entry) => !entry.affectsBalance), isTrue);
      expect(
        balances[FinancialUnit.syp],
        LedgerEntry.amountToMicros(885000),
      );
      expect(loaded, isNotNull);
      expect(loaded!.allocatedMicros, LedgerEntry.amountToMicros(840000));
    });

    test('cannot allocate the same weekly income twice', () async {
      final occurrence = await _receivedOccurrence(
        ledger,
        amount: 885000,
        key: 'income:weeklySyp:2026-10-15',
      );

      await service.allocate(
        occurrence: occurrence,
        expensesMicros: LedgerEntry.amountToMicros(540000),
        savingsMicros: LedgerEntry.amountToMicros(345000),
      );

      await expectLater(
        service.allocate(
          occurrence: occurrence,
          expensesMicros: LedgerEntry.amountToMicros(500000),
          savingsMicros: LedgerEntry.amountToMicros(300000),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}

Future<ExpectedIncome> _receivedOccurrence(
  FinancialLedgerStorage ledger, {
  required int amount,
  required String key,
}) async {
  final event = FinancialEvent.create(
    type: FinancialEventType.income,
    occurredAt: DateTime(2026, 10, 1, 12),
    entries: <LedgerEntry>[
      LedgerEntry(
        unit: FinancialUnit.syp,
        amountMicros: LedgerEntry.amountToMicros(amount),
      ),
    ],
    category: 'راتب أسبوعي',
    recurrenceKey: key,
  );
  await ledger.addEvent(event);

  return ExpectedIncome(
    recurrenceKey: key,
    kind: RecurringIncomeKind.weeklySyp,
    scheduledDate: DateTime(2026, 10, 1),
    unit: FinancialUnit.syp,
    expectedAmountMicros: LedgerEntry.amountToMicros(885000),
    receivedEvent: event,
  );
}
