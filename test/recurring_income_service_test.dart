import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/expected_income.dart';
import 'package:mo_save/models/financial_settings.dart';
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
      );
    });

    tearDown(() async {
      await database.close();
      await tempDirectory.delete(recursive: true);
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
