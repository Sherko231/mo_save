import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/models/recurring_expense_item.dart';
import 'package:mo_save/services/expense_plan_storage.dart';
import 'package:mo_save/services/expense_service.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/local_database.dart';
import 'package:mo_save/services/spending_analytics_service.dart';
import 'package:mo_save/services/transaction_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MS-11 monthly categorized actual spending', () {
    late Directory directory;
    late LocalDatabase database;
    late FinancialLedgerStorage ledger;
    late ExpensePlanStorage plans;
    late ExpenseService expenses;
    late SpendingAnalyticsService analytics;
    late TransactionHistoryService history;
    late DateTime month;
    late DateTime prior;
    late RecurringExpenseItem bill;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('mosave_analytics_');
      database = LocalDatabase.forTesting(
        '${directory.path}${Platform.pathSeparator}analytics.db',
      );
      ledger = FinancialLedgerStorage(database: database);
      plans = ExpensePlanStorage(database: database);
      expenses = ExpenseService(planStorage: plans, ledgerStorage: ledger);
      analytics = SpendingAnalyticsService(expenses: expenses);
      history = TransactionHistoryService(database: database, ledger: ledger);
      final now = DateTime.now();
      month = DateTime(now.year, now.month);
      prior = DateTime(now.year, now.month - 1);
      await (await database.database).insert('app_metadata',
        <String, Object?>{
          'key': 'expense_plan_client_defaults_seeded_v1', 'value': '1',
        });
      bill = RecurringExpenseItem.create(
        name: 'إنترنت',
        unit: FinancialUnit.syp,
        amountMicros: LedgerEntry.amountToMicros(120000),
        sortOrder: 0,
      );
      await plans.addItem(bill, effectiveFromMonth: month);
      await ledger.addEvent(FinancialEvent.create(
        type: FinancialEventType.income,
        occurredAt: DateTime.now(),
        entries: <LedgerEntry>[
          LedgerEntry(unit: FinancialUnit.syp,
            amountMicros: LedgerEntry.amountToMicros(900000),
            fund: FinancialFund.spending),
          LedgerEntry(unit: FinancialUnit.usd,
            amountMicros: LedgerEntry.amountToMicros(1000),
            fund: FinancialFund.savings),
          LedgerEntry(unit: FinancialUnit.usd,
            amountMicros: LedgerEntry.amountToMicros(200),
            fund: FinancialFund.spending),
          LedgerEntry(unit: FinancialUnit.sypNew,
            amountMicros: LedgerEntry.amountToMicros(300),
            fund: FinancialFund.spending),
        ],
      ));
      await ledger.addEvent(FinancialEvent.create(
        type: FinancialEventType.openingBalance,
        occurredAt: DateTime.now(),
        entries: <LedgerEntry>[
          LedgerEntry(unit: FinancialUnit.syp,
            amountMicros: LedgerEntry.amountToMicros(50000),
            fund: FinancialFund.unallocated),
        ],
      ));
    });

    tearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    Future<void> expense(int amount, FinancialUnit unit, String category, {
      FinancialFund fund = FinancialFund.spending,
      DateTime? at,
      String? note,
      String? plannedId,
    }) => expenses.logExpense(
      amountMicros: LedgerEntry.amountToMicros(amount),
      unit: unit,
      occurredAt: at ?? DateTime.now(),
      category: category,
      sourceFund: fund,
      note: note,
      plannedItemId: plannedId,
    );

    test('100 USD from Savings counts once, transfer/opening never count',
        () async {
      await ledger.transferFunds(
        unit: FinancialUnit.usd,
        source: FinancialFund.savings,
        destination: FinancialFund.spending,
        amountMicros: LedgerEntry.amountToMicros(50),
        occurredAt: DateTime.now(),
        id: 'analytics-move',
      );
      await expense(100, FinancialUnit.usd, 'صحة',
        fund: FinancialFund.savings, note: 'علاج ضروري');
      final result = await analytics.loadMonth(month);
      final snapshot = await expenses.loadMonth(month);
      expect(result.actualMicros(FinancialUnit.usd),
          LedgerEntry.amountToMicros(100));
      expect(result.actualMicros(FinancialUnit.usd,
        fund: FinancialFund.savings), LedgerEntry.amountToMicros(100));
      expect(result.actualMicros(FinancialUnit.usd,
        fund: FinancialFund.spending), 0);
      expect(result.actualMicros(FinancialUnit.syp), 0);
      expect(result.categories(FinancialUnit.usd).single.category, 'صحة');
      expect(result.categories(FinancialUnit.usd).single.lines.single.event.note,
        'علاج ضروري');
      expect(result.allActualTotals(), snapshot.actualTotalsMicros);
      expect((await ledger.loadEvents(type: FinancialEventType.expense)),
        hasLength(1));
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
        LedgerEntry.amountToMicros(1100));
      expect((await ledger.loadEvents(type: FinancialEventType.fundTransfer)),
        hasLength(1));
    });

    test('categories, recurring plan and one-offs reconcile with real entries',
        () async {
      await expense(80000, FinancialUnit.syp, 'نزهة', note: 'خروج');
      await expense(20000, FinancialUnit.syp, 'طعام');
      await expense(120000, FinancialUnit.syp, 'إنترنت',
        plannedId: bill.id, note: 'فاتورة الشهر');
      final result = await analytics.loadMonth(month);
      expect(result.actualMicros(FinancialUnit.syp),
        LedgerEntry.amountToMicros(220000));
      expect(result.actualMicros(FinancialUnit.syp, recurring: true),
        LedgerEntry.amountToMicros(120000));
      expect(result.actualMicros(FinancialUnit.syp, recurring: false),
        LedgerEntry.amountToMicros(100000));
      expect(result.planMicros(FinancialUnit.syp),
        LedgerEntry.amountToMicros(120000));
      expect(result.budgetDifferenceMicros(FinancialUnit.syp),
        -LedgerEntry.amountToMicros(100000));
      final groups = result.categories(FinancialUnit.syp);
      expect(groups.map((g) => g.category),
        <String>['إنترنت', 'نزهة', 'طعام']);
      expect(groups.fold<int>(0, (s,g) => s+g.amountMicros),
        result.actualMicros(FinancialUnit.syp));
      expect(result.categories(FinancialUnit.syp,
        recurring: true).single.lines.single.event.recurrenceKey,
        'expense-plan:${bill.id}:${month.year * 100 + month.month}');
      expect(result.allActualTotals(),
        (await expenses.loadMonth(month)).actualTotalsMicros);
      expect((await ledger.loadBalanceMicros())[FinancialUnit.syp],
        LedgerEntry.amountToMicros(730000));
    });

    test('unlinked same-name expense is NOT misclassified as plan payment',
        () async {
      await expense(45000, FinancialUnit.syp, 'إنترنت',
        note: 'تكلفة إضافية');
      final result = await analytics.loadMonth(month);
      expect(result.actualMicros(FinancialUnit.syp, recurring: true), 0);
      expect(result.actualMicros(FinancialUnit.syp, recurring: false),
        LedgerEntry.amountToMicros(45000));
      expect((await expenses.loadMonth(month)).paidPlanItemIds, isEmpty);
      expect(result.planMicros(FinancialUnit.syp),
        LedgerEntry.amountToMicros(120000));
    });

    test('previous-month comparisons use the same unit/source/kind filter',
        () async {
      await expense(50000, FinancialUnit.syp, 'نزهة',
        at: DateTime(prior.year, prior.month, 15));
      await expense(80000, FinancialUnit.syp, 'نزهة');
      await expense(100, FinancialUnit.usd, 'فواتير',
        fund: FinancialFund.savings, note: 'اشتراك');
      final result = await analytics.loadMonth(month);
      expect(result.previousMonth, prior);
      expect(result.actualMicros(FinancialUnit.syp),
        LedgerEntry.amountToMicros(80000));
      expect(result.previousActualMicros(FinancialUnit.syp),
        LedgerEntry.amountToMicros(50000));
      expect(result.previousActualMicros(FinancialUnit.usd), 0);
      expect(result.previousActualMicros(FinancialUnit.syp,
        fund: FinancialFund.savings), 0);
      expect(result.previousActualMicros(FinancialUnit.syp,
        recurring: true), 0);
      expect(result.actualMicros(FinancialUnit.usd),
        LedgerEntry.amountToMicros(100));
    });

    test('corrections and deletion recompute report with archived revisions',
        () async {
      await expense(80000, FinancialUnit.syp, 'نزهة', note: 'خروج');
      final payment = (await ledger.loadEvents(
        type: FinancialEventType.expense)).single;
      await history.correctAmounts(
        eventId: payment.id,
        absoluteAmountsMicros: <int>[LedgerEntry.amountToMicros(60000)],
      );
      final corrected = await analytics.loadMonth(month);
      expect(corrected.actualMicros(FinancialUnit.syp),
        LedgerEntry.amountToMicros(60000));
      expect(corrected.categories(FinancialUnit.syp).single.lines.single.event.id,
        payment.id);
      final revisions = await history.loadRevisions(payment.id);
      expect(revisions, hasLength(1));
      expect(revisions.single.snapshot.note, 'خروج');
      await history.deleteEvent(payment.id);
      final deleted = await analytics.loadMonth(month);
      expect(deleted.actualMicros(FinancialUnit.syp), 0);
      expect(deleted.categories(FinancialUnit.syp), isEmpty);
      expect((await history.loadRevisions(payment.id)), hasLength(2));
    });

    test('different currencies never combine, and Unallocated is explicit',
        () async {
      await expense(70, FinancialUnit.sypNew, 'منزل');
      await expense(10000, FinancialUnit.syp, 'منزل');
      await expense(3000, FinancialUnit.syp, 'مواصلات',
        fund: FinancialFund.unallocated);
      final report = await analytics.loadMonth(month);
      expect(report.actualMicros(FinancialUnit.sypNew),
        LedgerEntry.amountToMicros(70));
      expect(report.actualMicros(FinancialUnit.syp),
        LedgerEntry.amountToMicros(13000));
      expect(report.actualMicros(FinancialUnit.syp,
        fund: FinancialFund.unallocated), LedgerEntry.amountToMicros(3000));
      expect(report.actualMicros(FinancialUnit.usd), 0);
      expect(report.allActualTotals(),
        (await expenses.loadMonth(month)).actualTotalsMicros);
    });

    test('scheduled planned change never rewrites historical analytics',
        () async {
      await expense(60000, FinancialUnit.syp, 'إنترنت',
        plannedId: bill.id);
      final before = await analytics.loadMonth(month);
      await plans.updateItem(bill.copyWith(
        amountMicros: LedgerEntry.amountToMicros(200000),
      ), effectiveFromMonth: DateTime(month.year, month.month + 1));
      final after = await analytics.loadMonth(month);
      final next = await analytics.loadMonth(DateTime(
        month.year, month.month + 1,
      ));
      expect(before.actualMicros(FinancialUnit.syp),
        after.actualMicros(FinancialUnit.syp));
      expect(after.planMicros(FinancialUnit.syp),
        LedgerEntry.amountToMicros(120000));
      expect(next.planMicros(FinancialUnit.syp),
        LedgerEntry.amountToMicros(200000));
      expect(next.actualMicros(FinancialUnit.syp), 0);
    });
  });
}
