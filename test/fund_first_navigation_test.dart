import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mo_save/main.dart';
import 'package:mo_save/pages/home_page.dart';

class _FundTestContent extends StatelessWidget {
  const _FundTestContent({required this.view, required this.active});
  final HomeFinancialView view;
  final bool active;
  @override
  Widget build(BuildContext context) {
    final savings = view == HomeFinancialView.savings;
    return Scaffold(
      body: Center(
        child: Text(savings
            ? 'المحتوى: الادخار الحقيقي'
            : 'المحتوى: المصاريف المتاحة'),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget app() => MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: AppShell(
        homeBuilder: (view, active) =>
            _FundTestContent(view: view, active: active),
        settingsBody: const Scaffold(
          body: Center(child: Text('بيانات الإعدادات والنسخ الاحتياطي')),
        ),
      ),
    ),
  );

  testWidgets('MS-17 mobile primary destinations are Savings / Spending / Settings',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('الادخار'), findsOneWidget);
    expect(find.text('المصاريف'), findsOneWidget);
    expect(find.text('الإعدادات'), findsOneWidget);
    expect(find.text('المحتوى: الادخار الحقيقي'), findsOneWidget);
    expect(find.text('المحتوى: المصاريف المتاحة'), findsNothing);
    expect(find.text('الأهداف'), findsNothing);

    await tester.tap(find.text('المصاريف'));
    await tester.pumpAndSettle();
    expect(find.text('المحتوى: المصاريف المتاحة'), findsOneWidget);
    expect(find.text('المحتوى: الادخار الحقيقي'), findsNothing);

    await tester.tap(find.text('الإعدادات'));
    await tester.pumpAndSettle();
    expect(find.text('بيانات الإعدادات والنسخ الاحتياطي'), findsOneWidget);

    await tester.tap(find.text('الادخار'));
    await tester.pumpAndSettle();
    expect(find.text('المحتوى: الادخار الحقيقي'), findsOneWidget);
  });

  testWidgets('MS-17 wide layout uses an adaptive RTL NavigationRail',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('الادخار'), findsOneWidget);
    await tester.tap(find.text('المصاريف'));
    await tester.pumpAndSettle();
    expect(find.text('المحتوى: المصاريف المتاحة'), findsOneWidget);
  });
}
