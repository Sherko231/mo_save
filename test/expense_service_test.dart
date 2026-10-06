import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/services/expense_plan_storage.dart';
import 'package:mo_save/services/expense_service.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/local_database.dart';

void main() {
  group('ExpenseService', () {
    late Directory tempDirectory;
    late LocalDatabase database;
    late FinancialLedgerStorage ledger;
    late ExpenseService service;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('mo_save_expense_');
      database = LocalDatabase.forTesting(
        '${tempDirectory.path}${Platform.pathSeparator}expense.db',
      );
      ledger = FinancialLedgerStorage(database: database);
      service = ExpenseService(
        planStorage: ExpensePlanStorage(database: database),
        ledgerStorage: ledger,
      );

      await ledger.addEvent(
        FinancialEvent.create(
          type: FinancialEventType.income,
          occurredAt: DateTime.now(),
          entries: <LedgerEntry>[
            LedgerEntry(
              unit: FinancialUnit.syp,
              amountMicros: LedgerEntry.amountToMicros(100000),
            ),
          ],
          category: 'testSeed',
        ),
      );
    });

    tearDown(() async {
      await database.close();
      await tempDirectory.delete(recursive: true);
    });

    test('valid expense reduces owned cash balance', () async {
      await service.logExpense(
        amountMicros: LedgerEntry.amountToMicros(60000),
        unit: FinancialUnit.syp,
        occurredAt: DateTime.now(),
        category: 'اختبار',
      );

      final balances = await ledger.loadBalanceMicros();
      expect(
        balances[FinancialUnit.syp],
        LedgerEntry.amountToMicros(40000),
      );
    });

    test('expense above available balance is rejected without mutation', () async {
      await expectLater(
        service.logExpense(
          amountMicros: LedgerEntry.amountToMicros(120000),
          unit: FinancialUnit.syp,
          occurredAt: DateTime.now(),
          category: 'اختبار',
        ),
        throwsA(isA<InsufficientBalanceException>()),
      );

      final balances = await ledger.loadBalanceMicros();
      expect(
        balances[FinancialUnit.syp],
        LedgerEntry.amountToMicros(100000),
      );
    });

    test('future dated expense is rejected', () async {
      final tomorrow = DateTime.now().add(const Duration(days: 1));

      await expectLater(
        service.logExpense(
          amountMicros: LedgerEntry.amountToMicros(1000),
          unit: FinancialUnit.syp,
          occurredAt: tomorrow,
          category: 'اختبار',
        ),
        throwsArgumentError,
      );
    });
  });
}
