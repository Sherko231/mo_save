import 'package:sqflite/sqflite.dart';

import '../models/financial_event.dart';
import '../models/recurring_expense_item.dart';
import 'local_database.dart';

/// A scheduled plan revision is *not* an actual payment. Versions remain
/// immutable for earlier months after an edit or scheduled removal.
class ExpensePlanChange {
  const ExpensePlanChange({
    required this.itemId,
    required this.effectiveMonth,
    required this.name,
    required this.unit,
    required this.amountMicros,
    required this.isActive,
  });

  final String itemId;
  final DateTime effectiveMonth;
  final String name;
  final FinancialUnit unit;
  final int amountMicros;
  final bool isActive;
}

class ExpensePlanStorage {
  ExpensePlanStorage({LocalDatabase? database})
      : _database = database ?? LocalDatabase.instance;

  static const String _seedMetadataKey = 'expense_plan_client_defaults_seeded_v1';

  final LocalDatabase _database;

  /// Current month's plan, not all future scheduled revisions.
  Future<List<RecurringExpenseItem>> loadItems() =>
      loadItemsForMonth(DateTime.now());

  /// The effective values for this particular calendar month. Historical
  /// months never read the currently edited latest row as a replacement.
  Future<List<RecurringExpenseItem>> loadItemsForMonth(DateTime month) async {
    final database = await _database.database;
    await _ensureInitialDefaults(database);
    final effective = _monthKey(month);
    final rows = await database.rawQuery('''
      SELECT b.id, b.sort_order, b.created_at_ms,
        v.name, v.unit, v.amount_micros, v.recorded_at_ms
      FROM recurring_expense_items b
      JOIN recurring_expense_plan_versions v
        ON v.item_id = b.id
      WHERE v.effective_month = (
        SELECT MAX(v2.effective_month)
        FROM recurring_expense_plan_versions v2
        WHERE v2.item_id = b.id AND v2.effective_month <= ?
      )
      AND v.is_active = 1
      ORDER BY b.sort_order ASC, b.created_at_ms ASC, b.id ASC
    ''', <Object?>[effective]);
    return rows.map((row) => RecurringExpenseItem(
      id: row['id']! as String,
      name: row['name']! as String,
      unit: _parseUnit(row['unit']! as String),
      amountMicros: (row['amount_micros']! as num).toInt(),
      sortOrder: (row['sort_order']! as num).toInt(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (row['created_at_ms']! as num).toInt(), isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (row['recorded_at_ms']! as num).toInt(), isUtc: true),
    )).toList(growable: false);
  }

