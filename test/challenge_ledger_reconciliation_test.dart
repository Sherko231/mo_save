import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/models/saving_challenge.dart';
import 'package:mo_save/services/challenge_storage.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/local_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('challenge ledger reconciliation', () {
    late Directory tempDirectory;
    late LocalDatabase database;
    late ChallengeStorage storage;
    late FinancialLedgerStorage ledger;

    setUp(() async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      tempDirectory = await Directory.systemTemp.createTemp('mo_save_goal_');
      database = LocalDatabase.forTesting(
        '${tempDirectory.path}${Platform.pathSeparator}goal.db',
      );
      storage = ChallengeStorage(
        database: database,
        preferences: SharedPreferencesAsync(),
      );
      ledger = FinancialLedgerStorage(database: database);
    });

    tearDown(() async {
      await database.close();
      await tempDirectory.delete(recursive: true);
    });

    test('completed cells keep one canonical non-balance contribution', () async {
      final base = SavingChallenge.create(
        id: 'goal-1',
        name: 'هدف',
        targetAmount: 100,
        currency: ChallengeCurrency.usd,
        sequence: ChallengeSequence.ordered,
        cellCount: 4,
      );
      await storage.addChallenge(base);

      final firstProgress = base.copyWith(
        cells: <ChallengeCell>[
          base.cells[0].copyWith(isCompleted: true),
          base.cells[1].copyWith(isCompleted: true),
          ...base.cells.skip(2),
        ],
      );
      await storage.updateChallenge(firstProgress);

      final firstEvent = await ledger.loadEventByRecurrenceKey(
        'challenge-progress:goal-1',
      );
      final firstEventId = firstEvent!.id;
      expect(firstEvent.type, FinancialEventType.savingContribution);
      expect(firstEvent.relatedChallengeId, 'goal-1');
      expect(firstEvent.entries, hasLength(1));
      expect(firstEvent.entries.single.affectsBalance, isFalse);
      expect(
        firstEvent.entries.single.amountMicros,
        firstProgress.savedAmount * LedgerEntry.microsPerUnit,
      );

      final secondProgress = firstProgress.copyWith(
        cells: <ChallengeCell>[
          firstProgress.cells[0].copyWith(isCompleted: false),
          ...firstProgress.cells.skip(1),
        ],
      );
      await storage.updateChallenge(secondProgress);

      final secondEvent = await ledger.loadEventByRecurrenceKey(
        'challenge-progress:goal-1',
      );
      expect(secondEvent, isNotNull);
      expect(secondEvent!.id, firstEventId);
      expect(
        secondEvent.entries.single.amountMicros,
        secondProgress.savedAmount * LedgerEntry.microsPerUnit,
      );

      final balances = await ledger.loadBalanceMicros();
      expect(balances.values.every((value) => value == 0), isTrue);

      final sqlite = await database.database;
      final rows = await sqlite.query(
        'financial_events',
        where: 'recurrence_key = ?',
        whereArgs: <Object?>['challenge-progress:goal-1'],
      );
      expect(rows, hasLength(1));
    });

    test('undoing all completed cells removes contribution event', () async {
      final base = SavingChallenge.create(
        id: 'goal-undo',
        name: 'تراجع',
        targetAmount: 100,
        currency: ChallengeCurrency.usd,
        sequence: ChallengeSequence.ordered,
        cellCount: 4,
      );
      final withProgress = base.copyWith(
        cells: <ChallengeCell>[
          base.cells[0].copyWith(isCompleted: true),
          ...base.cells.skip(1),
        ],
      );
      await storage.addChallenge(withProgress);
      expect(
        await ledger.loadEventByRecurrenceKey('challenge-progress:goal-undo'),
        isNotNull,
      );

      final cleared = withProgress.copyWith(
        cells: <ChallengeCell>[
          for (final cell in withProgress.cells)
            cell.copyWith(isCompleted: false),
        ],
      );
      await storage.updateChallenge(cleared);

      expect(
        await ledger.loadEventByRecurrenceKey('challenge-progress:goal-undo'),
        isNull,
      );
    });
  });
}
