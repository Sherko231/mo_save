import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../models/financial_event.dart';
import 'local_database.dart';

class InsufficientBalanceException implements Exception {
  const InsufficientBalanceException({
    required this.unit,
    required this.availableMicros,
    required this.requiredMicros,
  });

  final FinancialUnit unit;
  final int availableMicros;
  final int requiredMicros;

  @override
  String toString() =>
      'Insufficient balance for ${unit.name}: $availableMicros < $requiredMicros';
}

/// Raised when an operation would make a fund negative.
class InsufficientFundBalanceException implements Exception {
  const InsufficientFundBalanceException({
    required this.fund,
    required this.unit,
    required this.availableMicros,
    required this.requiredMicros,
  });

  final FinancialFund fund;
  final FinancialUnit unit;
  final int availableMicros;
  final int requiredMicros;

  @override
  String toString() =>
      'Insufficient ${fund.name} ${unit.name}: $availableMicros < $requiredMicros';
}

class FinancialLedgerStorage {
  FinancialLedgerStorage({LocalDatabase? database})
      : _database = database ?? LocalDatabase.instance;

  static final StreamController<void> _changesController =
      StreamController<void>.broadcast();

  /// Emits after successful ledger mutations so derived balance and history
  /// views can refresh without storing duplicate running totals.
  static Stream<void> get changes => _changesController.stream;

  final LocalDatabase _database;

