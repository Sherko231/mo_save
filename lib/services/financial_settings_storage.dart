import 'package:sqflite/sqflite.dart';

import '../models/financial_settings.dart';
import 'local_database.dart';

class FinancialSettingsStorage {
  FinancialSettingsStorage({LocalDatabase? database})
      : _database = database ?? LocalDatabase.instance;

  final LocalDatabase _database;

  Future<FinancialSettings> loadSettings() async {
    final Database database = await _database.database;
    final List<Map<String, Object?>> rows = await database.query(
      'financial_settings',
      where: 'id = 1',
      limit: 1,
    );

    if (rows.isEmpty) {
      const FinancialSettings defaults = FinancialSettings.clientDefaults;
      await saveSettings(defaults);
      return defaults;
    }

    final Map<String, Object?> row = rows.first;
    return FinancialSettings(
      weeklySypIncome: (row['weekly_syp_income']! as num).toInt(),
      weeklyPayday: (row['weekly_payday']! as num).toInt(),
      monthlyUsdIncome: (row['monthly_usd_income']! as num).toDouble(),
      monthlyPayday: (row['monthly_payday']! as num).toInt(),
      referenceSypPerUsd: (row['reference_syp_per_usd']! as num).toDouble(),
      goldUsdPerGram: (row['gold_usd_per_gram']! as num).toDouble(),
      weeklyExpensesAllocation:
          (row['weekly_expenses_allocation']! as num).toInt(),
      weeklySavingsAllocation:
          (row['weekly_savings_allocation']! as num).toInt(),
    );
  }

  Future<void> saveSettings(FinancialSettings settings) async {
    final Database database = await _database.database;
    await database.insert(
      'financial_settings',
      <String, Object?>{
        'id': 1,
        'weekly_syp_income': settings.weeklySypIncome,
        'weekly_payday': settings.weeklyPayday,
        'monthly_usd_income': settings.monthlyUsdIncome,
        'monthly_payday': settings.monthlyPayday,
        'reference_syp_per_usd': settings.referenceSypPerUsd,
        'gold_usd_per_gram': settings.goldUsdPerGram,
        'weekly_expenses_allocation': settings.weeklyExpensesAllocation,
        'weekly_savings_allocation': settings.weeklySavingsAllocation,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
