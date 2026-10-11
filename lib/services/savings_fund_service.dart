import '../models/financial_balance_snapshot.dart';
import '../models/financial_event.dart';
import 'financial_ledger_storage.dart';
import 'financial_settings_storage.dart';
import 'local_database.dart';

/// One month's realized, per-unit change to the Savings fund.
///
/// "Funding" means actual cash/asset deposits assigned to Savings or
/// reclassifications from another fund, NOT newly earned income in every case.
/// Principal from FX/gold exchanges and opening/technical adjustments remain
/// separately identified; reference-price fluctuations are not ledger entries.
class SavingsMonthMovement {
  SavingsMonthMovement({
    required this.month,
    required Map<FinancialUnit, int> receivedMicros,
    required Map<FinancialUnit, int> transferredInMicros,
    required Map<FinancialUnit, int> paidExpenseMicros,
    required Map<FinancialUnit, int> transferredOutMicros,
    required Map<FinancialUnit, int> openingMicros,
    required Map<FinancialUnit, int> convertedMicros,
    required Map<FinancialUnit, int> otherMicros,
  }) : receivedMicros = Map.unmodifiable(receivedMicros),
       transferredInMicros = Map.unmodifiable(transferredInMicros),
       paidExpenseMicros = Map.unmodifiable(paidExpenseMicros),
       transferredOutMicros = Map.unmodifiable(transferredOutMicros),
       openingMicros = Map.unmodifiable(openingMicros),
       convertedMicros = Map.unmodifiable(convertedMicros),
       otherMicros = Map.unmodifiable(otherMicros);

  final DateTime month;
  final Map<FinancialUnit, int> receivedMicros;
  final Map<FinancialUnit, int> transferredInMicros;
  final Map<FinancialUnit, int> paidExpenseMicros;
  final Map<FinancialUnit, int> transferredOutMicros;
  final Map<FinancialUnit, int> openingMicros;
  /// Signed movement resulting from a trade, NOT earned or saved cash.
  final Map<FinancialUnit, int> convertedMicros;
  /// Corrections and older bookkeeping events, not assumed fresh savings.
  final Map<FinancialUnit, int> otherMicros;

  int _amount(Map<FinancialUnit, int> amounts, FinancialUnit unit) =>
      amounts[unit] ?? 0;

  int received(FinancialUnit unit) => _amount(receivedMicros, unit);
  int transferredIn(FinancialUnit unit) => _amount(transferredInMicros, unit);
  int paidFromSavings(FinancialUnit unit) => _amount(paidExpenseMicros, unit);
  int transferredOut(FinancialUnit unit) => _amount(transferredOutMicros, unit);
  int opening(FinancialUnit unit) => _amount(openingMicros, unit);
  int converted(FinancialUnit unit) => _amount(convertedMicros, unit);
  int other(FinancialUnit unit) => _amount(otherMicros, unit);

  int added(FinancialUnit unit) => received(unit) + transferredIn(unit);
  int withdrawn(FinancialUnit unit) =>
      paidFromSavings(unit) + transferredOut(unit);

  /// Real fund change through receipts, direct payments and reclassification.
  /// It excludes openings, conversions and reference-price movements.
  int netFunding(FinancialUnit unit) => added(unit) - withdrawn(unit);

  /// Exact change of Savings ledger holdings in this unit for the month.
  int netFundMovement(FinancialUnit unit) =>
      netFunding(unit) + opening(unit) + converted(unit) + other(unit);
}

class SavingsFundSnapshot {
  SavingsFundSnapshot({
    required this.asOf,
    required Map<FinancialFund, Map<FinancialUnit, int>> fundBalancesMicros,
    required Map<FinancialUnit, int> ownedMicros,
    required Map<FinancialUnit, int> reservedMicros,
    required this.valuation,
    required List<SavingsMonthMovement> trend,
  }) : fundBalancesMicros = Map.unmodifiable({
         for (final fund in FinancialFund.values)
           fund: Map<FinancialUnit, int>.unmodifiable({
             for (final unit in FinancialUnit.values)
               unit: fundBalancesMicros[fund]?[unit] ?? 0,
           }),
       }),
       reservedMicros = Map.unmodifiable({
         for (final unit in FinancialUnit.values) unit: reservedMicros[unit] ?? 0,
       }),
       ownedMicros = Map.unmodifiable({
         for (final unit in FinancialUnit.values)
           unit: ownedMicros[unit] ?? 0,
       }),
       trend = List.unmodifiable(trend);

  final DateTime asOf;
  final Map<FinancialFund, Map<FinancialUnit, int>> fundBalancesMicros;
  final Map<FinancialUnit, int> ownedMicros;
  final Map<FinancialUnit, int> reservedMicros;
  /// Built from Savings amounts only, not all owned cash/gold.
  final FinancialBalanceSnapshot valuation;
  /// Oldest month first, last element is current calendar month.
  final List<SavingsMonthMovement> trend;

