import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/pages/home_savings_fund_section.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/financial_settings_storage.dart';
import 'package:mo_save/services/local_database.dart';
import 'package:mo_save/services/savings_fund_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MS-12 Savings dashboard shows real cash and live fund transfer',
      (tester) async {
    final directory = await Directory.systemTemp
        .createTemp('mosave_savings_widget_');
    final database = LocalDatabase.forTesting(
      '${directory.path}${Platform.pathSeparator}savings.db',
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
          unit: FinancialUnit.usd,
          amountMicros: LedgerEntry.amountToMicros(200),
          fund: FinancialFund.savings,
        ),
        LedgerEntry(
          unit: FinancialUnit.usd,
          amountMicros: LedgerEntry.amountToMicros(50),
          fund: FinancialFund.unallocated,
        ),
      ],
    ));

    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: HomeSavingsFundSection(
              refreshToken: 0,
              service: SavingsFundService(
                ledger: ledger,
                settings: FinancialSettingsStorage(database: database),
                database: database,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('صندوق الادخار الحقيقي'), findsOneWidget);
    expect(find.text('القيمة التقريبية للادخار فقط'), findsOneWidget);
    expect(find.text('≈ \$200'), findsOneWidget);
    expect(find.text(
      'من إجمالي ممتلكاتك بهالعملة: \$250',
    ), findsOneWidget);
    expect(find.text(
      'في أموال غير موزّعة، ما بتنحسب ادخار لحتى تخصّصها أنت.',
    ), findsOneWidget);

    await ledger.transferFunds(
      unit: FinancialUnit.usd,
      source: FinancialFund.savings,
      destination: FinancialFund.spending,
      amountMicros: LedgerEntry.amountToMicros(80),
      occurredAt: DateTime.now(),
    );
    await tester.pumpAndSettle();

    expect(find.text('≈ \$120'), findsOneWidget);
    expect(find.text(
      'من إجمالي ممتلكاتك بهالعملة: \$250',
    ), findsOneWidget);
    expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
      LedgerEntry.amountToMicros(250));
    expect(await ledger.loadFundBalanceMicros(
      FinancialFund.savings, FinancialUnit.usd,
    ), LedgerEntry.amountToMicros(120));
  });
}
