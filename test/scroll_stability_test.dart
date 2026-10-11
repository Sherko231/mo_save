import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mo_save/ui/app_scroll_behavior.dart';

void main() {
  testWidgets('downward swipe returns to content instead of stretching a blank canvas',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const MoSaveScrollBehavior(),
        home: Scaffold(
          body: ListView(
            controller: controller,
            children: const <Widget>[
              SizedBox(height: 200, child: Text('الادخار')),
              SizedBox(height: 500, child: Text('الأرصدة')),
              SizedBox(height: 500, child: Text('الأهداف')),
              SizedBox(height: 500, child: Text('المصاريف')),
            ],
          ),
        ),
      ),
    );

    final context = tester.element(find.byType(ListView));
    expect(
      ScrollConfiguration.of(context).getScrollPhysics(context),
      isA<ClampingScrollPhysics>(),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));

    await tester.drag(find.byType(ListView), const Offset(0, 1500));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    expect(find.text('الادخار'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
