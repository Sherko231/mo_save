import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/financial_event.dart';
import '../models/saving_challenge.dart';
import 'financial_ledger_storage.dart';
import 'local_database.dart';

class ChallengeStorage {
  ChallengeStorage({
    LocalDatabase? database,
    SharedPreferencesAsync? preferences,
  })  : _database = database ?? LocalDatabase.instance,
        _preferences = preferences ?? SharedPreferencesAsync();

  static const String _legacyStorageKey = 'saving_challenges_v1';
  static const String _legacyMigrationFlag =
      'legacy_shared_preferences_challenges_v1_migrated';
  static const String _contributionBackfillFlag =
      'challenge_grid_contributions_v1_backfilled';
  static const String _contributionCategory = 'challengeGrid';

  final LocalDatabase _database;
  final SharedPreferencesAsync _preferences;

  Future<void>? _legacyMigration;
  Future<void>? _contributionBackfill;

  Future<List<SavingChallenge>> loadChallenges() async {
    final Database database = await _readyDatabase();
    final List<Map<String, Object?>> challengeRows = await database.query(
      'challenges',
      orderBy: 'sort_order ASC',
    );

    final List<SavingChallenge> challenges = <SavingChallenge>[];
    for (final Map<String, Object?> row in challengeRows) {
      final String id = row['id']! as String;
      final List<Map<String, Object?>> cellRows = await database.query(
        'challenge_cells',
        where: 'challenge_id = ?',
        whereArgs: <Object?>[id],
        orderBy: 'position ASC',
      );

      challenges.add(
        SavingChallenge(
          id: id,
          name: row['name']! as String,
          targetAmount: (row['target_amount']! as num).toDouble(),
          currency: _parseCurrency(row['currency']! as String),
          sequence: _parseSequence(row['sequence']! as String),
          cellCount: (row['cell_count']! as num).toInt(),
          cells: cellRows
              .map(
                (cell) => ChallengeCell(
                  value: (cell['value']! as num).toInt(),
                  isCompleted: (cell['is_completed']! as num).toInt() == 1,
                ),
              )
              .toList(growable: false),
          deadline: _readDeadline(row['deadline_ms']),
          goalNote: _normalizeOptionalText(row['goal_note'] as String?),
        ),
      );
    }

    return challenges;
  }

  Future<void> addChallenge(SavingChallenge challenge) async {
    final Database database = await _readyDatabase();

    await database.transaction((transaction) async {
      final int nextSortOrder = await _nextSortOrder(transaction);
      await _insertChallenge(
        transaction,
        challenge,
        sortOrder: nextSortOrder,
      );
      await _syncChallengeContribution(transaction, challenge);
    });
    FinancialLedgerStorage.notifyChanged();
  }

  Future<void> updateChallenge(SavingChallenge challenge) async {
    final Database database = await _readyDatabase();

    await database.transaction((transaction) async {
      final int updated = await transaction.update(
        'challenges',
        <String, Object?>{
          'name': challenge.name,
          'target_amount': challenge.targetAmount,
          'currency': challenge.currency.name,
          'sequence': challenge.sequence.name,
          'cell_count': challenge.cellCount,
          'deadline_ms': challenge.deadline?.toUtc().millisecondsSinceEpoch,
          'goal_note': _normalizeOptionalText(challenge.goalNote),
        },
        where: 'id = ?',
        whereArgs: <Object?>[challenge.id],
      );

      if (updated == 0) {
        throw StateError('Challenge ${challenge.id} does not exist.');
      }

      await transaction.delete(
        'challenge_cells',
        where: 'challenge_id = ?',
        whereArgs: <Object?>[challenge.id],
      );
      await _insertCells(transaction, challenge);
      await _syncChallengeContribution(transaction, challenge);
    });
    FinancialLedgerStorage.notifyChanged();
  }

  Future<void> deleteChallenge(String challengeId) async {
    final Database database = await _readyDatabase();
    await database.transaction((transaction) async {
      await transaction.delete(
        'financial_events',
        where: 'recurrence_key = ?',
        whereArgs: <Object?>[_contributionRecurrenceKey(challengeId)],
      );
      await transaction.delete(
        'challenges',
        where: 'id = ?',
        whereArgs: <Object?>[challengeId],
      );
    });
    FinancialLedgerStorage.notifyChanged();
  }

  /// Compatibility path for callers that still submit the full list.
  ///
  /// Dedicated challenge-grid saving contributions are removed before the
  /// challenge rows are replaced, then recreated from the persisted completion
  /// state in the same transaction. This keeps the ledger and grid exact.
  Future<void> saveChallenges(List<SavingChallenge> challenges) async {
    final Database database = await _readyDatabase();

    await database.transaction((transaction) async {
      await transaction.delete(
        'financial_events',
        where: 'event_type = ? AND category = ?',
        whereArgs: <Object?>[
          FinancialEventType.savingContribution.name,
          _contributionCategory,
        ],
      );
      await transaction.delete('challenges');

      for (int index = 0; index < challenges.length; index++) {
        final SavingChallenge challenge = challenges[index];
        await _insertChallenge(
          transaction,
          challenge,
          sortOrder: index,
        );
        await _syncChallengeContribution(transaction, challenge);
      }
    });
    FinancialLedgerStorage.notifyChanged();
  }

