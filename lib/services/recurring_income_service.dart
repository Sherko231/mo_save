import 'package:sqflite/sqflite.dart';

import '../models/expected_income.dart';
import '../models/financial_event.dart';
import '../models/financial_settings.dart';
import 'financial_ledger_storage.dart';
import 'financial_settings_storage.dart';
import 'local_database.dart';

class RecurringIncomeService {
  RecurringIncomeService({
    FinancialSettingsStorage? settingsStorage,
    FinancialLedgerStorage? ledgerStorage,
    LocalDatabase? database,
  })  : _settingsStorage = settingsStorage ?? FinancialSettingsStorage(),
        _ledgerStorage = ledgerStorage ?? FinancialLedgerStorage(),
        _database = database ?? LocalDatabase.instance;

  static const String _ignoredPrefix = 'ignored_income_occurrence:';
  final FinancialSettingsStorage _settingsStorage;
  final FinancialLedgerStorage _ledgerStorage;
  final LocalDatabase _database;

  Future<List<ExpectedIncome>> loadMonth(DateTime month) async {
    final FinancialSettings settings = await _settingsStorage.loadSettings();
    final DateTime monthStart = DateTime(month.year, month.month, 1);

    final List<ExpectedIncome> expected = _buildExpectedMonth(
      settings: settings,
      monthStart: monthStart,
    );

    final List<FinancialEvent> incomeEvents =
        await _ledgerStorage.loadRecurringIncomeEventsForMonth(monthStart);
    final Map<String, FinancialEvent> receivedByKey = <String, FinancialEvent>{
      for (final event in incomeEvents)
        if (event.recurrenceKey != null) event.recurrenceKey!: event,
    };
    final Database database = await _database.database;
    final ignoredRows = await database.query(
      'app_metadata',
      columns: <String>['key'],
      where: 'key LIKE ?',
      whereArgs: <Object?>[
        '${_ignoredPrefix}income:%:${monthStart.year}-'
            '${monthStart.month.toString().padLeft(2, '0')}-%',
      ],
    );
    final ignoredKeys = ignoredRows
        .map((row) => (row['key']! as String).substring(_ignoredPrefix.length))
        .toSet();
    final Map<String, ExpectedIncome> byKey = <String, ExpectedIncome>{
      for (final occurrence in expected) occurrence.recurrenceKey: occurrence,
    };
    // Actual receipts survive a later change of salary schedule or amount.
    for (final event in incomeEvents) {
      final key = event.recurrenceKey;
      if (key == null || byKey.containsKey(key)) continue;
      final recorded = _parseRecordedOccurrence(event);
      if (recorded != null) byKey[key] = recorded;
    }
    final result = byKey.values.map((occurrence) {
      final received = receivedByKey[occurrence.recurrenceKey];
      if (received != null) return occurrence.copyWithReceived(received);
      return ignoredKeys.contains(occurrence.recurrenceKey)
          ? occurrence.copyWithIgnored()
          : occurrence;
    }).toList(growable: false);
    result.sort((a, b) {
      final date = a.scheduledDate.compareTo(b.scheduledDate);
      return date != 0 ? date : a.kind.index.compareTo(b.kind.index);
    });
    return result;
  }

  Future<ExpectedIncome?> loadNextExpected({DateTime? from}) async {
    final DateTime now = from ?? DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    for (int monthOffset = 0; monthOffset < 3; monthOffset++) {
      final DateTime month = DateTime(today.year, today.month + monthOffset, 1);
      final List<ExpectedIncome> occurrences = await loadMonth(month);
      for (final ExpectedIncome occurrence in occurrences) {
        if (occurrence.needsAction && !occurrence.scheduledDate.isBefore(today)) {
          return occurrence;
        }
      }
    }

    return null;
  }

