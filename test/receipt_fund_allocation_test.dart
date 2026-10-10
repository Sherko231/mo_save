import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/expected_income.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/models/financial_settings.dart';
import 'package:mo_save/models/receipt_fund_allocation.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/financial_settings_storage.dart';
import 'package:mo_save/services/local_database.dart';
import 'package:mo_save/services/manual_inflow_service.dart';
import 'package:mo_save/services/recurring_income_service.dart';
import 'package:mo_save/services/transaction_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MS-06: real receipt allocation', () {
    late Directory dir;
    late LocalDatabase database;
    late FinancialLedgerStorage ledger;
    late RecurringIncomeService recurring;
    late ManualInflowService manual;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('mosave_receipt_split_');
      database = LocalDatabase.forTesting(
        '${dir.path}${Platform.pathSeparator}receipt_split.db',
      );
      ledger = FinancialLedgerStorage(database: database);
      recurring = RecurringIncomeService(
        ledgerStorage: ledger,
        database: database,
        settingsStorage: FinancialSettingsStorage(database: database),
      );
      manual = ManualInflowService(ledger: ledger);
      await FinancialSettingsStorage(database: database)
          .saveSettings(FinancialSettings.clientDefaults);
    });

    tearDown(() async {
      await database.close();
      await dir.delete(recursive: true);
    });

    Future<ExpectedIncome> payday(RecurringIncomeKind kind) async {
      final month = await recurring.loadMonth(DateTime(2026, 10));
      final day = kind == RecurringIncomeKind.weeklySyp ? 8 : 1;
      return month.firstWhere((item) =>
          item.kind == kind && item.scheduledDate.day == day);
    }

    test('885000 SYP is one receipt split 540000/345000 and survives reload',
        () async {
      final occurrence = await payday(RecurringIncomeKind.weeklySyp);
      final event = await recurring.confirmReceived(
        occurrence: occurrence,
        amountMicros: LedgerEntry.amountToMicros(885000),
        spendingMicros: LedgerEntry.amountToMicros(540000),
        savingsMicros: LedgerEntry.amountToMicros(345000),
      );
      expect(event.entries, hasLength(2));
      expect((await ledger.loadEvents(type: FinancialEventType.income)),
          hasLength(1));
      expect((await ledger.loadEvents(type: FinancialEventType.expense)),
          isEmpty);
      expect((await ledger.loadBalanceMicros())[FinancialUnit.syp],
          LedgerEntry.amountToMicros(885000));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.spending, FinancialUnit.syp,
      ), LedgerEntry.amountToMicros(540000));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.syp,
      ), LedgerEntry.amountToMicros(345000));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.unallocated, FinancialUnit.syp,
      ), 0);

      // The source of truth is SQLite entries, not transient in-memory state.
      final reloaded = FinancialLedgerStorage(database: database);
      final posted = await reloaded.loadEvent(event.id);
      expect(posted!.entries, hasLength(2));
      expect(posted.entries[0].fund, FinancialFund.savings);
      expect(posted.entries[1].fund, FinancialFund.spending);
      expect(await reloaded.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.syp,
      ), LedgerEntry.amountToMicros(345000));
      await expectLater(
        recurring.confirmReceived(
          occurrence: occurrence,
          amountMicros: LedgerEntry.amountToMicros(885000),
          spendingMicros: LedgerEntry.amountToMicros(540000),
          savingsMicros: LedgerEntry.amountToMicros(345000),
        ),
        throwsStateError,
      );
      expect((await ledger.loadEvents(type: FinancialEventType.income)),
          hasLength(1));
    });

    test('300 USD can be allocated freely with a genuine Unallocated remainder',
        () async {
      final occurrence = await payday(RecurringIncomeKind.monthlyUsd);
      await recurring.confirmReceived(
        occurrence: occurrence,
        amountMicros: LedgerEntry.amountToMicros(300),
        savingsMicros: LedgerEntry.amountToMicros(200),
        spendingMicros: LedgerEntry.amountToMicros(75),
      );
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(300));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(200));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.spending, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(75));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.unallocated, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(25));
    });

    test('historic spending is reserved before allocating current money',
        () async {
      final occurrence = await payday(RecurringIncomeKind.weeklySyp);
      final event = await recurring.confirmReceived(
        occurrence: occurrence,
        amountMicros: LedgerEntry.amountToMicros(885000),
        alreadySpentMicros: LedgerEntry.amountToMicros(80000),
        spendingMicros: LedgerEntry.amountToMicros(460000),
        savingsMicros: LedgerEntry.amountToMicros(345000),
        spentCategory: 'outing',
        spentAt: DateTime(2026, 10, 8),
      );
      final expenses = await ledger.loadEvents(type: FinancialEventType.expense);
      expect(expenses, hasLength(1));
      expect(expenses.single.sourceEventId, event.id);
      expect(expenses.single.entries.single.fund,
          FinancialFund.unallocated);
      expect(event.entries, hasLength(3));
      expect((await ledger.loadBalanceMicros())[FinancialUnit.syp],
          LedgerEntry.amountToMicros(805000));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.syp,
      ), LedgerEntry.amountToMicros(345000));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.spending, FinancialUnit.syp,
      ), LedgerEntry.amountToMicros(460000));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.unallocated, FinancialUnit.syp,
      ), 0);
    });

    test('over-allocation fails before any event can be posted', () async {
      final occurrence = await payday(RecurringIncomeKind.weeklySyp);
      await expectLater(
        recurring.confirmReceived(
          occurrence: occurrence,
          amountMicros: LedgerEntry.amountToMicros(885000),
          alreadySpentMicros: LedgerEntry.amountToMicros(80000),
          spendingMicros: LedgerEntry.amountToMicros(540000),
          savingsMicros: LedgerEntry.amountToMicros(345000),
        ),
        throwsArgumentError,
      );
      expect(await ledger.loadEvents(), isEmpty);
      expect((await ledger.loadBalanceMicros())[FinancialUnit.syp], 0);
    });

    test('audited split correction preserves source and exact total',
        () async {
      final cash = await manual.record(
        kind: ManualInflowKind.gift,
        unit: FinancialUnit.usd,
        amountMicros: LedgerEntry.amountToMicros(50),
        occurredAt: DateTime(2026, 10, 10),
        fund: FinancialFund.unallocated,
        savingsMicros: LedgerEntry.amountToMicros(30),
        spendingMicros: LedgerEntry.amountToMicros(15),
        source: 'Friend',
        requestId: 'correct-split',
      );
      final audit = TransactionHistoryService(database: database, ledger: ledger);
      await audit.correctAmounts(
        eventId: cash.id,
        absoluteAmountsMicros: <int>[
          LedgerEntry.amountToMicros(25),
          LedgerEntry.amountToMicros(20),
          LedgerEntry.amountToMicros(5),
        ],
      );
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(50));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(25));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.spending, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(20));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.unallocated, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(5));
      final revisions = await audit.loadRevisions(cash.id);
      expect(revisions, hasLength(1));
      expect(revisions.single.snapshot.entries[0].fund, FinancialFund.savings);
      expect(revisions.single.snapshot.entries[0].amountMicros,
          LedgerEntry.amountToMicros(30));
      expect((await ledger.loadEvent(cash.id))!.note,
          contains('Friend'));
    });

    test('manual gift split creates one income and retry cannot duplicate it',
        () async {
      Future<FinancialEvent> record({int savings = 30}) => manual.record(
        kind: ManualInflowKind.gift,
        unit: FinancialUnit.usd,
        amountMicros: LedgerEntry.amountToMicros(50),
        occurredAt: DateTime(2026, 10, 10),
        fund: FinancialFund.unallocated,
        savingsMicros: LedgerEntry.amountToMicros(savings),
        spendingMicros: LedgerEntry.amountToMicros(15),
        requestId: 'one-gift-split',
      );
      final first = await record();
      final retry = await record();
      expect(first.id, retry.id);
      expect((await ledger.loadEvents(type: FinancialEventType.income)),
          hasLength(1));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(30));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.spending, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(15));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.unallocated, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(5));
      await expectLater(record(savings: 29), throwsA(isA<Exception>()));
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(50));
    });
  });

  group('MS-06: allocation model', () {
    test('rejects negative/over-committed funds', () {
      expect(
        () => ReceiptFundAllocation(
          receivedMicros: 100,
          savingsMicros: 101,
          spendingMicros: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => ReceiptFundAllocation(
          receivedMicros: 100,
          savingsMicros: 60,
          spendingMicros: 41,
        ),
        throwsArgumentError,
      );
      expect(
        () => ReceiptFundAllocation(
          receivedMicros: 100,
          savingsMicros: 40,
          spendingMicros: 30,
          alreadySpentMicros: 31,
        ),
        throwsArgumentError,
      );
      expect(
        () => ReceiptFundAllocation(
          receivedMicros: 100,
          savingsMicros: -1,
          spendingMicros: 0,
        ),
        throwsArgumentError,
      );
    });
    test('zero allocation is valid and remains explicitly unallocated', () {
      final split = ReceiptFundAllocation(
        receivedMicros: LedgerEntry.amountToMicros(50),
        savingsMicros: 0,
        spendingMicros: 0,
      );
      expect(split.incomingUnallocatedMicros,
          LedgerEntry.amountToMicros(50));
      final entries = split.receiptEntries(FinancialUnit.usd);
      expect(entries, hasLength(1));
      expect(entries.single.fund, FinancialFund.unallocated);
    });
  });
}