  Future<Database> _readyDatabase() async {
    final Database database = await _database.database;
    await _ensureLegacyMigration(database);
    await _ensureContributionBackfill(database);
    return database;
  }

  Future<void> _ensureLegacyMigration(Database database) async {
    final Future<void>? activeMigration = _legacyMigration;
    if (activeMigration != null) {
      return activeMigration;
    }

    final Future<void> migration = _migrateLegacyData(database);
    _legacyMigration = migration;

    try {
      await migration;
    } catch (_) {
      _legacyMigration = null;
      rethrow;
    }
  }

  Future<void> _migrateLegacyData(Database database) async {
    final List<Map<String, Object?>> migrated = await database.query(
      'app_metadata',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[_legacyMigrationFlag],
      limit: 1,
    );

    if (migrated.isNotEmpty && migrated.first['value'] == '1') {
      return;
    }

    final String? raw = await _preferences.getString(_legacyStorageKey);
    final List<SavingChallenge> legacyChallenges;

    if (raw == null || raw.trim().isEmpty) {
      legacyChallenges = const <SavingChallenge>[];
    } else {
      legacyChallenges = _decodeLegacyChallenges(raw);
    }

    await database.transaction((transaction) async {
      int nextSortOrder = await _nextSortOrder(transaction);

      for (final SavingChallenge challenge in legacyChallenges) {
        final List<Map<String, Object?>> existing = await transaction.query(
          'challenges',
          columns: <String>['id'],
          where: 'id = ?',
          whereArgs: <Object?>[challenge.id],
          limit: 1,
        );

        if (existing.isNotEmpty) {
          continue;
        }

        await _insertChallenge(
          transaction,
          challenge,
          sortOrder: nextSortOrder,
        );
        nextSortOrder++;
      }

      await transaction.insert(
        'app_metadata',
        <String, Object?>{
          'key': _legacyMigrationFlag,
          'value': '1',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    if (raw != null) {
      await _preferences.remove(_legacyStorageKey);
    }
  }

  Future<void> _ensureContributionBackfill(Database database) async {
    final Future<void>? activeBackfill = _contributionBackfill;
    if (activeBackfill != null) {
      return activeBackfill;
    }

    final Future<void> backfill = _backfillChallengeContributions(database);
    _contributionBackfill = backfill;

    try {
      await backfill;
    } catch (_) {
      _contributionBackfill = null;
      rethrow;
    }
  }

  Future<void> _backfillChallengeContributions(Database database) async {
    final List<Map<String, Object?>> migrated = await database.query(
      'app_metadata',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[_contributionBackfillFlag],
      limit: 1,
    );

    if (migrated.isNotEmpty && migrated.first['value'] == '1') {
      return;
    }

    await database.transaction((transaction) async {
      final List<Map<String, Object?>> challenges = await transaction.query(
        'challenges',
        columns: <String>['id', 'currency'],
      );

      for (final Map<String, Object?> row in challenges) {
        final String challengeId = row['id']! as String;
        final ChallengeCurrency currency =
            _parseCurrency(row['currency']! as String);
        final List<Map<String, Object?>> totalRows = await transaction.rawQuery(
          '''
          SELECT COALESCE(SUM(value), 0) AS saved_amount
          FROM challenge_cells
          WHERE challenge_id = ? AND is_completed = 1
          ''',
          <Object?>[challengeId],
        );
        final int savedAmount =
            (totalRows.single['saved_amount']! as num).toInt();

        await _syncContributionValues(
          transaction,
          challengeId: challengeId,
          currency: currency,
          savedAmount: savedAmount,
        );
      }

      await transaction.insert(
        'app_metadata',
        <String, Object?>{
          'key': _contributionBackfillFlag,
          'value': '1',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    FinancialLedgerStorage.notifyChanged();
  }

  static List<SavingChallenge> _decodeLegacyChallenges(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) {
      throw const FormatException('Legacy challenge payload is not a list.');
    }

    return decoded.map((item) {
      if (item is! Map) {
        throw const FormatException('Legacy challenge entry is not an object.');
      }

      return SavingChallenge.fromJson(
        Map<String, dynamic>.from(item),
      );
    }).toList(growable: false);
  }

  static Future<int> _nextSortOrder(DatabaseExecutor database) async {
    final List<Map<String, Object?>> result = await database.rawQuery(
      'SELECT COALESCE(MAX(sort_order), -1) + 1 AS next_order FROM challenges',
    );
    return (result.first['next_order']! as num).toInt();
  }

  static Future<void> _insertChallenge(
    DatabaseExecutor database,
    SavingChallenge challenge, {
    required int sortOrder,
  }) async {
    await database.insert(
      'challenges',
      <String, Object?>{
        'id': challenge.id,
        'name': challenge.name,
        'target_amount': challenge.targetAmount,
        'currency': challenge.currency.name,
        'sequence': challenge.sequence.name,
        'cell_count': challenge.cellCount,
        'sort_order': sortOrder,
        'deadline_ms': challenge.deadline?.toUtc().millisecondsSinceEpoch,
        'goal_note': _normalizeOptionalText(challenge.goalNote),
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    await _insertCells(database, challenge);
  }

  static Future<void> _insertCells(
    DatabaseExecutor database,
    SavingChallenge challenge,
  ) async {
    for (int index = 0; index < challenge.cells.length; index++) {
      final ChallengeCell cell = challenge.cells[index];
      await database.insert(
        'challenge_cells',
        <String, Object?>{
          'challenge_id': challenge.id,
          'position': index,
          'value': cell.value,
          'is_completed': cell.isCompleted ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
  }

  static Future<void> _syncChallengeContribution(
    DatabaseExecutor database,
    SavingChallenge challenge,
  ) {
    return _syncContributionValues(
      database,
      challengeId: challenge.id,
      currency: challenge.currency,
      savedAmount: challenge.savedAmount,
    );
  }

  static Future<void> _syncContributionValues(
    DatabaseExecutor database, {
    required String challengeId,
    required ChallengeCurrency currency,
    required int savedAmount,
  }) async {
    final String recurrenceKey = _contributionRecurrenceKey(challengeId);
    final List<Map<String, Object?>> existing = await database.query(
      'financial_events',
      columns: <String>['id', 'created_at_ms'],
      where: 'recurrence_key = ?',
      whereArgs: <Object?>[recurrenceKey],
      limit: 1,
    );

    if (savedAmount <= 0) {
      if (existing.isNotEmpty) {
        await database.delete(
          'financial_events',
          where: 'id = ?',
          whereArgs: <Object?>[existing.single['id']],
        );
      }
      return;
    }

    final FinancialUnit unit = _financialUnitForCurrency(currency);
    final int desiredMicros = savedAmount * LedgerEntry.microsPerUnit;

    if (existing.isNotEmpty) {
      final String existingEventId = existing.single['id']! as String;
      final List<Map<String, Object?>> entries = await database.query(
        'financial_event_entries',
        columns: <String>['unit', 'amount_micros', 'affects_balance'],
        where: 'event_id = ?',
        whereArgs: <Object?>[existingEventId],
        orderBy: 'position ASC',
      );
      if (entries.length == 1 &&
          entries.single['unit'] == unit.name &&
          (entries.single['amount_micros']! as num).toInt() == desiredMicros &&
          (entries.single['affects_balance']! as num).toInt() == 0) {
        return;
      }
    }

    final int nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final String eventId = existing.isEmpty
        ? _contributionEventId(challengeId)
        : existing.single['id']! as String;
    final int createdAtMs = existing.isEmpty
        ? nowMs
        : (existing.single['created_at_ms']! as num).toInt();

    final Map<String, Object?> eventRow = <String, Object?>{
      'event_type': FinancialEventType.savingContribution.name,
      'occurred_at_ms': nowMs,
      'note': null,
      'category': _contributionCategory,
      'related_challenge_id': challengeId,
      'related_goal_id': challengeId,
      'recurrence_key': recurrenceKey,
      'source_event_id': null,
      'created_at_ms': createdAtMs,
      'updated_at_ms': nowMs,
    };

    if (existing.isEmpty) {
      await database.insert(
        'financial_events',
        <String, Object?>{'id': eventId, ...eventRow},
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } else {
      await database.update(
        'financial_events',
        eventRow,
        where: 'id = ?',
        whereArgs: <Object?>[eventId],
      );
      await database.delete(
        'financial_event_entries',
        where: 'event_id = ?',
        whereArgs: <Object?>[eventId],
      );
    }

    await database.insert(
      'financial_event_entries',
      <String, Object?>{
        'event_id': eventId,
        'position': 0,
        'unit': unit.name,
        'amount_micros': desiredMicros,
        'affects_balance': 0,
        'entry_role': null,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  static String _contributionRecurrenceKey(String challengeId) =>
      'challenge-progress:$challengeId';

  static String _contributionEventId(String challengeId) =>
      'evt_challenge_progress_$challengeId';

  static FinancialUnit _financialUnitForCurrency(ChallengeCurrency currency) {
    return switch (currency) {
      ChallengeCurrency.usd => FinancialUnit.usd,
      ChallengeCurrency.syp => FinancialUnit.syp,
      ChallengeCurrency.sypNew => FinancialUnit.sypNew,
    };
  }

  static DateTime? _readDeadline(Object? raw) {
    if (raw == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(
      (raw as num).toInt(),
      isUtc: true,
    );
  }

  static String? _normalizeOptionalText(String? value) {
    final String? trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static ChallengeCurrency _parseCurrency(String name) {
    return ChallengeCurrency.values.firstWhere(
      (currency) => currency.name == name,
      orElse: () => ChallengeCurrency.usd,
    );
  }

  static ChallengeSequence _parseSequence(String name) {
    return ChallengeSequence.values.firstWhere(
      (sequence) => sequence.name == name,
      orElse: () => ChallengeSequence.ordered,
    );
  }
}
