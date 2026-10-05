import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/financial_balance_snapshot.dart';
import '../models/financial_event.dart';
import '../services/currency_conversion_service.dart';
import '../services/financial_ledger_storage.dart';
import '../utils/financial_format.dart';

class CurrencyConversionButton extends StatefulWidget {
  const CurrencyConversionButton({
    super.key,
    required this.snapshot,
  });

  final FinancialBalanceSnapshot snapshot;

  @override
  State<CurrencyConversionButton> createState() =>
      _CurrencyConversionButtonState();
}

class _CurrencyConversionButtonState extends State<CurrencyConversionButton> {
  final CurrencyConversionService _service = CurrencyConversionService();
  bool _isSaving = false;

  Future<void> _openConversion() async {
    if (_isSaving) return;

    final _ConversionDraft? draft = await showModalBottomSheet<_ConversionDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _CurrencyConversionSheet(
        snapshot: widget.snapshot,
      ),
    );
    if (draft == null || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final FinancialEvent event = await _service.recordConversion(
        sourceUnit: draft.sourceUnit,
        destinationUnit: draft.destinationUnit,
        sourceAmountMicros: draft.sourceAmountMicros,
        destinationAmountMicros: draft.destinationAmountMicros,
        occurredAt: draft.occurredAt,
        note: draft.note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تسجيل التحويل بسعر فعلي ${FinancialFormat.referenceRate(event.executedSypPerUsd!)}.',
          ),
        ),
      );
    } on InsufficientBalanceException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'الرصيد غير كافٍ. المتاح ${FinancialFormat.assetBalance(error.availableMicros, error.unit)}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تسجيل تحويل العملة.')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        onPressed: _isSaving ? null : _openConversion,
        icon: _isSaving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.currency_exchange),
        label: const Text('تسجيل تحويل ليرة ↔ دولار'),
      ),
    );
  }
}

class _CurrencyConversionSheet extends StatefulWidget {
  const _CurrencyConversionSheet({required this.snapshot});

  final FinancialBalanceSnapshot snapshot;

  @override
  State<_CurrencyConversionSheet> createState() =>
      _CurrencyConversionSheetState();
}

class _CurrencyConversionSheetState extends State<_CurrencyConversionSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  FinancialUnit _sourceUnit = FinancialUnit.syp;
  DateTime _occurredAt = DateTime.now();

  FinancialUnit get _destinationUnit => _sourceUnit == FinancialUnit.syp
      ? FinancialUnit.usd
      : FinancialUnit.syp;

  @override
  void dispose() {
    _sourceController.dispose();
    _destinationController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _occurredAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _occurredAt.hour,
        _occurredAt.minute,
        _occurredAt.second,
      );
    });
  }

  void _changeDirection(FinancialUnit unit) {
    if (unit == _sourceUnit) return;
    setState(() {
      _sourceUnit = unit;
      _sourceController.clear();
      _destinationController.clear();
    });
  }

  num? _parseAmount(String raw, FinancialUnit unit) {
    final String value = raw.trim();
    if (unit == FinancialUnit.syp) return int.tryParse(value);
    return double.tryParse(value);
  }

  int? _amountMicros(TextEditingController controller, FinancialUnit unit) {
    final num? amount = _parseAmount(controller.text, unit);
    if (amount == null || amount <= 0) return null;
    return LedgerEntry.amountToMicros(amount);
  }

  double? get _executedRate {
    final int? sourceMicros = _amountMicros(_sourceController, _sourceUnit);
    final int? destinationMicros =
        _amountMicros(_destinationController, _destinationUnit);
    if (sourceMicros == null || destinationMicros == null) return null;

    final int sypMicros = _sourceUnit == FinancialUnit.syp
        ? sourceMicros
        : destinationMicros;
    final int usdMicros = _sourceUnit == FinancialUnit.usd
        ? sourceMicros
        : destinationMicros;
    return sypMicros / usdMicros;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final int sourceMicros = _amountMicros(_sourceController, _sourceUnit)!;
    final int destinationMicros =
        _amountMicros(_destinationController, _destinationUnit)!;
    final int available = widget.snapshot.balanceMicros(_sourceUnit);
    if (sourceMicros > available) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'المبلغ أكبر من الرصيد المتاح: ${FinancialFormat.assetBalance(available, _sourceUnit)}.',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      _ConversionDraft(
        sourceUnit: _sourceUnit,
        destinationUnit: _destinationUnit,
        sourceAmountMicros: sourceMicros,
        destinationAmountMicros: destinationMicros,
        occurredAt: _occurredAt,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int available = widget.snapshot.balanceMicros(_sourceUnit);
    final double? rate = _executedRate;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'تحويل عملة فعلي',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'سجّل المبلغ الذي دفعته والمبلغ الذي استلمته فعلياً. سعر الإعدادات لا يُستخدم لإنشاء التحويل.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                SegmentedButton<FinancialUnit>(
                  showSelectedIcon: false,
                  segments: const <ButtonSegment<FinancialUnit>>[
                    ButtonSegment<FinancialUnit>(
                      value: FinancialUnit.syp,
                      label: Text('ل.س ← USD', textDirection: TextDirection.ltr),
                    ),
                    ButtonSegment<FinancialUnit>(
                      value: FinancialUnit.usd,
                      label: Text('USD ← ل.س', textDirection: TextDirection.ltr),
                    ),
                  ],
                  selected: <FinancialUnit>{_sourceUnit},
                  onSelectionChanged: (selection) =>
                      _changeDirection(selection.first),
                ),
                const SizedBox(height: 14),
                Text(
                  'الرصيد المتاح: ${FinancialFormat.assetBalance(available, _sourceUnit)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                _AmountField(
                  controller: _sourceController,
                  unit: _sourceUnit,
                  label: 'المبلغ المدفوع',
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                _AmountField(
                  controller: _destinationController,
                  unit: _destinationUnit,
                  label: 'المبلغ المستلم',
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.calculate_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            rate == null
                                ? 'أدخل المبلغين لحساب سعر الصرف الفعلي.'
                                : 'سعر الصرف الفعلي: ${FinancialFormat.referenceRate(rate)}',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text('تاريخ العملية: ${_formatDate(_occurredAt)}'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.check),
                  label: const Text('تسجيل التحويل'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day}/${date.month}/${date.year}';
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.unit,
    required this.label,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FinancialUnit unit;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final bool isSyp = unit == FinancialUnit.syp;
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: !isSyp),
      inputFormatters: <TextInputFormatter>[
        if (isSyp)
          FilteringTextInputFormatter.digitsOnly
        else
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        suffixText: isSyp ? 'ل.س' : 'USD',
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        final num? parsed = isSyp
            ? int.tryParse((value ?? '').trim())
            : double.tryParse((value ?? '').trim());
        if (parsed == null || parsed <= 0) {
          return 'أدخل مبلغاً أكبر من صفر.';
        }
        return null;
      },
    );
  }
}

class _ConversionDraft {
  const _ConversionDraft({
    required this.sourceUnit,
    required this.destinationUnit,
    required this.sourceAmountMicros,
    required this.destinationAmountMicros,
    required this.occurredAt,
    this.note,
  });

  final FinancialUnit sourceUnit;
  final FinancialUnit destinationUnit;
  final int sourceAmountMicros;
  final int destinationAmountMicros;
  final DateTime occurredAt;
  final String? note;
}
