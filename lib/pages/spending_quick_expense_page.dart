import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/financial_event.dart';
import '../services/expense_service.dart';
import '../services/financial_ledger_storage.dart';
import '../utils/financial_format.dart';

/// The Spending dashboard's primary quick action.
/// MS-08 will expand this to a fund chooser and richer categories; this
/// bounded screen deliberately pays from Spending only.
class SpendingQuickExpensePage extends StatefulWidget {
  const SpendingQuickExpensePage({super.key});

  @override
  State<SpendingQuickExpensePage> createState() =>
      _SpendingQuickExpensePageState();
}

class _SpendingQuickExpensePageState extends State<SpendingQuickExpensePage> {
  final ExpenseService _expenses = ExpenseService();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _category = TextEditingController();
  final TextEditingController _note = TextEditingController();

  FinancialUnit _unit = FinancialUnit.syp;
  DateTime _date = DateTime.now();
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _category.dispose();
    _note.dispose();
    super.dispose();
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

  Future<void> _chooseDate() async {
    final today = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(today) ? today : _date,
      firstDate: DateTime(2000),
      lastDate: today,
    );
    if (date != null && mounted) setState(() => _date = date);
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final micros = _parseMicros();
    if (micros == null || micros <= 0 || _category.text.trim().isEmpty) {
      setState(() => _error = 'أدخل مبلغاً موجباً وتصنيفاً للمصروف.');
      return;
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
        category: _category.text.trim(),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        sourceFund: FinancialFund.spending,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on InsufficientBalanceException catch (error) {
      if (!mounted) return;
      setState(() => _error =
          'رصيد صندوق المصاريف غير كافٍ. المتاح: '
          '${FinancialFormat.assetBalance(error.availableMicros, error.unit)}');
    } on InsufficientFundBalanceException catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'الرصيد المتاح بالصندوق تغيّر. راجع الرصيد وحدّث العملية.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'لم يُسجّل المصروف. تحقق من سجل الحركات قبل إعادة المحاولة.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة مصروف من الصندوق')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 30),
          children: <Widget>[
            Text('دفع فعلي من صندوق المصاريف',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text(
              'هذا خصم حقيقي من رصيد صندوق المصاريف فقط، '
              'وليس من صندوق الادخار أو الأموال غير الموزّعة. '
              'الخطة الشهرية وحدها لا تسجّل مصروفاً.',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _category,
              enabled: !_isSaving,
              maxLength: 80,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'تصنيف المصروف',
                hintText: 'مثلاً: إنترنت، طعام، مواصلات',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<FinancialUnit>(
              value: _unit,
              decoration: const InputDecoration(
                labelText: 'العملة',
                border: OutlineInputBorder(),
              ),
              items: SpendingCashUnits.values.map((unit) =>
                  DropdownMenuItem<FinancialUnit>(
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
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              enabled: !_isSaving,
              keyboardType: TextInputType.numberWithOptions(
                  decimal: _unit == FinancialUnit.usd),
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
              decoration: const InputDecoration(
                labelText: 'ملاحظة (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(_error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  )),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
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

abstract final class SpendingCashUnits {
  static const List<FinancialUnit> values = <FinancialUnit>[
    FinancialUnit.syp,
    FinancialUnit.usd,
    FinancialUnit.sypNew,
  ];
}
