import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/services/backup_service.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/local_database.dart';
import 'package:mo_save/services/notification_preferences_storage.dart';
import 'package:mo_save/services/transaction_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MS-03: v9 backup compatibility and preservation', () {
    late Directory directory;
    late LocalDatabase source;
    late LocalDatabase target;
    late BackupService sourceBackup;
    late BackupService targetBackup;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('mosave_v9_restore_');
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      source = LocalDatabase.forTesting(
        '${directory.path}${Platform.pathSeparator}source.db',
      );
      target = LocalDatabase.forTesting(
        '${directory.path}${Platform.pathSeparator}target.db',
      );
      final notifications = NotificationPreferencesStorage(
        preferences: SharedPreferencesAsync(),
      );
      sourceBackup = BackupService(
        database: source,
        notificationPreferencesStorage: notifications,
      );
      targetBackup = BackupService(
        database: target,
        notificationPreferencesStorage: notifications,
      );

      final ledger = FinancialLedgerStorage(database: source);
      await ledger.addEvent(FinancialEvent.create(
        id: 'october-pay',
        type: FinancialEventType.income,
        occurredAt: DateTime.utc(2026, 10, 8),
        recurrenceKey: 'income:weeklySyp:2026-10-08',
        entries: <LedgerEntry>[
          LedgerEntry(unit: FinancialUnit.syp,
              amountMicros: LedgerEntry.amountToMicros(885000)),
        ],
      ));
      await ledger.addEvent(FinancialEvent.create(
        id: 'old-gold',
        type: FinancialEventType.manualAdjustment,
        occurredAt: DateTime.utc(2026, 10, 8),
        entries: <LedgerEntry>[
          LedgerEntry(unit: FinancialUnit.goldGram,
              amountMicros: LedgerEntry.amountToMicros(2)),
        ],
      ));
      final database = await source.database;
      await database.insert('challenges', <String, Object?>{
        'id': 'old-goal',
        'name': 'Legacy savings',
        'target_amount': 100.0,
        'currency': 'usd',
        'sequence': 'ordered',
        'cell_count': 1,
        'sort_order': 0,
      });
      await database.insert('challenge_cells', <String, Object?>{
        'challenge_id': 'old-goal',
        'position': 0,
        'value': 100,
        'is_completed': 1,
      });
      await ledger.addEvent(FinancialEvent.create(
        id: 'progress',
        type: FinancialEventType.savingContribution,
        occurredAt: DateTime.utc(2026, 10, 8),
        relatedChallengeId: 'old-goal',
        entries: <LedgerEntry>[
          LedgerEntry(unit: FinancialUnit.usd,
              amountMicros: LedgerEntry.amountToMicros(100),
              affectsBalance: false),
        ],
      ));
      await database.insert('recurring_expense_items', <String, Object?>{
        'id': 'ampere',
        'name': 'Ampere',
        'unit': 'syp',
        'amount_micros': LedgerEntry.amountToMicros(240000),
        'sort_order': 0,
        'created_at_ms': 1,
        'updated_at_ms': 1,
      });
      final history = TransactionHistoryService(
        database: source,
        ledger: ledger,
      );
      await history.updateMetadata(
        eventId: 'october-pay',
        occurredAt: DateTime.utc(2026, 10, 8),
        category: 'salary',
        note: 'Corrected historic salary note',
      );
      await database.insert('app_metadata', <String, Object?>{
        'key': 'legacy_marker',
        'value': 'kept',
      });
    });

    tearDown(() async {
      await source.close();
      await target.close();
      await directory.delete(recursive: true);
    });

    Uint8List legacyV9(Uint8List modernBytes) {
      final outer = jsonDecode(utf8.decode(modernBytes))
          as Map<String, dynamic>;
      final payload = jsonDecode(outer['payloadJson']! as String)
          as Map<String, dynamic>;
      final tables = payload['tables']! as Map<String, dynamic>;
      final entries = tables['financial_event_entries']! as List<dynamic>;
      for (final item in entries) {
        (item as Map<String, dynamic>).remove('fund');
      }
      final revisions = tables['financial_event_revisions']! as List<dynamic>;
      for (final revision in revisions) {
        final row = revision as Map<String, dynamic>;
        final snapshot = jsonDecode(row['snapshot_json']! as String)
            as Map<String, dynamic>;
        for (final item in snapshot['entries']! as List<dynamic>) {
          (item as Map<String, dynamic>).remove('fund');
        }
        row['snapshot_json'] = jsonEncode(snapshot);
      }
      final text = jsonEncode(payload);
      outer['databaseSchemaVersion'] = 9;
      outer['payloadJson'] = text;
      outer['checksumSha256'] = sha256.convert(utf8.encode(text)).toString();
      return Uint8List.fromList(utf8.encode(jsonEncode(outer)));
    }

    test('restores v9 ledger, goals, audit and expenses as Unallocated', () async {
      final bytes = legacyV9(await sourceBackup.createBackupBytes());
      expect(sourceBackup.inspectBackupBytes(bytes).databaseSchemaVersion, 9);
      final summary = await targetBackup.restoreBackupBytes(bytes);
      expect(summary.databaseSchemaVersion, 9);
      expect(summary.transactionCount, 3);
      expect(summary.challengeCount, 1);
      expect(summary.expensePlanCount, 1);
      final database = await target.database;
      expect(await database.query('challenge_cells'), hasLength(1));
      expect(await database.query('recurring_expense_items'), hasLength(1));
      expect(await database.query('financial_event_revisions'), hasLength(1));
      final history = TransactionHistoryService(
        database: target,
        ledger: FinancialLedgerStorage(database: target),
      );
      final historyRevisions = await history.loadRevisions('october-pay');
      expect(historyRevisions, hasLength(1));
      expect(historyRevisions.single.snapshot.entries.single.fund,
          FinancialFund.unallocated);
      final metadata = await database.query('app_metadata',
          where: 'key = ?', whereArgs: <Object?>['legacy_marker']);
      expect(metadata.single['value'], 'kept');
      final entries = await database.query('financial_event_entries');
      expect(entries.every((row) => row['fund'] == 'unallocated'), isTrue);

      final ledger = FinancialLedgerStorage(database: target);
      expect((await ledger.loadBalanceMicros())[FinancialUnit.syp],
          LedgerEntry.amountToMicros(885000));
      expect((await ledger.loadBalanceMicros())[FinancialUnit.goldGram],
          LedgerEntry.amountToMicros(2));
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd], 0);
      expect(await ledger.loadFundBalanceMicros(
          FinancialFund.savings, FinancialUnit.syp), 0);
      expect(await ledger.loadFundBalanceMicros(
          FinancialFund.unallocated, FinancialUnit.syp),
          LedgerEntry.amountToMicros(885000));
      expect(await ledger.loadChallengeContributionMicros(
          challengeId: 'old-goal', unit: FinancialUnit.usd),
          LedgerEntry.amountToMicros(100));

      await ledger.transferFunds(
        id: 'classify-old-money',
        unit: FinancialUnit.syp,
        source: FinancialFund.unallocated,
        destination: FinancialFund.savings,
        amountMicros: LedgerEntry.amountToMicros(345000),
        occurredAt: DateTime.utc(2026, 10, 10),
      );
      expect(await ledger.loadFundBalanceMicros(
          FinancialFund.savings, FinancialUnit.syp),
          LedgerEntry.amountToMicros(345000));
      expect((await ledger.loadBalanceMicros())[FinancialUnit.syp],
          LedgerEntry.amountToMicros(885000));

      final again = await targetBackup.createBackupBytes();
      expect(targetBackup.inspectBackupBytes(again).databaseSchemaVersion, 10);
      await targetBackup.restoreBackupBytes(again);
      expect(await database.query('financial_events'), hasLength(4));
      expect(await database.query('financial_event_revisions'), hasLength(1));
      expect((await ledger.loadBalanceMicros())[FinancialUnit.syp],
          LedgerEntry.amountToMicros(885000));
      expect(await ledger.loadFundBalanceMicros(
          FinancialFund.savings, FinancialUnit.syp),
          LedgerEntry.amountToMicros(345000));
      expect(await ledger.loadFundBalanceMicros(
          FinancialFund.unallocated, FinancialUnit.syp),
          LedgerEntry.amountToMicros(540000));
    });

    test('rejects corrupt checksum and future schema without deleting data', () async {
      final service = FinancialLedgerStorage(database: target);
      await service.addEvent(FinancialEvent.create(
        id: 'keep-existing',
        type: FinancialEventType.income,
        occurredAt: DateTime.utc(2026, 10, 10),
        entries: <LedgerEntry>[
          LedgerEntry(unit: FinancialUnit.usd,
              amountMicros: LedgerEntry.amountToMicros(75)),
        ],
      ));

      final modern = await sourceBackup.createBackupBytes();
      final legacy = legacyV9(modern);
      final corrupt = jsonDecode(utf8.decode(legacy)) as Map<String, dynamic>;
      corrupt['checksumSha256'] = 'not-a-real-checksum';
      await expectLater(
        targetBackup.restoreBackupBytes(
            Uint8List.fromList(utf8.encode(jsonEncode(corrupt)))),
        throwsA(isA<BackupException>()),
      );
      final future = jsonDecode(utf8.decode(modern)) as Map<String, dynamic>;
      future['databaseSchemaVersion'] = 11;
      await expectLater(
        targetBackup.restoreBackupBytes(
            Uint8List.fromList(utf8.encode(jsonEncode(future)))),
        throwsA(isA<BackupException>()),
      );
      expect(await target.database.then((db) => db.query('financial_events')),
          hasLength(1));
      expect((await service.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(75));
    });
  });
}
