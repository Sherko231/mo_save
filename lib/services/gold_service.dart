import 'package:sqflite/sqflite.dart';

import '../models/financial_event.dart';
import 'financial_ledger_storage.dart';
import 'local_database.dart';

class GoldService {
  GoldService({LocalDatabase? database})
      : _database = database ?? LocalDatabase.instance;

  final LocalDatabase _database;

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

    await _recordEvent(
      event,
      requiredUnit: sourceUnit,
      requiredMicros: cashPaidMicros,
    );
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

    await _recordEvent(
      event,
      requiredUnit: FinancialUnit.goldGram,
      requiredMicros: goldSoldMicros,
    );
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

    await _recordEvent(
      event,
      requiredUnit:
          goldDeltaMicros < 0 ? FinancialUnit.goldGram : null,
      requiredMicros: goldDeltaMicros < 0 ? -goldDeltaMicros : null,
    );
    return event;
  }

  Future<void> _recordEvent(
    FinancialEvent event, {
    FinancialUnit? requiredUnit,
    int? requiredMicros,
  }) async {
    if ((requiredUnit == null) != (requiredMicros == null)) {
      throw ArgumentError(
        'requiredUnit and requiredMicros must either both be set or both be null.',
      );
    }

    final Database database = await _database.database;

    await database.transaction((transaction) async {
      if (requiredUnit != null && requiredMicros != null) {
        final List<Map<String, Object?>> rows = await transaction.rawQuery(
          '''
          SELECT COALESCE(SUM(amount_micros), 0) AS balance_micros
          FROM financial_event_entries
          WHERE affects_balance = 1 AND unit = ?
          ''',
          <Object?>[requiredUnit.name],
        );
        final int available = (rows.single['balance_micros']! as num).toInt();
        if (available < requiredMicros) {
          throw InsufficientBalanceException(
            unit: requiredUnit,
            availableMicros: available,
            requiredMicros: requiredMicros,
          );
        }
      }

      await transaction.insert(
        'financial_events',
        <String, Object?>{
          'id': event.id,
          'event_type': event.type.name,
          'occurred_at_ms': event.occurredAt.toUtc().millisecondsSinceEpoch,
          'note': _normalizeOptionalText(event.note),
          'category': _normalizeOptionalText(event.category),
          'related_challenge_id': null,
          'related_goal_id': null,
          'recurrence_key': null,
          'source_event_id': null,
          'executed_syp_per_usd': null,
          'created_at_ms': event.createdAt.toUtc().millisecondsSinceEpoch,
          'updated_at_ms': event.updatedAt.toUtc().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      for (int index = 0; index < event.entries.length; index++) {
        final LedgerEntry entry = event.entries[index];
        await transaction.insert(
          'financial_event_entries',
          <String, Object?>{
            'event_id': event.id,
            'position': index,
            'unit': entry.unit.name,
            'amount_micros': entry.amountMicros,
            'affects_balance': entry.affectsBalance ? 1 : 0,
            'entry_role': entry.role?.name,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    });

    FinancialLedgerStorage.notifyChanged();
  }

  static bool _isSupportedCashUnit(FinancialUnit unit) {
    return unit == FinancialUnit.usd || unit == FinancialUnit.syp;
  }

  static String? _normalizeOptionalText(String? value) {
    final String? trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
