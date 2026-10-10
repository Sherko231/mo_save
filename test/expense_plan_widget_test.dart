import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/pages/expense_plan_sheet.dart';
import 'package:mo_save/services/expense_plan_storage.dart';
import 'package:mo_save/services/local_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('plan UI schedules future edits and cancellation without rewriting current',
      (tester) async {
    final temp = await Directory.systemTemp.createTemp('mo_save_plan_widget_');
    final db = LocalDatabase.forTesting(
      '${temp.path}${Platform.pathSeparator}widget.db',
    );
    addTearDown(() async {
      await db.close();
      await temp.delete(recursive: true);
    });
    final sqlite = await db.database;
    await sqlite.insert('app_metadata', <String, Object?>{
      'key': 'expense_plan_client_defaults_seeded_v1',
      'value': '1',
    });
    final plans = ExpensePlanStorage(database: db);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ExpensePlanSheet(storage: plans)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('الخطة فارغة'), findsOneWidget);
    await tester.tap(find.text('إضافة أول بند'));
    await tester.pumpAndSettle();

    final add = find.byType(TextField);
    expect(add, findsNWidgets(2));
    await tester.enterText(add.at(0), 'اختبار أمبير');
    await tester.enterText(add.at(1), '125000');
    await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
    await tester.pumpAndSettle();
    expect(find.text('اختبار أمبير'), findsOneWidget);

    await tester.tap(find.text('اختبار أمبير'));
    await tester.pumpAndSettle();
    expect(find.text('تعديل المصروف'), findsOneWidget);
    final edit = find.byType(TextField);
    await tester.enterText(edit.at(0), 'أمبير معدل');
    await tester.enterText(edit.at(1), '175000');
    await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
    await tester.pumpAndSettle();

    // The current month remains the original plan; the future edit is shown
    // as scheduled, not misrepresented as a retroactive historical change.
    expect(find.text('اختبار أمبير'), findsOneWidget);
    expect(find.textContaining('تغيير مجدول'), findsOneWidget);
    final now = DateTime.now();
    final current = await plans.loadItemsForMonth(now);
    final next = await plans.loadItemsForMonth(
      DateTime(now.year, now.month + 1),
    );
    expect(current.single.name, 'اختبار أمبير');
    expect(current.single.amountMicros, LedgerEntry.amountToMicros(125000));
    expect(next.single.name, 'أمبير معدل');
    expect(next.single.amountMicros, LedgerEntry.amountToMicros(175000));

    await tester.tap(find.byTooltip('حذف'));
    await tester.pumpAndSettle();
    expect(find.text('إيقاف بند متكرر'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'جدولة الإيقاف'));
    await tester.pumpAndSettle();

    expect(find.text('اختبار أمبير'), findsOneWidget);
    expect(find.textContaining('إيقاف مجدول'), findsOneWidget);
    expect((await plans.loadItemsForMonth(now)).single.name, 'اختبار أمبير');
    expect(await plans.loadItemsForMonth(DateTime(now.year, now.month + 1)),
        isEmpty);
  });
}
