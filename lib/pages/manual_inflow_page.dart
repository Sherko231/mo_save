import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/financial_event.dart';
import '../models/receipt_fund_allocation.dart';
import '../services/manual_inflow_service.dart';
import '../utils/financial_format.dart';

/// Records cash the owner actually received, or pre-existing cash not yet
/// entered into Mo Save. Goal allocations are separate from this workflow.
class ManualInflowPage extends StatefulWidget {
  const ManualInflowPage({super.key});

  @override
  State<ManualInflowPage> createState() => _ManualInflowPageState();
}

class _ManualInflowPageState extends State<ManualInflowPage> {
  final _service = ManualInflowService();
  final _amountController = TextEditingController();
  final _savingsController = TextEditingController(text: '0');
  final _spendingController = TextEditingController(text: '0');
  final _sourceController = TextEditingController();
  final _noteController = TextEditingController();
  final String _requestId = FinancialEvent.newId();

  ManualInflowKind _kind = ManualInflowKind.gift;
  FinancialUnit _unit = FinancialUnit.syp;
  FinancialFund _fund = FinancialFund.unallocated;
  bool _splitFunds = false;
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _savingsController.dispose();
    _spendingController.dispose();
    _sourceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _fundLabel(FinancialFund fund) => switch (fund) {
    FinancialFund.savings => 'صندوق الادخار',
    FinancialFund.spending => 'صندوق المصاريف',
    FinancialFund.unallocated => 'غير موزّع حالياً',
  };

