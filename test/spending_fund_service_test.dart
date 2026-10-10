import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/models/recurring_expense_item.dart';
import 'package:mo_save/services/expense_plan_storage.dart';
import 'package:mo_save/services/expense_service.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/local_database.dart';
import 'package:mo_save/services/spending_fund_service.dart';
import 'package:mo_save/services/transaction_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MS-07 Spending fund dashboard', () {
    late Directory directory;
    late LocalDatabase database;
    late FinancialLedgerStorage ledger;
    late ExpensePlanStorage plans;
    late ExpenseService expenses;
    late SpendingFundService spending;

    final today = DateTime.now();
    final currentMonth = DateTime(today.year, today.month);

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('mosave_spending_');
      database = LocalDatabase.forTesting(
        '${directory.path}${Platform.pathSeparator}spending.db',
      );
      ledger = FinancialLedgerStorage(database: database);
      plans = ExpensePlanStorage(database: database);
      expenses = ExpenseService(planStorage: plans, ledgerStorage: ledger);
      spending = SpendingFundService(ledger: ledger, expenses: expenses);

      // Isolate the fixture from first-run default monthly plan seeding.
      final db = await database.database;
      await db.insert('app_metadata', <String, Object?>{
        'key': 'expense_plan_client_defaults_seeded_v1',
        'value': '1',
      });
      await ledger.addEvent(FinancialEvent.create(
        type: FinancialEventType.income,
        occurredAt: today,
        entries: <LedgerEntry>[
          LedgerEntry(
            unit: FinancialUnit.syp,
            amountMicros: LedgerEntry.amountToMicros(885000),
            fund: FinancialFund.spending,
          ),
          LedgerEntry(
            unit: FinancialUnit.syp,
            amountMicros: LedgerEntry.amountToMicros(40000),
            fund: FinancialFund.unallocated,
          ),
        ],
      ));
      await ledger.addEvent(FinancialEvent.create(
        type: FinancialEventType.openingBalance,
        occurredAt: today,
        entries: <LedgerEntry>[
          LedgerEntry(
            unit: FinancialUnit.usd,
            amountMicros: LedgerEntry.amountToMicros(500),
            fund: FinancialFund.savings,
          ),
        ],
      ));
    });

    tearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    test('no projected bills are deducted from real spendable cash', () async {
      await plans.addItem(RecurringExpenseItem.create(
        name: 'الإنترنت',
        unit: FinancialUnit.syp,
        amountMicros: LedgerEntry.amountToMicros(120000),
        sortOrder: 0,
      ));
      final picture = await spending.loadCurrentMonth(now: today);
      expect(picture.month, currentMonth);
      expect(picture.spendableMicros(FinancialUnit.syp),
          LedgerEntry.amountToMicros(885000));
      expect(picture.spendableMicros(FinancialUnit.usd), 0);
      expect(picture.unallocatedBalanceMicros(FinancialUnit.syp),
          LedgerEntry.amountToMicros(40000));
      expect(picture.plannedCommitmentsMicros(FinancialUnit.syp),
          LedgerEntry.amountToMicros(120000));
      expect(picture.paidFromSpendingMicros(FinancialUnit.syp), 0);
      expect(picture.hypotheticalAfterFullPlanMicros(FinancialUnit.syp),
          LedgerEntry.amountToMicros(765000));
      expect((await ledger.loadBalanceMicros())[FinancialUnit.syp],
          LedgerEntry.amountToMicros(925000));
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(500));
    });

    test('actual expense debits Spending once, does not debit Savings', () async {
      await plans.addItem(RecurringExpenseItem.create(
        name: 'إنترنت',
        unit: FinancialUnit.syp,
        amountMicros: LedgerEntry.amountToMicros(120000),
        sortOrder: 0,
      ));
      await expenses.logExpense(
        amountMicros: LedgerEntry.amountToMicros(80000),
        unit: FinancialUnit.syp,
        occurredAt: today,
        category: 'إنترنت',
        sourceFund: FinancialFund.spending,
      );
      final picture = await spending.loadCurrentMonth(now: today);
      expect(picture.spendableMicros(FinancialUnit.syp),
          LedgerEntry.amountToMicros(805000));
      expect(picture.paidFromSpendingMicros(FinancialUnit.syp),
          LedgerEntry.amountToMicros(80000));
      expect(picture.actualPaidAcrossAllFundsMicros(FinancialUnit.syp),
          LedgerEntry.amountToMicros(80000));
      expect(picture.hypotheticalAfterFullPlanMicros(FinancialUnit.syp),
          LedgerEntry.amountToMicros(685000));
      expect(await ledger.loadFundBalanceMicros(
          FinancialFund.savings, FinancialUnit.usd),
          LedgerEntry.amountToMicros(500));
      final paid = await ledger.loadEvents(type: FinancialEventType.expense);
      expect(paid, hasLength(1));
      expect(paid.single.entries.single.fund, FinancialFund.spending);
      expect((await ledger.loadBalanceMicros())[FinancialUnit.syp],
          LedgerEntry.amountToMicros(845000));
    });

    test('shows all actual expenses, but separates other funding sources',
        () async {
      await expenses.logExpense(
        amountMicros: LedgerEntry.amountToMicros(50000),
        unit: FinancialUnit.syp,
        occurredAt: today,
        category: 'مواصلات',
        sourceFund: FinancialFund.spending,
      );
      await expenses.logExpense(
        amountMicros: LedgerEntry.amountToMicros(10000),
        unit: FinancialUnit.syp,
        occurredAt: today,
        category: 'أخرى',
      );
      final result = await spending.loadCurrentMonth(now: today);
      expect(result.paidFromSpendingMicros(FinancialUnit.syp),
          LedgerEntry.amountToMicros(50000));
      expect(result.actualPaidAcrossAllFundsMicros(FinancialUnit.syp),
          LedgerEntry.amountToMicros(60000));
      expect(result.spendableMicros(FinancialUnit.syp),
          LedgerEntry.amountToMicros(835000));
      expect(result.unallocatedBalanceMicros(FinancialUnit.syp),
          LedgerEntry.amountToMicros(30000));
      expect((await ledger.loadEvents(type: FinancialEventType.expense)),
          hasLength(2));
    });

    test('cannot spend Savings or unallocated money from Spending button',
        () async {
      await expectLater(
        expenses.logExpense(
          amountMicros: LedgerEntry.amountToMicros(50),
          unit: FinancialUnit.usd,
          occurredAt: today,
          category: 'اشتراك',
          sourceFund: FinancialFund.spending,
        ),
        throwsA(isA<InsufficientBalanceException>()),
      );
      await expectLater(
        expenses.logExpense(
          amountMicros: LedgerEntry.amountToMicros(900000),
          unit: FinancialUnit.syp,
          occurredAt: today,
          category: 'زيادة',
          sourceFund: FinancialFund.spending,
        ),
        throwsA(isA<InsufficientBalanceException>()),
      );
      expect((await ledger.loadEvents(type: FinancialEventType.expense)),
          isEmpty);
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(500));
      expect(await ledger.loadFundBalanceMicros(
          FinancialFund.spending, FinancialUnit.syp),
          LedgerEntry.amountToMicros(885000));
    });

    test('Spending history filter includes original receipt and expense',
        () async {
      await expenses.logExpense(
        amountMicros: LedgerEntry.amountToMicros(10000),
        unit: FinancialUnit.syp,
        occurredAt: today,
        category: 'قهوة',
        sourceFund: FinancialFund.spending,
      );
      final history = TransactionHistoryService(database: database, ledger: ledger);
      final spendingHistory = await history.loadMonth(
        currentMonth,
        fund: FinancialFund.spending,
      );
      expect(spendingHistory, hasLength(2));
      expect(spendingHistory.any(
          (item) => item.event.type == FinancialEventType.income), isTrue);
      expect(spendingHistory.any(
          (item) => item.event.type == FinancialEventType.expense), isTrue);
      final savingsHistory = await history.loadMonth(
        currentMonth,
        fund: FinancialFund.savings,
      );
      expect(savingsHistory, hasLength(1));
      expect(savingsHistory.single.event.type,
          FinancialEventType.openingBalance);
    });

    test('SYP New cash stays in its own per-currency row', () async {
      await ledger.addEvent(FinancialEvent.create(
        type: FinancialEventType.income,
        occurredAt: today,
        entries: <LedgerEntry>[
          LedgerEntry(
            unit: FinancialUnit.sypNew,
            amountMicros: LedgerEntry.amountToMicros(150),
            fund: FinancialFund.spending,
          ),
        ],
      ));
      final result = await spending.loadCurrentMonth(now: today);
      expect(result.spendableMicros(FinancialUnit.sypNew),
          LedgerEntry.amountToMicros(150));
      expect(result.spendableMicros(FinancialUnit.syp),
          LedgerEntry.amountToMicros(885000));
      expect(result.spendableMicros(FinancialUnit.usd), 0);
    });
  });
}
