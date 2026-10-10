import '../models/financial_event.dart';
import '../models/receipt_fund_allocation.dart';
import 'financial_ledger_storage.dart';

/// Sources of a one-off cash inflow. These are not recurring salaries,
/// investment conversions or the resale of an already-tracked asset.
enum ManualInflowKind {
  gift,
  itemSale,
  bonus,
  sideWork,
  otherIncome,
  openingBalance,
}

extension ManualInflowKindDetails on ManualInflowKind {
  bool get isOpeningBalance => this == ManualInflowKind.openingBalance;

  String get categoryLabel => switch (this) {
    ManualInflowKind.gift => 'هدية',
    ManualInflowKind.itemSale => 'بيع غرض غير مسجل كأصل',
    ManualInflowKind.bonus => 'مكافأة',
    ManualInflowKind.sideWork => 'عمل جانبي',
    ManualInflowKind.otherIncome => 'دخل إضافي',
    ManualInflowKind.openingBalance => 'رصيد افتتاحي سابق',
  };
}

/// Stores actual cash receipts in the canonical ledger. An opening balance
/// represents existing money not recorded yet: it is NOT reportable income.
/// An initial fund choice classifies that single receipt, not a second deposit.
class ManualInflowService {
  ManualInflowService({FinancialLedgerStorage? ledger})
      : _ledger = ledger ?? FinancialLedgerStorage();

  final FinancialLedgerStorage _ledger;

  Future<FinancialEvent> record({
    required ManualInflowKind kind,
    required FinancialUnit unit,
    required int amountMicros,
    required DateTime occurredAt,
    required FinancialFund fund,
    int? savingsMicros,
    int? spendingMicros,
    String? source,
    String? note,
    String? requestId,
    bool untrackedAssetSaleConfirmed = false,
  }) async {
    if (kind == ManualInflowKind.itemSale &&
        !untrackedAssetSaleConfirmed) {
      throw ArgumentError(
        'Only sales of previously untracked items can be recorded as income. '
        'Use asset trades for tracked gold or currency.',
      );
    }
    if (unit == FinancialUnit.goldGram) {
      throw ArgumentError('Manual receipts are cash-only. Use a gold trade.');
    }
    if (amountMicros <= 0) {
      throw ArgumentError.value(amountMicros, 'amountMicros',
          'Receipt or opening balance must be greater than zero.');
    }
    final today = DateTime.now();
    final occurredDay = DateTime(
      occurredAt.year, occurredAt.month, occurredAt.day, 12,
    );
    if (occurredDay.isAfter(DateTime(
      today.year, today.month, today.day, 23, 59, 59,
    ))) {
      throw ArgumentError('Cash receipt date cannot be in the future.');
    }
    final String identity = (requestId ?? FinancialEvent.newId()).trim();
    if (identity.isEmpty || identity.length > 128) {
      throw ArgumentError('Manual cash operation identity is invalid.');
    }

    final String? sourceText =
        source?.trim().isNotEmpty == true ? source!.trim() : null;
    final String? noteText =
        note?.trim().isNotEmpty == true ? note!.trim() : null;

    // Current v10 ledger already persists category, note, and source fund.
    // A human-readable source prefix preserves the source and reason without
    // introducing another schema upgrade or changing old backup structures.
    final String? description = <String>[
      if (sourceText != null) 'المصدر: $sourceText',
      if (noteText != null) 'التفاصيل: $noteText',
    ].isEmpty
        ? null
        : <String>[
            if (sourceText != null) 'المصدر: $sourceText',
            if (noteText != null) 'التفاصيل: $noteText',
          ].join('\n');

    final bool explicitSplit = savingsMicros != null || spendingMicros != null;
    if (explicitSplit && fund != FinancialFund.unallocated) {
      throw ArgumentError('Choose Unallocated when providing an explicit split.');
    }
    final ReceiptFundAllocation? allocation = explicitSplit
        ? ReceiptFundAllocation(
            receivedMicros: amountMicros,
            savingsMicros: savingsMicros ?? 0,
            spendingMicros: spendingMicros ?? 0,
          )
        : null;

    final event = FinancialEvent.create(
      id: 'cash_$identity',
      recurrenceKey: 'manual-cash:$identity',
      type: kind.isOpeningBalance
          ? FinancialEventType.openingBalance
          : FinancialEventType.income,
      occurredAt: occurredDay,
      category: kind.categoryLabel,
      note: description,
      entries: allocation?.receiptEntries(unit) ?? <LedgerEntry>[
        LedgerEntry(
          unit: unit,
          amountMicros: amountMicros,
          fund: fund,
        ),
      ],
    );

    try {
      await _ledger.addEvent(event);
      return event;
    } catch (_) {
      // Unique event ID/recurrence key blocks a double-click or app retry.
      // A true retry returns only the same posting; conflicting reuse fails.
      final existing =
          await _ledger.loadEventByRecurrenceKey(event.recurrenceKey!);
      if (existing != null &&
          existing.id == event.id &&
          existing.type == event.type &&
          existing.occurredAt == event.occurredAt &&
          existing.category == event.category &&
          existing.note == event.note &&
          existing.entries.length == event.entries.length &&
          List<bool>.generate(event.entries.length, (index) {
            final prior = existing.entries[index];
            final incoming = event.entries[index];
            return prior.unit == incoming.unit &&
                prior.amountMicros == incoming.amountMicros &&
                prior.fund == incoming.fund &&
                prior.affectsBalance == incoming.affectsBalance;
          }).every((same) => same)) {
        return existing;
      }
      rethrow;
    }
  }
}
