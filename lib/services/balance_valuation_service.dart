import '../models/financial_balance_snapshot.dart';
import 'financial_ledger_storage.dart';
import 'financial_settings_storage.dart';

class BalanceValuationService {
  BalanceValuationService({
    FinancialLedgerStorage? ledgerStorage,
    FinancialSettingsStorage? settingsStorage,
  })  : _ledgerStorage = ledgerStorage ?? FinancialLedgerStorage(),
        _settingsStorage = settingsStorage ?? FinancialSettingsStorage();

  final FinancialLedgerStorage _ledgerStorage;
  final FinancialSettingsStorage _settingsStorage;

  Future<FinancialBalanceSnapshot> loadSnapshot() async {
    final balances = await _ledgerStorage.loadBalanceMicros();
    final settings = await _settingsStorage.loadSettings();

    return FinancialBalanceSnapshot(
      balancesMicros: balances,
      referenceSypPerUsd: settings.referenceSypPerUsd,
      goldUsdPerGram: settings.goldUsdPerGram,
    );
  }
}
