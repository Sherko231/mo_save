import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/expense_category.dart';
import '../models/financial_event.dart';
import '../models/recurring_expense_item.dart';
import '../services/expense_plan_storage.dart';
import '../services/expense_service.dart';
import '../services/financial_ledger_storage.dart';
import '../utils/financial_format.dart';

/// Shared actual-payment form, launched from the Spending dashboard and from
/// the existing Expenses section. A selected monthly plan only PREFILLS the
/// payment; it does not pay the plan, create a schedule or settle an occurrence.
class SpendingQuickExpensePage extends StatefulWidget {
  const SpendingQuickExpensePage({
    super.key,
    this.initialFund = FinancialFund.spending,
  }) : assert(initialFund != FinancialFund.unallocated);

  final FinancialFund initialFund;

  @override
  State<SpendingQuickExpensePage> createState() =>
      _SpendingQuickExpensePageState();
}

class _SpendingQuickExpensePageState extends State<SpendingQuickExpensePage> {
  static const List<FinancialUnit> _cashUnits = <FinancialUnit>[
    FinancialUnit.syp,
    FinancialUnit.usd,
    FinancialUnit.sypNew,
  ];

  final ExpenseService _expenses = ExpenseService();
  final FinancialLedgerStorage _ledger = FinancialLedgerStorage();
  final ExpensePlanStorage _plans = ExpensePlanStorage();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _otherCategory = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final String _requestId = FinancialEvent.newId();

