import 'package:sqflite/sqflite.dart';

import 'local_database.dart';

class AppSetupStorage {
  AppSetupStorage({LocalDatabase? database})
      : _database = database ?? LocalDatabase.instance;

  static const String _setupCompleteKey = 'initial_setup_complete_v1';

  final LocalDatabase _database;

  /// Returns whether the one-time setup should be considered complete.
  ///
  /// Older installations predate the setup flag. If they already contain any
  /// persisted finance configuration or user data, they are migrated directly
  /// to the completed state so an app update never forces an onboarding flow
  /// over existing data.
  Future<bool> loadIsComplete() async {
    final Database database = await _database.database;
    final List<Map<String, Object?>> existingFlag = await database.query(
      'app_metadata',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: const <Object?>[_setupCompleteKey],
      limit: 1,
    );

    if (existingFlag.isNotEmpty) {
      return existingFlag.single['value'] == '1';
    }

    if (await _looksLikeExistingInstall(database)) {
      await _writeCompleteFlag(database);
      return true;
    }

    return false;
  }

  Future<void> markComplete() async {
    final Database database = await _database.database;
    await _writeCompleteFlag(database);
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

  static Future<void> _writeCompleteFlag(Database database) async {
    await database.insert(
      'app_metadata',
      const <String, Object?>{
        'key': _setupCompleteKey,
        'value': '1',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
