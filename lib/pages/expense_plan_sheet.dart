import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/financial_event.dart';
import '../models/recurring_expense_item.dart';
import '../services/expense_plan_storage.dart';
import '../utils/financial_format.dart';

class ExpensePlanSheet extends StatefulWidget {
  const ExpensePlanSheet({super.key});

  @override
  State<ExpensePlanSheet> createState() => _ExpensePlanSheetState();
}

class _ExpensePlanSheetState extends State<ExpensePlanSheet> {
  final ExpensePlanStorage _storage = ExpensePlanStorage();
  List<RecurringExpenseItem> _items = const <RecurringExpenseItem>[];
  bool _isLoading = true;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final List<RecurringExpenseItem> items = await _storage.loadItems();
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحميل خطة المصاريف.')),
      );
    }
  }

  Future<void> _addItem() async {
    final _ExpenseDraft? draft = await _showItemDialog();
    if (draft == null) return;

    try {
      await _storage.addItem(
        RecurringExpenseItem.create(
          name: draft.name,
          unit: draft.unit,
          amountMicros: LedgerEntry.amountToMicros(draft.amount),
          sortOrder: _items.length,
        ),
      );
      _changed = true;
      await _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إضافة المصروف.')),
      );
    }
  }

  Future<void> _editItem(RecurringExpenseItem item) async {
    final _ExpenseDraft? draft = await _showItemDialog(item: item);
    if (draft == null) return;

    try {
      await _storage.updateItem(
        item.copyWith(
          name: draft.name,
          unit: draft.unit,
          amountMicros: LedgerEntry.amountToMicros(draft.amount),
        ),
      );
      _changed = true;
      await _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تعديل المصروف.')),
      );
    }
  }

  Future<void> _deleteItem(RecurringExpenseItem item) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف المصروف'),
        content: Text('حذف «${item.name}» من الخطة الشهرية؟'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _storage.deleteItem(item.id);
      _changed = true;
      await _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حذف المصروف.')),
      );
    }
  }

  Future<_ExpenseDraft?> _showItemDialog({RecurringExpenseItem? item}) async {
    final TextEditingController nameController = TextEditingController(
      text: item?.name ?? '',
    );
    final TextEditingController amountController = TextEditingController(
      text: item == null
          ? ''
          : FinancialFormat.editableAmount(item.amountMicros, item.unit),
    );
    FinancialUnit unit = item?.unit ?? FinancialUnit.syp;

    final _ExpenseDraft? result = await showDialog<_ExpenseDraft>(
      context: context,
      builder: (dialogContext) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(item == null ? 'إضافة مصروف شهري' : 'تعديل المصروف'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم المصروف',
                      border: OutlineInputBorder(),
                    ),
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
                      if (value != null) {
                        setDialogState(() => unit = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'المبلغ الشهري',
                      suffixText: FinancialFormat.unitShort(unit),
                      errorText: errorText,
                      border: const OutlineInputBorder(),
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
                  final String name = nameController.text.trim();
                  final double? amount =
                      double.tryParse(amountController.text.trim());
                  if (name.isEmpty || amount == null || amount <= 0) {
                    setDialogState(() {
                      errorText = 'أدخل اسماً ومبلغاً أكبر من صفر.';
                    });
                    return;
                  }
                  Navigator.pop(
                    dialogContext,
                    _ExpenseDraft(name: name, unit: unit, amount: amount),
                  );
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        );
      },
    );

    nameController.dispose();
    amountController.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final int sypTotal = _items
        .where((item) => item.unit == FinancialUnit.syp)
        .fold<int>(0, (sum, item) => sum + item.amountMicros);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'خطة المصاريف الشهرية',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (!_isLoading)
                          Text(
                            'إجمالي الليرة السورية: ${FinancialFormat.assetBalance(sypTotal, FinancialUnit.syp)}',
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(_changed),
                    tooltip: 'إغلاق',
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _items.isEmpty
                        ? const Center(child: Text('لا توجد مصاريف مخططة.'))
                        : ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final RecurringExpenseItem item = _items[index];
                              return Card(
                                child: ListTile(
                                  title: Text(item.name),
                                  subtitle: Text(
                                    FinancialFormat.assetBalance(
                                      item.amountMicros,
                                      item.unit,
                                    ),
                                  ),
                                  onTap: () => _editItem(item),
                                  trailing: IconButton(
                                    tooltip: 'حذف',
                                    onPressed: () => _deleteItem(item),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة مصروف شهري'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpenseDraft {
  const _ExpenseDraft({
    required this.name,
    required this.unit,
    required this.amount,
  });

  final String name;
  final FinancialUnit unit;
  final double amount;
}

const List<FinancialUnit> _cashUnits = <FinancialUnit>[
  FinancialUnit.syp,
  FinancialUnit.usd,
  FinancialUnit.sypNew,
];
