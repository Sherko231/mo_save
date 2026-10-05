import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/saving_challenge.dart';
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

  final LocalDatabase _database;
  final SharedPreferencesAsync _preferences;

  Future<void>? _legacyMigration;

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
    });
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
    });
  }

  Future<void> deleteChallenge(String challengeId) async {
    final Database database = await _readyDatabase();
    await database.delete(
      'challenges',
      where: 'id = ?',
      whereArgs: <Object?>[challengeId],
    );
  }

  Future<void> saveChallenges(List<SavingChallenge> challenges) async {
    final Database database = await _readyDatabase();

    await database.transaction((transaction) async {
      await transaction.delete('challenges');

      for (int index = 0; index < challenges.length; index++) {
        await _insertChallenge(
          transaction,
          challenges[index],
          sortOrder: index,
        );
      }
    });
  }

  Future<Database> _readyDatabase() async {
    final Database database = await _database.database;
    await _ensureLegacyMigration(database);
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
