import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/saving_challenge.dart';
import 'package:mo_save/pages/challenge_detail_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MS-13 legacy grid needs explicit owner-backed reconciliation',
      (tester) async {
    final base = SavingChallenge.create(
      id: 'widget-old', name: 'سفر', targetAmount: 100,
      currency: ChallengeCurrency.usd,
      sequence: ChallengeSequence.ordered, cellCount: 1,
    );
    SavingChallenge displayed = SavingChallenge(
      id: base.id, name: base.name, targetAmount: base.targetAmount,
      currency: base.currency, sequence: base.sequence,
      cellCount: base.cellCount,
      cells: <ChallengeCell>[
        base.cells.single.copyWith(isCompleted: true),
      ],
      // Deliberately missing verified backing, as in v9-v11.
    );
    bool? chosen;

    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: StatefulBuilder(
            builder: (context, updateParent) => ChallengeDetailPage(
              challenge: displayed,
              onChanged: (updated) async => false,
              onReconcile: (keepMarks) async {
                chosen = keepMarks;
                if (keepMarks) {
                  updateParent(() {
                    displayed = SavingChallenge(
                      id: displayed.id, name: displayed.name,
                      targetAmount: displayed.targetAmount,
                      currency: displayed.currency,
                      sequence: displayed.sequence,
                      cellCount: displayed.cellCount,
                      cells: displayed.cells,
                      backedAmountMicros: 100000000,
                    );
                  });
                }
                return keepMarks;
              },
              onBack: () {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('خانات قديمة غير مثبّتة من رصيد الادخار'), findsNothing);
    expect(find.text('هذا الهدف قديم وخاناته غير موثّقة بأموال حقيقية.'),
        findsOneWidget);
    expect(find.text('هدف مكتمل ومغطّى'), findsNothing);
    await tester.tap(find.text('تثبيت الخانات أو تصفيرها'));
    await tester.pumpAndSettle();
    expect(find.text('توثيق ادخار الهدف القديم'), findsOneWidget);
    expect(find.text('تصفير الخانات القديمة'), findsOneWidget);
    expect(find.text('تثبيت الرصيد من الادخار'), findsOneWidget);
    await tester.tap(find.text('تثبيت الرصيد من الادخار'));
    await tester.pumpAndSettle();

    expect(chosen, isTrue);
    expect(find.text('هدف مكتمل ومغطّى'), findsOneWidget);
    expect(find.text('هذا الهدف قديم وخاناته غير موثّقة بأموال حقيقية.'),
        findsNothing);
  });
}
