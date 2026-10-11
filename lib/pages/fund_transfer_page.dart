import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/financial_event.dart';
import '../services/financial_ledger_storage.dart';
import '../services/fund_transfer_service.dart';
import '../utils/financial_format.dart';

/// Fund-to-fund cash reclassification. It intentionally does NOT offer a
/// currency switch as part of the transaction: exchanging SYP and USD needs
/// a separate executed FX event with its recorded exchange rate.
class FundTransferPage extends StatefulWidget {
  const FundTransferPage({super.key, this.ledger, this.service});

  /// Optional dependency injection for isolated widget acceptance scenarios.
  final FinancialLedgerStorage? ledger;
  final FundTransferService? service;

  @override
  State<FundTransferPage> createState() => _FundTransferPageState();
}

class _FundTransferPageState extends State<FundTransferPage> {
  static const List<FinancialUnit> _cashUnits = <FinancialUnit>[
    FinancialUnit.syp,
    FinancialUnit.usd,
    FinancialUnit.sypNew,
  ];

  late final FinancialLedgerStorage _ledger;
  late final FundTransferService _transfers;
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final String _requestId = FinancialEvent.newId();

  FinancialFund _source = FinancialFund.savings;
  FinancialUnit _unit = FinancialUnit.syp;
  DateTime _date = DateTime.now();
  Map<FinancialFund, Map<FinancialUnit, int>>? _balances;
  bool _saving = false;
  bool _loading = true;
  String? _error;

  FinancialFund get _destination =>
      _source == FinancialFund.savings
          ? FinancialFund.spending
          : FinancialFund.savings;

  String _fundLabel(FinancialFund fund) =>
      fund == FinancialFund.savings ? 'الادخار' : 'المصاريف';

  int? get _sourceBalance => _balances?[_source]?[_unit];
  int? get _destinationBalance => _balances?[_destination]?[_unit];

