import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/expected_income.dart';
import 'package:mo_save/models/financial_settings.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/financial_settings_storage.dart';
import 'package:mo_save/services/local_database.dart';
import 'package:mo_save/services/recurring_income_service.dart';

void main() {
  group('RecurringIncomeService', () {
    late Directory tempDirectory;
    late LocalDatabase database;
    late FinancialSettingsStorage settingsStorage;
    late RecurringIncomeService service;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('mo_save_income_');
      database = LocalDatabase.forTesting(
        '${tempDirectory.path}${Platform.pathSeparator}income.db',
      );
      settingsStorage = FinancialSettingsStorage(database: database);
      service = RecurringIncomeService(
        settingsStorage: settingsStorage,
        ledgerStorage: FinancialLedgerStorage(database: database),
        database: database,
      );
    });

    tearDown(() async {
      await database.close();
      await tempDirectory.delete(recursive: true);
    });

    test('ignoring a past payday persists without creating income', () async {
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
      final october = await service.loadMonth(DateTime(2026, 10));
      final past = october.firstWhere((item) =>
          item.kind == RecurringIncomeKind.weeklySyp &&
          item.scheduledDate.day == 1);
      await service.ignoreOccurrence(past);
      await service.ignoreOccurrence(past); // No duplicate ignored identity.

      final after = await service.loadMonth(DateTime(2026, 10));
      final ignored = after.firstWhere(
          (item) => item.recurrenceKey == past.recurrenceKey);
      expect(ignored.isIgnored, isTrue);
      expect(ignored.isReceived, isFalse);
      expect(ignored.needsAction, isFalse);
      final ledger = FinancialLedgerStorage(database: database);
      expect((await ledger.loadBalanceMicros())[FinancialUnit.syp], 0);
      expect(await ledger.loadEvents(), isEmpty);
      await expectLater(
        service.confirmReceived(
          occurrence: ignored,
          amountMicros: LedgerEntry.amountToMicros(885000),
        ),
        throwsStateError,
      );
      expect((await ledger.loadBalanceMicros())[FinancialUnit.syp], 0);

      await database.close();
      final reopened = LocalDatabase.forTesting(
        '${tempDirectory.path}${Platform.pathSeparator}income.db',
      );
      final persisted = RecurringIncomeService(
        settingsStorage: FinancialSettingsStorage(database: reopened),
        ledgerStorage: FinancialLedgerStorage(database: reopened),
        database: reopened,
      );
      final again = await persisted.loadMonth(DateTime(2026, 10));
      expect(again.firstWhere((item) =>
          item.recurrenceKey == past.recurrenceKey).isIgnored, isTrue);
      await persisted.undoIgnore(past);
      final restored = await persisted.loadMonth(DateTime(2026, 10));
      expect(restored.firstWhere((item) =>
          item.recurrenceKey == past.recurrenceKey).needsAction, isTrue);
      expect((await FinancialLedgerStorage(database: reopened)
          .loadBalanceMicros())[FinancialUnit.syp], 0);
      await reopened.close();
    });

    test('recording an already-spent historical payday is zero net cash', () async {
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
      final payday = (await service.loadMonth(DateTime(2026, 10)))
          .firstWhere((item) =>
              item.kind == RecurringIncomeKind.weeklySyp &&
              item.scheduledDate.day == 8);
      final receipt = await service.confirmReceived(
        occurrence: payday,
        amountMicros: LedgerEntry.amountToMicros(885000),
        receivedAt: DateTime(2026, 10, 7),
        alreadySpentMicros: LedgerEntry.amountToMicros(885000),
        spentAt: DateTime(2026, 10, 9),
        spentCategory: 'past-living-expenses',
        spentNote: 'Previously paid',
      );
      final ledger = FinancialLedgerStorage(database: database);
      final events = await ledger.loadEvents();
      expect(events, hasLength(2));
      expect(events.where((event) => event.type ==
          FinancialEventType.income), hasLength(1));
      final spent = events.singleWhere(
          (event) => event.type == FinancialEventType.expense);
      expect(spent.sourceEventId, receipt.id);
      expect(spent.category, 'past-living-expenses');
      expect(spent.note, 'Previously paid');
      expect(receipt.occurredAt.toLocal().day, 7);
      expect(spent.occurredAt.toLocal().day, 9);
      expect((await ledger.loadBalanceMicros())[FinancialUnit.syp], 0);
      expect(await ledger.loadFundBalanceMicros(
          FinancialFund.unallocated, FinancialUnit.syp), 0);
      final month = await service.loadMonth(DateTime(2026, 10));
      final shown = month.singleWhere(
          (item) => item.recurrenceKey == payday.recurrenceKey);
      expect(shown.isReceived, isTrue);
      expect(shown.receivedAmountMicros, LedgerEntry.amountToMicros(885000));
      await expectLater(
        service.confirmReceived(
          occurrence: payday,
          amountMicros: LedgerEntry.amountToMicros(885000),
          alreadySpentMicros: LedgerEntry.amountToMicros(885000),
        ),
        throwsStateError,
      );
      expect(await ledger.loadEvents(), hasLength(2));
    });

    test('backdated receipt survives later changes to recurring defaults', () async {
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
      final payday = (await service.loadMonth(DateTime(2026, 10)))
          .firstWhere((item) =>
              item.kind == RecurringIncomeKind.monthlyUsd);
      await service.confirmReceived(
        occurrence: payday,
        amountMicros: LedgerEntry.amountToMicros(295),
        receivedAt: DateTime(2026, 9, 29),
      );
      await settingsStorage.saveSettings(const FinancialSettings(
        weeklySypIncome: 0,
        weeklyPayday: DateTime.friday,
        monthlyUsdIncome: 0,
        monthlyPayday: 20,
        referenceSypPerUsd: 0,
        goldUsdPerGram: 0,
        weeklyExpensesAllocation: 0,
        weeklySavingsAllocation: 0,
      ));
      final october = await service.loadMonth(DateTime(2026, 10));
      final historical = october.singleWhere(
          (item) => item.recurrenceKey == payday.recurrenceKey);
      expect(historical.isReceived, isTrue);
      expect(historical.receivedAmountMicros, LedgerEntry.amountToMicros(295));
      expect((await FinancialLedgerStorage(database: database)
          .loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(295));
    });

    test('real calendar produces five Thursdays in October 2026', () async {
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

      final occurrences = await service.loadMonth(DateTime(2026, 10));
      final weekly = occurrences
          .where((item) => item.kind == RecurringIncomeKind.weeklySyp)
          .toList(growable: false);
      final monthly = occurrences
          .where((item) => item.kind == RecurringIncomeKind.monthlyUsd)
          .toList(growable: false);

      expect(weekly, hasLength(5));
      expect(weekly.map((item) => item.scheduledDate.day), [1, 8, 15, 22, 29]);
      expect(monthly, hasLength(1));
      expect(monthly.single.scheduledDate.day, 1);
    });

    test('real calendar produces four Thursdays in November 2026', () async {
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

      final occurrences = await service.loadMonth(DateTime(2026, 11));
      final weekly = occurrences
          .where((item) => item.kind == RecurringIncomeKind.weeklySyp)
          .toList(growable: false);

      expect(weekly, hasLength(4));
      expect(weekly.map((item) => item.scheduledDate.day), [5, 12, 19, 26]);
    });

    test('monthly payday 31 clamps to the last real day of February', () async {
      await settingsStorage.saveSettings(const FinancialSettings(
        weeklySypIncome: 0,
        weeklyPayday: DateTime.thursday,
        monthlyUsdIncome: 300,
        monthlyPayday: 31,
        referenceSypPerUsd: 0,
        goldUsdPerGram: 0,
        weeklyExpensesAllocation: 0,
        weeklySavingsAllocation: 0,
      ));

      final occurrences = await service.loadMonth(DateTime(2027, 2));

      expect(occurrences, hasLength(1));
      expect(occurrences.single.kind, RecurringIncomeKind.monthlyUsd);
      expect(occurrences.single.scheduledDate, DateTime(2027, 2, 28));
    });
  });
}
