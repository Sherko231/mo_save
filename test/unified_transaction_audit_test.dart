import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/models/recurring_expense_item.dart';
import 'package:mo_save/models/saving_challenge.dart';
import 'package:mo_save/services/challenge_storage.dart';
import 'package:mo_save/services/expense_plan_storage.dart';
import 'package:mo_save/services/expense_service.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/local_database.dart';
import 'package:mo_save/services/transaction_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('MS-16 auditable actual and planned history', () {
    late Directory dir;
    late LocalDatabase database;
    late FinancialLedgerStorage ledger;
    late TransactionHistoryService history;
    late ExpensePlanStorage plans;
    late ExpenseService expenses;
    late ChallengeStorage goals;
    late DateTime month;

    setUp(() async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      dir = await Directory.systemTemp.createTemp('mosave_history_audit_');
      database = LocalDatabase.forTesting(
        '${dir.path}${Platform.pathSeparator}history.db',
      );
      ledger = FinancialLedgerStorage(database: database);
      plans = ExpensePlanStorage(database: database);
      history = TransactionHistoryService(
        database: database, ledger: ledger, plans: plans,
      );
      expenses = ExpenseService(
        planStorage: plans, ledgerStorage: ledger,
      );
      goals = ChallengeStorage(
        database: database, preferences: SharedPreferencesAsync(),
      );
      final now = DateTime.now();
      month = DateTime(now.year, now.month);
      await (await database.database).insert('app_metadata',
        <String, Object?>{
          'key': 'expense_plan_client_defaults_seeded_v1',
          'value': '1',
        });
    });

    tearDown(() async {
      await database.close();
      await dir.delete(recursive: true);
    });

    Future<void> opening(int amount, {
      FinancialUnit unit = FinancialUnit.usd,
      FinancialFund fund = FinancialFund.savings,
    }) => ledger.addEvent(FinancialEvent.create(
      type: FinancialEventType.openingBalance,
      occurredAt: DateTime.now(),
      entries: <LedgerEntry>[
        LedgerEntry(
          unit: unit, fund: fund,
          amountMicros: LedgerEntry.amountToMicros(amount),
        ),
      ],
    ));

    test('Savings 100 USD purchase posts once; audit edit and cancel',
        () async {
      await opening(500);
      await expenses.logExpense(
        amountMicros: LedgerEntry.amountToMicros(100),
        unit: FinancialUnit.usd, occurredAt: DateTime.now(),
        category: 'صحة', note: 'دواء ضروري',
        sourceFund: FinancialFund.savings,
      );
      final active = await history.loadMonth(month,
        type: FinancialEventType.expense,
        fund: FinancialFund.savings,
        unit: FinancialUnit.usd, search: 'دواء');
      expect(active, hasLength(1));
      expect(active.single.event.entries.single.fund,
        FinancialFund.savings);
      expect(active.single.event.entries.single.amountMicros,
        -LedgerEntry.amountToMicros(100));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(400));
      await history.correctAmounts(
        eventId: active.single.event.id,
        absoluteAmountsMicros: <int>[LedgerEntry.amountToMicros(80)],
      );
      final revisions = await history.loadRevisions(active.single.event.id);
      expect(revisions, hasLength(1));
      expect(revisions.single.snapshot.note, 'دواء ضروري');
      expect(revisions.single.snapshot.entries.single.amountMicros,
        -LedgerEntry.amountToMicros(100));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(420));
      await history.deleteEvent(active.single.event.id);
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(500));
      final after = await history.loadMonth(month,
        type: FinancialEventType.expense,
        fund: FinancialFund.savings,
        search: 'دواء');
      expect(after, hasLength(1));
      expect(after.single.isDeleted, isTrue);
      expect((await history.loadRevisions(active.single.event.id)),
        hasLength(2));
      expect((await expenses.loadMonth(month))
        .actualTotalsMicros[FinancialUnit.usd], 0);
    });

    test('fund transfer has two opposing fund legs; unbalanced edit rolls back',
        () async {
      await opening(200);
      await ledger.transferFunds(
        unit: FinancialUnit.usd,
        source: FinancialFund.savings,
        destination: FinancialFund.spending,
        amountMicros: LedgerEntry.amountToMicros(50),
        occurredAt: DateTime.now(),
      );
      final event = (await history.loadMonth(month,
        type: FinancialEventType.fundTransfer)).single.event;
      expect(event.entries, hasLength(2));
      expect(event.entries.first.amountMicros,
        -LedgerEntry.amountToMicros(50));
      expect(event.entries.last.amountMicros,
        LedgerEntry.amountToMicros(50));
      await expectLater(history.correctAmounts(
        eventId: event.id,
        absoluteAmountsMicros: <int>[
          LedgerEntry.amountToMicros(60),
          LedgerEntry.amountToMicros(70),
        ],
      ), throwsA(isA<TransactionMutationException>()));
      expect(await history.loadRevisions(event.id), isEmpty);
      await history.correctAmounts(
        eventId: event.id,
        absoluteAmountsMicros: <int>[
          LedgerEntry.amountToMicros(70),
          LedgerEntry.amountToMicros(70),
        ],
      );
      expect((await history.loadRevisions(event.id)).single
        .snapshot.entries.first.amountMicros,
        -LedgerEntry.amountToMicros(50));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(130));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.spending, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(70));
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
        LedgerEntry.amountToMicros(200));
      await history.deleteEvent(event.id);
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(200));
      expect((await history.loadRevisions(event.id)), hasLength(2));
    });

    test('historical executed FX rate and old revision remain auditable',
        () async {
      await opening(3000000, unit: FinancialUnit.syp,
        fund: FinancialFund.spending);
      await ledger.addCurrencyConversion(FinancialEvent.create(
        type: FinancialEventType.currencyConversion,
        occurredAt: DateTime.now(),
        executedSypPerUsd: 15000,
        entries: <LedgerEntry>[
          LedgerEntry(unit: FinancialUnit.syp,
            amountMicros: -LedgerEntry.amountToMicros(1500000),
            fund: FinancialFund.spending),
          LedgerEntry(unit: FinancialUnit.usd,
            amountMicros: LedgerEntry.amountToMicros(100),
            fund: FinancialFund.savings),
        ],
      ));
      final conversion = (await history.loadMonth(month,
        type: FinancialEventType.currencyConversion)).single.event;
      expect(conversion.executedSypPerUsd, 15000);
      await history.correctAmounts(
        eventId: conversion.id,
        absoluteAmountsMicros: <int>[
          LedgerEntry.amountToMicros(1600000),
          LedgerEntry.amountToMicros(100),
        ],
      );
      final changed = (await history.loadMonth(month,
        type: FinancialEventType.currencyConversion)).single.event;
      expect(changed.executedSypPerUsd, 16000);
      expect((await history.loadRevisions(changed.id)).single
        .snapshot.executedSypPerUsd, 15000);
      expect((await ledger.loadBalanceMicros())[FinancialUnit.syp],
        LedgerEntry.amountToMicros(1400000));
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
        LedgerEntry.amountToMicros(100));
    });

    test('unchanged metadata never creates an audit revision', () async {
      await opening(300);
      await expenses.logExpense(
        amountMicros: LedgerEntry.amountToMicros(10),
        unit: FinancialUnit.usd,
        occurredAt: DateTime.now(),
        category: 'طعام', note: 'غداء',
        sourceFund: FinancialFund.savings,
      );
      final e = (await ledger.loadEvents(
        type: FinancialEventType.expense)).single;
      await history.updateMetadata(
        eventId: e.id,
        occurredAt: e.occurredAt.toLocal(),
        category: e.category,
        note: e.note,
      );
      expect(await history.loadRevisions(e.id), isEmpty);
      expect((await history.loadMonth(month,
        type: FinancialEventType.expense, search: 'غداء')), hasLength(1));
      expect((await history.loadMonth(month,
        type: FinancialEventType.expense, search: 'غير موجود')), isEmpty);
    });

    test('planned expense and expected salary are separate from ledger',
        () async {
      final bill = RecurringExpenseItem.create(
        name: 'إنترنت',
        unit: FinancialUnit.syp,
        amountMicros: LedgerEntry.amountToMicros(120000),
        sortOrder: 0,
      );
      await plans.addItem(bill, effectiveFromMonth: month);
      final expected = await history.loadExpectedMonth(month);
      expect(expected.plannedBills, hasLength(1));
      expect(expected.plannedBills.single.amountMicros,
        LedgerEntry.amountToMicros(120000));
      expect((await history.loadMonth(month)), isEmpty);
      expect((await ledger.loadBalanceMicros())[FinancialUnit.syp], 0);
      expect((await expenses.loadMonth(month))
        .actualTotalsMicros[FinancialUnit.syp], 0);
    });

    test('goal cell changes retain archived noncash progress without assets',
        () async {
      await opening(200);
      final goal = SavingChallenge.create(
        id: 'history-goal', name: 'سفر',
        targetAmount: 100, currency: ChallengeCurrency.usd,
        sequence: ChallengeSequence.ordered, cellCount: 1,
      );
      await goals.addChallenge(goal);
      await goals.updateChallenge(goal.copyWith(cells:
        <ChallengeCell>[goal.cells.single.copyWith(isCompleted: true)]));
      final current = (await ledger.loadEvents(
        type: FinancialEventType.savingContribution)).single;
      expect(current.entries.single.affectsBalance, isFalse);
      final backed = (await goals.loadChallenges()).single;
      await goals.updateChallenge(backed.copyWith(cells:
        <ChallengeCell>[backed.cells.single.copyWith(isCompleted: false)]));
      final revisions = await history.loadRevisions(current.id);
      expect(revisions, hasLength(1));
      expect(revisions.single.isDelete, isTrue);
      expect(revisions.single.snapshot.relatedGoalId, goal.id);
      expect(revisions.single.snapshot.entries.single.amountMicros,
        LedgerEntry.amountToMicros(100));
      expect((await history.loadMonth(month,
        type: FinancialEventType.savingContribution,
        goalId: goal.id)), hasLength(1));
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
        LedgerEntry.amountToMicros(200));
      final reopened = (await goals.loadChallenges()).single;
      await goals.updateChallenge(reopened.copyWith(cells:
        <ChallengeCell>[
          reopened.cells.single.copyWith(isCompleted: true),
        ]));
      final after = await history.loadMonth(month,
        type: FinancialEventType.savingContribution,
        goalId: goal.id);
      expect(after, hasLength(1)); // Active stable ID supersedes tombstone.
      expect(after.single.isDeleted, isFalse);
      expect(after.single.revisionCount, 1);
      expect((await history.loadRevisions(current.id)), hasLength(1));
    });

    test('history correction cannot break Savings-backed earmarks',
        () async {
      await opening(200);
      final initial = (await ledger.loadEvents(
        type: FinancialEventType.openingBalance)).single;
      final goal = SavingChallenge.create(
        id: 'reserved', name: 'سفر', targetAmount: 100,
        currency: ChallengeCurrency.usd,
        sequence: ChallengeSequence.ordered, cellCount: 1,
      );
      await goals.addChallenge(goal);
      await goals.updateChallenge(goal.copyWith(cells:
        <ChallengeCell>[goal.cells.single.copyWith(isCompleted: true)]));
      await expectLater(
        history.correctAmounts(
          eventId: initial.id,
          absoluteAmountsMicros: <int>[LedgerEntry.amountToMicros(80)],
        ),
        throwsA(isA<GoalBackingInsufficientException>()),
      );
      expect(await history.loadRevisions(initial.id), isEmpty);
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
        LedgerEntry.amountToMicros(200));
    });
  });
}
