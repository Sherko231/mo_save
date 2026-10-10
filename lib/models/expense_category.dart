/// Shared user-visible expense classifications. Recurring plan item titles
/// remain available as a separate quick-pick; no paid-plan linkage is
/// inferred until the future recurring-expense issue.
enum ExpenseCategory {
  food,
  outing,
  bills,
  transport,
  household,
  health,
  shopping,
  subscriptions,
  other,
}

extension ExpenseCategoryArabic on ExpenseCategory {
  String get label => switch (this) {
    ExpenseCategory.food => 'طعام',
    ExpenseCategory.outing => 'نزهة',
    ExpenseCategory.bills => 'فواتير',
    ExpenseCategory.transport => 'مواصلات',
    ExpenseCategory.household => 'منزل',
    ExpenseCategory.health => 'صحة',
    ExpenseCategory.shopping => 'تسوق',
    ExpenseCategory.subscriptions => 'اشتراكات',
    ExpenseCategory.other => 'أخرى',
  };

  /// Other always carries a meaningful user-supplied category name.
  String resolve({String? customName}) {
    if (this != ExpenseCategory.other) return label;
    final name = customName?.trim() ?? '';
    if (name.isEmpty) {
      throw ArgumentError('A custom expense category is required.');
    }
    if (name.length > 80) {
      throw ArgumentError('The expense category must be at most 80 chars.');
    }
    return name;
  }
}