  /// Settings must also show entries that START in a future month, even
  /// though they do not affect this month's amount or current quick-pay list.
  Future<List<RecurringExpenseItem>> loadManageableItems() async {
    final current = await loadItemsForMonth(DateTime.now());
    final known = {for (final item in current) item.id: item};
    final database = await _database.database;
    final rows = await database.query('recurring_expense_items',
      orderBy: 'sort_order ASC, created_at_ms ASC');
    final month = _monthKey(DateTime.now());
    for (final row in rows) {
      final id = row['id']! as String;
      if (known.containsKey(id)) continue;
      final upcoming = await database.query('recurring_expense_plan_versions',
        where: 'item_id = ? AND effective_month > ? AND is_active = 1',
        whereArgs: <Object?>[id, month],
        orderBy: 'effective_month ASC', limit: 1);
      if (upcoming.isEmpty) continue;
      final version = upcoming.first;
      known[id] = RecurringExpenseItem(
        id: id,
        name: version['name']! as String,
        unit: _parseUnit(version['unit']! as String),
        amountMicros: (version['amount_micros']! as num).toInt(),
        sortOrder: (row['sort_order']! as num).toInt(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (row['created_at_ms']! as num).toInt(), isUtc: true),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (version['recorded_at_ms']! as num).toInt(), isUtc: true),
      );
    }
    final result = known.values.toList(growable: false);
    result.sort((a,b) {
      final sort = a.sortOrder.compareTo(b.sortOrder);
      return sort == 0 ? a.createdAt.compareTo(b.createdAt) : sort;
    });
    return result;
  }

  /// Future changes for a named plan, including scheduled discontinuation.
  Future<List<ExpensePlanChange>> loadFutureChanges(String id, {
    DateTime? fromMonth,
  }) async {
    final database = await _database.database;
    final month = fromMonth ?? DateTime.now();
    final rows = await database.query(
      'recurring_expense_plan_versions',
      where: 'item_id = ? AND effective_month > ?',
      whereArgs: <Object?>[id, _monthKey(month)],
      orderBy: 'effective_month ASC',
    );
    return rows.map((row) {
      final key = (row['effective_month']! as num).toInt();
      return ExpensePlanChange(
        itemId: id,
        effectiveMonth: DateTime(key ~/ 100, key % 100),
        name: row['name']! as String,
        unit: _parseUnit(row['unit']! as String),
        amountMicros: (row['amount_micros']! as num).toInt(),
        isActive: (row['is_active']! as num).toInt() == 1,
      );
    }).toList(growable: false);
  }

  /// New commitments may begin this month or later. They never produce an
  /// actual expense. All persistence is atomic with the canonical item ID.
  Future<void> addItem(
    RecurringExpenseItem item, {
    DateTime? effectiveFromMonth,
  }) async {
    final effective = effectiveFromMonth ?? DateTime.now();
    _validateEffectiveDate(effective, allowCurrent: true);
    _validateItem(item);
    final database = await _database.database;
    await _ensureInitialDefaults(database);
    await database.transaction((txn) async {
      await txn.insert('recurring_expense_items', _toRow(item),
          conflictAlgorithm: ConflictAlgorithm.abort);
      await _saveVersion(txn, item, _monthKey(effective), true);
    });
  }

  /// Edits apply next month or a later month, NEVER retroactively. Multiple
  /// edits to the same future month replace only that still-future revision.
  Future<void> updateItem(
    RecurringExpenseItem item, {
    DateTime? effectiveFromMonth,
  }) async {
    final effective = effectiveFromMonth ??
        DateTime(DateTime.now().year, DateTime.now().month + 1);
    _validateEffectiveDate(effective, allowCurrent: false);
    _validateItem(item);
    final database = await _database.database;
    await database.transaction((txn) async {
      final source = await txn.query('recurring_expense_items',
        columns: <String>['id'], where: 'id = ?',
        whereArgs: <Object?>[item.id], limit: 1);
      if (source.isEmpty) {
        throw StateError('Recurring expense ${item.id} does not exist.');
      }
      await _saveVersion(txn, item, _monthKey(effective), true);
    });
  }

  /// Scheduled cancellation, not destructive row deletion. Earlier months
  /// remain queryable, and manually posted payments are always untouched.
  Future<void> deleteItem(String id, {
    DateTime? effectiveFromMonth,
  }) async {
    final effective = effectiveFromMonth ??
        DateTime(DateTime.now().year, DateTime.now().month + 1);
    _validateEffectiveDate(effective, allowCurrent: false);
    final database = await _database.database;
    await database.transaction((txn) async {
      final source = await txn.query('recurring_expense_items',
        where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
      if (source.isEmpty) return;
      final current = await _versionAt(txn, id, _monthKey(effective));
      if (current == null) {
        throw StateError('Cannot cancel a plan before its first effective month.');
      }
      final item = RecurringExpenseItem(
        id: id,
        name: current['name']! as String,
        unit: _parseUnit(current['unit']! as String),
        amountMicros: (current['amount_micros']! as num).toInt(),
        sortOrder: (source.single['sort_order']! as num).toInt(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (source.single['created_at_ms']! as num).toInt(), isUtc: true),
        updatedAt: DateTime.now().toUtc(),
      );
      await _saveVersion(txn, item, _monthKey(effective), false);
    });
  }

  static Future<Map<String, Object?>?> _versionAt(
    DatabaseExecutor db, String id, int throughMonth,
  ) async {
    final rows = await db.query('recurring_expense_plan_versions',
      where: 'item_id = ? AND effective_month <= ?',
      whereArgs: <Object?>[id, throughMonth],
      orderBy: 'effective_month DESC', limit: 1);
    return rows.isEmpty ? null : rows.single;
  }

  static Future<void> _saveVersion(
    DatabaseExecutor txn,
    RecurringExpenseItem item,
    int key,
    bool active,
  ) async {
    await txn.insert(
      'recurring_expense_plan_versions',
      <String, Object?>{
        'item_id': item.id,
        'effective_month': key,
        'name': item.name.trim(),
        'unit': item.unit.name,
        'amount_micros': item.amountMicros,
        'is_active': active ? 1 : 0,
        'recorded_at_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static int _monthKey(DateTime date) => date.year * 100 + date.month;

  static void _validateEffectiveDate(DateTime date, {
    required bool allowCurrent,
  }) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month + (allowCurrent ? 0 : 1));
    final chosen = DateTime(date.year, date.month);
    if (chosen.isBefore(start)) {
      throw ArgumentError('Plan revisions cannot rewrite past/current months.');
    }
    if (chosen.year < 1900 || chosen.year > 9999) {
      throw ArgumentError('Plan effective year is not supported.');
    }
  }

  static void _validateItem(RecurringExpenseItem item) {
    if (item.id.trim().isEmpty || item.name.trim().isEmpty ||
        item.name.trim().length > 80 || item.amountMicros <= 0 ||
        item.unit == FinancialUnit.goldGram) {
      throw ArgumentError('Invalid recurring expense name/amount/currency.');
    }
  }

  Future<void> _ensureInitialDefaults(Database database) async {
    await database.transaction((txn) async {
      final metadata = await txn.query('app_metadata',
        columns: <String>['value'], where: 'key = ?',
        whereArgs: <Object?>[_seedMetadataKey], limit: 1);
      if (metadata.isNotEmpty) return;

      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final month = _monthKey(DateTime.now());
      const defaults = <(String, int)>[
        ('أمبير', 240000),
        ('إنترنت', 200000),
        ('كهرباء', 150000),
        ('غاز', 100000),
        ('تليفون', 30000),
        ('طابة / خدمات', 140000),
        ('مصاريف عائلية', 200000),
        ('مصاريف جانبية', 100000),
        ('مصروف شخصي', 1000000),
      ];
      for (int index = 0; index < defaults.length; index++) {
        final (name, amount) = defaults[index];
        final id = 'client_expense_${index + 1}';
        final micros = LedgerEntry.amountToMicros(amount);
        await txn.insert('recurring_expense_items', <String, Object?>{
          'id': id,
          'name': name,
          'unit': FinancialUnit.syp.name,
          'amount_micros': micros,
          'sort_order': index,
          'created_at_ms': now,
          'updated_at_ms': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        // If an item with the same ID already exists, keep its own baseline.
        final original = await txn.query('recurring_expense_items',
          where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
        final version = await txn.query('recurring_expense_plan_versions',
          where: 'item_id = ?', whereArgs: <Object?>[id], limit: 1);
        if (original.isNotEmpty && version.isEmpty) {
          final row = original.single;
          await txn.insert('recurring_expense_plan_versions', <String, Object?>{
            'item_id': id,
            'effective_month': month,
            'name': row['name'],
            'unit': row['unit'],
            'amount_micros': row['amount_micros'],
            'is_active': 1,
            'recorded_at_ms': now,
          });
        }
      }
      await txn.insert('app_metadata',
        <String, Object?>{'key': _seedMetadataKey, 'value': '1'},
        conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// Rebuilds only the *known* v10 baseline after a legacy portable restore.
  /// This is called inside the backup restore transaction, never app startup.
  static Future<void> restoreLegacyPlanBaselines(DatabaseExecutor txn) async {
    final rows = await txn.query('recurring_expense_items');
    for (final row in rows) {
      final created = DateTime.fromMillisecondsSinceEpoch(
        (row['created_at_ms']! as num).toInt(),
      );
      await txn.insert('recurring_expense_plan_versions', <String, Object?>{
        'item_id': row['id'],
        'effective_month': _monthKey(created),
        'name': row['name'],
        'unit': row['unit'],
        'amount_micros': row['amount_micros'],
        'is_active': 1,
        'recorded_at_ms': row['updated_at_ms'],
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    }
  }

  static Map<String, Object?> _toRow(RecurringExpenseItem item) =>
      <String, Object?>{
        'id': item.id,
        'name': item.name.trim(),
        'unit': item.unit.name,
        'amount_micros': item.amountMicros,
        'sort_order': item.sortOrder,
        'created_at_ms': item.createdAt.toUtc().millisecondsSinceEpoch,
        'updated_at_ms': item.updatedAt.toUtc().millisecondsSinceEpoch,
      };

  static FinancialUnit _parseUnit(String name) {
    return FinancialUnit.values.firstWhere(
      (unit) => unit.name == name,
      orElse: () => throw StateError('Unknown expense currency: $name'),
    );
  }
}