  Future<FinancialEvent> confirmReceived({
    required ExpectedIncome occurrence,
    required int amountMicros,
    DateTime? receivedAt,
    int alreadySpentMicros = 0,
    String? spentCategory,
    String? spentNote,
  }) async {
    if (amountMicros <= 0) {
      throw ArgumentError.value(
        amountMicros,
        'amountMicros',
        'Received amount must be positive.',
      );
    }

    _validateOccurrence(occurrence);
    final today = _calendarDay(DateTime.now());
    if (_calendarDay(occurrence.scheduledDate).isAfter(today)) {
      throw StateError('Future recurring income cannot be confirmed yet.');
    }
    if (alreadySpentMicros < 0 || alreadySpentMicros > amountMicros) {
      throw ArgumentError('Historical expense must not exceed receipt.');
    }
    final DateTime actualDay = _calendarDay(
      receivedAt ?? occurrence.scheduledDate,
    );
    if (actualDay.isAfter(today)) {
      throw ArgumentError('Actual receipt date cannot be in the future.');
    }
    final FinancialEvent? existing =
        await _ledgerStorage.loadEventByRecurrenceKey(occurrence.recurrenceKey);
    if (existing != null) {
      throw StateError('This recurring income occurrence is already confirmed.');
    }

    final DateTime scheduledLocal = actualDay;
    final FinancialEvent event = FinancialEvent.create(
      type: FinancialEventType.income,
      occurredAt: DateTime(
        scheduledLocal.year,
        scheduledLocal.month,
        scheduledLocal.day,
        12,
      ),
      entries: <LedgerEntry>[
        LedgerEntry(
          unit: occurrence.unit,
          amountMicros: amountMicros,
        ),
      ],
      category: occurrence.kind == RecurringIncomeKind.weeklySyp
          ? 'راتب أسبوعي'
          : 'راتب شهري',
      note: occurrence.kind == RecurringIncomeKind.weeklySyp
          ? 'استلام راتب الخميس'
          : 'استلام راتب أول الشهر',
      recurrenceKey: occurrence.recurrenceKey,
    );

    final FinancialEvent? spent = alreadySpentMicros == 0
        ? null
        : FinancialEvent.create(
            id: 'historical_spent_${event.id}',
            type: FinancialEventType.expense,
            occurredAt: DateTime(
              actualDay.year, actualDay.month, actualDay.day, 12,
            ),
            entries: <LedgerEntry>[
              LedgerEntry(
                unit: occurrence.unit,
                amountMicros: -alreadySpentMicros,
                fund: FinancialFund.unallocated,
              ),
            ],
            sourceEventId: event.id,
            category: (spentCategory?.trim().isNotEmpty ?? false)
                ? spentCategory!.trim()
                : 'مصاريف راتب سابق',
            note: spentNote?.trim().isNotEmpty == true
                ? spentNote!.trim()
                : 'مبلغ صُرف سابقاً من هذه الدفعة',
          );
    await _ledgerStorage.addRecurringIncomeReceipt(
      income: event,
      historicalExpense: spent,
    );
    return event;
  }

