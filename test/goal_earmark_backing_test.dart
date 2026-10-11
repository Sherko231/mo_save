import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/models/saving_challenge.dart';
import 'package:mo_save/services/backup_service.dart';
import 'package:mo_save/services/challenge_storage.dart';
import 'package:mo_save/services/expense_plan_storage.dart';
import 'package:mo_save/services/expense_service.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/local_database.dart';
import 'package:mo_save/services/notification_preferences_storage.dart';
import 'package:mo_save/services/transaction_history_service.dart';
import 'package:mo_save/services/savings_fund_service.dart';
import 'package:mo_save/services/financial_settings_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MS-13 goal backing vs real Savings', () {
    late Directory dir;
    late LocalDatabase db;
    late FinancialLedgerStorage ledger;
    late ChallengeStorage goals;
    late ExpenseService expenses;
    late DateTime now;

    setUp(() async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      dir = await Directory.systemTemp.createTemp('mosave_backed_goals_');
      db = LocalDatabase.forTesting(
        '${dir.path}${Platform.pathSeparator}goals.db',
      );
      ledger = FinancialLedgerStorage(database: db);
      goals = ChallengeStorage(
        database: db, preferences: SharedPreferencesAsync(),
      );
      expenses = ExpenseService(
        ledgerStorage: ledger,
        planStorage: ExpensePlanStorage(database: db),
      );
      now = DateTime.now();
      await (await db.database).insert('app_metadata', <String, Object?>{
        'key': 'expense_plan_client_defaults_seeded_v1', 'value': '1',
      });
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    Future<void> deposit(int value, {
      FinancialUnit unit = FinancialUnit.usd,
      FinancialFund fund = FinancialFund.savings,
    }) => ledger.addEvent(FinancialEvent.create(
      type: FinancialEventType.openingBalance,
      occurredAt: now,
      entries: <LedgerEntry>[
        LedgerEntry(unit: unit, fund: fund,
          amountMicros: LedgerEntry.amountToMicros(value)),
      ],
    ));

    SavingChallenge goal(String id, {
      ChallengeCurrency currency = ChallengeCurrency.usd,
      int amount = 100,
    }) => SavingChallenge.create(
      id: id,
      name: id,
      targetAmount: amount.toDouble(),
      currency: currency,
      sequence: ChallengeSequence.ordered,
      cellCount: 1,
    );

    SavingChallenge mark(SavingChallenge g, bool completed) => g.copyWith(
      cells: <ChallengeCell>[g.cells.single.copyWith(isCompleted: completed)],
    );

    test('earmark 100 USD from existing Savings without new assets', () async {
      await deposit(200);
      final first = goal('travel');
      await goals.addChallenge(first);
      await goals.updateChallenge(mark(first, true));
      final returned = (await goals.loadChallenges()).single;
      expect(returned.isBackingVerified, isTrue);
      expect(returned.verifiedSavedAmount, 100);
      expect(returned.verifiedProgress, 1);
      expect((await goals.loadVerifiedEarmarks())['travel'],
        LedgerEntry.amountToMicros(100));
      final savingsView = await SavingsFundService(
        ledger: ledger, database: db,
        settings: FinancialSettingsStorage(database: db),
      ).loadCurrent();
      expect(savingsView.saved(FinancialUnit.usd),
        LedgerEntry.amountToMicros(200));
      expect(savingsView.reserved(FinancialUnit.usd),
        LedgerEntry.amountToMicros(100));
      expect(savingsView.free(FinancialUnit.usd),
        LedgerEntry.amountToMicros(100));
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
        LedgerEntry.amountToMicros(200));
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(200));
      expect(await ledger.loadEvents(type: FinancialEventType.income), isEmpty);
      final historicalMarker = await ledger.loadEventByRecurrenceKey(
        'challenge-progress:travel');
      expect(historicalMarker!.entries.single.affectsBalance, isFalse);
    });

    test('two goals cannot earmark the same \$100 twice', () async {
      await deposit(100);
      final a = goal('a');
      final b = goal('b');
      await goals.addChallenge(a);
      await goals.addChallenge(b);
      await goals.updateChallenge(mark(a, true));
      await expectLater(goals.updateChallenge(mark(b, true)),
        throwsA(isA<GoalBackingInsufficientException>()));
      final refreshed = await goals.loadChallenges();
      expect(refreshed.firstWhere((g) => g.id == 'a').verifiedSavedAmount, 100);
      expect(refreshed.firstWhere((g) => g.id == 'b').verifiedSavedAmount, 0);
      expect((await goals.loadVerifiedEarmarks()).values.fold<int>(
        0, (sum, value) => sum + value,
      ), LedgerEntry.amountToMicros(100));
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
        LedgerEntry.amountToMicros(100));
    });

    test('Savings outflow blocked until goal cell explicitly released',
        () async {
      await deposit(150);
      final a = goal('protected-goal');
      await goals.addChallenge(a);
      await goals.updateChallenge(mark(a, true));
      await expectLater(
        ledger.transferFunds(
          unit: FinancialUnit.usd,
          source: FinancialFund.savings,
          destination: FinancialFund.spending,
          amountMicros: LedgerEntry.amountToMicros(60),
          occurredAt: now,
        ),
        throwsA(isA<GoalBackingInsufficientException>()),
      );
      await expectLater(
        expenses.logExpense(
          amountMicros: LedgerEntry.amountToMicros(60),
          unit: FinancialUnit.usd,
          occurredAt: now,
          category: 'صحة', note: 'ضرورة',
          sourceFund: FinancialFund.savings,
        ),
        throwsA(isA<GoalBackingInsufficientException>()),
      );
      expect(await ledger.loadEvents(type: FinancialEventType.expense), isEmpty);
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(150));
      final reopened = (await goals.loadChallenges()).single;
      expect(reopened.verifiedSavedAmount, 100);
      await goals.updateChallenge(mark(reopened, false));
      await ledger.transferFunds(
        unit: FinancialUnit.usd,
        source: FinancialFund.savings,
        destination: FinancialFund.spending,
        amountMicros: LedgerEntry.amountToMicros(60),
        occurredAt: now,
      );
      expect((await goals.loadChallenges()).single.verifiedSavedAmount, 0);
      expect(await ledger.loadFundBalanceMicros(
        FinancialFund.savings, FinancialUnit.usd,
      ), LedgerEntry.amountToMicros(90));
    });

    test('delete one goal releases allocation without crediting owned cash',
        () async {
      await deposit(100);
      final a = goal('one');
      final b = goal('two');
      await goals.addChallenge(a);
      await goals.addChallenge(b);
      await goals.updateChallenge(mark(a, true));
      await goals.deleteChallenge('one');
      await goals.updateChallenge(mark(b, true));
      expect((await goals.loadChallenges()).single.verifiedSavedAmount, 100);
      expect((await goals.loadVerifiedEarmarks()).length, 1);
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
        LedgerEntry.amountToMicros(100));
    });

    test('adding an imported unverified goal never auto-pledges a cell',
        () async {
      await deposit(100);
      final base = goal('imported-old');
      final imported = SavingChallenge(
        id: base.id, name: base.name,
        targetAmount: base.targetAmount, currency: base.currency,
        sequence: base.sequence, cellCount: base.cellCount,
        cells: <ChallengeCell>[
          base.cells.single.copyWith(isCompleted: true),
        ],
        // Backing intentionally absent as it was in v9-v11 data.
      );
      await goals.addChallenge(imported);
      final saved = (await goals.loadChallenges()).single;
      expect(saved.savedAmount, 100);
      expect(saved.isBackingVerified, isFalse);
      expect(saved.verifiedSavedAmount, 0);
      expect(await goals.loadVerifiedEarmarks(), isEmpty);
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
        LedgerEntry.amountToMicros(100));
    });

    test('legacy completed cells stay unverified until deliberate consent',
        () async {
      final raw = await db.database;
      await raw.insert('challenges', <String, Object?>{
        'id': 'old', 'name': 'قديم', 'target_amount': 100.0,
        'currency': 'usd', 'sequence': 'ordered',
        'cell_count': 1, 'sort_order': 0,
      });
      await raw.insert('challenge_cells', <String, Object?>{
        'challenge_id': 'old', 'position': 0, 'value': 100,
        'is_completed': 1,
      });
      var restored = (await goals.loadChallenges()).single;
      expect(restored.savedAmount, 100); // legacy record preserved
      expect(restored.verifiedSavedAmount, 0);
      expect(restored.isBackingVerified, isFalse);
      await expectLater(
        goals.reconcileLegacyGoal('old', useExistingMarks: true),
        throwsA(isA<GoalBackingInsufficientException>()),
      );
      restored = (await goals.loadChallenges()).single;
      expect(restored.savedAmount, 100);
      expect(restored.isBackingVerified, isFalse);
      await deposit(100);
      await goals.reconcileLegacyGoal('old', useExistingMarks: true);
      restored = (await goals.loadChallenges()).single;
      expect(restored.verifiedSavedAmount, 100);
      await goals.reconcileLegacyGoal('old', useExistingMarks: true);
      expect((await goals.loadVerifiedEarmarks()).length, 1);
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
        LedgerEntry.amountToMicros(100));
    });

    test('explicit legacy reset clears old cells without fake cash', () async {
      final raw = await db.database;
      await raw.insert('challenges', <String, Object?>{
        'id': 'old', 'name': 'سابق', 'target_amount': 100.0,
        'currency': 'usd', 'sequence': 'ordered',
        'cell_count': 1, 'sort_order': 0,
      });
      await raw.insert('challenge_cells', <String, Object?>{
        'challenge_id': 'old', 'position': 0,
        'value': 100, 'is_completed': 1,
      });
      await goals.reconcileLegacyGoal('old', useExistingMarks: false);
      final verified = (await goals.loadChallenges()).single;
      expect(verified.isBackingVerified, isTrue);
      expect(verified.savedAmount, 0);
      expect(verified.verifiedSavedAmount, 0);
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd], 0);
    });

    test('historical correction cannot reduce Savings below reserved goals',
        () async {
      await deposit(200);
      final opened = (await ledger.loadEvents(
        type: FinancialEventType.openingBalance)).single;
      final g = goal('corrected');
      await goals.addChallenge(g);
      await goals.updateChallenge(mark(g, true));
      final history = TransactionHistoryService(database: db, ledger: ledger);
      await expectLater(
        history.correctAmounts(
          eventId: opened.id,
          absoluteAmountsMicros: <int>[LedgerEntry.amountToMicros(80)],
        ),
        throwsA(isA<GoalBackingInsufficientException>()),
      );
      expect((await ledger.loadBalanceMicros())[FinancialUnit.usd],
        LedgerEntry.amountToMicros(200));
      expect((await goals.loadChallenges()).single.verifiedSavedAmount, 100);
    });

    test('v11 archive keeps old checked cells pending until owner backs them',
        () async {
      await deposit(300);
      final current = goal('older-grid');
      await goals.addChallenge(current);
      await goals.updateChallenge(mark(current, true));
      final notifications = NotificationPreferencesStorage(
        preferences: SharedPreferencesAsync(),
      );
      final exporter = BackupService(database: db,
        notificationPreferencesStorage: notifications);
      final modern = jsonDecode(utf8.decode(await exporter.createBackupBytes()))
          as Map<String, dynamic>;
      final payload = jsonDecode(modern['payloadJson'] as String)
          as Map<String, dynamic>;
      (payload['tables'] as Map<String, dynamic>).remove('goal_earmarks');
      final payloadJson = jsonEncode(payload);
      modern['databaseSchemaVersion'] = 11;
      modern['payloadJson'] = payloadJson;
      modern['checksumSha256'] =
          sha256.convert(utf8.encode(payloadJson)).toString();
      final archived = Uint8List.fromList(utf8.encode(jsonEncode(modern)));
      final target = LocalDatabase.forTesting(
        '${dir.path}${Platform.pathSeparator}older.db',
      );
      try {
        final importer = BackupService(database: target,
          notificationPreferencesStorage: notifications);
        await importer.restoreBackupBytes(archived);
        final oldGoals = ChallengeStorage(database: target,
          preferences: SharedPreferencesAsync());
        final loaded = (await oldGoals.loadChallenges()).single;
        expect(loaded.savedAmount, 100); // the old cells survive unchanged
        expect(loaded.verifiedSavedAmount, 0); // NO automatic reservation
        expect(loaded.isBackingVerified, isFalse);
        expect(await oldGoals.loadVerifiedEarmarks(), isEmpty);
        expect((await FinancialLedgerStorage(database: target)
          .loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(300));
        await oldGoals.reconcileLegacyGoal('older-grid',
          useExistingMarks: true);
        expect((await oldGoals.loadChallenges()).single.verifiedSavedAmount,
          100);
      } finally {
        await target.close();
      }
    });

    test('invalid v12 earmark backup rolls back without deleting prior data',
        () async {
      await deposit(300);
      final g = goal('restore-goal');
      await goals.addChallenge(g);
      await goals.updateChallenge(mark(g, true));
      final notifications = NotificationPreferencesStorage(
        preferences: SharedPreferencesAsync(),
      );
      final exporter = BackupService(database: db,
        notificationPreferencesStorage: notifications);
      final modern = jsonDecode(utf8.decode(await exporter.createBackupBytes()))
          as Map<String, dynamic>;
      final payload = jsonDecode(modern['payloadJson'] as String)
          as Map<String, dynamic>;
      final earmarks = (payload['tables'] as Map<String, dynamic>)
          ['goal_earmarks'] as List<dynamic>;
      (earmarks.single as Map<String, dynamic>)['amount_micros'] =
          LedgerEntry.amountToMicros(500);
      final payloadJson = jsonEncode(payload);
      modern['payloadJson'] = payloadJson;
      modern['checksumSha256'] =
          sha256.convert(utf8.encode(payloadJson)).toString();
      final target = LocalDatabase.forTesting(
        '${dir.path}${Platform.pathSeparator}refuse.db',
      );
      final targetLedger = FinancialLedgerStorage(database: target);
      try {
        await targetLedger.addEvent(FinancialEvent.create(
          type: FinancialEventType.openingBalance,
          occurredAt: now,
          entries: <LedgerEntry>[
            LedgerEntry(unit: FinancialUnit.usd,
              amountMicros: LedgerEntry.amountToMicros(55),
              fund: FinancialFund.savings),
          ],
        ));
        final importer = BackupService(database: target,
          notificationPreferencesStorage: notifications);
        await expectLater(
          importer.restoreBackupBytes(Uint8List.fromList(
            utf8.encode(jsonEncode(modern)),
          )),
          throwsA(isA<BackupException>()),
        );
        expect((await targetLedger.loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(55));
        expect(await (await target.database).query('goal_earmarks'), isEmpty);
        expect(await (await target.database).query('challenges'), isEmpty);
      } finally {
        await target.close();
      }
    });

    test('v12 backup restores pledged goals and v11 keeps legacy pending',
        () async {
      await deposit(300);
      final g = goal('saved-trip');
      await goals.addChallenge(g);
      await goals.updateChallenge(mark(g, true));
      final notifications = NotificationPreferencesStorage(
        preferences: SharedPreferencesAsync(),
      );
      final exporter = BackupService(database: db,
        notificationPreferencesStorage: notifications);
      final original = await exporter.createBackupBytes();
      final target = LocalDatabase.forTesting(
        '${dir.path}${Platform.pathSeparator}restored.db',
      );
      final importer = BackupService(database: target,
        notificationPreferencesStorage: notifications);
      try {
        await importer.restoreBackupBytes(original);
        final restored = ChallengeStorage(database: target,
          preferences: SharedPreferencesAsync());
        final one = (await restored.loadChallenges()).single;
        expect(one.verifiedSavedAmount, 100);
        expect((await FinancialLedgerStorage(database: target)
          .loadBalanceMicros())[FinancialUnit.usd],
          LedgerEntry.amountToMicros(300));
      } finally {
        await target.close();
      }
    });
  });
}
