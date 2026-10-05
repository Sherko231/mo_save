import 'package:sqflite/sqflite.dart';

import '../models/financial_event.dart';
import '../models/recurring_expense_item.dart';
import 'local_database.dart';

class ExpensePlanStorage {
  ExpensePlanStorage({LocalDatabase? database})
      : _database = database ?? LocalDatabase.instance;

  static const String _seedMetadataKey = 'expense_plan_client_defaults_seeded_v1';

  final LocalDatabase _database;

  Future<List<RecurringExpenseItem>> loadItems() async {
    final Database database = await _database.database;
    await _ensureInitialDefaults(database);

    final List<Map<String, Object?>> rows = await database.query(
      'recurring_expense_items',
      orderBy: 'sort_order ASC, created_at_ms ASC',
    );

    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> addItem(RecurringExpenseItem item) async {
    final Database database = await _database.database;
    await database.insert(
      'recurring_expense_items',
      _toRow(item),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> updateItem(RecurringExpenseItem item) async {
    final Database database = await _database.database;
    final int updated = await database.update(
      'recurring_expense_items',
      _toRow(item, includeId: false),
      where: 'id = ?',
      whereArgs: <Object?>[item.id],
    );
    if (updated == 0) {
      throw StateError('Recurring expense ${item.id} does not exist.');
    }
  }

  Future<void> deleteItem(String id) async {
    final Database database = await _database.database;
    await database.delete(
      'recurring_expense_items',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> _ensureInitialDefaults(Database database) async {
    await database.transaction((transaction) async {
      final List<Map<String, Object?>> metadata = await transaction.query(
        'app_metadata',
        columns: <String>['value'],
        where: 'key = ?',
        whereArgs: <Object?>[_seedMetadataKey],
        limit: 1,
      );
      if (metadata.isNotEmpty) {
        return;
      }

      final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
      const List<(String, int)> defaults = <(String, int)>[
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
        final (String name, int amount) = defaults[index];
        await transaction.insert(
          'recurring_expense_items',
          <String, Object?>{
            'id': 'client_expense_${index + 1}',
            'name': name,
            'unit': FinancialUnit.syp.name,
            'amount_micros': LedgerEntry.amountToMicros(amount),
            'sort_order': index,
            'created_at_ms': now,
            'updated_at_ms': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      await transaction.insert(
        'app_metadata',
        <String, Object?>{
          'key': _seedMetadataKey,
          'value': '1',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  static Map<String, Object?> _toRow(
    RecurringExpenseItem item, {
    bool includeId = true,
  }) {
    return <String, Object?>{
      if (includeId) 'id': item.id,
      'name': item.name.trim(),
      'unit': item.unit.name,
      'amount_micros': item.amountMicros,
      'sort_order': item.sortOrder,
      'created_at_ms': item.createdAt.toUtc().millisecondsSinceEpoch,
      'updated_at_ms': item.updatedAt.toUtc().millisecondsSinceEpoch,
    };
  }

  static RecurringExpenseItem _fromRow(Map<String, Object?> row) {
    return RecurringExpenseItem(
      id: row['id']! as String,
      name: row['name']! as String,
      unit: _parseUnit(row['unit']! as String),
      amountMicros: (row['amount_micros']! as num).toInt(),
      sortOrder: (row['sort_order']! as num).toInt(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (row['created_at_ms']! as num).toInt(),
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['updated_at_ms']! as num).toInt(),
        isUtc: true,
      ),
    );
  }

  static FinancialUnit _parseUnit(String name) {
    for (final FinancialUnit unit in FinancialUnit.values) {
      if (unit.name == name) {
        return unit;
      }
    }
    throw StateError('Unknown financial unit: $name');
  }
}
