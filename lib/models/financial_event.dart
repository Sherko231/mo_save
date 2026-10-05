enum FinancialEventType {
  income,
  expense,
  savingContribution,
  weeklyAllocation,
  currencyConversion,
  goldPurchase,
  goldSale,
  manualAdjustment,
}

enum FinancialUnit {
  usd,
  syp,
  sypNew,
  goldGram,
}

enum LedgerEntryRole {
  weeklyExpensesEnvelope,
  weeklySavingsEnvelope,
}

class LedgerEntry {
  const LedgerEntry({
    required this.unit,
    required this.amountMicros,
    this.affectsBalance = true,
    this.role,
  }) : assert(amountMicros != 0);

  static const int microsPerUnit = 1000000;

  final FinancialUnit unit;

  /// Signed quantity in fixed-point micro-units (1 unit = 1,000,000 micros).
  ///
  /// Examples:
  /// - 300 USD = 300,000,000 micros
  /// - 885,000 SYP = 885,000,000,000 micros
  /// - 2.5 g gold = 2,500,000 micros
  final int amountMicros;

  /// Whether this posting changes the owned-asset balance.
  ///
  /// Goal/saving tracking and envelope allocation can deliberately use
  /// non-balance entries so earmarking cash does not count it twice.
  final bool affectsBalance;

  /// Optional semantic role inside a multi-entry event.
  final LedgerEntryRole? role;

  double get amount => amountMicros / microsPerUnit;

  static int amountToMicros(num amount) {
    return (amount * microsPerUnit).round();
  }
}

class FinancialEvent {
  FinancialEvent({
    required this.id,
    required this.type,
    required this.occurredAt,
    required List<LedgerEntry> entries,
    this.note,
    this.category,
    this.relatedChallengeId,
    this.relatedGoalId,
    this.recurrenceKey,
    this.sourceEventId,
    required this.createdAt,
    required this.updatedAt,
  }) : entries = List<LedgerEntry>.unmodifiable(entries) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Event id must not be empty.');
    }
    if (entries.isEmpty) {
      throw ArgumentError('A financial event must contain at least one entry.');
    }
    if (entries.any((entry) => entry.amountMicros == 0)) {
      throw ArgumentError('Ledger entries cannot have a zero amount.');
    }
    if (recurrenceKey != null && recurrenceKey!.trim().isEmpty) {
      throw ArgumentError.value(
        recurrenceKey,
        'recurrenceKey',
        'Recurrence key must be null or non-empty.',
      );
    }
    if (sourceEventId != null && sourceEventId!.trim().isEmpty) {
      throw ArgumentError.value(
        sourceEventId,
        'sourceEventId',
        'Source event id must be null or non-empty.',
      );
    }
  }

  factory FinancialEvent.create({
    required FinancialEventType type,
    required DateTime occurredAt,
    required List<LedgerEntry> entries,
    String? note,
    String? category,
    String? relatedChallengeId,
    String? relatedGoalId,
    String? recurrenceKey,
    String? sourceEventId,
    String? id,
  }) {
    final DateTime now = DateTime.now().toUtc();
    return FinancialEvent(
      id: id ?? newId(),
      type: type,
      occurredAt: occurredAt.toUtc(),
      entries: entries,
      note: note,
      category: category,
      relatedChallengeId: relatedChallengeId,
      relatedGoalId: relatedGoalId,
      recurrenceKey: recurrenceKey,
      sourceEventId: sourceEventId,
      createdAt: now,
      updatedAt: now,
    );
  }

  final String id;
  final FinancialEventType type;
  final DateTime occurredAt;
  final List<LedgerEntry> entries;
  final String? note;
  final String? category;
  final String? relatedChallengeId;
  final String? relatedGoalId;

  /// Stable identity for one generated recurring occurrence.
  ///
  /// This is null for ordinary/manual financial events. Recurring workflows use
  /// it to prevent the same scheduled action from being confirmed twice.
  final String? recurrenceKey;

  /// Optional direct link to the financial event that caused this event.
  ///
  /// Weekly envelope allocation points to the confirmed Thursday income event.
  final String? sourceEventId;

  final DateTime createdAt;
  final DateTime updatedAt;

  int balanceDeltaMicros(FinancialUnit unit) {
    return entries
        .where((entry) => entry.affectsBalance && entry.unit == unit)
        .fold<int>(0, (sum, entry) => sum + entry.amountMicros);
  }

  FinancialEvent copyWith({
    FinancialEventType? type,
    DateTime? occurredAt,
    List<LedgerEntry>? entries,
    String? note,
    bool clearNote = false,
    String? category,
    bool clearCategory = false,
    String? relatedChallengeId,
    bool clearRelatedChallengeId = false,
    String? relatedGoalId,
    bool clearRelatedGoalId = false,
    String? recurrenceKey,
    bool clearRecurrenceKey = false,
    String? sourceEventId,
    bool clearSourceEventId = false,
    DateTime? updatedAt,
  }) {
    return FinancialEvent(
      id: id,
      type: type ?? this.type,
      occurredAt: occurredAt ?? this.occurredAt,
      entries: entries ?? this.entries,
      note: clearNote ? null : (note ?? this.note),
      category: clearCategory ? null : (category ?? this.category),
      relatedChallengeId: clearRelatedChallengeId
          ? null
          : (relatedChallengeId ?? this.relatedChallengeId),
      relatedGoalId:
          clearRelatedGoalId ? null : (relatedGoalId ?? this.relatedGoalId),
      recurrenceKey:
          clearRecurrenceKey ? null : (recurrenceKey ?? this.recurrenceKey),
      sourceEventId:
          clearSourceEventId ? null : (sourceEventId ?? this.sourceEventId),
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  static String newId() {
    return 'evt_${DateTime.now().microsecondsSinceEpoch}';
  }
}