  Future<List<FinancialEvent>> loadEvents({
    DateTime? from,
    DateTime? to,
    FinancialEventType? type,
    String? relatedChallengeId,
  }) async {
    final Database database = await _database.database;
    final List<String> where = <String>[];
    final List<Object?> whereArgs = <Object?>[];

    if (from != null) {
      where.add('occurred_at_ms >= ?');
      whereArgs.add(from.toUtc().millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('occurred_at_ms < ?');
      whereArgs.add(to.toUtc().millisecondsSinceEpoch);
    }
    if (type != null) {
      where.add('event_type = ?');
      whereArgs.add(type.name);
    }
    if (relatedChallengeId != null) {
      where.add('related_challenge_id = ?');
      whereArgs.add(relatedChallengeId);
    }

    final List<Map<String, Object?>> rows = await database.query(
      'financial_events',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'occurred_at_ms DESC, created_at_ms DESC',
    );

    return _hydrateEvents(database, rows);
  }

  Future<FinancialEvent?> loadEvent(String eventId) async {
    final Database database = await _database.database;
    final List<Map<String, Object?>> rows = await database.query(
      'financial_events',
      where: 'id = ?',
      whereArgs: <Object?>[eventId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    final List<FinancialEvent> events = await _hydrateEvents(database, rows);
    return events.single;
  }

  Future<FinancialEvent?> loadEventByRecurrenceKey(String recurrenceKey) async {
    final Database database = await _database.database;
    final List<Map<String, Object?>> rows = await database.query(
      'financial_events',
      where: 'recurrence_key = ?',
      whereArgs: <Object?>[recurrenceKey],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    final List<FinancialEvent> events = await _hydrateEvents(database, rows);
    return events.single;
  }

  /// Receipts are indexed by their scheduled recurrence date, not necessarily
  /// the actual receipt date, which can be backdated to another month.
  /// This also preserves already-confirmed receipts when schedule defaults change.
  Future<List<FinancialEvent>> loadRecurringIncomeEventsForMonth(
    DateTime month,
  ) async {
    final String yearMonth =
        '${month.year}-${month.month.toString().padLeft(2, '0')}';
    final Database database = await _database.database;
    final rows = await database.query(
      'financial_events',
      where: 'event_type = ? AND '
          '(recurrence_key LIKE ? OR recurrence_key LIKE ?)',
      whereArgs: <Object?>[
        FinancialEventType.income.name,
        'income:weeklySyp:$yearMonth-%',
        'income:monthlyUsd:$yearMonth-%',
      ],
      orderBy: 'occurred_at_ms ASC, created_at_ms ASC',
    );
    return _hydrateEvents(database, rows);
  }

  Future<void> addEvent(FinancialEvent event) async {
    switch (event.type) {
      case FinancialEventType.currencyConversion:
        await addCurrencyConversion(event);
        return;
      case FinancialEventType.goldPurchase:
        await addGoldPurchase(event);
        return;
      case FinancialEventType.goldSale:
        await addGoldSale(event);
        return;
      case FinancialEventType.fundTransfer:
        await addFundTransfer(event);
        return;
      default:
        break;
    }

    final Database database = await _database.database;
    await database.transaction((transaction) async {
      _validateFundEntryShape(event);
      final before = await _loadFundBalances(transaction);
      await _insertEvent(transaction, event);
      await _ensureSafeFundMutation(transaction, before);
    });
    notifyChanged();
  }

  /// Move an existing asset between funds without altering owned assets,
  /// income, or expense. A stable event ID / recurrence key may be retried.
  Future<void> addFundTransfer(FinancialEvent event) async {
    _validateFundTransfer(event);
    final Database database = await _database.database;
    final bool inserted = await database.transaction((transaction) async {
      final List<Map<String, Object?>> duplicate = await transaction.rawQuery(
        '''
        SELECT id FROM financial_events
        WHERE id = ? OR (recurrence_key IS NOT NULL AND recurrence_key = ?)
        LIMIT 1
        ''',
        <Object?>[event.id, event.recurrenceKey],
      );
      if (duplicate.isNotEmpty) {
        final String id = duplicate.single['id']! as String;
        final List<Map<String, Object?>> rows = await transaction.query(
          'financial_event_entries',
          where: 'event_id = ?',
          whereArgs: <Object?>[id],
          orderBy: 'position ASC',
        );
        final List<Map<String, Object?>> meta = await transaction.query(
          'financial_events',
          columns: <String>['event_type', 'occurred_at_ms', 'recurrence_key', 'note'],
          where: 'id = ?',
          whereArgs: <Object?>[id],
          limit: 1,
        );
        final bool matches = meta.single['event_type'] ==
                FinancialEventType.fundTransfer.name &&
            (meta.single['occurred_at_ms'] as num).toInt() ==
                event.occurredAt.toUtc().millisecondsSinceEpoch &&
            meta.single['recurrence_key'] == event.recurrenceKey &&
            meta.single['note'] == _normalizeOptionalText(event.note) &&
            rows.length == event.entries.length &&
            List<bool>.generate(rows.length, (index) {
              final row = rows[index];
              final entry = event.entries[index];
              return row['unit'] == entry.unit.name &&
                  row['fund'] == entry.fund.name &&
                  (row['amount_micros'] as num).toInt() == entry.amountMicros &&
                  (row['affects_balance'] as num).toInt() == 0;
            }).every((same) => same);
        if (!matches) {
          throw StateError('A different financial event already uses this identity.');
        }
        return false; // A genuine retry is a no-op.
      }
      final before = await _loadFundBalances(transaction);
      await _insertEvent(transaction, event);
      await _ensureSafeFundMutation(transaction, before);
      return true;
    });
    if (inserted) notifyChanged();
  }

  Future<void> transferFunds({
    required FinancialUnit unit,
    required FinancialFund source,
    required FinancialFund destination,
    required int amountMicros,
    required DateTime occurredAt,
    String? note,
    String? id,
    String? recurrenceKey,
  }) async {
    final FinancialEvent event = FinancialEvent.create(
      type: FinancialEventType.fundTransfer,
      id: id,
      recurrenceKey: recurrenceKey,
      occurredAt: occurredAt,
      note: note,
      entries: <LedgerEntry>[
        LedgerEntry(unit: unit, amountMicros: -amountMicros,
            affectsBalance: false, fund: source),
        LedgerEntry(unit: unit, amountMicros: amountMicros,
            affectsBalance: false, fund: destination),
      ],
    );
    await addFundTransfer(event);
  }

  /// Record one recurring receipt, optionally netting already-spent historic
  /// money with a separately classified expense in the very same transaction.
  /// Ignore and receipt race safely: their SQLite writes serialize and only
  /// one disposition can win. Historical spending is NOT a fund transfer.
  Future<void> addRecurringIncomeReceipt({
    required FinancialEvent income,
    FinancialEvent? historicalExpense,
  }) async {
    if (income.type != FinancialEventType.income ||
        income.recurrenceKey == null ||
        income.entries.isEmpty ||
        income.entries.any(
          (entry) => !entry.affectsBalance || entry.amountMicros <= 0,
        )) {
      throw ArgumentError('Recurring receipt must be positive real income.');
    }
    _validateFundEntryShape(income);
    if (historicalExpense != null) {
      final Map<FinancialUnit, int> received = <FinancialUnit, int>{};
      for (final LedgerEntry entry in income.entries) {
        received[entry.unit] =
            (received[entry.unit] ?? 0) + entry.amountMicros;
      }
      final Map<FinancialUnit, int> spent = <FinancialUnit, int>{};
      if (historicalExpense.type != FinancialEventType.expense ||
          historicalExpense.sourceEventId != income.id ||
          historicalExpense.recurrenceKey != null ||
          historicalExpense.entries.isEmpty ||
          historicalExpense.entries.any(
            (entry) => !entry.affectsBalance ||
                entry.amountMicros >= 0 ||
                entry.fund != FinancialFund.unallocated ||
                entry.unit == FinancialUnit.goldGram,
          )) {
        throw ArgumentError('Historical expense must be linked cash spending.');
      }
      for (final LedgerEntry entry in historicalExpense.entries) {
        spent[entry.unit] = (spent[entry.unit] ?? 0) -
            entry.amountMicros;
      }
      for (final MapEntry<FinancialUnit, int> paid in spent.entries) {
        if (paid.value > (received[paid.key] ?? 0)) {
          throw ArgumentError(
            'Historical spending exceeds the receipt for ${paid.key.name}.',
          );
        }
      }
    }

    final Database database = await _database.database;
    await database.transaction((transaction) async {
      final List<Map<String, Object?>> ignored = await transaction.query(
        'app_metadata',
        columns: <String>['key'],
        where: 'key = ?',
        whereArgs: <Object?>[
          'ignored_income_occurrence:${income.recurrenceKey}',
        ],
        limit: 1,
      );
      if (ignored.isNotEmpty) {
        throw StateError('This recurring income occurrence is ignored.');
      }
      final before = await _loadFundBalances(transaction);
      await _insertEvent(transaction, income);
      if (historicalExpense != null) {
        await _insertEvent(transaction, historicalExpense);
      }
      await _ensureSafeFundMutation(transaction, before);
    });
    notifyChanged();
  }

  /// Adds one real SYP <-> USD conversion as one atomic ledger event.
  ///
  /// The source balance is checked inside the same SQLite transaction that
  /// posts the negative source entry and positive destination entry.
  Future<void> addCurrencyConversion(FinancialEvent event) async {
    final _ConversionPosting posting = _validateCurrencyConversion(event);
    await _addBalanceCheckedEvent(
      event,
      requiredUnit: posting.sourceUnit,
      requiredMicros: posting.sourceAmountMicros,
    );
  }

  /// Adds one physical-gold purchase atomically: cash out and grams in.
  Future<void> addGoldPurchase(FinancialEvent event) async {
    final _BalanceRequirement requirement = _validateGoldPurchase(event);
    await _addBalanceCheckedEvent(
      event,
      requiredUnit: requirement.unit,
      requiredMicros: requirement.amountMicros,
    );
  }

  /// Foundation for a future sale UI: grams out and cash in atomically.
  Future<void> addGoldSale(FinancialEvent event) async {
    final _BalanceRequirement requirement = _validateGoldSale(event);
    await _addBalanceCheckedEvent(
      event,
      requiredUnit: requirement.unit,
      requiredMicros: requirement.amountMicros,
    );
  }

  /// Adds an explicit gold quantity correction while preventing negative
  /// holdings. Positive corrections need no source-balance requirement.
  Future<void> addGoldCorrection(FinancialEvent event) async {
    final _BalanceRequirement? requirement = _validateGoldCorrection(event);
    if (requirement == null) {
      _validateFundEntryShape(event);
      final Database database = await _database.database;
      await database.transaction((transaction) async {
        final before = await _loadFundBalances(transaction);
        await _insertEvent(transaction, event);
        await _ensureSafeFundMutation(transaction, before);
      });
      notifyChanged();
      return;
    }

    await _addBalanceCheckedEvent(
      event,
      requiredUnit: requirement.unit,
      requiredMicros: requirement.amountMicros,
    );
  }

  Future<void> _addBalanceCheckedEvent(
    FinancialEvent event, {
    required FinancialUnit requiredUnit,
    required int requiredMicros,
  }) async {
    final Database database = await _database.database;

    await database.transaction((transaction) async {
      _validateFundEntryShape(event);
      final before = await _loadFundBalances(transaction);
      final int available = await _loadUnitBalanceMicros(
        transaction,
        requiredUnit,
      );
      if (available < requiredMicros) {
        throw InsufficientBalanceException(
          unit: requiredUnit,
          availableMicros: available,
          requiredMicros: requiredMicros,
        );
      }

      await _insertEvent(transaction, event);
      await _ensureSafeFundMutation(transaction, before);
    });
    notifyChanged();
  }

  /// Explicit user-authorized correction of an existing historical event.
  ///
  /// The event keeps its original id and creation timestamp. Entries are
  /// replaced atomically with the corrected event payload.
  Future<void> updateEvent(FinancialEvent event) async {
    _validateFundEntryShape(event);
    if (event.type == FinancialEventType.fundTransfer) {
      _validateFundTransfer(event);
    }
    switch (event.type) {
      case FinancialEventType.currencyConversion:
        _validateCurrencyConversion(event);
        break;
      case FinancialEventType.goldPurchase:
        _validateGoldPurchase(event);
        break;
      case FinancialEventType.goldSale:
        _validateGoldSale(event);
        break;
      default:
        break;
    }

    final Database database = await _database.database;
    await database.transaction((transaction) async {
      final before = await _loadFundBalances(transaction);
      final List<Map<String, Object?>> existing = await transaction.query(
        'financial_events',
        columns: <String>['created_at_ms'],
        where: 'id = ?',
        whereArgs: <Object?>[event.id],
        limit: 1,
      );

      if (existing.isEmpty) {
        throw StateError('Financial event ${event.id} does not exist.');
      }
      final dependents = await transaction.query(
        'financial_events',
        columns: <String>['id'],
        where: 'source_event_id = ?',
        whereArgs: <Object?>[event.id],
        limit: 1,
      );
      if (dependents.isNotEmpty) {
        throw StateError('Cannot modify an event with dependent transactions.');
      }

      final Map<String, Object?> row = _eventRow(event);
      row['created_at_ms'] = existing.single['created_at_ms'];

      await transaction.update(
        'financial_events',
        row,
        where: 'id = ?',
        whereArgs: <Object?>[event.id],
      );

      await transaction.delete(
        'financial_event_entries',
        where: 'event_id = ?',
        whereArgs: <Object?>[event.id],
      );
      await _insertEntries(transaction, event);
      await _ensureSafeFundMutation(transaction, before);
    });
    notifyChanged();
  }

  /// Explicit user-authorized deletion of a historical event.
  Future<void> deleteEvent(String eventId) async {
    final Database database = await _database.database;
    final int deleted = await database.transaction((transaction) async {
      final before = await _loadFundBalances(transaction);
      final dependents = await transaction.rawQuery(
        'SELECT id FROM financial_events WHERE source_event_id = ? LIMIT 1',
        <Object?>[eventId],
      );
      if (dependents.isNotEmpty) {
        throw StateError('Cannot delete an event with dependent transactions.');
      }
      final count = await transaction.delete(
        'financial_events',
        where: 'id = ?',
        whereArgs: <Object?>[eventId],
      );
      if (count > 0) await _ensureSafeFundMutation(transaction, before);
      return count;
    });
    if (deleted > 0) {
      notifyChanged();
    }
  }

  /// Returns owned-asset balances derived exclusively from balance-affecting
  /// ledger entries. No cached totals are maintained.
  Future<Map<FinancialUnit, int>> loadBalanceMicros() async {
    final Database database = await _database.database;
    final List<Map<String, Object?>> rows = await database.rawQuery('''
      SELECT unit, COALESCE(SUM(amount_micros), 0) AS balance_micros
      FROM financial_event_entries
      WHERE affects_balance = 1
      GROUP BY unit
    ''');

    final Map<FinancialUnit, int> balances = <FinancialUnit, int>{
      for (final FinancialUnit unit in FinancialUnit.values) unit: 0,
    };

    for (final Map<String, Object?> row in rows) {
      final FinancialUnit unit = _parseUnit(row['unit']! as String);
      balances[unit] = (row['balance_micros']! as num).toInt();
    }

    return balances;
  }

  /// Active fund holdings. The fund-only transfer postings are deliberately
  /// excluded from owned-asset balances but included here. The sum over
  /// funds for each unit must equal loadBalanceMicros()[unit].
  Future<Map<FinancialFund, Map<FinancialUnit, int>>> loadFundBalancesMicros() async {
    final Database database = await _database.database;
    return _loadFundBalances(database);
  }

  Future<int> loadFundBalanceMicros(FinancialFund fund, FinancialUnit unit) async {
    final balances = await loadFundBalancesMicros();
    return balances[fund]![unit]!;
  }

  /// Transaction-scoped balance snapshots for audited history corrections.
  static Future<Map<FinancialFund, Map<FinancialUnit, int>>>
      loadFundBalancesForMutation(DatabaseExecutor executor) =>
          _loadFundBalances(executor);

  static Future<void> ensureFundMutationSafe(
    DatabaseExecutor executor,
    Map<FinancialFund, Map<FinancialUnit, int>> before,
  ) => _ensureSafeFundMutation(executor, before);

  static Future<Map<FinancialFund, Map<FinancialUnit, int>>> _loadFundBalances(
    DatabaseExecutor executor,
  ) async {
    final rows = await executor.rawQuery('''
      SELECT e.fund, e.unit, SUM(e.amount_micros) AS amount
      FROM financial_event_entries e
      JOIN financial_events f ON f.id = e.event_id
      WHERE e.affects_balance = 1 OR f.event_type = 'fundTransfer'
      GROUP BY e.fund, e.unit
    ''');
    final result = <FinancialFund, Map<FinancialUnit, int>>{
      for (final fund in FinancialFund.values)
        fund: <FinancialUnit, int>{
          for (final unit in FinancialUnit.values) unit: 0,
        },
    };
    for (final row in rows) {
      final fund = FinancialFund.values.byName(row['fund']! as String);
      final unit = _parseUnit(row['unit']! as String);
      result[fund]![unit] = (row['amount']! as num).toInt();
    }
    return result;
  }

  static Future<void> _ensureSafeFundMutation(
    DatabaseExecutor executor,
    Map<FinancialFund, Map<FinancialUnit, int>> before,
  ) async {
    final after = await _loadFundBalances(executor);
    final assetRows = await executor.rawQuery('''
      SELECT unit, SUM(amount_micros) AS total
      FROM financial_event_entries
      WHERE affects_balance = 1
      GROUP BY unit
    ''');
    final owned = <FinancialUnit, int>{
      for (final unit in FinancialUnit.values) unit: 0,
    };
    for (final row in assetRows) {
      owned[_parseUnit(row['unit']! as String)] =
          (row['total']! as num).toInt();
    }
    for (final unit in FinancialUnit.values) {
      final classified = FinancialFund.values.fold<int>(0,
          (total, fund) => total + after[fund]![unit]!);
      if (classified != owned[unit]) {
        throw StateError('Fund postings do not reconcile with owned ${unit.name}.');
      }
    }
    for (final fund in FinancialFund.values) {
      for (final unit in FinancialUnit.values) {
        final previous = before[fund]![unit]!;
        final next = after[fund]![unit]!;
        if (next < 0 && next < previous) {
          throw InsufficientFundBalanceException(
            fund: fund,
            unit: unit,
            availableMicros: previous,
            requiredMicros: previous - next,
          );
        }
      }
    }
  }

  static void _validateFundEntryShape(FinancialEvent event) {
    for (final entry in event.entries) {
      if (entry.unit == FinancialUnit.goldGram &&
          entry.fund == FinancialFund.spending) {
        throw ArgumentError('Gold grams cannot be held as spendable cash.');
      }
    }
  }

  static void _validateFundTransfer(FinancialEvent event) {
    _validateFundEntryShape(event);
    if (event.type != FinancialEventType.fundTransfer ||
        event.entries.length != 2) {
      throw ArgumentError('Fund transfer requires two entries.');
    }
    final outgoing = event.entries[0];
    final incoming = event.entries[1];
    if (outgoing.affectsBalance || incoming.affectsBalance ||
        outgoing.unit != incoming.unit ||
        outgoing.fund == incoming.fund ||
        outgoing.amountMicros >= 0 || incoming.amountMicros <= 0 ||
        outgoing.amountMicros != -incoming.amountMicros ||
        outgoing.role != null || incoming.role != null) {
      throw ArgumentError('Fund transfers must be equal, opposite, same-unit postings.');
    }
  }

  /// Goal/challenge progress is intentionally separate from owned-asset
  /// balances. Saving contributions may therefore be non-balance-affecting.
  Future<int> loadChallengeContributionMicros({
    required String challengeId,
    required FinancialUnit unit,
  }) async {
    final Database database = await _database.database;
    final List<Map<String, Object?>> rows = await database.rawQuery(
      '''
      SELECT COALESCE(SUM(e.amount_micros), 0) AS contribution_micros
      FROM financial_events f
      JOIN financial_event_entries e ON e.event_id = f.id
      WHERE f.event_type = ?
        AND f.related_challenge_id = ?
        AND e.unit = ?
      ''',
      <Object?>[
        FinancialEventType.savingContribution.name,
        challengeId,
        unit.name,
      ],
    );

    return (rows.single['contribution_micros']! as num).toInt();
  }

  static Future<List<FinancialEvent>> _hydrateEvents(
    DatabaseExecutor database,
    List<Map<String, Object?>> eventRows,
  ) async {
    if (eventRows.isEmpty) {
      return <FinancialEvent>[];
    }

    final List<FinancialEvent> events = <FinancialEvent>[];
    for (final Map<String, Object?> row in eventRows) {
      final String eventId = row['id']! as String;
      final List<Map<String, Object?>> entryRows = await database.query(
        'financial_event_entries',
        where: 'event_id = ?',
        whereArgs: <Object?>[eventId],
        orderBy: 'position ASC',
      );

      events.add(
        FinancialEvent(
          id: eventId,
          type: _parseEventType(row['event_type']! as String),
          occurredAt: DateTime.fromMillisecondsSinceEpoch(
            (row['occurred_at_ms']! as num).toInt(),
            isUtc: true,
          ),
          entries: entryRows
              .map(
                (entry) => LedgerEntry(
                  unit: _parseUnit(entry['unit']! as String),
                  amountMicros: (entry['amount_micros']! as num).toInt(),
                  affectsBalance:
                      (entry['affects_balance']! as num).toInt() == 1,
                  role: _parseEntryRole(entry['entry_role'] as String?),
                  fund: FinancialFund.values.byName(entry['fund']! as String),
                ),
              )
              .toList(growable: false),
          note: row['note'] as String?,
          category: row['category'] as String?,
          relatedChallengeId: row['related_challenge_id'] as String?,
          relatedGoalId: row['related_goal_id'] as String?,
          recurrenceKey: row['recurrence_key'] as String?,
          sourceEventId: row['source_event_id'] as String?,
          executedSypPerUsd:
              (row['executed_syp_per_usd'] as num?)?.toDouble(),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            (row['created_at_ms']! as num).toInt(),
            isUtc: true,
          ),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            (row['updated_at_ms']! as num).toInt(),
            isUtc: true,
          ),
        ),
      );
    }

    return events;
  }

  static Future<void> _insertEvent(
    DatabaseExecutor database,
    FinancialEvent event,
  ) async {
    await database.insert(
      'financial_events',
      <String, Object?>{
        'id': event.id,
        ..._eventRow(event),
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    await _insertEntries(database, event);
  }

  static Map<String, Object?> _eventRow(FinancialEvent event) {
    return <String, Object?>{
      'event_type': event.type.name,
      'occurred_at_ms': event.occurredAt.toUtc().millisecondsSinceEpoch,
      'note': _normalizeOptionalText(event.note),
      'category': _normalizeOptionalText(event.category),
      'related_challenge_id': _normalizeOptionalText(event.relatedChallengeId),
      'related_goal_id': _normalizeOptionalText(event.relatedGoalId),
      'recurrence_key': _normalizeOptionalText(event.recurrenceKey),
      'source_event_id': _normalizeOptionalText(event.sourceEventId),
      'executed_syp_per_usd': event.executedSypPerUsd,
      'created_at_ms': event.createdAt.toUtc().millisecondsSinceEpoch,
      'updated_at_ms': event.updatedAt.toUtc().millisecondsSinceEpoch,
    };
  }

  static Future<void> _insertEntries(
    DatabaseExecutor database,
    FinancialEvent event,
  ) async {
    for (int index = 0; index < event.entries.length; index++) {
      final LedgerEntry entry = event.entries[index];
      await database.insert(
        'financial_event_entries',
        <String, Object?>{
          'event_id': event.id,
          'position': index,
          'unit': entry.unit.name,
          'amount_micros': entry.amountMicros,
          'affects_balance': entry.affectsBalance ? 1 : 0,
          'entry_role': entry.role?.name,
          'fund': entry.fund.name,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
  }

  static Future<int> _loadUnitBalanceMicros(
    DatabaseExecutor database,
    FinancialUnit unit,
  ) async {
    final List<Map<String, Object?>> rows = await database.rawQuery(
      '''
      SELECT COALESCE(SUM(amount_micros), 0) AS balance_micros
      FROM financial_event_entries
      WHERE affects_balance = 1 AND unit = ?
      ''',
      <Object?>[unit.name],
    );
    return (rows.single['balance_micros']! as num).toInt();
  }

  static _ConversionPosting _validateCurrencyConversion(FinancialEvent event) {
    if (event.type != FinancialEventType.currencyConversion) {
      throw ArgumentError('Event is not a currency conversion.');
    }
    if (event.entries.length != 2 ||
        event.entries.any((entry) => !entry.affectsBalance)) {
      throw ArgumentError(
        'Currency conversion must contain exactly two balance entries.',
      );
    }

    final List<LedgerEntry> negative = event.entries
        .where((entry) => entry.amountMicros < 0)
        .toList(growable: false);
    final List<LedgerEntry> positive = event.entries
        .where((entry) => entry.amountMicros > 0)
        .toList(growable: false);
    if (negative.length != 1 || positive.length != 1) {
      throw ArgumentError(
        'Currency conversion must have one source and one destination entry.',
      );
    }

    final LedgerEntry source = negative.single;
    final LedgerEntry destination = positive.single;
    final Set<FinancialUnit> pair = <FinancialUnit>{
      source.unit,
      destination.unit,
    };
    if (pair.length != 2 ||
        !pair.contains(FinancialUnit.syp) ||
        !pair.contains(FinancialUnit.usd)) {
      throw ArgumentError('Only SYP <-> USD conversions are supported.');
    }

    final int sypMicros = source.unit == FinancialUnit.syp
        ? source.amountMicros.abs()
        : destination.amountMicros.abs();
    final int usdMicros = source.unit == FinancialUnit.usd
        ? source.amountMicros.abs()
        : destination.amountMicros.abs();
    final double derivedRate = sypMicros / usdMicros;
    final double storedRate = event.executedSypPerUsd!;
    final double tolerance = derivedRate.abs() * 0.000000001 + 0.000000001;
    if ((storedRate - derivedRate).abs() > tolerance) {
      throw ArgumentError(
        'Stored executed exchange rate does not match conversion amounts.',
      );
    }

    return _ConversionPosting(
      sourceUnit: source.unit,
      sourceAmountMicros: source.amountMicros.abs(),
    );
  }

  static _BalanceRequirement _validateGoldPurchase(FinancialEvent event) {
    if (event.type != FinancialEventType.goldPurchase) {
      throw ArgumentError('Event is not a gold purchase.');
    }
    final _AssetExchangePosting posting = _validateTwoEntryAssetExchange(event);
    if (posting.destination.unit != FinancialUnit.goldGram ||
        !_isSupportedGoldCashUnit(posting.source.unit)) {
      throw ArgumentError(
        'Gold purchase must exchange USD or SYP cash for gold grams.',
      );
    }
    return _BalanceRequirement(
      unit: posting.source.unit,
      amountMicros: posting.source.amountMicros.abs(),
    );
  }

  static _BalanceRequirement _validateGoldSale(FinancialEvent event) {
    if (event.type != FinancialEventType.goldSale) {
      throw ArgumentError('Event is not a gold sale.');
    }
    final _AssetExchangePosting posting = _validateTwoEntryAssetExchange(event);
    if (posting.source.unit != FinancialUnit.goldGram ||
        !_isSupportedGoldCashUnit(posting.destination.unit)) {
      throw ArgumentError(
        'Gold sale must exchange gold grams for USD or SYP cash.',
      );
    }
    return _BalanceRequirement(
      unit: FinancialUnit.goldGram,
      amountMicros: posting.source.amountMicros.abs(),
    );
  }

  static _BalanceRequirement? _validateGoldCorrection(FinancialEvent event) {
    if (event.type != FinancialEventType.manualAdjustment ||
        event.entries.length != 1 ||
        !event.entries.single.affectsBalance ||
        event.entries.single.unit != FinancialUnit.goldGram) {
      throw ArgumentError(
        'Gold correction must be one balance-affecting gold adjustment.',
      );
    }
    final int delta = event.entries.single.amountMicros;
    if (delta >= 0) return null;
    return _BalanceRequirement(
      unit: FinancialUnit.goldGram,
      amountMicros: delta.abs(),
    );
  }

  static _AssetExchangePosting _validateTwoEntryAssetExchange(
    FinancialEvent event,
  ) {
    if (event.entries.length != 2 ||
        event.entries.any((entry) => !entry.affectsBalance)) {
      throw ArgumentError(
        'Asset exchange must contain exactly two balance entries.',
      );
    }

    final List<LedgerEntry> negative = event.entries
        .where((entry) => entry.amountMicros < 0)
        .toList(growable: false);
    final List<LedgerEntry> positive = event.entries
        .where((entry) => entry.amountMicros > 0)
        .toList(growable: false);
    if (negative.length != 1 || positive.length != 1) {
      throw ArgumentError(
        'Asset exchange must have one source and one destination entry.',
      );
    }

    return _AssetExchangePosting(
      source: negative.single,
      destination: positive.single,
    );
  }

  static bool _isSupportedGoldCashUnit(FinancialUnit unit) {
    return unit == FinancialUnit.usd || unit == FinancialUnit.syp;
  }

  static String? _normalizeOptionalText(String? value) {
    final String? trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static FinancialEventType _parseEventType(String name) {
    for (final FinancialEventType type in FinancialEventType.values) {
      if (type.name == name) {
        return type;
      }
    }
    throw StateError('Unknown financial event type: $name');
  }

  static FinancialUnit _parseUnit(String name) {
    for (final FinancialUnit unit in FinancialUnit.values) {
      if (unit.name == name) {
        return unit;
      }
    }
    throw StateError('Unknown ledger entry unit: $name');
  }

  static LedgerEntryRole? _parseEntryRole(String? name) {
    if (name == null) {
      return null;
    }
    for (final LedgerEntryRole role in LedgerEntryRole.values) {
      if (role.name == name) {
        return role;
      }
    }
    throw StateError('Unknown ledger entry role: $name');
  }

  /// Notifies derived views after a successful ledger mutation performed by a
  /// coordinated storage workflow such as challenge-grid reconciliation.
  static void notifyChanged() {
    if (!_changesController.isClosed) {
      _changesController.add(null);
    }
  }
}

class _ConversionPosting {
  const _ConversionPosting({
    required this.sourceUnit,
    required this.sourceAmountMicros,
  });

  final FinancialUnit sourceUnit;
  final int sourceAmountMicros;
}

class _BalanceRequirement {
  const _BalanceRequirement({
    required this.unit,
    required this.amountMicros,
  });

  final FinancialUnit unit;
  final int amountMicros;
}

class _AssetExchangePosting {
  const _AssetExchangePosting({
    required this.source,
    required this.destination,
  });

  final LedgerEntry source;
  final LedgerEntry destination;
}
