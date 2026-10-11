import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/ui/ux_components.dart';

void main() {
  testWidgets('closed disclosures defer children and preserve expanded state',
      (tester) async {
    var mountCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: <Widget>[
              UxDisclosureCard(
                title: 'تفاصيل',
                icon: Icons.account_balance_wallet_outlined,
                child: _MountProbe(onMount: () => mountCount++),
              ),
            ],
          ),
        ),
      ),
    );

    expect(mountCount, 0);
    await tester.tap(find.text('تفاصيل'));
    await tester.pumpAndSettle();
    expect(mountCount, 1);

    await tester.tap(find.text('تفاصيل'));
    await tester.pumpAndSettle();
    expect(mountCount, 1);

    await tester.tap(find.text('تفاصيل'));
    await tester.pumpAndSettle();
    expect(mountCount, 1);
  });
}

class _MountProbe extends StatefulWidget {
  const _MountProbe({required this.onMount});
  final VoidCallback onMount;

  @override
  State<_MountProbe> createState() => _MountProbeState();
}

class _MountProbeState extends State<_MountProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const Text('Financial form');
}
