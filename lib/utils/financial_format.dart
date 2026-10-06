import '../models/financial_event.dart';

class FinancialFormat {
  const FinancialFormat._();

  static String assetBalance(int micros, FinancialUnit unit) {
    return amount(micros / LedgerEntry.microsPerUnit, unit);
  }

  static String amount(num value, FinancialUnit unit) {
    switch (unit) {
      case FinancialUnit.usd:
        return '\$${number(value, maxDecimals: 2)}';
      case FinancialUnit.syp:
        return '${number(value, maxDecimals: 0)} ل.س';
      case FinancialUnit.sypNew:
        return '${number(value, maxDecimals: 0)} ل.س جديدة';
      case FinancialUnit.goldGram:
        return '${number(value, maxDecimals: 3)} غ';
    }
  }

  static String estimatedUsd(double value) =>
      '≈ \$${number(value, maxDecimals: 2)}';

  static String referenceRate(double value) =>
      '1 دولار = ${number(value, maxDecimals: 2)} ل.س';

  static String goldReference(double value) =>
      '\$${number(value, maxDecimals: 2)} لكل غرام';

  static String percentage(num value) =>
      '${number(value, maxDecimals: 1)}٪';

  static String progress(double value) => percentage(value * 100);

  static String date(DateTime value) {
    final DateTime local = value.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }

  static String dateTime(DateTime value) {
    final DateTime local = value.toLocal();
    return '${date(local)} ${_two(local.hour)}:${_two(local.minute)}';
  }

  static String editableAmount(int micros, FinancialUnit unit) {
    final double value = micros / LedgerEntry.microsPerUnit;
    final int decimals = switch (unit) {
      FinancialUnit.goldGram => 3,
      FinancialUnit.usd => 2,
      FinancialUnit.syp => 0,
      FinancialUnit.sypNew => 0,
    };
    if (decimals == 0) return value.round().toString();
    return _trimFraction(value.toStringAsFixed(decimals));
  }

  static String unitLabel(FinancialUnit unit) {
    return switch (unit) {
      FinancialUnit.usd => 'الدولار الأمريكي',
      FinancialUnit.syp => 'الليرة السورية',
      FinancialUnit.sypNew => 'الليرة السورية الجديدة',
      FinancialUnit.goldGram => 'الذهب',
    };
  }

  static String unitShort(FinancialUnit unit) {
    return switch (unit) {
      FinancialUnit.usd => '\$',
      FinancialUnit.syp => 'ل.س',
      FinancialUnit.sypNew => 'ل.س جديدة',
      FinancialUnit.goldGram => 'غ',
    };
  }

  static String number(
    num value, {
    int maxDecimals = 2,
    int minDecimals = 0,
  }) {
    final double numeric = value.toDouble();
    String fixed = numeric.toStringAsFixed(maxDecimals);
    if (maxDecimals > minDecimals) {
      final List<String> parts = fixed.split('.');
      if (parts.length == 2) {
        String fraction = parts[1];
        while (fraction.length > minDecimals && fraction.endsWith('0')) {
          fraction = fraction.substring(0, fraction.length - 1);
        }
        fixed = fraction.isEmpty ? parts[0] : '${parts[0]}.$fraction';
      }
    }

    final List<String> parts = fixed.split('.');
    final bool negative = parts.first.startsWith('-');
    final String digits = negative ? parts.first.substring(1) : parts.first;
    final StringBuffer result = StringBuffer();

    if (negative) result.write('-');
    for (int index = 0; index < digits.length; index++) {
      final int remaining = digits.length - index;
      result.write(digits[index]);
      if (remaining > 1 && remaining % 3 == 1) result.write(',');
    }

    if (parts.length > 1 && parts[1].isNotEmpty) {
      result.write('.${parts[1]}');
    }
    return result.toString();
  }

  static String _trimFraction(String value) {
    if (!value.contains('.')) return value;
    String result = value;
    while (result.endsWith('0')) {
      result = result.substring(0, result.length - 1);
    }
    if (result.endsWith('.')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
