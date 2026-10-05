enum FinancialEventType {
  income,
  expense,
  savingContribution,
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

class LedgerEntry {
  const LedgerEntry({
    required this.unit,
    required this.amountMicros,
    this.affectsBalance = true,
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
  /// Goal/saving tracking can deliberately use non-balance entries so the same
  /// cash is not counted twice merely because it was assigned to a goal.
  final bool affectsBalance;

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
  }

  final String id;
  final FinancialEventType type;
  final DateTime occurredAt;
  final List<LedgerEntry> entries;
  final String? note;
  final String? category;
  final String? relatedChallengeId;
  final String? relatedGoalId;
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
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String newId() {
    return 'evt_${DateTime.now().microsecondsSinceEpoch}';
  }
}
