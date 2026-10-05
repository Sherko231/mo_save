import 'dart:io';

import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  LocalDatabase._();

  static final LocalDatabase instance = LocalDatabase._();

  static const String databaseName = 'mo_save.db';
  static const int schemaVersion = 1;

  Database? _database;

  Future<Database> get database async {
    final Database? existing = _database;
    if (existing != null) {
      return existing;
    }

    final Database opened = await _openDatabase();
    _database = opened;
    return opened;
  }

  Future<Database> _openDatabase() async {
    final String root = await getDatabasesPath();
    final String path = '$root${Platform.pathSeparator}$databaseName';

    return openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, version) async {
        await _createSchemaV1(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        await _runMigrations(database, oldVersion, newVersion);
      },
    );
  }

  static Future<void> _createSchemaV1(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE app_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE challenges (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        target_amount REAL NOT NULL,
        currency TEXT NOT NULL,
        sequence TEXT NOT NULL,
        cell_count INTEGER NOT NULL,
        sort_order INTEGER NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE challenge_cells (
        challenge_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        value INTEGER NOT NULL,
        is_completed INTEGER NOT NULL DEFAULT 0
          CHECK (is_completed IN (0, 1)),
        PRIMARY KEY (challenge_id, position),
        FOREIGN KEY (challenge_id)
          REFERENCES challenges(id)
          ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE INDEX challenge_cells_challenge_id_idx
      ON challenge_cells(challenge_id)
    ''');
  }

  static Future<void> _runMigrations(
    DatabaseExecutor database,
    int oldVersion,
    int newVersion,
  ) async {
    for (int version = oldVersion + 1; version <= newVersion; version++) {
      switch (version) {
        default:
          throw StateError('Missing database migration for schema v$version.');
      }
    }
  }
}
