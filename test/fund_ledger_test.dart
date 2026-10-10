import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/local_database.dart';

void main() {
  group('MS-02 fund-aware ledger', () {
    late Directory directory;
    late LocalDatabase database;
    late FinancialLedgerStorage ledger;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('mosave_funds_');
      database = LocalDatabase.forTesting(
        '${directory.path}${Platform.pathSeparator}funds.db',
      );
      ledger = FinancialLedgerStorage(database: database);
    });

    tearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    Future<void> income(
      FinancialUnit unit,
      int micros, {
      FinancialFund fund = FinancialFund.unallocated,
      String? id,
    }) async {
      await ledger.addEvent(FinancialEvent.create(
        id: id,
        type: FinancialEventType.income,
        occurredAt: DateTime.now(),
        entries: <LedgerEntry>[
          LedgerEntry(unit: unit, amountMicros: micros, fund: fund),
        ],
      ));
    }

    test('split income and direct expense conserve real assets', () async {
      final savings = LedgerEntry.amountToMicros(345000);
      final spending = LedgerEntry.amountToMicros(540000);
      await ledger.addEvent(FinancialEvent.create(
        type: FinancialEventType.income,
        occurredAt: DateTime.now(),
        entries: <LedgerEntry>[
          LedgerEntry(unit: FinancialUnit.syp, amountMicros: savings,
              fund: FinancialFund.savings),
          LedgerEntry(unit: FinancialUnit.syp, amountMicros: spending,
              fund: FinancialFund.spending),
        ],
      ));
      await ledger.addEvent(FinancialEvent.create(
        type: FinancialEventType.expense,
        occurredAt: DateTime.now(),
        category: 'outing',
        entries: <LedgerEntry>[
          LedgerEntry(unit: FinancialUnit.syp,
              amountMicros: -LedgerEntry.amountToMicros(80000),
              fund: FinancialFund.spending),
        ],
      ));
      final owned = await ledger.loadBalanceMicros();
      final funds = await ledger.loadFundBalancesMicros();
      expect(owned[FinancialUnit.syp], LedgerEntry.amountToMicros(805000));
      expect(funds[FinancialFund.savings]![FinancialUnit.syp], savings);
      expect(funds[FinancialFund.spending]![FinancialUnit.syp],
          LedgerEntry.amountToMicros(460000));
      expect(funds[FinancialFund.unallocated]![FinancialUnit.syp], 0);
      expect(funds.values.fold<int>(0, (sum, byUnit) =>
          sum + byUnit[FinancialUnit.syp]!), owned[FinancialUnit.syp]);
    });

    test('fund transfer is idempotent, fund-only and checks the source', () async {
      await income(FinancialUnit.usd, LedgerEntry.amountToMicros(500));
      Future<void> allocate() => ledger.transferFunds(
        unit: FinancialUnit.usd,
        source: FinancialFund.unallocated,
        destination: FinancialFund.savings,
        amountMicros: LedgerEntry.amountToMicros(500),
        occurredAt: DateTime(2026, 10, 10),
        id: 'allocate-500',
      );
      await allocate();
      await allocate(); // Same stable ID and posting content: no duplicate.
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(500));
      expect(await ledger.loadFundBalanceMicros(
          FinancialFund.savings, FinancialUnit.usd),
          LedgerEntry.amountToMicros(500));
      expect(await ledger.loadFundBalanceMicros(
          FinancialFund.unallocated, FinancialUnit.usd), 0);

      await ledger.addEvent(FinancialEvent.create(
        type: FinancialEventType.expense,
        occurredAt: DateTime.now(),
        category: 'purchase',
        entries: <LedgerEntry>[
          LedgerEntry(unit: FinancialUnit.usd,
              amountMicros: -LedgerEntry.amountToMicros(100),
              fund: FinancialFund.savings),
        ],
      ));
      expect(await ledger.loadFundBalanceMicros(
          FinancialFund.savings, FinancialUnit.usd),
          LedgerEntry.amountToMicros(400));
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(400));
      await expectLater(
        ledger.transferFunds(
          unit: FinancialUnit.usd,
          source: FinancialFund.savings,
          destination: FinancialFund.spending,
          amountMicros: LedgerEntry.amountToMicros(450),
          occurredAt: DateTime.now(),
        ),
        throwsA(isA<InsufficientFundBalanceException>()),
      );
    });

    test('cannot delete income that backs an allocation', () async {
      await income(FinancialUnit.usd,
          LedgerEntry.amountToMicros(200), id: 'receipt');
      await ledger.transferFunds(
        unit: FinancialUnit.usd,
        source: FinancialFund.unallocated,
        destination: FinancialFund.savings,
        amountMicros: LedgerEntry.amountToMicros(200),
        occurredAt: DateTime.now(),
      );
      await expectLater(
        ledger.deleteEvent('receipt'),
        throwsA(isA<InsufficientFundBalanceException>()),
      );
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(200));
    });

    test('cannot classify physical gold as spendable cash', () async {
      await expectLater(
        ledger.addEvent(FinancialEvent.create(
          type: FinancialEventType.manualAdjustment,
          occurredAt: DateTime.now(),
          entries: <LedgerEntry>[
            LedgerEntry(unit: FinancialUnit.goldGram,
                amountMicros: LedgerEntry.amountToMicros(1),
                fund: FinancialFund.spending),
          ],
        )),
        throwsArgumentError,
      );
    });
  });
}
