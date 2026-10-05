import 'financial_event.dart';

class RecurringExpenseItem {
  const RecurringExpenseItem({
    required this.id,
    required this.name,
    required this.unit,
    required this.amountMicros,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final FinancialUnit unit;
  final int amountMicros;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  RecurringExpenseItem copyWith({
    String? name,
    FinancialUnit? unit,
    int? amountMicros,
    int? sortOrder,
    DateTime? updatedAt,
  }) {
    return RecurringExpenseItem(
      id: id,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      amountMicros: amountMicros ?? this.amountMicros,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  static RecurringExpenseItem create({
    required String name,
    required FinancialUnit unit,
    required int amountMicros,
    required int sortOrder,
  }) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Expense name must not be empty.');
    }
    if (amountMicros <= 0) {
      throw ArgumentError('Expense amount must be greater than zero.');
    }
    if (unit == FinancialUnit.goldGram) {
      throw ArgumentError('Gold cannot be used as an expense-plan currency.');
    }

    final DateTime now = DateTime.now().toUtc();
    return RecurringExpenseItem(
      id: 'exp_${DateTime.now().microsecondsSinceEpoch}',
      name: trimmed,
      unit: unit,
      amountMicros: amountMicros,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );
  }
}