  int fundAmount(FinancialFund fund, FinancialUnit unit) =>
      fundBalancesMicros[fund]?[unit] ?? 0;
  int saved(FinancialUnit unit) => fundAmount(FinancialFund.savings, unit);
  int reserved(FinancialUnit unit) => reservedMicros[unit] ?? 0;
  int free(FinancialUnit unit) => saved(unit) - reserved(unit);
  int totalOwned(FinancialUnit unit) => ownedMicros[unit] ?? 0;
  int notSaved(FinancialUnit unit) =>
      fundAmount(FinancialFund.spending, unit) +
      fundAmount(FinancialFund.unallocated, unit);
  SavingsMonthMovement get thisMonth => trend.last;

  bool get reconcilesWithOwned => FinancialUnit.values.every(
    (unit) => FinancialFund.values.fold<int>(
      0, (sum, fund) => sum + fundAmount(fund, unit),
    ) == totalOwned(unit),
  );
}

class SavingsFundService {
  SavingsFundService({
    FinancialLedgerStorage? ledger,
    FinancialSettingsStorage? settings,
    LocalDatabase? database,
  }) : _ledger = ledger ?? FinancialLedgerStorage(),
       _settings = settings ?? FinancialSettingsStorage(),
       _database = database ?? LocalDatabase.instance;

  final FinancialLedgerStorage _ledger;
  final FinancialSettingsStorage _settings;
  final LocalDatabase _database;

  Future<SavingsFundSnapshot> loadCurrent({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final firstMonth = DateTime(today.year, today.month - 5);
    final nextMonth = DateTime(today.year, today.month + 1);
    final funds = await _ledger.loadFundBalancesMicros();
    final owned = await _ledger.loadBalanceMicros();
    final reserveRows = await (await _database.database).rawQuery('''
      SELECT unit, SUM(amount_micros) AS amount
      FROM goal_earmarks GROUP BY unit
    ''');
    final reserved = <FinancialUnit, int>{
      for (final unit in FinancialUnit.values) unit: 0,
    };
    for (final row in reserveRows) {
      final unit = FinancialUnit.values.byName(row['unit']! as String);
      reserved[unit] = (row['amount']! as num).toInt();
    }
    final settings = await _settings.loadSettings();
    final events = await _ledger.loadEvents(from: firstMonth, to: nextMonth);

    final builders = <int, _SavingsMovementBuilder>{
      for (int i = 0; i < 6; i++)
        _monthKey(DateTime(firstMonth.year, firstMonth.month + i)):
            _SavingsMovementBuilder(),
    };

    for (final event in events) {
      final local = event.occurredAt.toLocal();
      final builder = builders[_monthKey(local)];
      if (builder == null) continue;
      for (final entry in event.entries) {
        if (entry.fund != FinancialFund.savings) continue;
        if (event.type == FinancialEventType.fundTransfer) {
          builder.add(
            entry.amountMicros >= 0 ? builder.transferredIn : builder.transferredOut,
            entry.unit,
            entry.amountMicros.abs(),
          );
          continue;
        }
        if (!entry.affectsBalance) continue;
        switch (event.type) {
          case FinancialEventType.income:
            builder.add(builder.received, entry.unit, entry.amountMicros);
          case FinancialEventType.expense:
            builder.add(builder.expenses, entry.unit, -entry.amountMicros);
          case FinancialEventType.openingBalance:
            builder.add(builder.opening, entry.unit, entry.amountMicros);
          case FinancialEventType.currencyConversion:
          case FinancialEventType.goldPurchase:
          case FinancialEventType.goldSale:
            builder.add(builder.converted, entry.unit, entry.amountMicros);
          default:
            builder.add(builder.other, entry.unit, entry.amountMicros);
        }
      }
    }

    final months = <SavingsMonthMovement>[];
    for (int i = 0; i < 6; i++) {
      final month = DateTime(firstMonth.year, firstMonth.month + i);
      months.add(builders[_monthKey(month)]!.snapshot(month));
    }
    final savings = funds[FinancialFund.savings]!;
    final valuation = FinancialBalanceSnapshot(
      balancesMicros: savings,
      referenceSypPerUsd: settings.referenceSypPerUsd,
      goldUsdPerGram: settings.goldUsdPerGram,
    );
    return SavingsFundSnapshot(
      asOf: today,
      fundBalancesMicros: funds,
      ownedMicros: owned,
      reservedMicros: reserved,
      valuation: valuation,
      trend: months,
    );
  }

  static int _monthKey(DateTime d) => d.year * 100 + d.month;
}

class _SavingsMovementBuilder {
  final received = <FinancialUnit, int>{};
  final transferredIn = <FinancialUnit, int>{};
  final expenses = <FinancialUnit, int>{};
  final transferredOut = <FinancialUnit, int>{};
  final opening = <FinancialUnit, int>{};
  final converted = <FinancialUnit, int>{};
  final other = <FinancialUnit, int>{};

  void add(Map<FinancialUnit, int> source, FinancialUnit unit, int amount) {
    source[unit] = (source[unit] ?? 0) + amount;
  }

  SavingsMonthMovement snapshot(DateTime month) => SavingsMonthMovement(
    month: month,
    receivedMicros: received,
    transferredInMicros: transferredIn,
    paidExpenseMicros: expenses,
    transferredOutMicros: transferredOut,
    openingMicros: opening,
    convertedMicros: converted,
    otherMicros: other,
  );
}
