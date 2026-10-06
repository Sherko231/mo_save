import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/saving_challenge.dart';
import 'package:mo_save/services/challenge_storage.dart';
import 'package:mo_save/services/local_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('database migration QA', () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('mo_save_migration_');
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    tearDown(() async {
      await tempDirectory.delete(recursive: true);
    });

    test('schema v1 upgrades to v9 without losing challenge data', () async {
      final path = '${tempDirectory.path}${Platform.pathSeparator}legacy_v1.db';
      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE app_metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
              )
            ''');
            await db.execute('''
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
            await db.execute('''
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
            await db.execute('''
              CREATE INDEX challenge_cells_challenge_id_idx
              ON challenge_cells(challenge_id)
            ''');
            await db.insert('challenges', <String, Object?>{
              'id': 'legacy-db',
              'name': 'Legacy DB goal',
              'target_amount': 100.0,
              'currency': 'usd',
              'sequence': 'ordered',
              'cell_count': 2,
              'sort_order': 0,
            });
            await db.insert('challenge_cells', <String, Object?>{
              'challenge_id': 'legacy-db',
              'position': 0,
              'value': 40,
              'is_completed': 0,
            });
            await db.insert('challenge_cells', <String, Object?>{
              'challenge_id': 'legacy-db',
              'position': 1,
              'value': 60,
              'is_completed': 1,
            });
          },
        ),
      );
      await legacy.close();

      final database = LocalDatabase.forTesting(path);
      final upgraded = await database.database;

      expect(await upgraded.getVersion(), LocalDatabase.schemaVersion);
      expect(await upgraded.query('challenges'), hasLength(1));
      expect(await upgraded.query('challenge_cells'), hasLength(2));

      final eventColumns = await upgraded.rawQuery(
        'PRAGMA table_info(financial_events)',
      );
      final eventColumnNames = eventColumns
          .map((row) => row['name'] as String)
          .toSet();
      expect(eventColumnNames, contains('recurrence_key'));
      expect(eventColumnNames, contains('source_event_id'));
      expect(eventColumnNames, contains('executed_syp_per_usd'));

      final challengeColumns = await upgraded.rawQuery(
        'PRAGMA table_info(challenges)',
      );
      final challengeColumnNames = challengeColumns
          .map((row) => row['name'] as String)
          .toSet();
      expect(challengeColumnNames, contains('deadline_ms'));
      expect(challengeColumnNames, contains('goal_note'));

      final tables = await upgraded.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final tableNames = tables.map((row) => row['name'] as String).toSet();
      expect(tableNames, contains('financial_settings'));
      expect(tableNames, contains('financial_events'));
      expect(tableNames, contains('financial_event_entries'));
      expect(tableNames, contains('recurring_expense_items'));
      expect(tableNames, contains('financial_event_revisions'));

      await database.close();
    });

    test('legacy SharedPreferences challenges migrate once and backfill progress', () async {
      final base = SavingChallenge.create(
        id: 'legacy-pref',
        name: 'Legacy preferences goal',
        targetAmount: 100,
        currency: ChallengeCurrency.usd,
        sequence: ChallengeSequence.ordered,
        cellCount: 4,
      );
      final legacyChallenge = base.copyWith(
        cells: <ChallengeCell>[
          base.cells[0].copyWith(isCompleted: true),
          ...base.cells.skip(1),
        ],
      );
      const legacyKey = 'saving_challenges_v1';
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
        legacyKey: jsonEncode(<Object?>[legacyChallenge.toJson()]),
      });

      final path = '${tempDirectory.path}${Platform.pathSeparator}prefs.db';
      final database = LocalDatabase.forTesting(path);
      final storage = ChallengeStorage(
        database: database,
        preferences: SharedPreferencesAsync(),
      );

      final loaded = await storage.loadChallenges();
      final sqlite = await database.database;
      final contributionEvents = await sqlite.query(
        'financial_events',
        where: 'recurrence_key = ?',
        whereArgs: <Object?>['challenge-progress:legacy-pref'],
      );
      final migrationFlag = await sqlite.query(
        'app_metadata',
        where: 'key = ?',
        whereArgs: <Object?>['legacy_shared_preferences_challenges_v1_migrated'],
      );
      final prefs = SharedPreferencesAsync();

      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'legacy-pref');
      expect(loaded.single.savedAmount, legacyChallenge.savedAmount);
      expect(contributionEvents, hasLength(1));
      expect(migrationFlag.single['value'], '1');
      expect(await prefs.getString(legacyKey), isNull);

      final secondLoad = await storage.loadChallenges();
      expect(secondLoad, hasLength(1));
      expect(await sqlite.query('challenges'), hasLength(1));

      await database.close();
    });
  });
}
