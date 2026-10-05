class FinancialSettings {
  const FinancialSettings({
    required this.weeklySypIncome,
    required this.weeklyPayday,
    required this.monthlyUsdIncome,
    required this.monthlyPayday,
    required this.referenceSypPerUsd,
    required this.goldUsdPerGram,
    required this.weeklyExpensesAllocation,
    required this.weeklySavingsAllocation,
  });

  static const FinancialSettings clientDefaults = FinancialSettings(
    weeklySypIncome: 885000,
    weeklyPayday: DateTime.thursday,
    monthlyUsdIncome: 300,
    monthlyPayday: 1,
    referenceSypPerUsd: 0,
    goldUsdPerGram: 0,
    weeklyExpensesAllocation: 540000,
    weeklySavingsAllocation: 345000,
  );

  final int weeklySypIncome;
  final int weeklyPayday;
  final double monthlyUsdIncome;
  final int monthlyPayday;
  final double referenceSypPerUsd;
  final double goldUsdPerGram;
  final int weeklyExpensesAllocation;
  final int weeklySavingsAllocation;

  int get weeklyAllocatedTotal =>
      weeklyExpensesAllocation + weeklySavingsAllocation;

  int get weeklyUnallocatedAmount => weeklySypIncome - weeklyAllocatedTotal;
}
