import '../models/financial_event.dart';

class FinancialFormat {
  const FinancialFormat._();

  static String assetBalance(int micros, FinancialUnit unit) {
    final double value = micros / LedgerEntry.microsPerUnit;
    switch (unit) {
      case FinancialUnit.usd:
        return '\$${_number(value, decimals: 2)}';
      case FinancialUnit.syp:
        return '${_number(value, decimals: 0)} ل.س';
      case FinancialUnit.sypNew:
        return '${_number(value, decimals: 0)} ل.س (جديدة)';
      case FinancialUnit.goldGram:
        return '${_number(value, decimals: 3)} غ';
    }
  }

  static String estimatedUsd(double value) =>
      '~\$${_number(value, decimals: 2)}';

  static String referenceRate(double value) =>
      '${_number(value, decimals: 2)} ل.س / 1 USD';

  static String goldReference(double value) =>
      '\$${_number(value, decimals: 2)} / غ';

  static String _number(double value, {required int decimals}) {
    final String fixed = value.toStringAsFixed(decimals);
    final List<String> parts = fixed.split('.');
    final bool negative = parts.first.startsWith('-');
    final String digits = negative ? parts.first.substring(1) : parts.first;
    final StringBuffer result = StringBuffer();

    if (negative) result.write('-');
    for (int i = 0; i < digits.length; i++) {
      final int remaining = digits.length - i;
      result.write(digits[i]);
      if (remaining > 1 && remaining % 3 == 1) result.write(',');
    }

    if (decimals > 0) {
      result.write('.${parts.length > 1 ? parts[1] : ''.padRight(decimals, '0')}');
    }
    return result.toString();
  }
}
