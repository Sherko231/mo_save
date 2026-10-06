import '../models/saving_challenge.dart';
import 'financial_format.dart';

class ChallengeFormat {
  const ChallengeFormat._();

  static String sequenceLabel(ChallengeSequence sequence) {
    return switch (sequence) {
      ChallengeSequence.ordered => 'تصاعدي',
      ChallengeSequence.random => 'عشوائي',
      ChallengeSequence.reversed => 'تنازلي',
    };
  }

  static String currencyLabel(ChallengeCurrency currency) {
    return switch (currency) {
      ChallengeCurrency.usd => 'الدولار الأمريكي',
      ChallengeCurrency.syp => 'الليرة السورية',
      ChallengeCurrency.sypNew => 'الليرة السورية الجديدة',
    };
  }

  static String currencyShort(ChallengeCurrency currency) {
    return switch (currency) {
      ChallengeCurrency.usd => '\$',
      ChallengeCurrency.syp => 'ل.س',
      ChallengeCurrency.sypNew => 'ل.س جديدة',
    };
  }

  static String amount(num amount, ChallengeCurrency currency) {
    return switch (currency) {
      ChallengeCurrency.usd => '\$${FinancialFormat.number(amount, maxDecimals: 2)}',
      ChallengeCurrency.syp =>
        '${FinancialFormat.number(amount, maxDecimals: 0)} ل.س',
      ChallengeCurrency.sypNew =>
        '${FinancialFormat.number(amount, maxDecimals: 0)} ل.س جديدة',
    };
  }

  static String cellStep(ChallengeCurrency currency) =>
      FinancialFormat.number(currency.cellStep, maxDecimals: 0);
}
