import '../models/financial_event.dart';
import 'financial_ledger_storage.dart';

/// One explicitly authorized SAME-CURRENCY reclassification of already owned
/// cash between Savings and Spending. It is never income, an expense, a gold
/// sale, or a foreign-exchange conversion.
class FundTransferService {
  FundTransferService({FinancialLedgerStorage? ledger})
      : _ledger = ledger ?? FinancialLedgerStorage();

  final FinancialLedgerStorage _ledger;

  Future<void> move({
    required FinancialFund source,
    required FinancialFund destination,
    required FinancialUnit unit,
    required int amountMicros,
    required DateTime occurredAt,
    required String requestId,
    String? note,
  }) async {
    if (source == destination ||
        (source != FinancialFund.savings &&
            source != FinancialFund.spending) ||
        (destination != FinancialFund.savings &&
            destination != FinancialFund.spending)) {
      throw ArgumentError('Choose distinct Savings and Spending funds.');
    }
    if (unit == FinancialUnit.goldGram) {
      throw ArgumentError('Physical gold must be sold, not transferred as cash.');
    }
    if (amountMicros <= 0) {
      throw ArgumentError('Transfer amount must be positive.');
    }
    final today = DateTime.now();
    final date = DateTime(
      occurredAt.year, occurredAt.month, occurredAt.day,
    );
    if (date.isAfter(DateTime(today.year, today.month, today.day))) {
      throw ArgumentError('Transfer cannot have a future date.');
    }
    final identity = requestId.trim();
    if (identity.isEmpty || identity.length > 128) {
      throw ArgumentError('Transfer request ID is invalid.');
    }
    final cleanNote = note?.trim();
    if (cleanNote != null && cleanNote.length > 300) {
      throw ArgumentError('Transfer note is too long.');
    }

    // Full duplicate validation and source-fund balance protection are
    // performed inside the ledger's own atomic transaction. The same form
    // identity remains safe even after the first transfer spent all source cash.
    await _ledger.transferFunds(
      id: 'fund_move_$identity',
      unit: unit,
      source: source,
      destination: destination,
      amountMicros: amountMicros,
      occurredAt: date,
      note: cleanNote?.isEmpty == true ? null : cleanNote,
    );
  }
}
