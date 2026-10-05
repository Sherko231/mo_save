import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/financial_event.dart';
import '../models/recurring_expense_item.dart';
import '../services/expense_service.dart';
import 'expense_plan_sheet.dart';

class HomeExpensesSection extends StatefulWidget {
  const HomeExpensesSection({
    super.key,
    required this.month,
  });

  final DateTime month;

  @override
  State<HomeExpensesSection> createState() => _HomeExpensesSectionState();
}

class _HomeExpensesSectionState extends State<HomeExpensesSection> {
  final ExpenseService _service = ExpenseService();
  ExpenseMonthSnapshot? _snapshot;
  bool _isLoading = true;
  bool _isSavingExpense = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant HomeExpensesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month.year != widget.month.year ||
        oldWidget.month.month != widget.month.month) {
      _reload();
    }
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final ExpenseMonthSnapshot snapshot = await _service.loadMonth(widget.month);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحميل بيانات المصاريف.')),
      );
    }
  }

  Future<void> _managePlan() async {
    final bool? changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: const ExpensePlanSheet(),
      ),
    );
    if (changed == true) {
      await _reload();
    }
  }

  Future<void> _logExpense() async {
    final List<RecurringExpenseItem> planItems = _snapshot?.planItems ?? const [];
    final TextEditingController amountController = TextEditingController();
    final TextEditingController noteController = TextEditingController();
    String category = planItems.isEmpty ? 'مصروف طارئ' : planItems.first.name;
    FinancialUnit unit = planItems.isEmpty ? FinancialUnit.syp : planItems.first.unit;
    DateTime expenseDate = DateTime.now();

    final _ActualExpenseDraft? draft = await showDialog<_ActualExpenseDraft>(
      context: context,
      builder: (dialogContext) {
        String? amountError;
        return StatefulBuilder(
          builder: (context, setDialogState) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('تسجيل مصروف فعلي'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    DropdownButtonFormField<String>(
                      value: planItems.any((item) => item.name == category)
                          ? category
                          : '__other__',
                      decoration: const InputDecoration(
                        labelText: 'التصنيف',
                        border: OutlineInputBorder(),
                      ),
                      items: <DropdownMenuItem<String>>[
                        ...planItems.map(
                          (item) => DropdownMenuItem<String>(
                            value: item.name,
                            child: Text(item.name),
                          ),
                        ),
                        const DropdownMenuItem<String>(
                          value: '__other__',
                          child: Text('مصروف طارئ / آخر'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          if (value == '__other__') {
                            category = 'مصروف طارئ';
                            unit = FinancialUnit.syp;
                            amountController.clear();
                          } else {
                            category = value;
                            final RecurringExpenseItem selected =
                                planItems.firstWhere((item) => item.name == value);
                            unit = selected.unit;
                            amountController.text = _editableAmount(
                              selected.amountMicros,
                              selected.unit,
                            );
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'اسم/تصنيف المصروف',
                        hintText: category,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        if (value.trim().isNotEmpty) category = value.trim();
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<FinancialUnit>(
                      value: unit,
                      decoration: const InputDecoration(
                        labelText: 'العملة',
                        border: OutlineInputBorder(),
                      ),
                      items: _cashUnits
                          .map(
                            (value) => DropdownMenuItem<FinancialUnit>(
                              value: value,
                              child: Text(_unitLabel(value)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value != null) setDialogState(() => unit = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: InputDecoration(
                        labelText: 'المبلغ المصروف',
                        suffixText: _unitLabel(unit),
                        errorText: amountError,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final DateTime? picked = await showDatePicker(
                          context: dialogContext,
                          initialDate: expenseDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() => expenseDate = picked);
                        }
                      },
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(_formatDate(expenseDate)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظة (اختياري)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () {
                    final double? amount = double.tryParse(amountController.text.trim());
                    if (amount == null || amount <= 0 || category.trim().isEmpty) {
                      setDialogState(() {
                        amountError = 'أدخل مبلغاً أكبر من صفر.';
                      });
                      return;
                    }
                    Navigator.pop(
                      dialogContext,
                      _ActualExpenseDraft(
                        category: category.trim(),
                        unit: unit,
                        amount: amount,
                        date: expenseDate,
                        note: noteController.text.trim(),
                      ),
                    );
                  },
                  child: const Text('تسجيل'),
                ),
              ],
            ),
          ),
        );
      },
    );

    amountController.dispose();
    noteController.dispose();
    if (draft == null || !mounted) return;

    setState(() => _isSavingExpense = true);
    try {
      await _service.logExpense(
        amountMicros: LedgerEntry.amountToMicros(draft.amount),
        unit: draft.unit,
        occurredAt: draft.date,
        category: draft.category,
        note: draft.note.isEmpty ? null : draft.note,
      );
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل المصروف.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تسجيل المصروف.')),
      );
    } finally {
      if (mounted) setState(() => _isSavingExpense = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final ExpenseMonthSnapshot snapshot = _snapshot ?? const ExpenseMonthSnapshot(
      planItems: <RecurringExpenseItem>[],
      actualEvents: <FinancialEvent>[],
      plannedTotalsMicros: <FinancialUnit, int>{},
      actualTotalsMicros: <FinancialUnit, int>{},
    );

    final List<FinancialUnit> visibleUnits = _cashUnits
        .where(
          (unit) => (snapshot.plannedTotalsMicros[unit] ?? 0) != 0 ||
              (snapshot.actualTotalsMicros[unit] ?? 0) != 0,
        )
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'المصاريف',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton.icon(
              onPressed: _managePlan,
              icon: const Icon(Icons.tune),
              label: const Text('الخطة'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (visibleUnits.isEmpty)
                  const Text('لا توجد مصاريف مخططة أو فعلية لهذا الشهر.')
                else
                  ...visibleUnits.map(
                    (unit) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: _MoneyStat(
                              label: 'المخطط ${_unitLabel(unit)}',
                              value: _formatAmount(
                                snapshot.plannedTotalsMicros[unit] ?? 0,
                                unit,
                              ),
                            ),
                          ),
                          Expanded(
                            child: _MoneyStat(
                              label: 'المصروف فعلياً',
                              value: _formatAmount(
                                snapshot.actualTotalsMicros[unit] ?? 0,
                                unit,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                FilledButton.icon(
                  onPressed: _isSavingExpense ? null : _logExpense,
                  icon: _isSavingExpense
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_card_outlined),
                  label: const Text('تسجيل مصروف فعلي'),
                ),
              ],
            ),
          ),
        ),
        if (snapshot.actualEvents.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Text('آخر المصاريف المسجلة', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          ...snapshot.actualEvents.take(5).map(
            (event) {
              final LedgerEntry entry = event.entries.first;
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.payments_outlined)),
                  title: Text(event.category ?? 'مصروف'),
                  subtitle: Text(_formatDate(event.occurredAt.toLocal())),
                  trailing: Text(
                    _formatAmount(entry.amountMicros.abs(), entry.unit),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _MoneyStat extends StatelessWidget {
  const _MoneyStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 3),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _ActualExpenseDraft {
  const _ActualExpenseDraft({
    required this.category,
    required this.unit,
    required this.amount,
    required this.date,
    required this.note,
  });

  final String category;
  final FinancialUnit unit;
  final double amount;
  final DateTime date;
  final String note;
}

const List<FinancialUnit> _cashUnits = <FinancialUnit>[
  FinancialUnit.syp,
  FinancialUnit.usd,
  FinancialUnit.sypNew,
];

String _unitLabel(FinancialUnit unit) {
  switch (unit) {
    case FinancialUnit.usd:
      return 'USD';
    case FinancialUnit.syp:
      return 'ل.س';
    case FinancialUnit.sypNew:
      return 'SYP (N)';
    case FinancialUnit.goldGram:
      return 'غ ذهب';
  }
}

String _editableAmount(int micros, FinancialUnit unit) {
  final double value = micros / LedgerEntry.microsPerUnit;
  if (unit == FinancialUnit.syp || unit == FinancialUnit.sypNew) {
    return value.round().toString();
  }
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
}

String _formatAmount(int micros, FinancialUnit unit) {
  final double value = micros / LedgerEntry.microsPerUnit;
  final String raw = value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
  final List<String> parts = raw.split('.');
  final String digits = parts.first;
  final StringBuffer out = StringBuffer();
  for (int index = 0; index < digits.length; index++) {
    final int remaining = digits.length - index;
    out.write(digits[index]);
    if (remaining > 1 && remaining % 3 == 1) out.write(',');
  }
  if (parts.length > 1) out.write('.${parts[1]}');
  return '${out.toString()} ${_unitLabel(unit)}';
}

String _formatDate(DateTime date) => '${date.day}/${date.month}/${date.year}';
