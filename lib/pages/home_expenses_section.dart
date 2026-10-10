import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/financial_event.dart';
import '../models/recurring_expense_item.dart';
import '../services/expense_service.dart';
import '../services/financial_ledger_storage.dart';
import '../ui/ux_components.dart';
import '../utils/financial_format.dart';
import 'expense_plan_sheet.dart';

class HomeExpensesSection extends StatefulWidget {
  const HomeExpensesSection({
    super.key,
    required this.month,
    this.onPlanChanged,
  });

  final DateTime month;
  final VoidCallback? onPlanChanged;

  @override
  State<HomeExpensesSection> createState() => _HomeExpensesSectionState();
}

class _HomeExpensesSectionState extends State<HomeExpensesSection> {
  final ExpenseService _service = ExpenseService();
  StreamSubscription<void>? _ledgerChanges;
  ExpenseMonthSnapshot? _snapshot;
  bool _isLoading = true;
  bool _isSavingExpense = false;

  @override
  void initState() {
    super.initState();
    _ledgerChanges = FinancialLedgerStorage.changes.listen((_) {
      if (mounted) _reload();
    });
    _reload();
  }

  @override
  void dispose() {
    _ledgerChanges?.cancel();
    super.dispose();
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
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.92,
        child: ExpensePlanSheet(),
      ),
    );
    if (changed == true) {
      await _reload();
      if (mounted) widget.onPlanChanged?.call();
    }
  }

  Future<void> _logExpense() async {
    final List<RecurringExpenseItem> planItems = _snapshot?.planItems ?? const [];
    final TextEditingController amountController = TextEditingController();
    final TextEditingController noteController = TextEditingController();
    String category = planItems.isEmpty ? 'مصروف طارئ' : planItems.first.name;
    FinancialUnit unit =
        planItems.isEmpty ? FinancialUnit.syp : planItems.first.unit;
    DateTime expenseDate = DateTime.now();

    final _ActualExpenseDraft? draft = await showDialog<_ActualExpenseDraft>(
      context: context,
      builder: (dialogContext) {
        String? amountError;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('مصروف فعلي من صندوق المصاريف'),
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
                        amountError = null;
                        if (value == '__other__') {
                          category = 'مصروف طارئ';
                          unit = FinancialUnit.syp;
                          amountController.clear();
                        } else {
                          category = value;
                          final RecurringExpenseItem selected =
                              planItems.firstWhere((item) => item.name == value);
                          unit = selected.unit;
                          amountController.text = FinancialFormat.editableAmount(
                            selected.amountMicros,
                            selected.unit,
                          );
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    maxLength: 80,
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
                            child: Text(FinancialFormat.unitLabel(value)),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        unit = value;
                        amountError = null;
                        amountController.clear();
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: unit == FinancialUnit.usd,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      if (unit == FinancialUnit.usd)
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                      else
                        FilteringTextInputFormatter.digitsOnly,
                    ],
                    onChanged: (_) => setDialogState(() => amountError = null),
                    decoration: InputDecoration(
                      labelText: 'المبلغ المصروف',
                      suffixText: FinancialFormat.unitShort(unit),
                      errorText: amountError,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final DateTime now = DateTime.now();
                      final DateTime today = DateTime(now.year, now.month, now.day);
                      final DateTime? picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: expenseDate.isAfter(today) ? today : expenseDate,
                        firstDate: DateTime(2020),
                        lastDate: today,
                      );
                      if (picked != null) {
                        setDialogState(() => expenseDate = picked);
                      }
                    },
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(FinancialFormat.date(expenseDate)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    maxLength: 300,
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
                  final String rawAmount = amountController.text.trim();
                  final num? amount = unit == FinancialUnit.usd
                      ? double.tryParse(rawAmount)
                      : int.tryParse(rawAmount);
                  if (amount == null || amount <= 0) {
                    setDialogState(() {
                      amountError = 'أدخل مبلغاً صالحاً أكبر من صفر.';
                    });
                    return;
                  }
                  if (category.trim().isEmpty) {
                    setDialogState(() {
                      amountError = 'أدخل تصنيفاً للمصروف.';
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
        sourceFund: FinancialFund.spending,
      );
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل المصروف.')),
      );
    } on InsufficientBalanceException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'لا يمكن تسجيل المصروف لأن الرصيد غير كافٍ. المتاح ${FinancialFormat.assetBalance(error.availableMicros, error.unit)}.',
          ),
        ),
      );
    } on ArgumentError catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('بيانات المصروف غير صالحة. راجع المبلغ والتاريخ.')),
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

    final ExpenseMonthSnapshot snapshot =
        _snapshot ??
        const ExpenseMonthSnapshot(
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
        UxSoftCard(
          tone: Theme.of(context).colorScheme.error,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (visibleUnits.isEmpty)
                Text(
                  'لا توجد مصاريف مخططة أو فعلية لهذا الشهر.',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              else
                ...visibleUnits.map(
                  (unit) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: _MoneyStat(
                            icon: Icons.event_note_outlined,
                            label:
                                'المخطط — ${FinancialFormat.unitLabel(unit)}',
                            value: FinancialFormat.assetBalance(
                              snapshot.plannedTotalsMicros[unit] ?? 0,
                              unit,
                            ),
                            tone: Theme.of(context).colorScheme.tertiary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MoneyStat(
                            icon: Icons.payments_outlined,
                            label: 'المصروف فعلياً',
                            value: FinancialFormat.assetBalance(
                              snapshot.actualTotalsMicros[unit] ?? 0,
                              unit,
                            ),
                            tone: Theme.of(context).colorScheme.error,
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
                    : const Icon(Icons.add_card_rounded),
                label: const Text('تسجيل مصروف من الصندوق'),
              ),
            ],
          ),
        ),
        if (snapshot.actualEvents.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            'آخر المصاريف المسجلة',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          ...snapshot.actualEvents.take(5).map(
            (event) {
              final LedgerEntry entry = event.entries.first;
              return Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: UxSoftCard(
                  tone: Theme.of(context).colorScheme.error,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                  child: Row(
                    children: <Widget>[
                      UxIconBadge(
                        icon: Icons.payments_outlined,
                        tone: Theme.of(context).colorScheme.error,
                        size: 38,
                        iconSize: 19,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              event.category ?? 'مصروف',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              FinancialFormat.date(event.occurredAt),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        FinancialFormat.assetBalance(
                          entry.amountMicros.abs(),
                          entry.unit,
                        ),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                    ],
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
  const _MoneyStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        UxIconBadge(
          icon: icon,
          tone: tone,
          size: 34,
          iconSize: 17,
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
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
  final num amount;
  final DateTime date;
  final String note;
}

const List<FinancialUnit> _cashUnits = <FinancialUnit>[
  FinancialUnit.syp,
  FinancialUnit.usd,
  FinancialUnit.sypNew,
];
