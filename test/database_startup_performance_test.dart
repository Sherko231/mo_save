import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/financial_event.dart';
import 'package:mo_save/services/financial_ledger_storage.dart';
import 'package:mo_save/services/local_database.dart';

void main() {
  late Directory tempDirectory;
  late LocalDatabase database;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('mo_save_open_race_');
    database = LocalDatabase.forTesting(
      '${tempDirectory.path}${Platform.pathSeparator}finance.db',
    );
  });

  tearDown(() async {
    await database.close();
    await tempDirectory.delete(recursive: true);
  });

  test('simultaneous first reads share a single SQLite open', () async {
    final opened = await Future.wait(
      List.generate(25, (_) => database.database),
    );

    expect(opened.length, 25);
    expect(opened.every((handle) => identical(handle, opened.first)), isTrue);

    final rows = await opened.first.rawQuery(
      "SELECT COUNT(*) AS n FROM sqlite_master WHERE type='table' AND name='financial_events'",
    );
    expect((rows.single['n'] as num).toInt(), 1);

    await database.close();
    final reopened = await database.database;
    expect(identical(reopened, opened.first), isFalse);
  });

  test('batched event hydration preserves entry order across chunks', () async {
    final db = await database.database;
    final batch = db.batch();
    const count = 405;
    for (var i = 0; i < count; i++) {
      final id = 'history-$i';
      batch.insert('financial_events', {
        'id': id,
        'event_type': FinancialEventType.income.name,
        'occurred_at_ms': 1700000000000 + i * 1000,
        'created_at_ms': 1700000000000,
        'updated_at_ms': 1700000000000,
      });
      for (var position = 0; position < 2; position++) {
        batch.insert('financial_event_entries', {
          'event_id': id,
          'position': position,
          'unit': FinancialUnit.usd.name,
          'amount_micros': position == 0 ? 1000000 : 500000,
          'affects_balance': 1,
          'fund': position == 0
              ? FinancialFund.savings.name
              : FinancialFund.spending.name,
        });
      }
    }
    await batch.commit(noResult: true);

    final events = await FinancialLedgerStorage(
      database: database,
    ).loadEvents();

    expect(events.length, count);
    expect(events.first.id, 'history-404');
    expect(events.last.id, 'history-0');
    for (final event in events) {
      expect(event.entries.length, 2);
      expect(event.entries[0].fund, FinancialFund.savings);
      expect(event.entries[0].amountMicros, 1000000);
      expect(event.entries[1].fund, FinancialFund.spending);
      expect(event.entries[1].amountMicros, 500000);
    }
  });
}
