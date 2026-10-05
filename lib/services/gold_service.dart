import '../models/financial_event.dart';
import 'financial_ledger_storage.dart';

class GoldService {
  GoldService({FinancialLedgerStorage? ledger})
      : _ledger = ledger ?? FinancialLedgerStorage();

  final FinancialLedgerStorage _ledger;

  Future<FinancialEvent> recordPurchase({
    required FinancialUnit sourceUnit,
    required int cashPaidMicros,
    required int goldReceivedMicros,
    required DateTime occurredAt,
    String? note,
  }) async {
    if (!_isSupportedCashUnit(sourceUnit)) {
      throw ArgumentError('Gold purchases support USD or SYP cash only.');
    }
    if (cashPaidMicros <= 0 || goldReceivedMicros <= 0) {
      throw ArgumentError('Cash paid and gold received must be greater than zero.');
    }

    final FinancialEvent event = FinancialEvent.create(
      type: FinancialEventType.goldPurchase,
      occurredAt: occurredAt,
      entries: <LedgerEntry>[
        LedgerEntry(
          unit: sourceUnit,
          amountMicros: -cashPaidMicros,
        ),
        LedgerEntry(
          unit: FinancialUnit.goldGram,
          amountMicros: goldReceivedMicros,
        ),
      ],
      note: note,
      category: 'gold',
    );

    await _ledger.addGoldPurchase(event);
    return event;
  }

  /// Foundation for a later sale UI: one event removes gold and adds the
  /// cash actually received, with the same in-transaction balance protection.
  Future<FinancialEvent> recordSale({
    required FinancialUnit destinationUnit,
    required int goldSoldMicros,
    required int cashReceivedMicros,
    required DateTime occurredAt,
    String? note,
  }) async {
    if (!_isSupportedCashUnit(destinationUnit)) {
      throw ArgumentError('Gold sales support USD or SYP cash only.');
    }
    if (goldSoldMicros <= 0 || cashReceivedMicros <= 0) {
      throw ArgumentError('Gold sold and cash received must be greater than zero.');
    }

    final FinancialEvent event = FinancialEvent.create(
      type: FinancialEventType.goldSale,
      occurredAt: occurredAt,
      entries: <LedgerEntry>[
        LedgerEntry(
          unit: FinancialUnit.goldGram,
          amountMicros: -goldSoldMicros,
        ),
        LedgerEntry(
          unit: destinationUnit,
          amountMicros: cashReceivedMicros,
        ),
      ],
      note: note,
      category: 'gold',
    );

    await _ledger.addGoldSale(event);
    return event;
  }

  /// Records an explicit gold-quantity correction without pretending it was a
  /// purchase or sale. A negative correction cannot take holdings below zero.
  /// The correction UI itself belongs to the later history/correction task.
  Future<FinancialEvent> recordCorrection({
    required int goldDeltaMicros,
    required DateTime occurredAt,
    String? note,
  }) async {
    if (goldDeltaMicros == 0) {
      throw ArgumentError('Gold correction must be non-zero.');
    }

    final FinancialEvent event = FinancialEvent.create(
      type: FinancialEventType.manualAdjustment,
      occurredAt: occurredAt,
      entries: <LedgerEntry>[
        LedgerEntry(
          unit: FinancialUnit.goldGram,
          amountMicros: goldDeltaMicros,
        ),
      ],
      note: note,
      category: 'goldCorrection',
    );

    await _ledger.addGoldCorrection(event);
    return event;
  }

  static bool _isSupportedCashUnit(FinancialUnit unit) {
    return unit == FinancialUnit.usd || unit == FinancialUnit.syp;
  }
}
