import 'package:sqflite/sqflite.dart';

import '../models/financial_event.dart';
import 'local_database.dart';

class FinancialLedgerStorage {
  FinancialLedgerStorage({LocalDatabase? database})
      : _database = database ?? LocalDatabase.instance;

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

  Future<void> addEvent(FinancialEvent event) async {
    final Database database = await _database.database;
    await database.transaction((transaction) async {
      await _insertEvent(transaction, event);
    });
  }

  /// Explicit user-authorized correction of an existing historical event.
  ///
  /// The event keeps its original id and creation timestamp. Entries are
  /// replaced atomically with the corrected event payload.
  Future<void> updateEvent(FinancialEvent event) async {
    final Database database = await _database.database;
    await database.transaction((transaction) async {
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
    });
  }

  /// Explicit user-authorized deletion of a historical event.
  Future<void> deleteEvent(String eventId) async {
    final Database database = await _database.database;
    await database.delete(
      'financial_events',
      where: 'id = ?',
      whereArgs: <Object?>[eventId],
    );
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
                ),
              )
              .toList(growable: false),
          note: row['note'] as String?,
          category: row['category'] as String?,
          relatedChallengeId: row['related_challenge_id'] as String?,
          relatedGoalId: row['related_goal_id'] as String?,
          recurrenceKey: row['recurrence_key'] as String?,
          sourceEventId: row['source_event_id'] as String?,
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
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
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
    throw StateError('Unknown financial unit: $name');
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
}
