import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/pages/fund_transfer_page.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/local_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MS-10 transfer screen confirms one real internal transfer',
      (tester) async {
    final directory = await Directory.systemTemp
        .createTemp('mosave_transfer_widget_');
    final database = LocalDatabase.forTesting(
      '${directory.path}${Platform.pathSeparator}transfer.db',
    );
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });
    final ledger = FinancialLedgerStorage(database: database);
    await ledger.addEvent(FinancialEvent.create(
      type: FinancialEventType.openingBalance,
      occurredAt: DateTime.now(),
      entries: <LedgerEntry>[
        LedgerEntry(
          unit: FinancialUnit.syp,
          amountMicros: LedgerEntry.amountToMicros(200000),
          fund: FinancialFund.savings,
        ),
      ],
    ));

    bool returnedSuccess = false;
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                final result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => FundTransferPage(ledger: ledger),
                  ),
                );
                returnedSuccess = result == true;
              },
              child: const Text('افتح التحويل'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('افتح التحويل'));
    await tester.pumpAndSettle();

    expect(find.text('نقل أموال موجودة بالفعل'), findsOneWidget);
    expect(find.textContaining('200,000'), findsWidgets);
    await tester.enterText(find.byType(TextField).first, '100000');
    await tester.pumpAndSettle();
    expect(find.textContaining('بعد التحويل'), findsOneWidget);
    await tester.tap(find.text('نقل المبلغ'));
    await tester.pumpAndSettle();
    expect(find.text('تأكيد تحويل بين الصناديق'), findsOneWidget);
    await tester.tap(find.text('تأكيد النقل'));
    await tester.pumpAndSettle();

    expect(returnedSuccess, isTrue);
    expect(await ledger.loadFundBalanceMicros(
      FinancialFund.savings, FinancialUnit.syp,
    ), LedgerEntry.amountToMicros(100000));
    expect(await ledger.loadFundBalanceMicros(
      FinancialFund.spending, FinancialUnit.syp,
    ), LedgerEntry.amountToMicros(100000));
    expect((await ledger.loadBalanceMicros())[FinancialUnit.syp],
        LedgerEntry.amountToMicros(200000));
    expect(await ledger.loadEvents(type: FinancialEventType.fundTransfer),
        hasLength(1));
    expect(await ledger.loadEvents(type: FinancialEventType.expense), isEmpty);
  });
}
