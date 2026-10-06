import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/financial_balance_snapshot.dart';
import '../models/financial_event.dart';
import '../services/financial_ledger_storage.dart';
import '../services/gold_service.dart';
import '../utils/financial_format.dart';

class GoldPurchaseButton extends StatefulWidget {
  const GoldPurchaseButton({
    super.key,
    required this.snapshot,
  });

  final FinancialBalanceSnapshot snapshot;

  @override
  State<GoldPurchaseButton> createState() => _GoldPurchaseButtonState();
}

class _GoldPurchaseButtonState extends State<GoldPurchaseButton> {
  final GoldService _service = GoldService();
  bool _isSaving = false;

  Future<void> _openPurchase() async {
    if (_isSaving) return;

    final _GoldPurchaseDraft? draft =
        await showModalBottomSheet<_GoldPurchaseDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _GoldPurchaseSheet(snapshot: widget.snapshot),
    );
    if (draft == null || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await _service.recordPurchase(
        sourceUnit: draft.sourceUnit,
        cashPaidMicros: draft.cashPaidMicros,
        goldReceivedMicros: draft.goldReceivedMicros,
        occurredAt: draft.occurredAt,
        note: draft.note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل شراء الذهب.')),
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
    } on ArgumentError catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('بيانات شراء الذهب غير صالحة. راجع المبلغ والوزن والتاريخ.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تسجيل شراء الذهب.')),
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
        onPressed: _isSaving ? null : _openPurchase,
        icon: _isSaving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.diamond_outlined),
        label: const Text('تسجيل شراء ذهب'),
      ),
    );
  }
}

class _GoldPurchaseSheet extends StatefulWidget {
  const _GoldPurchaseSheet({required this.snapshot});

  final FinancialBalanceSnapshot snapshot;

  @override
  State<_GoldPurchaseSheet> createState() => _GoldPurchaseSheetState();
}

class _GoldPurchaseSheetState extends State<_GoldPurchaseSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _cashController = TextEditingController();
  final TextEditingController _gramsController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  FinancialUnit _sourceUnit = FinancialUnit.syp;
  DateTime _occurredAt = DateTime.now();

  @override
  void dispose() {
    _cashController.dispose();
    _gramsController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime initial = _occurredAt.isAfter(today) ? today : _occurredAt;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: today,
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

  void _changeSource(FinancialUnit unit) {
    if (unit == _sourceUnit) return;
    setState(() {
      _sourceUnit = unit;
      _cashController.clear();
    });
  }

  int? get _cashMicros {
    final String raw = _cashController.text.trim();
    final num? amount = _sourceUnit == FinancialUnit.syp
        ? int.tryParse(raw)
        : double.tryParse(raw);
    if (amount == null || amount <= 0) return null;
    return LedgerEntry.amountToMicros(amount);
  }

  int? get _goldMicros {
    final double? grams = double.tryParse(_gramsController.text.trim());
    if (grams == null || grams <= 0) return null;
    return LedgerEntry.amountToMicros(grams);
  }

  double? get _actualCashPerGram {
    final int? cash = _cashMicros;
    final int? gold = _goldMicros;
    if (cash == null || gold == null) return null;
    final double price = cash / gold;
    return price.isFinite && price > 0 ? price : null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final int cashMicros = _cashMicros!;
    final int goldMicros = _goldMicros!;
    final int available = widget.snapshot.balanceMicros(_sourceUnit);
    if (cashMicros > available) {
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
      _GoldPurchaseDraft(
        sourceUnit: _sourceUnit,
        cashPaidMicros: cashMicros,
        goldReceivedMicros: goldMicros,
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
    final double? actualPrice = _actualCashPerGram;

    return Padding(
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
                'شراء ذهب',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'سجّل المبلغ المدفوع والغرامات المستلمة فعلياً. سعر الذهب في الإعدادات يبقى للتقييم فقط.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 18),
              SegmentedButton<FinancialUnit>(
                showSelectedIcon: false,
                segments: const <ButtonSegment<FinancialUnit>>[
                  ButtonSegment<FinancialUnit>(
                    value: FinancialUnit.syp,
                    label: Text('ل.س'),
                  ),
                  ButtonSegment<FinancialUnit>(
                    value: FinancialUnit.usd,
                    label: Text('دولار'),
                  ),
                ],
                selected: <FinancialUnit>{_sourceUnit},
                onSelectionChanged: (selection) =>
                    _changeSource(selection.first),
              ),
              const SizedBox(height: 12),
              Text(
                'الرصيد المتاح: ${FinancialFormat.assetBalance(available, _sourceUnit)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cashController,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: _sourceUnit == FinancialUnit.usd,
                ),
                inputFormatters: <TextInputFormatter>[
                  if (_sourceUnit == FinancialUnit.syp)
                    FilteringTextInputFormatter.digitsOnly
                  else
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'المبلغ المدفوع',
                  suffixText: FinancialFormat.unitShort(_sourceUnit),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  final String raw = (value ?? '').trim();
                  final num? parsed = _sourceUnit == FinancialUnit.syp
                      ? int.tryParse(raw)
                      : double.tryParse(raw);
                  if (parsed == null || parsed <= 0) {
                    return 'أدخل مبلغاً أكبر من صفر.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _gramsController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'الغرامات المستلمة',
                  suffixText: 'غ',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final double? grams = double.tryParse((value ?? '').trim());
                  if (grams == null || grams <= 0 || !grams.isFinite) {
                    return 'أدخل كمية ذهب صالحة أكبر من صفر.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        actualPrice == null
                            ? 'أدخل المبلغ والغرامات لحساب سعر الشراء الفعلي.'
                            : _sourceUnit == FinancialUnit.usd
                                ? 'سعر الشراء الفعلي: ${FinancialFormat.amount(actualPrice, FinancialUnit.usd)} لكل غرام'
                                : 'سعر الشراء الفعلي: ${FinancialFormat.amount(actualPrice, FinancialUnit.syp)} لكل غرام',
                      ),
                      if (widget.snapshot.goldUsdPerGram > 0) ...<Widget>[
                        const SizedBox(height: 5),
                        Text(
                          'السعر المرجعي الحالي: ${FinancialFormat.goldReference(widget.snapshot.goldUsdPerGram)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text('تاريخ العملية: ${FinancialFormat.date(_occurredAt)}'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                maxLines: 2,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.check),
                label: const Text('تسجيل الشراء'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoldPurchaseDraft {
  const _GoldPurchaseDraft({
    required this.sourceUnit,
    required this.cashPaidMicros,
    required this.goldReceivedMicros,
    required this.occurredAt,
    this.note,
  });

  final FinancialUnit sourceUnit;
  final int cashPaidMicros;
  final int goldReceivedMicros;
  final DateTime occurredAt;
  final String? note;
}
