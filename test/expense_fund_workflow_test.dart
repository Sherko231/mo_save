import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/expense_category.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/models/recurring_expense_item.dart';
import 'package:mo_save/services/expense_plan_storage.dart';
import 'package:mo_save/services/expense_service.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/local_database.dart';
import 'package:mo_save/services/transaction_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MS-08 source-specific actual expenses', () {
    late Directory dir;
    late LocalDatabase db;
    late FinancialLedgerStorage ledger;
    late ExpensePlanStorage plans;
    late ExpenseService expenses;
    late DateTime today;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('mosave_fund_expense_');
      db = LocalDatabase.forTesting(
        '${dir.path}${Platform.pathSeparator}fund_expense.db',
      );
      ledger = FinancialLedgerStorage(database: db);
      plans = ExpensePlanStorage(database: db);
      expenses = ExpenseService(planStorage: plans, ledgerStorage: ledger);
      final now = DateTime.now();
      today = DateTime(now.year, now.month, now.day);

      // Avoid unrelated first-launch recurring-plan seed in these fixtures.
      final raw = await db.database;
      await raw.insert('app_metadata', <String, Object?>{
        'key': 'expense_plan_client_defaults_seeded_v1',
        'value': '1',
      });
      await ledger.addEvent(FinancialEvent.create(
        type: FinancialEventType.income,
        occurredAt: today,
        entries: <LedgerEntry>[
          LedgerEntry(
            unit: FinancialUnit.syp,
            amountMicros: LedgerEntry.amountToMicros(540000),
            fund: FinancialFund.spending,
          ),
          LedgerEntry(
            unit: FinancialUnit.usd,
            amountMicros: LedgerEntry.amountToMicros(500),
            fund: FinancialFund.savings,
          ),
          LedgerEntry(
            unit: FinancialUnit.syp,
            amountMicros: LedgerEntry.amountToMicros(50000),
            fund: FinancialFund.unallocated,
          ),
        ],
      ));
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test('80k SYP from Spending leaves 460k and one categorized expense',
        () async {
      await expenses.logExpense(
        amountMicros: LedgerEntry.amountToMicros(80000),
        unit: FinancialUnit.syp,
        occurredAt: today,
        category: ExpenseCategory.outing.label,
        note: 'رحلة',
        sourceFund: FinancialFund.spending,
      );
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.spending, FinancialUnit.syp,
      ), LedgerEntry.amountToMicros(460000));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.unallocated, FinancialUnit.syp,
      ), LedgerEntry.amountToMicros(50000));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(500));
      expect((await ledger.loadBalanceMicros())[FinancialUnit.syp],
          LedgerEntry.amountToMicros(510000));
      final posted = await ledger.loadEvents(type: FinancialEventType.expense);
      expect(posted, hasLength(1));
      expect(posted.single.category, 'نزهة');
      expect(posted.single.note, 'رحلة');
      expect(posted.single.entries.single.fund, FinancialFund.spending);
      final month = await expenses.loadMonth(today);
      expect(month.actualEvents, hasLength(1));
      expect(month.actualTotalsMicros[FinancialUnit.syp],
          LedgerEntry.amountToMicros(80000));
    });

    test('100 USD direct from Savings leaves 400 without moving into Spending',
        () async {
      await expenses.logExpense(
        amountMicros: LedgerEntry.amountToMicros(100),
        unit: FinancialUnit.usd,
        occurredAt: today,
        category: ExpenseCategory.bills.label,
        note: 'دفع فاتورة من المدخرات',
        sourceFund: FinancialFund.savings,
      );
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(400));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.spending, FinancialUnit.usd,
      ), 0);
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(400));
      final month = await expenses.loadMonth(today);
      expect(month.actualTotalsMicros[FinancialUnit.usd],
          LedgerEntry.amountToMicros(100));
      expect(month.actualEvents.single.entries.single.fund,
          FinancialFund.savings);
    });

    test('each same-unit fund debit is counted exactly once', () async {
      await ledger.addEvent(FinancialEvent.create(
        type: FinancialEventType.openingBalance,
        occurredAt: today,
        entries: <LedgerEntry>[
          LedgerEntry(
            unit: FinancialUnit.usd,
            amountMicros: LedgerEntry.amountToMicros(150),
            fund: FinancialFund.spending,
          ),
        ],
      ));
      await expenses.logExpense(
        amountMicros: LedgerEntry.amountToMicros(50),
        unit: FinancialUnit.usd,
        occurredAt: today,
        category: 'طعام',
        sourceFund: FinancialFund.spending,
      );
      await expenses.logExpense(
        amountMicros: LedgerEntry.amountToMicros(100),
        unit: FinancialUnit.usd,
        occurredAt: today,
        category: 'صحة',
        note: 'سحب اضطراري',
        sourceFund: FinancialFund.savings,
      );
      final month = await expenses.loadMonth(today);
      expect(month.actualEvents, hasLength(2));
      expect(month.actualTotalsMicros[FinancialUnit.usd],
          LedgerEntry.amountToMicros(150));
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(500));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(400));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.spending, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(100));
    });

    test('source fund shortage rejects even when other funds are rich',
        () async {
      await expectLater(
        expenses.logExpense(
          amountMicros: LedgerEntry.amountToMicros(100),
          unit: FinancialUnit.usd,
          occurredAt: today,
          category: 'طعام',
          sourceFund: FinancialFund.spending,
        ),
        throwsA(isA<InsufficientBalanceException>()),
      );
      await expectLater(
        expenses.logExpense(
          amountMicros: LedgerEntry.amountToMicros(1000),
          unit: FinancialUnit.syp,
          occurredAt: today,
          category: 'طعام',
          note: 'غير كافٍ',
          sourceFund: FinancialFund.savings,
        ),
        throwsA(isA<InsufficientBalanceException>()),
      );
      expect(await ledger.loadEvents(type: FinancialEventType.expense),
          isEmpty);
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(500));
    });

    test('Savings reason and a named category are mandatory', () async {
      await expectLater(
        expenses.logExpense(
          amountMicros: LedgerEntry.amountToMicros(100),
          unit: FinancialUnit.usd,
          occurredAt: today,
          category: 'صحة',
          sourceFund: FinancialFund.savings,
        ),
        throwsArgumentError,
      );
      await expectLater(
        expenses.logExpense(
          amountMicros: LedgerEntry.amountToMicros(100),
          unit: FinancialUnit.usd,
          occurredAt: today,
          category: '  ',
          note: 'ضرورة',
          sourceFund: FinancialFund.savings,
        ),
        throwsArgumentError,
      );
      expect(() => ExpenseCategory.other.resolve(), throwsArgumentError);
      expect(ExpenseCategory.other.resolve(customName: 'مساعدة عائلية'),
          'مساعدة عائلية');
      expect(await ledger.loadEvents(type: FinancialEventType.expense),
          isEmpty);
    });

    test('same UI payment request does not double-debit the selected fund',
        () async {
      Future<void> pay({String note = 'مواصلات'}) => expenses.logExpense(
        amountMicros: LedgerEntry.amountToMicros(40000),
        unit: FinancialUnit.syp,
        occurredAt: today,
        category: 'مواصلات',
        note: note,
        sourceFund: FinancialFund.spending,
        requestId: 'bus-october',
      );
      await pay();
      await pay();
      expect(await ledger.loadEvents(type: FinancialEventType.expense),
          hasLength(1));
      await expectLater(pay(note: 'different'), throwsA(isA<Exception>()));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.spending, FinancialUnit.syp,
      ), LedgerEntry.amountToMicros(500000));
    });

    test('bill plan is not cash: payment posts only after confirmation',
        () async {
      await plans.addItem(RecurringExpenseItem.create(
        name: 'أمبير',
        unit: FinancialUnit.syp,
        amountMicros: LedgerEntry.amountToMicros(120000),
        sortOrder: 0,
      ));
      final before = await expenses.loadMonth(today);
      expect(before.plannedTotalsMicros[FinancialUnit.syp],
          LedgerEntry.amountToMicros(120000));
      expect(before.actualTotalsMicros[FinancialUnit.syp], 0);
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.spending, FinancialUnit.syp,
      ), LedgerEntry.amountToMicros(540000));

      await expenses.logExpense(
        amountMicros: LedgerEntry.amountToMicros(120000),
        unit: FinancialUnit.syp,
        occurredAt: today,
        category: 'أمبير',
        sourceFund: FinancialFund.spending,
      );
      final after = await expenses.loadMonth(today);
      expect(after.plannedTotalsMicros[FinancialUnit.syp],
          LedgerEntry.amountToMicros(120000));
      expect(after.actualTotalsMicros[FinancialUnit.syp],
          LedgerEntry.amountToMicros(120000));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.spending, FinancialUnit.syp,
      ), LedgerEntry.amountToMicros(420000));
    });

    test('Savings payment correction and deletion retain revisions', () async {
      await expenses.logExpense(
        amountMicros: LedgerEntry.amountToMicros(100),
        unit: FinancialUnit.usd,
        occurredAt: today,
        category: 'صحة',
        note: 'علاج ضروري',
        sourceFund: FinancialFund.savings,
      );
      final event = (await ledger.loadEvents(type: FinancialEventType.expense))
          .single;
      final audit = TransactionHistoryService(database: db, ledger: ledger);
      await audit.correctAmounts(
        eventId: event.id,
        absoluteAmountsMicros: <int>[LedgerEntry.amountToMicros(80)],
      );
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(420));
      final snapshots = await audit.loadRevisions(event.id);
      expect(snapshots, hasLength(1));
      expect(snapshots.single.snapshot.entries.single.fund,
          FinancialFund.savings);
      expect(snapshots.single.snapshot.entries.single.amountMicros,
          -LedgerEntry.amountToMicros(100));
      await audit.deleteEvent(event.id);
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(500));
      final history = await audit.loadMonth(today,
          fund: FinancialFund.savings);
      expect(history.where((item) => item.isDeleted), hasLength(1));
      expect((await expenses.loadMonth(today))
          .actualTotalsMicros[FinancialUnit.usd], 0);
    });

    test('cash units remain distinct, gold and future payments rejected',
        () async {
      await ledger.addEvent(FinancialEvent.create(
        type: FinancialEventType.openingBalance,
        occurredAt: today,
        entries: <LedgerEntry>[
          LedgerEntry(
            unit: FinancialUnit.sypNew,
            amountMicros: LedgerEntry.amountToMicros(300),
            fund: FinancialFund.spending,
          ),
        ],
      ));
      await expenses.logExpense(
        amountMicros: LedgerEntry.amountToMicros(30),
        unit: FinancialUnit.sypNew,
        occurredAt: today,
        category: 'منزل',
        sourceFund: FinancialFund.spending,
      );
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.spending, FinancialUnit.sypNew,
      ), LedgerEntry.amountToMicros(270));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.spending, FinancialUnit.syp,
      ), LedgerEntry.amountToMicros(540000));
      await expectLater(
        expenses.logExpense(
          amountMicros: LedgerEntry.amountToMicros(1),
          unit: FinancialUnit.goldGram,
          occurredAt: today,
          category: 'شراء',
          sourceFund: FinancialFund.savings,
          note: 'شراء',
        ),
        throwsArgumentError,
      );
      await expectLater(
        expenses.logExpense(
          amountMicros: LedgerEntry.amountToMicros(1),
          unit: FinancialUnit.sypNew,
          occurredAt: today.add(const Duration(days: 1)),
          category: 'شراء',
          sourceFund: FinancialFund.spending,
        ),
        throwsArgumentError,
      );
    });
  });
}
