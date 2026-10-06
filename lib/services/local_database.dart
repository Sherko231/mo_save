import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LocalDatabase {
  LocalDatabase._() : _databasePathOverride = null;

  LocalDatabase.forTesting(String databasePath)
      : _databasePathOverride = databasePath;

  static final LocalDatabase instance = LocalDatabase._();

  static const String databaseName = 'mo_save.db';
  static const int schemaVersion = 9;

  static bool _databaseFactoryConfigured = false;

  final String? _databasePathOverride;
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

  Future<void> close() async {
    final Database? existing = _database;
    _database = null;
    if (existing != null) {
      await existing.close();
    }
  }

  Future<Database> _openDatabase() async {
    final String? overridePath = _databasePathOverride;
    if (overridePath != null) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _databaseFactoryConfigured = true;
    } else {
      _configureDatabaseFactory();
    }

    final String path;
    if (overridePath != null) {
      path = overridePath;
    } else {
      final String root = await getDatabasesPath();
      path = '$root${Platform.pathSeparator}$databaseName';
    }

    return openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, version) async {
        await _createSchemaV1(database);
        await _createSchemaV2(database);
        await _createSchemaV3(database);
        await _createSchemaV4(database);
        await _createSchemaV5(database);
        await _createSchemaV6(database);
        await _createSchemaV7(database);
        await _createSchemaV8(database);
        await _createSchemaV9(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        await _runMigrations(database, oldVersion, newVersion);
      },
    );
  }

  static void _configureDatabaseFactory() {
    if (_databaseFactoryConfigured) {
      return;
    }

    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    _databaseFactoryConfigured = true;
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

  static Future<void> _createSchemaV2(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE financial_settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        weekly_syp_income INTEGER NOT NULL CHECK (weekly_syp_income >= 0),
        weekly_payday INTEGER NOT NULL CHECK (weekly_payday BETWEEN 1 AND 7),
        monthly_usd_income REAL NOT NULL CHECK (monthly_usd_income >= 0),
        monthly_payday INTEGER NOT NULL CHECK (monthly_payday BETWEEN 1 AND 31),
        reference_syp_per_usd REAL NOT NULL DEFAULT 0
          CHECK (reference_syp_per_usd >= 0),
        gold_usd_per_gram REAL NOT NULL DEFAULT 0
          CHECK (gold_usd_per_gram >= 0),
        weekly_expenses_allocation INTEGER NOT NULL
          CHECK (weekly_expenses_allocation >= 0),
        weekly_savings_allocation INTEGER NOT NULL
          CHECK (weekly_savings_allocation >= 0),
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  static Future<void> _createSchemaV3(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE financial_events (
        id TEXT PRIMARY KEY,
        event_type TEXT NOT NULL,
        occurred_at_ms INTEGER NOT NULL,
        note TEXT,
        category TEXT,
        related_challenge_id TEXT,
        related_goal_id TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        FOREIGN KEY (related_challenge_id)
          REFERENCES challenges(id)
          ON DELETE SET NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE financial_event_entries (
        event_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        unit TEXT NOT NULL,
        amount_micros INTEGER NOT NULL CHECK (amount_micros != 0),
        affects_balance INTEGER NOT NULL DEFAULT 1
          CHECK (affects_balance IN (0, 1)),
        PRIMARY KEY (event_id, position),
        FOREIGN KEY (event_id)
          REFERENCES financial_events(id)
          ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE INDEX financial_events_occurred_at_idx
      ON financial_events(occurred_at_ms)
    ''');

    await database.execute('''
      CREATE INDEX financial_events_type_idx
      ON financial_events(event_type)
    ''');

    await database.execute('''
      CREATE INDEX financial_events_challenge_idx
      ON financial_events(related_challenge_id)
    ''');

    await database.execute('''
      CREATE INDEX financial_event_entries_unit_idx
      ON financial_event_entries(unit)
    ''');
  }

  static Future<void> _createSchemaV4(DatabaseExecutor database) async {
    await database.execute('''
      ALTER TABLE financial_events
      ADD COLUMN recurrence_key TEXT
    ''');

    await database.execute('''
      CREATE UNIQUE INDEX financial_events_recurrence_key_unique_idx
      ON financial_events(recurrence_key)
      WHERE recurrence_key IS NOT NULL
    ''');
  }

  static Future<void> _createSchemaV5(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE recurring_expense_items (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        unit TEXT NOT NULL,
        amount_micros INTEGER NOT NULL CHECK (amount_micros > 0),
        sort_order INTEGER NOT NULL,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');

    await database.execute('''
      CREATE INDEX recurring_expense_items_sort_idx
      ON recurring_expense_items(sort_order)
    ''');
  }

  static Future<void> _createSchemaV6(DatabaseExecutor database) async {
    await database.execute('''
      ALTER TABLE financial_events
      ADD COLUMN source_event_id TEXT
        REFERENCES financial_events(id)
        ON DELETE SET NULL
    ''');

    await database.execute('''
      ALTER TABLE financial_event_entries
      ADD COLUMN entry_role TEXT
    ''');

    await database.execute('''
      CREATE INDEX financial_events_source_event_idx
      ON financial_events(source_event_id)
    ''');

    await database.execute('''
      CREATE INDEX financial_event_entries_role_idx
      ON financial_event_entries(entry_role)
    ''');
  }

  static Future<void> _createSchemaV7(DatabaseExecutor database) async {
    await database.execute('''
      ALTER TABLE challenges
      ADD COLUMN deadline_ms INTEGER
    ''');

    await database.execute('''
      ALTER TABLE challenges
      ADD COLUMN goal_note TEXT
    ''');
  }

  static Future<void> _createSchemaV8(DatabaseExecutor database) async {
    await database.execute('''
      ALTER TABLE financial_events
      ADD COLUMN executed_syp_per_usd REAL
    ''');
  }

  static Future<void> _createSchemaV9(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE financial_event_revisions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id TEXT NOT NULL,
        action TEXT NOT NULL CHECK (action IN ('update', 'delete')),
        snapshot_json TEXT NOT NULL,
        changed_at_ms INTEGER NOT NULL
      )
    ''');

    await database.execute('''
      CREATE INDEX financial_event_revisions_event_idx
      ON financial_event_revisions(event_id, changed_at_ms DESC)
    ''');

    await database.execute('''
      CREATE INDEX financial_event_revisions_changed_at_idx
      ON financial_event_revisions(changed_at_ms DESC)
    ''');
  }

  static Future<void> _runMigrations(
    DatabaseExecutor database,
    int oldVersion,
    int newVersion,
  ) async {
    for (int version = oldVersion + 1; version <= newVersion; version++) {
      switch (version) {
        case 2:
          await _createSchemaV2(database);
          break;
        case 3:
          await _createSchemaV3(database);
          break;
        case 4:
          await _createSchemaV4(database);
          break;
        case 5:
          await _createSchemaV5(database);
          break;
        case 6:
          await _createSchemaV6(database);
          break;
        case 7:
          await _createSchemaV7(database);
          break;
        case 8:
          await _createSchemaV8(database);
          break;
        case 9:
          await _createSchemaV9(database);
          break;
        default:
          throw StateError('Missing database migration for schema v$version.');
      }
    }
  }
}
