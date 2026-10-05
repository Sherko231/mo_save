import '../models/financial_event.dart';
import 'financial_ledger_storage.dart';

class CurrencyConversionService {
  CurrencyConversionService({FinancialLedgerStorage? ledger})
      : _ledger = ledger ?? FinancialLedgerStorage();

  final FinancialLedgerStorage _ledger;

  Future<FinancialEvent> recordConversion({
    required FinancialUnit sourceUnit,
    required FinancialUnit destinationUnit,
    required int sourceAmountMicros,
    required int destinationAmountMicros,
    required DateTime occurredAt,
    String? note,
  }) async {
    if (!_isSupportedCashUnit(sourceUnit) ||
        !_isSupportedCashUnit(destinationUnit) ||
        sourceUnit == destinationUnit) {
      throw ArgumentError('Only SYP <-> USD conversions are supported.');
    }
    if (sourceAmountMicros <= 0 || destinationAmountMicros <= 0) {
      throw ArgumentError('Conversion amounts must be greater than zero.');
    }

    final int sypMicros = sourceUnit == FinancialUnit.syp
        ? sourceAmountMicros
        : destinationAmountMicros;
    final int usdMicros = sourceUnit == FinancialUnit.usd
        ? sourceAmountMicros
        : destinationAmountMicros;
    final double executedSypPerUsd = sypMicros / usdMicros;

    final FinancialEvent event = FinancialEvent.create(
      type: FinancialEventType.currencyConversion,
      occurredAt: occurredAt,
      entries: <LedgerEntry>[
        LedgerEntry(
          unit: sourceUnit,
          amountMicros: -sourceAmountMicros,
        ),
        LedgerEntry(
          unit: destinationUnit,
          amountMicros: destinationAmountMicros,
        ),
      ],
      note: note,
      category: 'currencyConversion',
      executedSypPerUsd: executedSypPerUsd,
    );

    await _ledger.addCurrencyConversion(event);
    return event;
  }

  static bool _isSupportedCashUnit(FinancialUnit unit) {
    return unit == FinancialUnit.syp || unit == FinancialUnit.usd;
  }
}
