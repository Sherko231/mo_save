import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/pages/funds_at_glance.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';

class _BalancesStub extends FinancialLedgerStorage {
  int loads = 0;
  @override
  Future<Map<FinancialFund, Map<FinancialUnit, int>>>
      loadFundBalancesMicros() async {
    loads++;
    return <FinancialFund, Map<FinancialUnit, int>>{
      FinancialFund.savings: <FinancialUnit, int>{
        FinancialUnit.usd: LedgerEntry.amountToMicros(200),
        FinancialUnit.syp: LedgerEntry.amountToMicros(500000),
        FinancialUnit.sypNew: 0,
        FinancialUnit.goldGram: LedgerEntry.amountToMicros(3),
      },
      FinancialFund.spending: <FinancialUnit, int>{
        FinancialUnit.usd: LedgerEntry.amountToMicros(80),
        FinancialUnit.syp: LedgerEntry.amountToMicros(170000),
        FinancialUnit.sypNew: 0,
        FinancialUnit.goldGram: 0,
      },
      FinancialFund.unallocated: <FinancialUnit, int>{
        FinancialUnit.usd: LedgerEntry.amountToMicros(20),
        FinancialUnit.syp: 0,
        FinancialUnit.sypNew: 0,
        FinancialUnit.goldGram: 0,
      },
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MS-17 overview uses actual per-unit funds, no conversion or unallocated savings',
      (tester) async {
    final stub = _BalancesStub();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(children: <Widget>[
          FundsAtGlance(refreshToken: 0, ledger: stub),
        ]),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('رصيد اليوم حسب الصندوق'), findsOneWidget);
    expect(find.text('ادخار حقيقي'), findsWidgets);
    expect(find.text('متاح للمصاريف'), findsWidgets);
    expect(find.textContaining('غير موزّعين'), findsOneWidget);
    expect(find.textContaining('ذهب الادخار:'), findsOneWidget);
    expect(find.textContaining('ما منجمع الدولار والليرة'), findsOneWidget);
    expect(find.text('الليرة السورية الجديدة'), findsNothing);
    expect(stub.loads, 1);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(children: <Widget>[
          FundsAtGlance(refreshToken: 1, ledger: stub),
        ]),
      )),
    ));
    await tester.pumpAndSettle();
    expect(stub.loads, 2);
  });
}
