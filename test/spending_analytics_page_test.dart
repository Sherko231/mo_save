import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/pages/spending_analytics_page.dart';
import 'package:mo_save/services/expense_plan_storage.dart';
import 'package:mo_save/services/expense_service.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/local_database.dart';
import 'package:mo_save/services/spending_analytics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MS-11 Arabic category drill-down preserves actual payment note',
      (tester) async {
    final directory = await Directory.systemTemp
        .createTemp('mosave_analytics_widget_');
    final db = LocalDatabase.forTesting(
      '${directory.path}${Platform.pathSeparator}analytics.db',
    );
    addTearDown(() async {
      await db.close();
      await directory.delete(recursive: true);
    });
    final ledger = FinancialLedgerStorage(database: db);
    await (await db.database).insert('app_metadata', <String, Object?>{
      'key': 'expense_plan_client_defaults_seeded_v1',
      'value': '1',
    });
    final expense = ExpenseService(
      planStorage: ExpensePlanStorage(database: db),
      ledgerStorage: ledger,
    );
    final now = DateTime.now();
    await ledger.addEvent(FinancialEvent.create(
      type: FinancialEventType.openingBalance,
      occurredAt: now,
      entries: <LedgerEntry>[
        LedgerEntry(
          unit: FinancialUnit.syp,
          amountMicros: LedgerEntry.amountToMicros(180000),
          fund: FinancialFund.spending,
        ),
      ],
    ));
    await expense.logExpense(
      amountMicros: LedgerEntry.amountToMicros(80000),
      unit: FinancialUnit.syp,
      occurredAt: now,
      category: 'نزهة',
      note: 'عشاء ومواصلات',
      sourceFund: FinancialFund.spending,
    );
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: SpendingAnalyticsPage(
          initialMonth: now,
          service: SpendingAnalyticsService(expenses: expense),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('تحليلات المصاريف الشهرية'), findsOneWidget);
    expect(find.text('إجمالي المصاريف الفعلية'), findsOneWidget);
    expect(find.text('نزهة'), findsOneWidget);
    final category = find.text('نزهة');
    await tester.ensureVisible(category);
    await tester.pumpAndSettle();
    await tester.tap(category);
    await tester.pumpAndSettle();

    expect(find.text('تفاصيل: نزهة'), findsOneWidget);
    expect(find.text('الملاحظة: عشاء ومواصلات'), findsOneWidget);
    expect(find.textContaining('رقم الحركة:'), findsOneWidget);
    expect(find.textContaining('المصدر: المصاريف'), findsOneWidget);
  });
}
