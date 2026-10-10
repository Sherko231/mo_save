import 'financial_event.dart';

/// One real received amount classified between the two funds and the
/// explicitly unallocated remainder. No second asset movement is created.
///
/// For a historic receipt with previously paid expenses, `alreadySpentMicros`
/// must remain in Unallocated on the incoming event so the linked expense can
/// debit that same bucket inside the atomic receipt transaction.
class ReceiptFundAllocation {
  ReceiptFundAllocation({
    required this.receivedMicros,
    required this.savingsMicros,
    required this.spendingMicros,
    this.alreadySpentMicros = 0,
  }) {
    if (receivedMicros <= 0 || savingsMicros < 0 ||
        spendingMicros < 0 || alreadySpentMicros < 0 ||
        alreadySpentMicros > receivedMicros ||
        savingsMicros > receivedMicros - alreadySpentMicros ||
        spendingMicros >
            receivedMicros - alreadySpentMicros - savingsMicros) {
      throw ArgumentError(
        'Savings, Spending and past expenses cannot exceed the receipt.',
      );
    }
  }

  final int receivedMicros;
  final int savingsMicros;
  final int spendingMicros;
  final int alreadySpentMicros;

  /// Income event's unallocated component includes past expenses that must
  /// subsequently be debited from Unallocated in the same transaction.
  int get incomingUnallocatedMicros =>
      receivedMicros - savingsMicros - spendingMicros;

  /// What is still truly held as Unallocated after linked past spending.
  int get remainingUnallocatedMicros =>
      incomingUnallocatedMicros - alreadySpentMicros;

  int get availableToAllocateMicros => receivedMicros - alreadySpentMicros;

  List<LedgerEntry> receiptEntries(FinancialUnit unit) => <LedgerEntry>[
    if (savingsMicros > 0)
      LedgerEntry(
        unit: unit,
        amountMicros: savingsMicros,
        fund: FinancialFund.savings,
      ),
    if (spendingMicros > 0)
      LedgerEntry(
        unit: unit,
        amountMicros: spendingMicros,
        fund: FinancialFund.spending,
      ),
    if (incomingUnallocatedMicros > 0)
      LedgerEntry(
        unit: unit,
        amountMicros: incomingUnallocatedMicros,
        fund: FinancialFund.unallocated,
      ),
  ];
}
