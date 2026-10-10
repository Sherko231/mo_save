import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/services/expense_plan_storage.dart';
import 'package:mo_save/services/expense_service.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/fund_transfer_service.dart';
import 'package:mo_save/services/local_database.dart';
import 'package:mo_save/services/transaction_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MS-10 Savings to Spending transfer', () {
    late Directory directory;
    late LocalDatabase database;
    late FinancialLedgerStorage ledger;
    late FundTransferService transfers;
    late ExpenseService expenses;
    late TransactionHistoryService history;
    late DateTime now;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('mosave_transfer_');
      database = LocalDatabase.forTesting(
        '${directory.path}${Platform.pathSeparator}transfer.db',
      );
      ledger = FinancialLedgerStorage(database: database);
      transfers = FundTransferService(ledger: ledger);
      expenses = ExpenseService(
        ledgerStorage: ledger,
        planStorage: ExpensePlanStorage(database: database),
      );
      history = TransactionHistoryService(
        ledger: ledger, database: database,
      );
      now = DateTime.now();
    });

    tearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    Future<void> savingsCash(FinancialUnit unit, int whole) async {
      await ledger.addEvent(FinancialEvent.create(
        type: FinancialEventType.openingBalance,
        occurredAt: now,
        entries: <LedgerEntry>[
          LedgerEntry(
            unit: unit,
            amountMicros: LedgerEntry.amountToMicros(whole),
            fund: FinancialFund.savings,
          ),
        ],
      ));
    }

    Future<void> move100({
      required String id,
      FinancialFund source = FinancialFund.savings,
      FinancialFund destination = FinancialFund.spending,
      int whole = 100,
      FinancialUnit unit = FinancialUnit.usd,
      String? note = 'خصّصت مبلغاً للصرف',
    }) => transfers.move(
      source: source,
      destination: destination,
      unit: unit,
      amountMicros: LedgerEntry.amountToMicros(whole),
      occurredAt: now,
      requestId: id,
      note: note,
    );

    test('500 USD: transfer 100 then pay 100; income stays zero', () async {
      await savingsCash(FinancialUnit.usd, 500);
      await move100(id: 'usd100');
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(500));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(400));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.spending, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(100));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.unallocated, FinancialUnit.usd,
      ), 0);
      expect(await ledger.loadEvents(type: FinancialEventType.income), isEmpty);
      expect(await ledger.loadEvents(type: FinancialEventType.expense), isEmpty);
      final linkedTransfer = (await ledger.loadEvents(
          type: FinancialEventType.fundTransfer)).single;
      expect(linkedTransfer.note, 'خصّصت مبلغاً للصرف');
      expect(linkedTransfer.entries, hasLength(2));
      expect(linkedTransfer.entries.every((entry) => !entry.affectsBalance),
          isTrue);
      expect(linkedTransfer.entries.first.amountMicros,
          -LedgerEntry.amountToMicros(100));
      expect(linkedTransfer.entries.last.amountMicros,
          LedgerEntry.amountToMicros(100));

      await expenses.logExpense(
        amountMicros: LedgerEntry.amountToMicros(100),
        unit: FinancialUnit.usd,
        occurredAt: now,
        category: 'فاتورة',
        sourceFund: FinancialFund.spending,
      );
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(400));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(400));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.spending, FinancialUnit.usd,
      ), 0);
      expect((await ledger.loadEvents(type: FinancialEventType.expense)),
          hasLength(1));
      expect(await ledger.loadEvents(type: FinancialEventType.income), isEmpty);
      final monthExpenses = await expenses.loadMonth(now);
      expect(monthExpenses.actualTotalsMicros[FinancialUnit.usd],
          LedgerEntry.amountToMicros(100));
    });

    test('reverse Spending to Savings is internal and fully balanced', () async {
      await savingsCash(FinancialUnit.usd, 300);
      await move100(id: 'to-spending', whole: 200);
      await move100(id: 'back-to-savings',
          source: FinancialFund.spending,
          destination: FinancialFund.savings,
          whole: 80);
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(300));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(180));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.spending, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(120));
      expect((await ledger.loadEvents(type: FinancialEventType.fundTransfer)),
          hasLength(2));
      expect(await ledger.loadEvents(type: FinancialEventType.expense), isEmpty);
    });

    test('cannot overspend Savings despite assets existing elsewhere',
        () async {
      await savingsCash(FinancialUnit.usd, 100);
      await move100(id: 'all-savings');
      await expectLater(
        move100(id: 'overdraw-savings', whole: 1),
        throwsA(isA<InsufficientFundBalanceException>()),
      );
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(100));
      expect((await ledger.loadEvents(type: FinancialEventType.fundTransfer)),
          hasLength(1));
    });

    test('identical retry after source reaches zero does not duplicate',
        () async {
      await savingsCash(FinancialUnit.usd, 100);
      await move100(id: 'use-full-balance');
      await move100(id: 'use-full-balance');
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.usd,
      ), 0);
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.spending, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(100));
      expect((await ledger.loadEvents(type: FinancialEventType.fundTransfer)),
          hasLength(1));
      await expectLater(
        move100(id: 'use-full-balance', whole: 99),
        throwsStateError,
      );
      await expectLater(
        move100(id: 'use-full-balance', note: 'different'),
        throwsStateError,
      );
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(100));
    });

    test('cash transfers reject invalid direction, currency, date and ID',
        () async {
      await savingsCash(FinancialUnit.usd, 200);
      Future<void> move({
        required FinancialFund from,
        required FinancialFund to,
        required FinancialUnit unit,
        required int amount,
        required DateTime date,
        required String identity,
      }) => transfers.move(
        source: from, destination: to,
        unit: unit, amountMicros: amount,
        occurredAt: date, requestId: identity,
      );
      await expectLater(
        move(from: FinancialFund.savings, to: FinancialFund.savings,
          unit: FinancialUnit.usd, amount: LedgerEntry.amountToMicros(10),
          date: now, identity: 'invalid-same'), throwsArgumentError,
      );
      await expectLater(
        move(from: FinancialFund.unallocated, to: FinancialFund.spending,
          unit: FinancialUnit.usd, amount: LedgerEntry.amountToMicros(10),
          date: now, identity: 'invalid-unallocated'), throwsArgumentError,
      );
      await expectLater(
        move(from: FinancialFund.savings, to: FinancialFund.spending,
          unit: FinancialUnit.goldGram, amount: LedgerEntry.amountToMicros(1),
          date: now, identity: 'invalid-gold'), throwsArgumentError,
      );
      await expectLater(
        move(from: FinancialFund.savings, to: FinancialFund.spending,
          unit: FinancialUnit.usd, amount: 0,
          date: now, identity: 'invalid-zero'), throwsArgumentError,
      );
      await expectLater(
        move(from: FinancialFund.savings, to: FinancialFund.spending,
          unit: FinancialUnit.usd, amount: LedgerEntry.amountToMicros(1),
          date: now.add(const Duration(days: 3)),
          identity: 'invalid-future'), throwsArgumentError,
      );
      await expectLater(
        move(from: FinancialFund.savings, to: FinancialFund.spending,
          unit: FinancialUnit.usd, amount: LedgerEntry.amountToMicros(1),
          date: now, identity: '  '), throwsArgumentError,
      );
      expect(await ledger.loadEvents(type: FinancialEventType.fundTransfer),
          isEmpty);
    });

    test('SYP New and SYP never interchange or infer an FX rate', () async {
      await savingsCash(FinancialUnit.syp, 300000);
      await savingsCash(FinancialUnit.sypNew, 250);
      await transfers.move(
        source: FinancialFund.savings,
        destination: FinancialFund.spending,
        unit: FinancialUnit.sypNew,
        amountMicros: LedgerEntry.amountToMicros(50),
        occurredAt: now,
        requestId: 'new-syp-fifty',
      );
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.spending, FinancialUnit.sypNew,
      ), LedgerEntry.amountToMicros(50));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.sypNew,
      ), LedgerEntry.amountToMicros(200));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.syp,
      ), LedgerEntry.amountToMicros(300000));
      expect((await ledger.loadBalanceMicros())[FinancialUnit.syp],
          LedgerEntry.amountToMicros(300000));
      expect((await ledger.loadBalanceMicros())[FinancialUnit.sypNew],
          LedgerEntry.amountToMicros(250));
      expect(await ledger.loadEvents(
        type: FinancialEventType.currencyConversion,
      ), isEmpty);
    });

    test('transaction audit retains source/destination and safe correction',
        () async {
      await savingsCash(FinancialUnit.usd, 500);
      await move100(id: 'audited-transfer');
      final transfer = (await ledger.loadEvents(
        type: FinancialEventType.fundTransfer)).single;
      final records = await history.loadMonth(now,
          fund: FinancialFund.spending);
      expect(records.any((record) => record.event.id == transfer.id), isTrue);

      await history.correctAmounts(
        eventId: transfer.id,
        absoluteAmountsMicros: <int>[
          LedgerEntry.amountToMicros(80),
          LedgerEntry.amountToMicros(80),
        ],
      );
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(420));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.spending, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(80));
      final revisions = await history.loadRevisions(transfer.id);
      expect(revisions, hasLength(1));
      expect(revisions.single.snapshot.entries[0].fund,
          FinancialFund.savings);
      expect(revisions.single.snapshot.entries[1].fund,
          FinancialFund.spending);
      expect(revisions.single.snapshot.entries[0].amountMicros,
          -LedgerEntry.amountToMicros(100));

      await history.deleteEvent(transfer.id);
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(500));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.spending, FinancialUnit.usd,
      ), 0);
      expect((await history.loadRevisions(transfer.id)), hasLength(2));
      final deleted = await history.loadMonth(now,
        fund: FinancialFund.spending);
      expect(deleted.any((record) => record.isDeleted &&
          record.event.id == transfer.id), isTrue);
    });

    test('spent transfer cannot be removed or shrunk below paid cash',
        () async {
      await savingsCash(FinancialUnit.usd, 500);
      await move100(id: 'used-transfer');
      final transfer = (await ledger.loadEvents(
        type: FinancialEventType.fundTransfer)).single;
      await expenses.logExpense(
        amountMicros: LedgerEntry.amountToMicros(90),
        unit: FinancialUnit.usd,
        occurredAt: now,
        category: 'فاتورة',
        sourceFund: FinancialFund.spending,
      );
      await expectLater(
        history.deleteEvent(transfer.id),
        throwsA(isA<InsufficientFundBalanceException>()),
      );
      await expectLater(
        history.correctAmounts(
          eventId: transfer.id,
          absoluteAmountsMicros: <int>[
            LedgerEntry.amountToMicros(80),
            LedgerEntry.amountToMicros(80),
          ],
        ),
        throwsA(isA<InsufficientFundBalanceException>()),
      );
      expect((await history.loadRevisions(transfer.id)), isEmpty);
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.spending, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(10));
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(410));
    });
  });
}
