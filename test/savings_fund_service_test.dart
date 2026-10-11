import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/models/financial_settings.dart';
import 'package:mo_save/services/expense_plan_storage.dart';
import 'package:mo_save/services/expense_service.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/financial_settings_storage.dart';
import 'package:mo_save/services/local_database.dart';
import 'package:mo_save/services/savings_fund_service.dart';
import 'package:mo_save/services/transaction_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('MS-12 real Savings fund balances', () {
    late Directory directory;
    late LocalDatabase database;
    late FinancialLedgerStorage ledger;
    late FinancialSettingsStorage settings;
    late SavingsFundService savings;
    late ExpenseService expenses;
    late TransactionHistoryService history;
    late DateTime now;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('mosave_savings_');
      database = LocalDatabase.forTesting(
        '${directory.path}${Platform.pathSeparator}savings.db',
      );
      ledger = FinancialLedgerStorage(database: database);
      settings = FinancialSettingsStorage(database: database);
      savings = SavingsFundService(ledger: ledger, settings: settings);
      expenses = ExpenseService(
        ledgerStorage: ledger,
        planStorage: ExpensePlanStorage(database: database),
      );
      history = TransactionHistoryService(database: database, ledger: ledger);
      now = DateTime.now();
      await settings.saveSettings(FinancialSettings.clientDefaults);
      await (await database.database).insert('app_metadata', <String, Object?>{
        'key': 'expense_plan_client_defaults_seeded_v1',
        'value': '1',
      });
    });

    tearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    Future<void> post(
      FinancialEventType type,
      List<LedgerEntry> entries, {
      DateTime? at,
      String? challengeId,
    }) => ledger.addEvent(FinancialEvent.create(
      type: type,
      occurredAt: at ?? now,
      entries: entries,
      relatedChallengeId: challengeId,
    ));

    LedgerEntry amount(
      FinancialUnit unit,
      num value,
      FinancialFund fund, {
      bool affectsBalance = true,
    }) => LedgerEntry(
      unit: unit,
      amountMicros: LedgerEntry.amountToMicros(value),
      fund: fund,
      affectsBalance: affectsBalance,
    );

    Future<void> setReferences(double sypRate, double goldRate) =>
      settings.saveSettings(FinancialSettings(
        weeklySypIncome: 885000,
        weeklyPayday: DateTime.thursday,
        monthlyUsdIncome: 300,
        monthlyPayday: 1,
        referenceSypPerUsd: sypRate,
        goldUsdPerGram: goldRate,
        weeklyExpensesAllocation: 540000,
        weeklySavingsAllocation: 345000,
      ));

    test('only assigned Savings counts, transfers and direct debits reduce it',
      () async {
      await post(FinancialEventType.income, <LedgerEntry>[
        amount(FinancialUnit.syp, 345000, FinancialFund.savings),
        amount(FinancialUnit.syp, 540000, FinancialFund.spending),
        amount(FinancialUnit.usd, 300, FinancialFund.savings),
      ]);
      await post(FinancialEventType.openingBalance, <LedgerEntry>[
        amount(FinancialUnit.usd, 50, FinancialFund.unallocated),
      ]);
      // A legacy challenge entry is a non-balance tracking event, not cash.
      // No relatedChallengeId is needed in this isolated ledger fixture.
      await post(FinancialEventType.savingContribution, <LedgerEntry>[
        amount(FinancialUnit.usd, 800,
          FinancialFund.savings, affectsBalance: false),
      ]);
      await ledger.transferFunds(
        unit: FinancialUnit.usd,
        source: FinancialFund.savings,
        destination: FinancialFund.spending,
        amountMicros: LedgerEntry.amountToMicros(100),
        occurredAt: now,
      );
      await expenses.logExpense(
        amountMicros: LedgerEntry.amountToMicros(20),
        unit: FinancialUnit.usd,
        occurredAt: now,
        category: 'صحة',
        note: 'احتجت مبلغ من الادخار',
        sourceFund: FinancialFund.savings,
      );
      await expenses.logExpense(
        amountMicros: LedgerEntry.amountToMicros(80),
        unit: FinancialUnit.syp,
        occurredAt: now,
        category: 'نزهة',
        sourceFund: FinancialFund.spending,
      );
      final view = await savings.loadCurrent();
      expect(view.reconcilesWithOwned, isTrue);
      expect(view.saved(FinancialUnit.syp),
        LedgerEntry.amountToMicros(345000));
      expect(view.saved(FinancialUnit.usd),
        LedgerEntry.amountToMicros(180));
      expect(view.fundAmount(FinancialFund.spending, FinancialUnit.usd),
        LedgerEntry.amountToMicros(100));
      expect(view.fundAmount(FinancialFund.unallocated, FinancialUnit.usd),
        LedgerEntry.amountToMicros(50));
      expect(view.totalOwned(FinancialUnit.usd),
        LedgerEntry.amountToMicros(330));
      expect(view.thisMonth.received(FinancialUnit.usd),
        LedgerEntry.amountToMicros(300));
      expect(view.thisMonth.transferredOut(FinancialUnit.usd),
        LedgerEntry.amountToMicros(100));
      expect(view.thisMonth.paidFromSavings(FinancialUnit.usd),
        LedgerEntry.amountToMicros(20));
      expect(view.thisMonth.netFunding(FinancialUnit.usd),
        LedgerEntry.amountToMicros(180));
      expect(view.thisMonth.opening(FinancialUnit.usd), 0);
      expect(view.thisMonth.other(FinancialUnit.usd), 0);
      expect((await ledger.loadEvents(type: FinancialEventType.income)),
        hasLength(1));
    });

    test('incoming internal transfer increases Savings, not earned income',
      () async {
      await post(FinancialEventType.openingBalance, <LedgerEntry>[
        amount(FinancialUnit.usd, 250, FinancialFund.spending),
      ]);
      await ledger.transferFunds(
        unit: FinancialUnit.usd,
        source: FinancialFund.spending,
        destination: FinancialFund.savings,
        amountMicros: LedgerEntry.amountToMicros(80),
        occurredAt: now,
      );
      final view = await savings.loadCurrent();
      expect(view.saved(FinancialUnit.usd), LedgerEntry.amountToMicros(80));
      expect(view.thisMonth.received(FinancialUnit.usd), 0);
      expect(view.thisMonth.transferredIn(FinancialUnit.usd),
        LedgerEntry.amountToMicros(80));
      expect(view.thisMonth.added(FinancialUnit.usd),
        LedgerEntry.amountToMicros(80));
      expect(view.totalOwned(FinancialUnit.usd),
        LedgerEntry.amountToMicros(250));
      expect(await ledger.loadEvents(type: FinancialEventType.income), isEmpty);
    });

    test('reference price changes estimate only, not principal or gold grams',
      () async {
      await post(FinancialEventType.openingBalance, <LedgerEntry>[
        amount(FinancialUnit.usd, 300, FinancialFund.savings),
        amount(FinancialUnit.syp, 1500000, FinancialFund.savings),
      ]);
      await post(FinancialEventType.goldPurchase, <LedgerEntry>[
        amount(FinancialUnit.usd, -200, FinancialFund.savings),
        amount(FinancialUnit.goldGram, 2, FinancialFund.savings),
      ]);
      await setReferences(15000, 100);
      final first = await savings.loadCurrent();
      expect(first.saved(FinancialUnit.usd), LedgerEntry.amountToMicros(100));
      expect(first.saved(FinancialUnit.goldGram), LedgerEntry.amountToMicros(2));
      expect(first.valuation.estimatedTotalUsd, 400);
      expect(first.thisMonth.received(FinancialUnit.goldGram), 0);
      expect(first.thisMonth.converted(FinancialUnit.goldGram),
        LedgerEntry.amountToMicros(2));
      expect(first.thisMonth.converted(FinancialUnit.usd),
        -LedgerEntry.amountToMicros(200));
      expect(first.thisMonth.netFunding(FinancialUnit.usd), 0);
      await setReferences(30000, 150);
      final updated = await savings.loadCurrent();
      expect(updated.valuation.estimatedTotalUsd, 450);
      expect(updated.saved(FinancialUnit.usd), first.saved(FinancialUnit.usd));
      expect(updated.saved(FinancialUnit.syp), first.saved(FinancialUnit.syp));
      expect(updated.saved(FinancialUnit.goldGram),
        first.saved(FinancialUnit.goldGram));
      expect((await ledger.loadEvents(type: FinancialEventType.goldPurchase)),
        hasLength(1));
    });

    test('absent rate or new SYP asset never becomes invented valued Savings',
      () async {
      await post(FinancialEventType.openingBalance, <LedgerEntry>[
        amount(FinancialUnit.syp, 500000, FinancialFund.savings),
        amount(FinancialUnit.sypNew, 100, FinancialFund.savings),
      ]);
      final withoutRates = await savings.loadCurrent();
      expect(withoutRates.valuation.estimatedTotalUsd, isNull);
      expect(withoutRates.valuation.hasUnvaluedSyp, isTrue);
      expect(withoutRates.valuation.hasUnvaluedSypNew, isTrue);
      await setReferences(15000, 100);
      final afterRates = await savings.loadCurrent();
      expect(afterRates.valuation.estimatedTotalUsd, isNull);
      expect(afterRates.valuation.hasUnvaluedSypNew, isTrue);
      expect(afterRates.saved(FinancialUnit.sypNew),
        LedgerEntry.amountToMicros(100));
      expect(afterRates.reconcilesWithOwned, isTrue);
    });

    test('six real calendar months show categorized movements without forecast',
      () async {
      final previous = DateTime(now.year, now.month - 1, 15, 12);
      final earlier = DateTime(now.year, now.month - 2, 15, 12);
      await post(FinancialEventType.openingBalance, <LedgerEntry>[
        amount(FinancialUnit.usd, 100, FinancialFund.savings),
      ], at: earlier);
      await post(FinancialEventType.income, <LedgerEntry>[
        amount(FinancialUnit.usd, 250, FinancialFund.savings),
      ], at: previous);
      await ledger.transferFunds(
        unit: FinancialUnit.usd,
        source: FinancialFund.savings,
        destination: FinancialFund.spending,
        amountMicros: LedgerEntry.amountToMicros(50),
        occurredAt: now,
      );
      final result = await savings.loadCurrent();
      expect(result.trend, hasLength(6));
      expect(result.trend.last.month,
        DateTime(now.year, now.month));
      expect(result.trend[3].opening(FinancialUnit.usd),
        LedgerEntry.amountToMicros(100));
      expect(result.trend[4].received(FinancialUnit.usd),
        LedgerEntry.amountToMicros(250));
      expect(result.trend.last.transferredOut(FinancialUnit.usd),
        LedgerEntry.amountToMicros(50));
      expect(result.trend.last.netFundMovement(FinancialUnit.usd),
        -LedgerEntry.amountToMicros(50));
      expect(result.saved(FinancialUnit.usd),
        LedgerEntry.amountToMicros(300));
      expect(result.trend.fold<int>(0, (total, month) =>
          total + month.netFundMovement(FinancialUnit.usd)),
        result.saved(FinancialUnit.usd));
    });

    test('audited correction and deletion update live Savings, not old revision',
      () async {
      await post(FinancialEventType.income, <LedgerEntry>[
        amount(FinancialUnit.usd, 300, FinancialFund.savings),
      ]);
      await expenses.logExpense(
        amountMicros: LedgerEntry.amountToMicros(100),
        unit: FinancialUnit.usd,
        occurredAt: now,
        category: 'علاج',
        note: 'طارئ',
        sourceFund: FinancialFund.savings,
      );
      final old = (await ledger.loadEvents(
        type: FinancialEventType.expense)).single;
      await history.correctAmounts(
        eventId: old.id,
        absoluteAmountsMicros: <int>[LedgerEntry.amountToMicros(60)],
      );
      final corrected = await savings.loadCurrent();
      expect(corrected.saved(FinancialUnit.usd),
        LedgerEntry.amountToMicros(240));
      expect(corrected.thisMonth.paidFromSavings(FinancialUnit.usd),
        LedgerEntry.amountToMicros(60));
      final revisions = await history.loadRevisions(old.id);
      expect(revisions.single.snapshot.entries.single.amountMicros,
        -LedgerEntry.amountToMicros(100));
      await history.deleteEvent(old.id);
      final deleted = await savings.loadCurrent();
      expect(deleted.saved(FinancialUnit.usd),
        LedgerEntry.amountToMicros(300));
      expect(deleted.thisMonth.paidFromSavings(FinancialUnit.usd), 0);
      expect(deleted.reconcilesWithOwned, isTrue);
      expect((await history.loadRevisions(old.id)), hasLength(2));
    });
  });
}
