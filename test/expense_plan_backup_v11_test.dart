import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/models/recurring_expense_item.dart';
import 'package:mo_save/services/backup_service.dart';
import 'package:mo_save/services/expense_plan_storage.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/local_database.dart';
import 'package:mo_save/services/notification_preferences_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MS-09 v11 backup migration and future version history', () {
    late Directory dir;
    late LocalDatabase source;
    late LocalDatabase target;
    late ExpensePlanStorage plan;
    late BackupService export;
    late BackupService restore;
    late DateTime current;
    late DateTime next;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('mosave_v11_archive_');
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      source = LocalDatabase.forTesting(
        '${dir.path}${Platform.pathSeparator}source.db',
      );
      target = LocalDatabase.forTesting(
        '${dir.path}${Platform.pathSeparator}target.db',
      );
      final notification = NotificationPreferencesStorage(
        preferences: SharedPreferencesAsync(),
      );
      export = BackupService(
        database: source,
        notificationPreferencesStorage: notification,
      );
      restore = BackupService(
        database: target,
        notificationPreferencesStorage: notification,
      );
      plan = ExpensePlanStorage(database: source);
      final now = DateTime.now();
      current = DateTime(now.year, now.month);
      next = DateTime(now.year, now.month + 1);
      await (await source.database).insert('app_metadata', <String, Object?>{
        'key': 'expense_plan_client_defaults_seeded_v1', 'value': '1',
      });
      final item = RecurringExpenseItem.create(
        name: 'أمبير',
        unit: FinancialUnit.syp,
        amountMicros: LedgerEntry.amountToMicros(240000),
        sortOrder: 0,
      );
      await plan.addItem(item, effectiveFromMonth: current);
      await plan.updateItem(
        item.copyWith(amountMicros: LedgerEntry.amountToMicros(310000)),
        effectiveFromMonth: next,
      );
      final ledger = FinancialLedgerStorage(database: source);
      await ledger.addEvent(FinancialEvent.create(
        type: FinancialEventType.income,
        occurredAt: now,
        entries: <LedgerEntry>[
          LedgerEntry(
            unit: FinancialUnit.syp,
            amountMicros: LedgerEntry.amountToMicros(400000),
            fund: FinancialFund.spending,
          ),
        ],
      ));
    });

    tearDown(() async {
      await source.close();
      await target.close();
      await dir.delete(recursive: true);
    });

    Uint8List legacyV10(Uint8List original) {
      final outer = jsonDecode(utf8.decode(original)) as Map<String, dynamic>;
      final payload = jsonDecode(outer['payloadJson'] as String)
          as Map<String, dynamic>;
      final tables = payload['tables'] as Map<String, dynamic>;
      tables.remove('recurring_expense_plan_versions');
      tables.remove('goal_earmarks');
      // Schema v10 has only the one known current-row value, not historic
      // revisions. It cannot include the new scheduled Nov price.
      final currentRow = (tables['recurring_expense_items'] as List).single
          as Map<String, dynamic>;
      currentRow['name'] = 'أمبير';
      currentRow['unit'] = 'syp';
      currentRow['amount_micros'] = LedgerEntry.amountToMicros(240000);
      final payloadJson = jsonEncode(payload);
      outer['databaseSchemaVersion'] = 10;
      outer['payloadJson'] = payloadJson;
      outer['checksumSha256'] =
          sha256.convert(utf8.encode(payloadJson)).toString();
      return Uint8List.fromList(utf8.encode(jsonEncode(outer)));
    }

    test('v12 export restores exact future plan revisions and no new cash', () async {
      final original = await export.createBackupBytes();
      expect(export.inspectBackupBytes(original).databaseSchemaVersion, LocalDatabase.schemaVersion);
      final summary = await restore.restoreBackupBytes(original);
      expect(summary.databaseSchemaVersion, LocalDatabase.schemaVersion);
      final restored = ExpensePlanStorage(database: target);
      expect((await restored.loadItemsForMonth(current)).single.amountMicros,
          LedgerEntry.amountToMicros(240000));
      expect((await restored.loadItemsForMonth(next)).single.amountMicros,
          LedgerEntry.amountToMicros(310000));
      final raw = await target.database;
      expect(await raw.query('recurring_expense_plan_versions'), hasLength(2));
      final ledger = FinancialLedgerStorage(database: target);
      expect((await ledger.loadBalanceMicros())[FinancialUnit.syp],
          LedgerEntry.amountToMicros(400000));
      expect((await ledger.loadEvents(type: FinancialEventType.income)),
          hasLength(1));

      final again = await restore.createBackupBytes();
      await restore.restoreBackupBytes(again);
      expect(await raw.query('recurring_expense_plan_versions'), hasLength(2));
      expect((await ledger.loadBalanceMicros())[FinancialUnit.syp],
          LedgerEntry.amountToMicros(400000));
    });

    test('v10 archive gets one known baseline without fabricated old prices',
        () async {
      final oldBytes = legacyV10(await export.createBackupBytes());
      expect(export.inspectBackupBytes(oldBytes).databaseSchemaVersion, 10);
      await restore.restoreBackupBytes(oldBytes);
      final restoredPlan = ExpensePlanStorage(database: target);
      expect((await restoredPlan.loadItemsForMonth(current)).single.amountMicros,
          LedgerEntry.amountToMicros(240000));
      expect((await restoredPlan.loadItemsForMonth(next)).single.amountMicros,
          LedgerEntry.amountToMicros(240000));
      expect(await (await target.database)
          .query('recurring_expense_plan_versions'), hasLength(1));
      expect((await FinancialLedgerStorage(database: target)
          .loadBalanceMicros())[FinancialUnit.syp],
          LedgerEntry.amountToMicros(400000));
    });

    test('corrupt v11 plan archive cannot overwrite existing local data',
        () async {
      final existing = ExpensePlanStorage(database: target);
      final item = RecurringExpenseItem.create(
        name: 'قديم عند العميل',
        unit: FinancialUnit.syp,
        amountMicros: LedgerEntry.amountToMicros(90000),
        sortOrder: 0,
      );
      await (await target.database).insert('app_metadata',
        <String, Object?>{
          'key': 'expense_plan_client_defaults_seeded_v1', 'value': '1',
        });
      await existing.addItem(item, effectiveFromMonth: current);
      final modern = await export.createBackupBytes();
      final corrupt = jsonDecode(utf8.decode(modern)) as Map<String, dynamic>;
      final payload = jsonDecode(corrupt['payloadJson'] as String)
          as Map<String, dynamic>;
      final tables = payload['tables'] as Map<String, dynamic>;
      (tables['recurring_expense_plan_versions'] as List).clear();
      final tamperedText = jsonEncode(payload);
      corrupt['payloadJson'] = tamperedText;
      corrupt['checksumSha256'] =
          sha256.convert(utf8.encode(tamperedText)).toString();
      await expectLater(
        restore.restoreBackupBytes(
          Uint8List.fromList(utf8.encode(jsonEncode(corrupt))),
        ),
        throwsA(isA<BackupException>()),
      );
      expect((await existing.loadItems()).single.name, 'قديم عند العميل');
      expect((await (await target.database)
          .query('recurring_expense_plan_versions')), hasLength(1));
    });
  });
}
