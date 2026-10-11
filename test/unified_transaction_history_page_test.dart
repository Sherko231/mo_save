import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/models/recurring_expense_item.dart';
import 'package:mo_save/pages/transaction_history_page.dart';
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

  testWidgets('MS-16 RTL actual expense, separated plan and expanded audit',
      (tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final dir = await Directory.systemTemp.createTemp('mosave_audit_ui_');
    final database = LocalDatabase.forTesting(
      '${dir.path}${Platform.pathSeparator}audit.db',
    );
    addTearDown(() async {
      await database.close();
      await dir.delete(recursive: true);
    });
    final ledger = FinancialLedgerStorage(database: database);
    final plans = ExpensePlanStorage(database: database);
    final history = TransactionHistoryService(
      database: database, ledger: ledger, plans: plans,
    );
    await (await database.database).insert('app_metadata',
      <String, Object?>{
        'key': 'expense_plan_client_defaults_seeded_v1',
        'value': '1',
      });
    final month = DateTime.now();
    await ledger.addEvent(FinancialEvent.create(
      type: FinancialEventType.openingBalance,
      occurredAt: month,
      entries: <LedgerEntry>[
        LedgerEntry(
          unit: FinancialUnit.usd,
          fund: FinancialFund.savings,
          amountMicros: LedgerEntry.amountToMicros(300),
        ),
      ],
    ));
    final actual = ExpenseService(
      planStorage: plans, ledgerStorage: ledger,
    );
    await actual.logExpense(
      amountMicros: LedgerEntry.amountToMicros(100),
      unit: FinancialUnit.usd,
      occurredAt: month,
      category: 'صحة',
      note: 'دواء سابق',
      sourceFund: FinancialFund.savings,
    );
    final id = (await ledger.loadEvents(
      type: FinancialEventType.expense)).single.id;
    await history.correctAmounts(
      eventId: id,
      absoluteAmountsMicros: <int>[LedgerEntry.amountToMicros(80)],
    );
    await plans.addItem(RecurringExpenseItem.create(
      name: 'إنترنت مخطط',
      unit: FinancialUnit.syp,
      amountMicros: LedgerEntry.amountToMicros(120000),
      sortOrder: 0,
    ), effectiveFromMonth: DateTime(month.year, month.month));

    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: TransactionHistoryPage(
          initialMonth: month,
          initialType: FinancialEventType.expense,
          historyService: history,
          goalStorage: ChallengeStorage(
            database: database,
            preferences: SharedPreferencesAsync(),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('سجل الحركات'), findsOneWidget);
    expect(find.text('المخطط والمتوقع — ليس مالاً منفذاً'), findsOneWidget);
    expect(find.text('الحركات المسجلة فعلياً'), findsOneWidget);
    expect(find.text('مصروف'), findsOneWidget);
    expect(find.text('معدّلة 1×'), findsOneWidget);

    await tester.tap(find.text('المخطط والمتوقع — ليس مالاً منفذاً'));
    await tester.pumpAndSettle();
    expect(find.text('إنترنت مخطط'), findsOneWidget);
    expect(find.text('فاتورة مخططة فقط — ليست مدفوعة'), findsOneWidget);

    await tester.ensureVisible(find.text('مصروف'));
    await tester.tap(find.text('مصروف'));
    await tester.pumpAndSettle();
    expect(find.text('سجل المراجعات'), findsOneWidget);
    expect(find.text('معرّف الحركة'), findsOneWidget);
    await tester.ensureVisible(find.text('نسخة قبل التعديل'));
    await tester.tap(find.text('نسخة قبل التعديل'));
    await tester.pumpAndSettle();
    expect(find.text('الملاحظة السابقة'), findsOneWidget);
    expect(find.text('دواء سابق'), findsWidgets);
    expect(find.text('سعر التنفيذ التاريخي'), findsNothing);
  });
}