  late FinancialFund _fund;
  FinancialUnit _unit = FinancialUnit.syp;
  String _categoryChoice = 'cat:food';
  List<RecurringExpenseItem> _planItems = const <RecurringExpenseItem>[];
  Map<FinancialFund, Map<FinancialUnit, int>>? _available;
  DateTime _date = DateTime.now();
  bool _isSaving = false;
  bool _isLoadingBalances = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fund = widget.initialFund;
    _loadReferenceData();
  }

  @override
  void dispose() {
    _amount.dispose();
    _otherCategory.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadReferenceData() async {
    try {
      final plans = await _plans.loadItems();
      final balances = await _ledger.loadFundBalancesMicros();
      if (!mounted) return;
      setState(() {
        _planItems = plans;
        _available = balances;
        _isLoadingBalances = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingBalances = false;
        _error = 'تعذر تحميل رصيد الصندوق. أعد المحاولة.';
      });
    }
  }

  int? _parseMicros() {
    final raw = _amount.text.trim();
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(raw)) return null;
    final parts = raw.split('.');
    final decimals = _unit == FinancialUnit.usd ? 2 : 0;
    if (parts.length > 1 &&
        (decimals == 0 || parts.last.length > decimals)) return null;
    final whole = int.tryParse(parts.first);
    final fractional = parts.length == 1
        ? 0
        : int.tryParse(parts.last.padRight(6, '0'));
    if (whole == null || fractional == null) return null;
    if (whole > (9223372036854775807 - fractional) ~/ 1000000) {
      return null;
    }
    return whole * 1000000 + fractional;
  }

  String get _fundLabel =>
      _fund == FinancialFund.savings ? 'الادخار' : 'المصاريف';

  int? get _selectedBalance => _available?[_fund]?[_unit];

  String _selectedCategory() {
    if (_categoryChoice.startsWith('plan:')) {
      final id = _categoryChoice.substring('plan:'.length);
      return _planItems.firstWhere((item) => item.id == id).name.trim();
    }
    final selected = ExpenseCategory.values.byName(
      _categoryChoice.substring('cat:'.length),
    );
    return selected.resolve(customName: _otherCategory.text);
  }

  void _chooseCategory(String value) {
    setState(() {
      _categoryChoice = value;
      _error = null;
      if (value.startsWith('plan:')) {
        final id = value.substring('plan:'.length);
        final item = _planItems.firstWhere((item) => item.id == id);
        _unit = item.unit;
        _amount.text = FinancialFormat.editableAmount(
          item.amountMicros, item.unit,
        );
      }
    });
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(today) ? today : _date,
      firstDate: DateTime(2000),
      lastDate: today,
    );
    if (date != null && mounted) setState(() => _date = date);
  }

  Future<void> _save() async {
    if (_isSaving || _isLoadingBalances) return;
    final micros = _parseMicros();
    String category;
    try {
      category = _selectedCategory();
    } on ArgumentError {
      setState(() => _error = 'اكتب تصنيفاً واضحاً عند اختيار «أخرى».');
      return;
    }
    if (micros == null || micros <= 0 || category.isEmpty ||
        category.length > 80) {
      setState(() => _error = 'أدخل مبلغاً موجباً وتصنيفاً صحيحاً.');
      return;
    }
    if (_fund == FinancialFund.savings && _note.text.trim().isEmpty) {
      setState(() => _error =
          'السحب من الادخار يحتاج سبباً في خانة الملاحظة.');
      return;
    }
    final available = _selectedBalance;
    if (available == null) {
      setState(() => _error = 'الرصيد غير متاح حالياً. أعد التحميل.');
      return;
    }
    if (micros > available) {
      setState(() => _error =
          'الرصيد في صندوق $_fundLabel غير كافٍ. '
          'المتاح: ${FinancialFormat.assetBalance(available, _unit)}');
      return;
    }

    if (_fund == FinancialFund.savings) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تأكيد السحب من الادخار'),
          content: Text(
            'سيُخصم ${FinancialFormat.assetBalance(micros, _unit)} '
            'من أموالك المدّخرة مباشرة، ويُسجّل كمصروف فعلي. '
            'لن يُنقل المبلغ تلقائياً لصندوق المصاريف.\n\n'
            'السبب: ${_note.text.trim()}',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('تأكيد المصروف'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await _expenses.logExpense(
        amountMicros: micros,
        unit: _unit,
        occurredAt: _date,
        category: category,
        note: _note.text.trim(),
        sourceFund: _fund,
        requestId: _requestId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on InsufficientBalanceException catch (error) {
      if (!mounted) return;
      setState(() => _error =
          'الرصيد الفعلي تغيّر. المتاح: '
          '${FinancialFormat.assetBalance(error.availableMicros, error.unit)}');
      await _loadReferenceData();
    } on InsufficientFundBalanceException catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'الرصيد الفعلي تغيّر، ولم يُسجّل المصروف.');
      await _loadReferenceData();
    } on ArgumentError catch (_) {
      if (!mounted) return;
      setState(() => _error = 'راجع المبلغ والعملة والتصنيف وسبب المصروف.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'تعذر تأكيد التسجيل. تحقق من سجل الحركات قبل المحاولة مجدداً.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = _selectedBalance;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل مصروف فعلي')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 32),
          children: <Widget>[
            Text(
              'من أي صندوق بدك تدفع؟',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 7),
            const Text(
              'المصروف يُخصم مرة واحدة من الصندوق الذي تختاره. '
              'الخطة الشهرية اقتراح ولا تخصم مالاً حتى تسجّل الدفع.',
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<FinancialFund>(
              value: _fund,
              decoration: const InputDecoration(
                labelText: 'مصدر الدفع',
                border: OutlineInputBorder(),
              ),
              items: const <DropdownMenuItem<FinancialFund>>[
                DropdownMenuItem(
                  value: FinancialFund.spending,
                  child: Text('صندوق المصاريف'),
                ),
                DropdownMenuItem(
                  value: FinancialFund.savings,
                  child: Text('صندوق الادخار'),
                ),
              ],
              onChanged: _isSaving ? null : (fund) {
                if (fund != null) setState(() {
                  _fund = fund;
                  _error = null;
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<FinancialUnit>(
              value: _unit,
              decoration: const InputDecoration(
                labelText: 'العملة',
                border: OutlineInputBorder(),
              ),
              items: _cashUnits.map((unit) => DropdownMenuItem(
                value: unit,
                child: Text(FinancialFormat.unitLabel(unit)),
              )).toList(growable: false),
              onChanged: _isSaving ? null : (value) {
                if (value != null) setState(() {
                  _unit = value;
                  _amount.clear();
                  _error = null;
                });
              },
            ),
            const SizedBox(height: 10),
            Text(
              _isLoadingBalances
                  ? 'جاري تحميل رصيد الصندوق...'
                  : available == null
                      ? 'تعذر تحميل الرصيد. استخدم تحديث الرصيد.'
                      : 'المتاح في صندوق $_fundLabel: '
                          '${FinancialFormat.assetBalance(available, _unit)}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: colors.primary,
              ),
            ),
            if (!_isLoadingBalances && available == null)
              TextButton.icon(
                onPressed: _loadReferenceData,
                icon: const Icon(Icons.refresh),
                label: const Text('تحديث الرصيد'),
              ),
            if (_fund == FinancialFund.savings)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'تنبيه: هذا خصم مباشر من المدخرات، مو تحويل لصندوق المصاريف. '
                  'اكتب سبب السحب أدناه.',
                  style: TextStyle(color: colors.error),
                ),
              ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              value: _categoryChoice,
              decoration: const InputDecoration(
                labelText: 'تصنيف المصروف أو بند الخطة',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String>>[
                ...ExpenseCategory.values.map((category) =>
                    DropdownMenuItem<String>(
                      value: 'cat:${category.name}',
                      child: Text(category.label),
                    )),
                ..._planItems.map((item) => DropdownMenuItem<String>(
                  value: 'plan:${item.id}',
                  child: Text('من الخطة: ${item.name}'),
                )),
              ],
              onChanged: _isSaving ? null : (value) {
                if (value != null) _chooseCategory(value);
              },
            ),
            if (_categoryChoice == 'cat:other') ...<Widget>[
              const SizedBox(height: 12),
              TextField(
                controller: _otherCategory,
                enabled: !_isSaving,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'اسم التصنيف (إجباري)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_categoryChoice.startsWith('plan:')) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                'اختيار بند من الخطة يملأ المبلغ والعملة فقط؛ '
                'لا يؤكد دفع الفاتورة تلقائياً ولا يعدّل الخطة.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              enabled: !_isSaving,
              keyboardType: TextInputType.numberWithOptions(
                decimal: _unit == FinancialUnit.usd,
              ),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(
                    _unit == FinancialUnit.usd ? r'[0-9.]' : r'[0-9]')),
              ],
              decoration: InputDecoration(
                labelText: 'المبلغ المدفوع فعلياً',
                suffixText: FinancialFormat.unitShort(_unit),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isSaving ? null : _chooseDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text('تاريخ الدفع: ${FinancialFormat.date(_date)}'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              enabled: !_isSaving,
              maxLines: 2,
              maxLength: 300,
              decoration: InputDecoration(
                labelText: _fund == FinancialFund.savings
                    ? 'سبب السحب من الادخار (إجباري)'
                    : 'سبب أو ملاحظة (اختياري)',
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: colors.error)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isSaving || _isLoadingBalances ||
                      available == null ? null : _save,
              icon: _isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_card_rounded),
              label: Text(_isSaving ? 'جاري التسجيل...' : 'تسجيل المصروف'),
            ),
          ],
        ),
      ),
    );
  }
}
