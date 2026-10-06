import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/pages/expense_plan_sheet.dart';
import 'package:mo_save/services/expense_plan_storage.dart';
import 'package:mo_save/services/local_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('expense plan supports create edit and delete', (tester) async {
    final tempDirectory =
        await Directory.systemTemp.createTemp('mo_save_expense_widget_');
    final database = LocalDatabase.forTesting(
      '${tempDirectory.path}${Platform.pathSeparator}widget.db',
    );

    addTearDown(() async {
      await database.close();
      await tempDirectory.delete(recursive: true);
    });

    final sqlite = await database.database;
    await sqlite.insert('app_metadata', <String, Object?>{
      'key': 'expense_plan_client_defaults_seeded_v1',
      'value': '1',
    });
    final storage = ExpensePlanStorage(database: database);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpensePlanSheet(storage: storage),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('لا توجد مصاريف مخططة'), findsOneWidget);

    await tester.tap(find.text('إضافة مصروف شهري'));
    await tester.pumpAndSettle();
    expect(find.text('إضافة مصروف شهري'), findsWidgets);

    final addFields = find.byType(TextField);
    expect(addFields, findsNWidgets(2));
    await tester.enterText(addFields.at(0), 'اختبار');
    await tester.enterText(addFields.at(1), '125000');
    await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('اختبار'), findsOneWidget);

    await tester.tap(find.text('اختبار'));
    await tester.pumpAndSettle();
    expect(find.text('تعديل المصروف'), findsOneWidget);

    final editFields = find.byType(TextField);
    await tester.enterText(editFields.at(0), 'اختبار معدل');
    await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('اختبار معدل'), findsOneWidget);
    expect(find.text('اختبار'), findsNothing);

    await tester.tap(find.byTooltip('حذف'));
    await tester.pumpAndSettle();
    expect(find.text('حذف المصروف'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'حذف'));
    await tester.pumpAndSettle();

    expect(find.text('اختبار معدل'), findsNothing);
    expect(find.textContaining('لا توجد مصاريف مخططة'), findsOneWidget);
  });
}
