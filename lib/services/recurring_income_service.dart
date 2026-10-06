import '../models/expected_income.dart';
import '../models/financial_event.dart';
import '../models/financial_settings.dart';
import 'financial_ledger_storage.dart';
import 'financial_settings_storage.dart';

class RecurringIncomeService {
  RecurringIncomeService({
    FinancialSettingsStorage? settingsStorage,
    FinancialLedgerStorage? ledgerStorage,
  })  : _settingsStorage = settingsStorage ?? FinancialSettingsStorage(),
        _ledgerStorage = ledgerStorage ?? FinancialLedgerStorage();

  final FinancialSettingsStorage _settingsStorage;
  final FinancialLedgerStorage _ledgerStorage;

  Future<List<ExpectedIncome>> loadMonth(DateTime month) async {
    final FinancialSettings settings = await _settingsStorage.loadSettings();
    final DateTime monthStart = DateTime(month.year, month.month, 1);
    final DateTime nextMonth = DateTime(month.year, month.month + 1, 1);

    final List<ExpectedIncome> expected = _buildExpectedMonth(
      settings: settings,
      monthStart: monthStart,
    );

    final List<FinancialEvent> incomeEvents = await _ledgerStorage.loadEvents(
      from: monthStart,
      to: nextMonth,
      type: FinancialEventType.income,
    );

    final Map<String, FinancialEvent> receivedByKey = <String, FinancialEvent>{
      for (final FinancialEvent event in incomeEvents)
        if (event.recurrenceKey != null) event.recurrenceKey!: event,
    };

    return expected
        .map(
          (occurrence) => receivedByKey[occurrence.recurrenceKey] == null
              ? occurrence
              : occurrence.copyWithReceived(
                  receivedByKey[occurrence.recurrenceKey]!,
                ),
        )
        .toList(growable: false);
  }

  Future<ExpectedIncome?> loadNextExpected({DateTime? from}) async {
    final DateTime now = from ?? DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    for (int monthOffset = 0; monthOffset < 3; monthOffset++) {
      final DateTime month = DateTime(today.year, today.month + monthOffset, 1);
      final List<ExpectedIncome> occurrences = await loadMonth(month);
      for (final ExpectedIncome occurrence in occurrences) {
        if (!occurrence.isReceived && !occurrence.scheduledDate.isBefore(today)) {
          return occurrence;
        }
      }
    }

    return null;
  }

  Future<FinancialEvent> confirmReceived({
    required ExpectedIncome occurrence,
    required int amountMicros,
  }) async {
    if (amountMicros <= 0) {
      throw ArgumentError.value(
        amountMicros,
        'amountMicros',
        'Received amount must be positive.',
      );
    }

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime scheduledDay = DateTime(
      occurrence.scheduledDate.year,
      occurrence.scheduledDate.month,
      occurrence.scheduledDate.day,
    );
    if (scheduledDay.isAfter(today)) {
      throw StateError('Future recurring income cannot be confirmed yet.');
    }

    final FinancialEvent? existing =
        await _ledgerStorage.loadEventByRecurrenceKey(occurrence.recurrenceKey);
    if (existing != null) {
      throw StateError('This recurring income occurrence is already confirmed.');
    }

    final DateTime scheduledLocal = occurrence.scheduledDate;
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

    await _ledgerStorage.addEvent(event);
    return event;
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
