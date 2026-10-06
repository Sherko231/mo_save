import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_balance_snapshot.dart';
import 'package:mo_save/models/financial_event.dart';

void main() {
  group('FinancialBalanceSnapshot', () {
    test('combines USD, SYP and gold only through reference valuation', () {
      final snapshot = FinancialBalanceSnapshot(
        balancesMicros: <FinancialUnit, int>{
          FinancialUnit.usd: LedgerEntry.amountToMicros(300),
          FinancialUnit.syp: LedgerEntry.amountToMicros(1500000),
          FinancialUnit.goldGram: LedgerEntry.amountToMicros(2),
        },
        referenceSypPerUsd: 15000,
        goldUsdPerGram: 100,
      );

      expect(snapshot.usdBalance, 300);
      expect(snapshot.estimatedSypUsd, 100);
      expect(snapshot.estimatedGoldUsd, 200);
      expect(snapshot.estimatedTotalUsd, 600);
      expect(snapshot.isEstimatedTotalComplete, isTrue);
      expect(snapshot.valuationWarnings, isEmpty);
    });

    test('missing SYP reference makes combined estimate incomplete', () {
      final snapshot = FinancialBalanceSnapshot(
        balancesMicros: <FinancialUnit, int>{
          FinancialUnit.syp: LedgerEntry.amountToMicros(1000000),
        },
        referenceSypPerUsd: 0,
        goldUsdPerGram: 0,
      );

      expect(snapshot.estimatedSypUsd, isNull);
      expect(snapshot.estimatedTotalUsd, isNull);
      expect(snapshot.hasUnvaluedSyp, isTrue);
      expect(snapshot.valuationWarnings, hasLength(1));
    });

    test('non-zero SYP (N) remains separate and blocks guessed total', () {
      final snapshot = FinancialBalanceSnapshot(
        balancesMicros: <FinancialUnit, int>{
          FinancialUnit.usd: LedgerEntry.amountToMicros(50),
          FinancialUnit.sypNew: LedgerEntry.amountToMicros(1000),
        },
        referenceSypPerUsd: 15000,
        goldUsdPerGram: 80,
      );

      expect(snapshot.sypNewBalance, 1000);
      expect(snapshot.hasUnvaluedSypNew, isTrue);
      expect(snapshot.estimatedTotalUsd, isNull);
      expect(snapshot.valuationWarnings.single, contains('الليرة السورية الجديدة'));
    });

    test('zero unpriced assets do not make the estimate incomplete', () {
      final snapshot = FinancialBalanceSnapshot(
        balancesMicros: <FinancialUnit, int>{
          FinancialUnit.usd: LedgerEntry.amountToMicros(25),
        },
        referenceSypPerUsd: 0,
        goldUsdPerGram: 0,
      );

      expect(snapshot.estimatedTotalUsd, 25);
      expect(snapshot.isEstimatedTotalComplete, isTrue);
    });
  });
}
