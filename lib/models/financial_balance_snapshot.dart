import 'financial_event.dart';

class FinancialBalanceSnapshot {
  FinancialBalanceSnapshot({
    required Map<FinancialUnit, int> balancesMicros,
    required this.referenceSypPerUsd,
    required this.goldUsdPerGram,
  }) : balancesMicros = Map<FinancialUnit, int>.unmodifiable(
          <FinancialUnit, int>{
            for (final FinancialUnit unit in FinancialUnit.values)
              unit: balancesMicros[unit] ?? 0,
          },
        );

  final Map<FinancialUnit, int> balancesMicros;
  final double referenceSypPerUsd;
  final double goldUsdPerGram;

  int balanceMicros(FinancialUnit unit) => balancesMicros[unit] ?? 0;

  double balance(FinancialUnit unit) =>
      balanceMicros(unit) / LedgerEntry.microsPerUnit;

  double get usdBalance => balance(FinancialUnit.usd);
  double get sypBalance => balance(FinancialUnit.syp);
  double get sypNewBalance => balance(FinancialUnit.sypNew);
  double get goldGrams => balance(FinancialUnit.goldGram);

  double? get estimatedSypUsd {
    if (sypBalance == 0) return 0;
    if (referenceSypPerUsd <= 0) return null;
    return sypBalance / referenceSypPerUsd;
  }

  double? get estimatedGoldUsd {
    if (goldGrams == 0) return 0;
    if (goldUsdPerGram <= 0) return null;
    return goldGrams * goldUsdPerGram;
  }

  /// SYP (N) deliberately has no implicit conversion rule.
  ///
  /// The product has not defined a trustworthy SYP (N) ↔ USD reference rate,
  /// so a non-zero SYP (N) balance remains visible as a separate asset and
  /// makes the combined estimate incomplete instead of silently guessing.
  bool get hasUnvaluedSypNew => sypNewBalance != 0;

  bool get hasUnvaluedSyp => sypBalance != 0 && estimatedSypUsd == null;
  bool get hasUnvaluedGold => goldGrams != 0 && estimatedGoldUsd == null;

  bool get isEstimatedTotalComplete =>
      !hasUnvaluedSyp && !hasUnvaluedSypNew && !hasUnvaluedGold;

  double? get estimatedTotalUsd {
    if (!isEstimatedTotalComplete) return null;
    return usdBalance + (estimatedSypUsd ?? 0) + (estimatedGoldUsd ?? 0);
  }

  List<String> get valuationWarnings {
    final List<String> warnings = <String>[];
    if (hasUnvaluedSyp) {
      warnings.add('أدخل سعر صرف الدولار مقابل الليرة السورية في الإعدادات.');
    }
    if (hasUnvaluedGold) {
      warnings.add('أدخل سعر غرام الذهب بالدولار في الإعدادات.');
    }
    if (hasUnvaluedSypNew) {
      warnings.add(
        'رصيد الليرة السورية الجديدة ظاهر بشكل منفصل ولا يدخل في التقدير حتى يتم تعريف سعر مرجعي لها.',
      );
    }
    return warnings;
  }
}