  int? _parseAmount(String raw) {
    final value = raw.trim();
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(value)) return null;
    final parts = value.split('.');
    final precision = _unit == FinancialUnit.usd ? 2 : 0;
    if (parts.length > 1 &&
        (precision == 0 || parts.last.length > precision)) {
      return null;
    }
    final whole = int.tryParse(parts.first);
    final fraction = parts.length == 1
        ? 0
        : int.tryParse(parts.last.padRight(6, '0'));
    if (whole == null || fraction == null) return null;
    if (whole > (9223372036854775807 - fraction) ~/ 1000000) {
      return null;
    }
    return whole * 1000000 + fraction;
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final chosen = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(today) ? today : _date,
      firstDate: DateTime(2000),
      lastDate: today,
    );
    if (chosen != null && mounted) setState(() => _date = chosen);
  }

  Future<void> _submit() async {
    if (_saving) return;
    final amount = _parseAmount(_amountController.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'أدخل مبلغاً موجباً بدقة العملة المحددة.');
      return;
    }

    final int? savings = _splitFunds
        ? _parseAmount(_savingsController.text) : null;
    final int? spending = _splitFunds
        ? _parseAmount(_spendingController.text) : null;
    if (_splitFunds) {
      if (savings == null || spending == null ||
          savings > amount || spending > amount - savings) {
        setState(() => _error =
            'توزيع الادخار والمصاريف أكبر من المبلغ المستلم.');
        return;
      }
    }

    if (_kind.isOpeningBalance || _kind == ManualInflowKind.itemSale) {
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_kind.isOpeningBalance
              ? 'تأكيد رصيد موجود مسبقاً'
              : 'تأكيد بيع غرض'),
          content: Text(_kind.isOpeningBalance
              ? 'سجّل فقط مالاً تملكه من قبل ولم تضفه للتطبيق. '
                  'هذا ليس دخلاً جديداً. إن كان المال مسجلاً ضمن '
                  '«غير موزّع» استخدم توزيع الأرصدة بدلاً من إضافته مجدداً.'
              : 'هذه العملية لبيع أغراض غير مسجلة سابقاً ضمن أصول التطبيق. '
                  'بيع الذهب أو تبديل العملة المسجّلين يجب أن يتم من '
                  'تحويلات الأصول، حتى لا يُحسب المال مرتين.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('متابعة'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.record(
        kind: _kind,
        unit: _unit,
        amountMicros: amount,
        occurredAt: _date,
        fund: _splitFunds ? FinancialFund.unallocated : _fund,
        savingsMicros: savings,
        spendingMicros: spending,
        source: _sourceController.text,
        note: _noteController.text,
        requestId: _requestId,
        untrackedAssetSaleConfirmed: _kind == ManualInflowKind.itemSale,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'لم يتم تأكيد الحفظ. تحقق من سجل الحركات قبل إعادة المحاولة.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final opening = _kind.isOpeningBalance;
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة مال إلى رصيدي')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
          children: <Widget>[
            Text(
              opening ? 'رصيد سابق، وليس دخلاً' : 'دخل فعلي غير راتب',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              opening
                  ? 'هذا المبلغ موجود عندك من قبل لكنه غير مسجّل بالتطبيق. '
                      'لن يظهر في إحصاءات الدخل الشهري.'
                  : 'سجّل المبلغ الذي استلمته فعلاً مع مصدره وتاريخه. '
                      'لن يُحسب كمصروف أو راتب متكرر.',
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<ManualInflowKind>(
              value: _kind,
              decoration: const InputDecoration(
                labelText: 'نوع المبلغ',
                border: OutlineInputBorder(),
              ),
              items: ManualInflowKind.values.map(
                (kind) => DropdownMenuItem<ManualInflowKind>(
                  value: kind,
                  child: Text(kind.categoryLabel),
                ),
              ).toList(growable: false),
              onChanged: _saving ? null : (kind) {
                if (kind != null) setState(() => _kind = kind);
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<FinancialUnit>(
              value: _unit,
              decoration: const InputDecoration(
                labelText: 'العملة',
                border: OutlineInputBorder(),
              ),
              items: FinancialUnit.values
                  .where((unit) => unit != FinancialUnit.goldGram)
                  .map((unit) => DropdownMenuItem<FinancialUnit>(
                        value: unit,
                        child: Text(FinancialFormat.unitLabel(unit)),
                      ))
                  .toList(growable: false),
              onChanged: _saving ? null : (unit) {
                if (unit != null) setState(() {
                  _unit = unit;
                  _error = null;
                });
              },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _amountController,
              enabled: !_saving,
              onChanged: (_) => setState(() => _error = null),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText: 'المبلغ الحقيقي',
                border: const OutlineInputBorder(),
                suffixText: FinancialFormat.unitShort(_unit),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _saving ? null : _chooseDate,
              icon: const Icon(Icons.event_outlined),
              label: Text('التاريخ: ${FinancialFormat.date(_date)}'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _sourceController,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'المصدر (اختياري)',
                hintText: 'مثلاً: هدية من صديق أو بيع جهاز',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _noteController,
              enabled: !_saving,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'ملاحظة أو سبب (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            SwitchListTile.adaptive(
              title: const Text('تقسيم المبلغ على أكثر من صندوق'),
              subtitle: const Text(
                'اختياري. توزع المبلغ الحقيقي بدون إنشاء إيداع ثاني.',
              ),
              value: _splitFunds,
              onChanged: _saving ? null : (value) =>
                  setState(() { _splitFunds = value; _error = null; }),
            ),
            if (!_splitFunds)
              DropdownButtonFormField<FinancialFund>(
                value: _fund,
                decoration: const InputDecoration(
                  labelText: 'وين بدك تخصص المبلغ؟',
                  border: OutlineInputBorder(),
                ),
                items: FinancialFund.values
                    .map((fund) => DropdownMenuItem<FinancialFund>(
                          value: fund,
                          child: Text(_fundLabel(fund)),
                        ))
                    .toList(growable: false),
                onChanged: _saving ? null : (fund) {
                  if (fund != null) setState(() => _fund = fund);
                },
              )
            else ...<Widget>[
              TextField(
                controller: _spendingController,
                enabled: !_saving,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  labelText: 'إلى صندوق المصاريف',
                  suffixText: FinancialFormat.unitShort(_unit),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _savingsController,
                enabled: !_saving,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  labelText: 'إلى صندوق الادخار',
                  suffixText: FinancialFormat.unitShort(_unit),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Builder(builder: (context) {
                final amount = _parseAmount(_amountController.text);
                final savings = _parseAmount(_savingsController.text);
                final spending = _parseAmount(_spendingController.text);
                if (amount == null || savings == null || spending == null) {
                  return const Text('أدخل مبالغ صحيحة لحساب الباقي.');
                }
                try {
                  final split = ReceiptFundAllocation(
                    receivedMicros: amount,
                    savingsMicros: savings,
                    spendingMicros: spending,
                  );
                  return Text(
                    'المتبقي غير الموزّع: '
                    '${FinancialFormat.assetBalance(
                      split.remainingUnallocatedMicros, _unit,
                    )}',
                  );
                } on ArgumentError {
                  return const Text('مجموع التوزيع أكبر من المبلغ المتاح.');
                }
              }),
            ],
            const SizedBox(height: 8),
            const Text(
              'كل صندوق يأخذ جزءاً من نفس المبلغ. '
              'أي مبلغ غير مخصص يبقى غير موزّع حتى تختار له صندوقاً.',
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'جاري الحفظ...' : 'تسجيل المبلغ'),
            ),
          ],
        ),
      ),
    );
  }
}