  /// Ignore one occurrence without posting any money.
  /// This metadata is already included in the portable app backup.
  Future<void> ignoreOccurrence(ExpectedIncome occurrence) async {
    _validateOccurrence(occurrence);
    if (_calendarDay(occurrence.scheduledDate)
        .isAfter(_calendarDay(DateTime.now()))) {
      throw StateError('Future income cannot be ignored yet.');
    }
    final Database database = await _database.database;
    await database.transaction((transaction) async {
      final existing = await transaction.query(
        'financial_events',
        columns: <String>['id'],
        where: 'recurrence_key = ?',
        whereArgs: <Object?>[occurrence.recurrenceKey],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw StateError('Received income cannot be ignored.');
      }
      await transaction.insert(
        'app_metadata',
        <String, Object?>{
          'key': '$_ignoredPrefix${occurrence.recurrenceKey}',
          'value': '1',
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    });
  }

  /// Undo ignoring a single occurrence. It remains unpaid until recorded.
  Future<void> undoIgnore(ExpectedIncome occurrence) async {
    _validateOccurrence(occurrence);
    final Database database = await _database.database;
    await database.delete(
      'app_metadata',
      where: 'key = ?',
      whereArgs: <Object?>['$_ignoredPrefix${occurrence.recurrenceKey}'],
    );
  }

  static DateTime _calendarDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static void _validateOccurrence(ExpectedIncome occurrence) {
    if (_recurrenceKey(
      kind: occurrence.kind,
      date: occurrence.scheduledDate,
    ) != occurrence.recurrenceKey) {
      throw ArgumentError('Recurring occurrence key and date disagree.');
    }
    if ((occurrence.kind == RecurringIncomeKind.weeklySyp &&
            occurrence.unit != FinancialUnit.syp) ||
        (occurrence.kind == RecurringIncomeKind.monthlyUsd &&
            occurrence.unit != FinancialUnit.usd)) {
      throw ArgumentError('Recurring income kind and unit disagree.');
    }
  }

  static ExpectedIncome? _parseRecordedOccurrence(FinancialEvent event) {
    final key = event.recurrenceKey;
    if (key == null) return null;
    final match = RegExp(
      r'^income:(weeklySyp|monthlyUsd):(\d{4})-(\d{2})-(\d{2})$',
    ).firstMatch(key);
    if (match == null) return null;
    final kind = match.group(1) == 'weeklySyp'
        ? RecurringIncomeKind.weeklySyp
        : RecurringIncomeKind.monthlyUsd;
    final date = DateTime(
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
    );
    if (_recurrenceKey(kind: kind, date: date) != key) return null;
    final unit = kind == RecurringIncomeKind.weeklySyp
        ? FinancialUnit.syp : FinancialUnit.usd;
    final amount = event.balanceDeltaMicros(unit);
    if (amount <= 0) return null;
    return ExpectedIncome(
      recurrenceKey: key,
      kind: kind,
      scheduledDate: date,
      unit: unit,
      expectedAmountMicros: amount,
      receivedEvent: event,
    );
  }

  static List<ExpectedIncome> _buildExpectedMonth({
    required FinancialSettings settings,
    required DateTime monthStart,
  }) {
    final int daysInMonth = DateTime(
      monthStart.year,
      monthStart.month + 1,
      0,
    ).day;
    final List<ExpectedIncome> result = <ExpectedIncome>[];

    for (int day = 1; day <= daysInMonth; day++) {
      final DateTime date = DateTime(monthStart.year, monthStart.month, day);
      if (date.weekday == settings.weeklyPayday &&
          settings.weeklySypIncome > 0) {
        result.add(
          ExpectedIncome(
            recurrenceKey: _recurrenceKey(
              kind: RecurringIncomeKind.weeklySyp,
              date: date,
            ),
            kind: RecurringIncomeKind.weeklySyp,
            scheduledDate: date,
            unit: FinancialUnit.syp,
            expectedAmountMicros:
                LedgerEntry.amountToMicros(settings.weeklySypIncome),
          ),
        );
      }
    }

    if (settings.monthlyUsdIncome > 0) {
      final int payday = settings.monthlyPayday.clamp(1, daysInMonth).toInt();
      final DateTime date = DateTime(monthStart.year, monthStart.month, payday);
      result.add(
        ExpectedIncome(
          recurrenceKey: _recurrenceKey(
            kind: RecurringIncomeKind.monthlyUsd,
            date: date,
          ),
          kind: RecurringIncomeKind.monthlyUsd,
          scheduledDate: date,
          unit: FinancialUnit.usd,
          expectedAmountMicros:
              LedgerEntry.amountToMicros(settings.monthlyUsdIncome),
        ),
      );
    }

    result.sort((a, b) {
      final int dateCompare = a.scheduledDate.compareTo(b.scheduledDate);
      if (dateCompare != 0) {
        return dateCompare;
      }
      return a.kind.index.compareTo(b.kind.index);
    });
    return result;
  }

  static String _recurrenceKey({
    required RecurringIncomeKind kind,
    required DateTime date,
  }) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return 'income:${kind.name}:${date.year}-$month-$day';
  }
}
