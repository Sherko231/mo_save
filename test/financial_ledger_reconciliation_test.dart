import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/services/currency_conversion_service.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/gold_service.dart';
import 'package:mo_save/services/local_database.dart';

void main() {
  group('financial ledger reconciliation', () {
    late Directory tempDirectory;
    late LocalDatabase database;
    late FinancialLedgerStorage ledger;
    late CurrencyConversionService conversionService;
    late GoldService goldService;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('mo_save_ledger_');
      database = LocalDatabase.forTesting(
        '${tempDirectory.path}${Platform.pathSeparator}ledger.db',
      );
      ledger = FinancialLedgerStorage(database: database);
      conversionService = CurrencyConversionService(ledger: ledger);
      goldService = GoldService(ledger: ledger);

      await ledger.addEvent(_income(FinancialUnit.syp, 2000000, 'seed-syp'));
      await ledger.addEvent(_income(FinancialUnit.usd, 500, 'seed-usd'));
    });

    tearDown(() async {
      await database.close();
      await tempDirectory.delete(recursive: true);
    });

    test('conversion moves value between currencies exactly once', () async {
      final event = await conversionService.recordConversion(
        sourceUnit: FinancialUnit.syp,
        destinationUnit: FinancialUnit.usd,
        sourceAmountMicros: LedgerEntry.amountToMicros(1000000),
        destinationAmountMicros: LedgerEntry.amountToMicros(100),
        occurredAt: DateTime.now(),
      );
      final balances = await ledger.loadBalanceMicros();

      expect(event.executedSypPerUsd, 10000);
      expect(
        balances[FinancialUnit.syp],
        LedgerEntry.amountToMicros(1000000),
      );
      expect(balances[FinancialUnit.usd], LedgerEntry.amountToMicros(600));
      expect(balances[FinancialUnit.goldGram], 0);
    });

    test('gold purchase reduces cash and adds grams without double counting', () async {
      await conversionService.recordConversion(
        sourceUnit: FinancialUnit.syp,
        destinationUnit: FinancialUnit.usd,
        sourceAmountMicros: LedgerEntry.amountToMicros(1000000),
        destinationAmountMicros: LedgerEntry.amountToMicros(100),
        occurredAt: DateTime.now(),
      );

      await goldService.recordPurchase(
        sourceUnit: FinancialUnit.usd,
        cashPaidMicros: LedgerEntry.amountToMicros(50),
        goldReceivedMicros: LedgerEntry.amountToMicros(0.5),
        occurredAt: DateTime.now(),
      );
      final balances = await ledger.loadBalanceMicros();

      expect(
        balances[FinancialUnit.syp],
        LedgerEntry.amountToMicros(1000000),
      );
      expect(balances[FinancialUnit.usd], LedgerEntry.amountToMicros(550));
      expect(
        balances[FinancialUnit.goldGram],
        LedgerEntry.amountToMicros(0.5),
      );
    });

    test('conversion rejects spending more than source balance', () async {
      await expectLater(
        conversionService.recordConversion(
          sourceUnit: FinancialUnit.syp,
          destinationUnit: FinancialUnit.usd,
          sourceAmountMicros: LedgerEntry.amountToMicros(3000000),
          destinationAmountMicros: LedgerEntry.amountToMicros(300),
          occurredAt: DateTime.now(),
        ),
        throwsA(isA<InsufficientBalanceException>()),
      );

      final balances = await ledger.loadBalanceMicros();
      expect(
        balances[FinancialUnit.syp],
        LedgerEntry.amountToMicros(2000000),
      );
      expect(balances[FinancialUnit.usd], LedgerEntry.amountToMicros(500));
    });

    test('gold purchase rejects spending more than cash balance', () async {
      await expectLater(
        goldService.recordPurchase(
          sourceUnit: FinancialUnit.usd,
          cashPaidMicros: LedgerEntry.amountToMicros(600),
          goldReceivedMicros: LedgerEntry.amountToMicros(6),
          occurredAt: DateTime.now(),
        ),
        throwsA(isA<InsufficientBalanceException>()),
      );

      final balances = await ledger.loadBalanceMicros();
      expect(balances[FinancialUnit.usd], LedgerEntry.amountToMicros(500));
      expect(balances[FinancialUnit.goldGram], 0);
    });
  });
}

FinancialEvent _income(FinancialUnit unit, num amount, String id) {
  return FinancialEvent.create(
    id: id,
    type: FinancialEventType.income,
    occurredAt: DateTime.now(),
    entries: <LedgerEntry>[
      LedgerEntry(
        unit: unit,
        amountMicros: LedgerEntry.amountToMicros(amount),
      ),
    ],
    category: 'testSeed',
  );
}