  @override
  void initState() {
    super.initState();
    _ledger = widget.ledger ?? FinancialLedgerStorage();
    _transfers = widget.service ?? FundTransferService(ledger: _ledger);
    _reload();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final balances = await _ledger.loadFundBalancesMicros();
      if (!mounted) return;
      setState(() {
        _balances = balances;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل أرصدة الصناديق. حاول تحديثها.',
      });
    }
  }

  int? _parseMicros(String raw) {
    final text = raw.trim();
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(text)) return null;
    final parts = text.split('.');
    final decimals = _unit == FinancialUnit.usd ? 2 : 0;
    if (parts.length > 1 &&
        (decimals == 0 || parts.last.length > decimals)) return null;
    final whole = int.tryParse(parts.first);
    final fraction = parts.length == 1
        ? 0
        : int.tryParse(parts.last.padRight(6, '0'));
    if (whole == null || fraction == null ||
        whole > (9223372036854775807 - fraction) ~/ 1000000) {
      return null;
    }
    return whole * 1000000 + fraction;
  }

  Future<void> _chooseDate() async {
    final today = DateTime.now();
    final lastDate = DateTime(today.year, today.month, today.day);
    final selected = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(lastDate) ? lastDate : _date,
      firstDate: DateTime(2000),
      lastDate: lastDate,
    );
    if (selected != null && mounted) {
      setState(() => _date = selected);
    }
  }

  Future<void> _submit() async {
    if (_saving || _loading) return;
    final amount = _parseMicros(_amount.text);
    final available = _sourceBalance;
    if (amount == null || amount <= 0) {
      setState(() => _error = 'أدخل مبلغاً موجباً بدقة العملة المحددة.');
      return;
    }
    if (available == null) {
      setState(() => _error = 'حدّث الرصيد قبل تنفيذ التحويل.');
      return;
    }
    if (amount > available) {
      setState(() => _error =
          'المبلغ أكبر من رصيد ${_fundLabel(_source)} المتاح. '
          'المتاح: ${FinancialFormat.assetBalance(available, _unit)}');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد تحويل بين الصناديق'),
        content: Text(
          'نقل ${FinancialFormat.assetBalance(amount, _unit)} '
          'من صندوق ${_fundLabel(_source)} إلى صندوق '
          '${_fundLabel(_destination)}.\n\n'
          'هذا لا يضيف دخلاً ولا يسجل مصروفاً '
          'ولا يبدّل العملة أو إجمالي ممتلكاتك.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تأكيد النقل'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _transfers.move(
        source: _source,
        destination: _destination,
        unit: _unit,
        amountMicros: amount,
        occurredAt: _date,
        requestId: _requestId,
        note: _note.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on GoalBackingInsufficientException catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'المبلغ المطلوب محجوز لأهداف الادخار. ألغِ حجز بعض خانات الهدف '
          'قبل النقل. لا يوجد أي تحويل منفّذ.');
    } on InsufficientFundBalanceException catch (_) {
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      setState(() => _error =
          'الرصيد تغيّر أثناء التحويل. لم تتم إضافة مال جديد. '
          'راجع الرصيد الحالي.');
    } on ArgumentError catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'تحقق من العملة والمبلغ والتاريخ والملاحظة.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'تعذر تأكيد التحويل. راجع سجل الحركات قبل إعادة المحاولة.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final amount = _parseMicros(_amount.text);
    final sourceBalance = _sourceBalance;
    final destinationBalance = _destinationBalance;
    final showPreview = amount != null &&
        amount > 0 && sourceBalance != null && destinationBalance != null &&
        amount <= sourceBalance;

    return Scaffold(
      appBar: AppBar(title: const Text('تحويل بين الادخار والمصاريف')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 36),
          children: <Widget>[
            Text(
              'نقل أموال موجودة بالفعل',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 7),
            const Text(
              'هالتحويل ينقل المبلغ بين الصندوقين بدون زيادة '
              'إجمالي الأموال، ولا يسجل دخل أو مصروف. '
              'لتبديل الدولار والليرة استخدم تحويل العملة المنفصل.',
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<FinancialFund>(
              value: _source,
              decoration: const InputDecoration(
                labelText: 'من الصندوق',
                border: OutlineInputBorder(),
              ),
              items: const <DropdownMenuItem<FinancialFund>>[
                DropdownMenuItem(
                  value: FinancialFund.savings, child: Text('الادخار')),
                DropdownMenuItem(
                  value: FinancialFund.spending, child: Text('المصاريف')),
              ],
              onChanged: _saving ? null : (value) {
                if (value != null) setState(() {
                  _source = value;
                  _error = null;
                });
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('إلى الصندوق'),
              subtitle: Text(_fundLabel(_destination)),
              leading: const Icon(Icons.swap_horiz_rounded),
              trailing: IconButton(
                onPressed: _saving ? null : () => setState(() {
                  _source = _destination;
                  _error = null;
                }),
                tooltip: 'عكس الاتجاه',
                icon: const Icon(Icons.swap_vert_rounded),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<FinancialUnit>(
              value: _unit,
              decoration: const InputDecoration(
                labelText: 'العملة المنقولة (نفسها بالجهتين)',
                border: OutlineInputBorder(),
              ),
              items: _cashUnits.map((unit) => DropdownMenuItem<FinancialUnit>(
                value: unit,
                child: Text(FinancialFormat.unitLabel(unit)),
              )).toList(growable: false),
              onChanged: _saving ? null : (unit) {
                if (unit != null) setState(() {
                  _unit = unit;
                  _amount.clear();
                  _error = null;
                });
              },
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_balances == null)
              TextButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('تحديث الأرصدة'),
              )
            else ...<Widget>[
              Text(
                'رصيد ${_fundLabel(_source)} المتاح: '
                '${FinancialFormat.assetBalance(sourceBalance!, _unit)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 5),
              Text(
                'رصيد ${_fundLabel(_destination)} الحالي: '
                '${FinancialFormat.assetBalance(destinationBalance!, _unit)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 15),
            TextField(
              controller: _amount,
              enabled: !_saving,
              keyboardType: TextInputType.numberWithOptions(
                decimal: _unit == FinancialUnit.usd,
              ),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(
                  _unit == FinancialUnit.usd ? r'[0-9.]' : r'[0-9]',
                )),
              ],
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                labelText: 'المبلغ المراد نقله',
                suffixText: FinancialFormat.unitShort(_unit),
                border: const OutlineInputBorder(),
              ),
            ),
            if (showPreview) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                'بعد التحويل: الادخار/المصاريف بحسب الاتجاه، '
                'رصيد المصدر ${FinancialFormat.assetBalance(
                  sourceBalance! - amount!, _unit,
                )}، والوجهة ${FinancialFormat.assetBalance(
                  destinationBalance! + amount!, _unit,
                )}.',
                style: TextStyle(color: colors.primary),
              ),
            ],
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _saving ? null : _chooseDate,
              icon: const Icon(Icons.event_outlined),
              label: Text('تاريخ التحويل: ${FinancialFormat.date(_date)}'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLines: 2,
              maxLength: 300,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'السبب أو الملاحظة (اختياري)',
                hintText: 'مثلاً: احتجت مبلغ للمصاريف',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: colors.error)),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving || _loading || _balances == null
                  ? null : _submit,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.swap_horiz_rounded),
              label: Text(_saving ? 'جاري النقل...' : 'نقل المبلغ'),
            ),
          ],
        ),
      ),
    );
  }
}
