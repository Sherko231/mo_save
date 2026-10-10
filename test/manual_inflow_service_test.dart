import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/local_database.dart';
import 'package:mo_save/services/manual_inflow_service.dart';
import 'package:mo_save/services/transaction_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MS-05 manual income and prior holdings', () {
    late Directory directory;
    late LocalDatabase database;
    late FinancialLedgerStorage ledger;
    late ManualInflowService manual;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('mo_save_cash_');
      database = LocalDatabase.forTesting(
        '${directory.path}${Platform.pathSeparator}cash.db',
      );
      ledger = FinancialLedgerStorage(database: database);
      manual = ManualInflowService(ledger: ledger);
    });

    tearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    test('gift of 50 USD adds one real income to Savings', () async {
      final gift = await manual.record(
        kind: ManualInflowKind.gift,
        unit: FinancialUnit.usd,
        amountMicros: LedgerEntry.amountToMicros(50),
        occurredAt: DateTime(2026, 10, 10),
        fund: FinancialFund.savings,
        source: 'Friend',
        note: 'Birthday present',
        requestId: 'gift-fifty',
      );

      expect(gift.type, FinancialEventType.income);
      expect(gift.category, 'هدية');
      expect(gift.note, contains('المصدر: Friend'));
      expect(gift.note, contains('التفاصيل: Birthday present'));
      expect(gift.entries.single.fund, FinancialFund.savings);
      expect((await ledger.loadEvents(type: FinancialEventType.income)),
          hasLength(1));
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(50));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(50));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.unallocated, FinancialUnit.usd,
      ), 0);
    });

    test('existing cash opening is not earned income', () async {
      final opening = await manual.record(
        kind: ManualInflowKind.openingBalance,
        unit: FinancialUnit.syp,
        amountMicros: LedgerEntry.amountToMicros(200000),
        occurredAt: DateTime(2026, 10, 9),
        fund: FinancialFund.unallocated,
        source: 'Cash kept before installing Mo Save',
        requestId: 'initial-syp',
      );
      expect(opening.type, FinancialEventType.openingBalance);
      expect(opening.category, 'رصيد افتتاحي سابق');
      expect((await ledger.loadEvents(type: FinancialEventType.income)),
          isEmpty);
      expect((await ledger.loadEvents(type: FinancialEventType.openingBalance)),
          hasLength(1));
      expect((await ledger.loadBalanceMicros())[FinancialUnit.syp],
          LedgerEntry.amountToMicros(200000));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.unallocated, FinancialUnit.syp,
      ), LedgerEntry.amountToMicros(200000));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.syp,
      ), 0);
    });

    test('repeat request is idempotent but different payload is rejected', () async {
      Future<FinancialEvent> record(int micros) => manual.record(
        kind: ManualInflowKind.bonus,
        unit: FinancialUnit.usd,
        amountMicros: micros,
        occurredAt: DateTime(2026, 10, 10),
        fund: FinancialFund.spending,
        requestId: 'same-action',
      );
      final first = await record(LedgerEntry.amountToMicros(25));
      final retry = await record(LedgerEntry.amountToMicros(25));
      expect(retry.id, first.id);
      expect((await ledger.loadEvents(type: FinancialEventType.income)),
          hasLength(1));
      await expectLater(
        record(LedgerEntry.amountToMicros(30)),
        throwsA(isA<Exception>()),
      );
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(25));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.spending, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(25));
    });

    test('untracked item sale requires explicit confirmation', () async {
      Future<FinancialEvent> sale({required bool confirmed}) => manual.record(
        kind: ManualInflowKind.itemSale,
        unit: FinancialUnit.usd,
        amountMicros: LedgerEntry.amountToMicros(30),
        occurredAt: DateTime(2026, 10, 10),
        fund: FinancialFund.unallocated,
        untrackedAssetSaleConfirmed: confirmed,
        requestId: 'untracked-item-sale',
      );
      await expectLater(sale(confirmed: false), throwsArgumentError);
      expect(await ledger.loadEvents(), isEmpty);
      final event = await sale(confirmed: true);
      expect(event.type, FinancialEventType.income);
      expect(event.category, 'بيع غرض غير مسجل كأصل');
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(30));
    });

    test('manual receipts are cash-only, positive and not future-dated', () async {
      Future<FinancialEvent> submit({
        required FinancialUnit unit,
        required int amountMicros,
        required DateTime date,
      }) => manual.record(
        kind: ManualInflowKind.itemSale,
        unit: unit,
        amountMicros: amountMicros,
        occurredAt: date,
        fund: FinancialFund.unallocated,
      );

      await expectLater(
        submit(unit: FinancialUnit.goldGram,
            amountMicros: LedgerEntry.amountToMicros(1),
            date: DateTime(2026, 10, 10)),
        throwsArgumentError,
      );
      await expectLater(
        submit(unit: FinancialUnit.usd, amountMicros: 0,
            date: DateTime(2026, 10, 10)),
        throwsArgumentError,
      );
      await expectLater(
        submit(unit: FinancialUnit.usd,
            amountMicros: LedgerEntry.amountToMicros(20),
            date: DateTime(2099, 1, 1)),
        throwsArgumentError,
      );
      expect(await ledger.loadEvents(), isEmpty);
    });

    test('history correction preserves category and prior snapshot', () async {
      final entry = await manual.record(
        kind: ManualInflowKind.sideWork,
        unit: FinancialUnit.usd,
        amountMicros: LedgerEntry.amountToMicros(40),
        occurredAt: DateTime(2026, 10, 10),
        fund: FinancialFund.savings,
        source: 'Freelance project',
        note: 'Delivered work',
        requestId: 'side-job',
      );
      final history = TransactionHistoryService(
        database: database,
        ledger: ledger,
      );
      await history.correctAmounts(
        eventId: entry.id,
        absoluteAmountsMicros: <int>[LedgerEntry.amountToMicros(45)],
      );
      final corrected = await ledger.loadEvent(entry.id);
      expect(corrected!.type, FinancialEventType.income);
      expect(corrected.category, 'عمل جانبي');
      expect(corrected.note, contains('Freelance project'));
      expect(corrected.entries.single.fund, FinancialFund.savings);
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(45));

      final revisions = await history.loadRevisions(entry.id);
      expect(revisions, hasLength(1));
      expect(revisions.single.snapshot.entries.single.amountMicros,
          LedgerEntry.amountToMicros(40));
      expect(revisions.single.snapshot.note, contains('Freelance project'));

      await history.updateMetadata(
        eventId: entry.id,
        occurredAt: DateTime(2026, 10, 9),
        category: corrected.category,
        note: 'المصدر: Freelance project\nالتفاصيل: Corrected',
      );
      final updated = await ledger.loadEvent(entry.id);
      expect(updated!.occurredAt.toLocal().day, 9);
      expect(updated.note, contains('Corrected'));
      expect(await history.loadRevisions(entry.id), hasLength(2));
    });
  });
}
