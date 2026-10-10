import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/models/recurring_expense_item.dart';
import 'package:mo_save/services/expense_plan_storage.dart';
import 'package:mo_save/services/expense_service.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/local_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MS-09 time-effective recurring expense plans', () {
    late Directory directory;
    late LocalDatabase db;
    late ExpensePlanStorage plans;
    late ExpenseService expenses;
    late FinancialLedgerStorage ledger;
    late DateTime current;
    late DateTime next;
    late DateTime third;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('mosave_plan_v11_');
      db = LocalDatabase.forTesting(
        '${directory.path}${Platform.pathSeparator}plan.db',
      );
      plans = ExpensePlanStorage(database: db);
      ledger = FinancialLedgerStorage(database: db);
      expenses = ExpenseService(planStorage: plans, ledgerStorage: ledger);
      final today = DateTime.now();
      current = DateTime(today.year, today.month);
      next = DateTime(today.year, today.month + 1);
      third = DateTime(today.year, today.month + 2);
      await (await db.database).insert('app_metadata', <String, Object?>{
        'key': 'expense_plan_client_defaults_seeded_v1',
        'value': '1',
      });
    });

    tearDown(() async {
      await db.close();
      await directory.delete(recursive: true);
    });

    Future<RecurringExpenseItem> addAmpere() async {
      final item = RecurringExpenseItem.create(
        name: 'أمبير',
        unit: FinancialUnit.syp,
        amountMicros: LedgerEntry.amountToMicros(240000),
        sortOrder: 0,
      );
      await plans.addItem(item, effectiveFromMonth: current);
      return item;
    }

    test('future 300k price leaves this month 240k and no cash debit',
        () async {
      final ampere = await addAmpere();
      await plans.updateItem(
        ampere.copyWith(
          amountMicros: LedgerEntry.amountToMicros(300000),
        ),
        effectiveFromMonth: next,
      );
      final oldMonth = await expenses.loadMonth(current);
      final newMonth = await expenses.loadMonth(next);
      expect(oldMonth.planItems.single.amountMicros,
          LedgerEntry.amountToMicros(240000));
      expect(oldMonth.plannedTotalsMicros[FinancialUnit.syp],
          LedgerEntry.amountToMicros(240000));
      expect(newMonth.planItems.single.amountMicros,
          LedgerEntry.amountToMicros(300000));
      expect(newMonth.plannedTotalsMicros[FinancialUnit.syp],
          LedgerEntry.amountToMicros(300000));
      expect(oldMonth.actualEvents, isEmpty);
      expect(newMonth.actualEvents, isEmpty);
      expect(await ledger.loadEvents(), isEmpty);
      expect((await ledger.loadBalanceMicros())[FinancialUnit.syp], 0);
      final revisions = await plans.loadFutureChanges(ampere.id);
      expect(revisions, hasLength(1));
      expect(revisions.single.effectiveMonth, next);
      expect(revisions.single.amountMicros,
          LedgerEntry.amountToMicros(300000));
    });

    test('multiple revisions, currency edits and future cancellation are scoped',
        () async {
      final ampere = await addAmpere();
      await plans.updateItem(
        ampere.copyWith(
          name: 'أمبير جديد',
          amountMicros: LedgerEntry.amountToMicros(300000),
        ),
        effectiveFromMonth: next,
      );
      await plans.updateItem(
        ampere.copyWith(
          name: 'أمبير بالدولار',
          unit: FinancialUnit.usd,
          amountMicros: LedgerEntry.amountToMicros(22),
        ),
        effectiveFromMonth: third,
      );
      final fourth = DateTime(third.year, third.month + 1);
      await plans.deleteItem(ampere.id, effectiveFromMonth: fourth);

      expect((await plans.loadItemsForMonth(current)).single.name, 'أمبير');
      expect((await plans.loadItemsForMonth(next)).single.name, 'أمبير جديد');
      expect((await plans.loadItemsForMonth(third)).single.unit, FinancialUnit.usd);
      expect(await plans.loadItemsForMonth(fourth), isEmpty);
      expect((await expenses.loadMonth(current)).plannedTotalsMicros[FinancialUnit.syp],
          LedgerEntry.amountToMicros(240000));
      expect((await expenses.loadMonth(next)).plannedTotalsMicros[FinancialUnit.syp],
          LedgerEntry.amountToMicros(300000));
      expect((await expenses.loadMonth(third)).plannedTotalsMicros[FinancialUnit.usd],
          LedgerEntry.amountToMicros(22));
      expect((await plans.loadFutureChanges(ampere.id)), hasLength(3));
      expect(await ledger.loadEvents(), isEmpty);
    });

    test('historical actual payment and its audit never change with a future plan',
        () async {
      final ampere = await addAmpere();
      await ledger.addEvent(FinancialEvent.create(
        type: FinancialEventType.income,
        occurredAt: DateTime.now(),
        entries: <LedgerEntry>[
          LedgerEntry(
            unit: FinancialUnit.syp,
            amountMicros: LedgerEntry.amountToMicros(500000),
            fund: FinancialFund.spending,
          ),
        ],
      ));
      await expenses.logExpense(
        amountMicros: LedgerEntry.amountToMicros(240000),
        unit: FinancialUnit.syp,
        occurredAt: DateTime.now(),
        category: 'أمبير',
        sourceFund: FinancialFund.spending,
      );
      final previous = await expenses.loadMonth(current);
      expect(previous.actualTotalsMicros[FinancialUnit.syp],
          LedgerEntry.amountToMicros(240000));
      await plans.updateItem(
        ampere.copyWith(amountMicros: LedgerEntry.amountToMicros(310000)),
        effectiveFromMonth: next,
      );
      await plans.deleteItem(
        ampere.id, effectiveFromMonth: third,
      );
      final after = await expenses.loadMonth(current);
      expect(after.actualTotalsMicros[FinancialUnit.syp],
          LedgerEntry.amountToMicros(240000));
      expect(after.plannedTotalsMicros[FinancialUnit.syp],
          LedgerEntry.amountToMicros(240000));
      expect((await expenses.loadMonth(next)).plannedTotalsMicros[FinancialUnit.syp],
          LedgerEntry.amountToMicros(310000));
      expect((await expenses.loadMonth(third)).plannedTotalsMicros[FinancialUnit.syp],
          0);
      expect((await ledger.loadBalanceMicros())[FinancialUnit.syp],
          LedgerEntry.amountToMicros(260000));
      final oldPayment = (await ledger.loadEvents(
          type: FinancialEventType.expense)).single;
      expect(oldPayment.entries.single.amountMicros,
          -LedgerEntry.amountToMicros(240000));
      expect(oldPayment.category, 'أمبير');
    });

    test('one paid planned occurrence is unique; extra one-off remains possible',
        () async {
      final item = await addAmpere();
      await ledger.addEvent(FinancialEvent.create(
        type: FinancialEventType.income,
        occurredAt: DateTime.now(),
        entries: <LedgerEntry>[
          LedgerEntry(
            unit: FinancialUnit.syp,
            amountMicros: LedgerEntry.amountToMicros(600000),
            fund: FinancialFund.spending,
          ),
        ],
      ));
      Future<void> pay(String identity, {int amount = 240000}) =>
          expenses.logExpense(
            amountMicros: LedgerEntry.amountToMicros(amount),
            unit: FinancialUnit.syp,
            occurredAt: DateTime.now(),
            category: item.name,
            sourceFund: FinancialFund.spending,
            plannedItemId: item.id,
            requestId: identity,
          );
      await pay('ampere-month-payment');
      final snapshot = await expenses.loadMonth(current);
      expect(snapshot.paidPlanItemIds, contains(item.id));
      expect(snapshot.actualTotalsMicros[FinancialUnit.syp],
          LedgerEntry.amountToMicros(240000));
      await pay('ampere-month-payment');
      expect((await ledger.loadEvents(type: FinancialEventType.expense)),
          hasLength(1));
      await expectLater(pay('new-request-id', amount: 250000), throwsStateError);
      await expenses.logExpense(
        amountMicros: LedgerEntry.amountToMicros(10000),
        unit: FinancialUnit.syp,
        occurredAt: DateTime.now(),
        category: 'أمبير إضافي',
        sourceFund: FinancialFund.spending,
      );
      expect((await ledger.loadEvents(type: FinancialEventType.expense)),
          hasLength(2));
      await plans.updateItem(item.copyWith(
        amountMicros: LedgerEntry.amountToMicros(310000),
      ), effectiveFromMonth: next);
      expect((await expenses.loadMonth(current)).actualTotalsMicros[FinancialUnit.syp],
          LedgerEntry.amountToMicros(250000));
      expect((await expenses.loadMonth(current)).paidPlanItemIds,
          contains(item.id));
      expect((await expenses.loadMonth(next)).paidPlanItemIds, isEmpty);
    });

    test('future-only planned gas appears in management, not early reports',
        () async {
      final gas = RecurringExpenseItem.create(
        name: 'أسطوانة غاز',
        unit: FinancialUnit.syp,
        amountMicros: LedgerEntry.amountToMicros(100000),
        sortOrder: 4,
      );
      await plans.addItem(gas, effectiveFromMonth: next);
      expect(await plans.loadItemsForMonth(current), isEmpty);
      expect((await plans.loadManageableItems()).single.id, gas.id);
      expect((await plans.loadItemsForMonth(next)).single.name, 'أسطوانة غاز');
      expect((await expenses.loadMonth(current)).plannedTotalsMicros[FinancialUnit.syp], 0);
    });

    test('existing restored bills are not duplicated by default seeding',
        () async {
      final original = await addAmpere();
      await (await db.database).delete('app_metadata',
        where: 'key = ?',
        whereArgs: <Object?>['expense_plan_client_defaults_seeded_v1']);
      final loaded = await plans.loadItems();
      expect(loaded, hasLength(1));
      expect(loaded.single.id, original.id);
      expect((await (await db.database)
          .query('recurring_expense_items')), hasLength(1));
      expect((await (await db.database)
          .query('recurring_expense_plan_versions')), hasLength(1));
    });

    test('older and current months cannot be retroactively modified',
        () async {
      final item = await addAmpere();
      await expectLater(
        plans.updateItem(item.copyWith(
          amountMicros: LedgerEntry.amountToMicros(350000),
        ), effectiveFromMonth: current),
        throwsArgumentError,
      );
      await expectLater(
        plans.deleteItem(item.id, effectiveFromMonth: current),
        throwsArgumentError,
      );
      await expectLater(
        plans.addItem(RecurringExpenseItem.create(
          name: 'قديم', unit: FinancialUnit.syp,
          amountMicros: LedgerEntry.amountToMicros(900),
          sortOrder: 2,
        ), effectiveFromMonth: DateTime(2020, 1)),
        throwsArgumentError,
      );
      expect((await plans.loadItemsForMonth(current)).single.amountMicros,
          LedgerEntry.amountToMicros(240000));
    });

    test('reopen database keeps all versions and scheduled removal', () async {
      final item = await addAmpere();
      await plans.updateItem(item.copyWith(
        amountMicros: LedgerEntry.amountToMicros(350000),
      ), effectiveFromMonth: next);
      await plans.deleteItem(item.id, effectiveFromMonth: third);
      await db.close();
      final reopened = LocalDatabase.forTesting(
        '${directory.path}${Platform.pathSeparator}plan.db',
      );
      final restored = ExpensePlanStorage(database: reopened);
      expect((await restored.loadItemsForMonth(current)).single.amountMicros,
          LedgerEntry.amountToMicros(240000));
      expect((await restored.loadItemsForMonth(next)).single.amountMicros,
          LedgerEntry.amountToMicros(350000));
      expect(await restored.loadItemsForMonth(third), isEmpty);
      expect((await restored.loadFutureChanges(item.id)), hasLength(2));
      await reopened.close();
    });
  });
}
