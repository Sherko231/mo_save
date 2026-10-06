import 'package:sqflite/sqflite.dart';

import 'local_database.dart';

class AppSetupStorage {
  AppSetupStorage({LocalDatabase? database})
      : _database = database ?? LocalDatabase.instance;

  static const String _setupStartedKey = 'initial_setup_started_v1';
  static const String _setupCompleteKey = 'initial_setup_complete_v1';

  final LocalDatabase _database;

  /// Returns whether the one-time setup should be considered complete.
  ///
  /// Older installations predate the setup flags. If they already contain any
  /// persisted finance configuration or user data, they are migrated directly
  /// to the completed state so an app update never forces onboarding over
  /// existing data.
  ///
  /// A truly fresh install writes a separate "started" marker before the setup
  /// screen loads. This prevents defaults seeded by that screen from making an
  /// interrupted first-run flow look like an older completed installation on
  /// the next app launch.
  Future<bool> loadIsComplete() async {
    final Database database = await _database.database;

    final String? completeValue = await _readMetadata(
      database,
      _setupCompleteKey,
    );
    if (completeValue != null) {
      return completeValue == '1';
    }

    final String? startedValue = await _readMetadata(
      database,
      _setupStartedKey,
    );
    if (startedValue == '1') {
      return false;
    }

    if (await _looksLikeExistingInstall(database)) {
      await _writeMetadata(database, _setupCompleteKey, '1');
      return true;
    }

    await _writeMetadata(database, _setupStartedKey, '1');
    return false;
  }

  Future<void> markComplete() async {
    final Database database = await _database.database;
    await database.transaction((transaction) async {
      await _writeMetadata(transaction, _setupStartedKey, '1');
      await _writeMetadata(transaction, _setupCompleteKey, '1');
    });
  }

  static Future<String?> _readMetadata(
    DatabaseExecutor database,
    String key,
  ) async {
    final List<Map<String, Object?>> rows = await database.query(
      'app_metadata',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  static Future<bool> _looksLikeExistingInstall(Database database) async {
    const List<String> tables = <String>[
      'financial_settings',
      'financial_events',
      'challenges',
      'recurring_expense_items',
    ];

    for (final String table in tables) {
      final List<Map<String, Object?>> rows = await database.query(
        table,
        columns: const <String>['rowid'],
        limit: 1,
      );
      if (rows.isNotEmpty) return true;
    }

    return false;
  }

  static Future<void> _writeMetadata(
    DatabaseExecutor database,
    String key,
    String value,
  ) async {
    await database.insert(
      'app_metadata',
      <String, Object?>{
        'key': key,
        'value': value,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
