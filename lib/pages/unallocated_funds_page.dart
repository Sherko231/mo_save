import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/financial_event.dart';
import '../services/financial_ledger_storage.dart';
import '../utils/financial_format.dart';

/// Explicit one-time classification of legacy/unassigned assets.
/// It never creates an income or an owned-asset credit. Existing goal-grid
/// progress stays historical until the separate goal-backing migration.
class UnallocatedFundsPage extends StatefulWidget {
  const UnallocatedFundsPage({super.key});

  @override
  State<UnallocatedFundsPage> createState() => _UnallocatedFundsPageState();
}

class _UnallocatedFundsPageState extends State<UnallocatedFundsPage> {
  final FinancialLedgerStorage _ledger = FinancialLedgerStorage();
  Map<FinancialUnit, int>? _unallocated;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final balances = await _ledger.loadFundBalancesMicros();
      if (!mounted) return;
      setState(() {
        _unallocated = balances[FinancialFund.unallocated];
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'تعذر تحميل الأرصدة غير الموزعة.');
    }
  }

  // Parse exact decimal micro-units without double arithmetic or rounding.
  static int? _parseMicros(String raw, FinancialUnit unit) {
    final text = raw.trim();
    final decimals = switch (unit) {
      FinancialUnit.usd => 2,
      FinancialUnit.goldGram => 3,
      FinancialUnit.syp || FinancialUnit.sypNew => 0,
    };
    if (text.isEmpty || !RegExp(r'^\d+(\.\d+)?$').hasMatch(text)) {
      return null;
    }
    final parts = text.split('.');
    if (parts.length > 1 &&
        (decimals == 0 || parts[1].length > decimals)) {
      return null;
    }
    final whole = int.tryParse(parts.first);
    if (whole == null) return null;
    final fraction = parts.length == 1
        ? 0
        : int.tryParse(parts.last.padRight(6, '0'));
    if (fraction == null) return null;
    return whole * LedgerEntry.microsPerUnit + fraction;
  }

  Future<void> _allocate(
    FinancialUnit unit,
    FinancialFund destination,
    int availableMicros,
  ) async {
    if (_busy || availableMicros <= 0) return;
    final controller = TextEditingController(
      text: FinancialFormat.editableAmount(availableMicros, unit),
    );
    final amount = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        String? errorText;
        return StatefulBuilder(
          builder: (dialogContext, updateDialog) => AlertDialog(
            title: Text(
              destination == FinancialFund.savings
                  ? 'تخصيص للادخار'
                  : 'تخصيص للمصاريف',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'حدد من أموالك الموجودة أصلاً المبلغ المخصص للصندوق. '
                  'هذا توزيع للرصيد وليس دخلاً جديداً.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'المبلغ',
                    suffixText: FinancialFormat.unitShort(unit),
                    errorText: errorText,
                  ),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () {
                  final parsed = _parseMicros(controller.text, unit);
                  if (parsed == null ||
                      parsed <= 0 ||
                      parsed > availableMicros) {
                    updateDialog(() {
                      errorText = 'أدخل مبلغاً صحيحاً ضمن الرصيد المتاح.';
                    });
                    return;
                  }
                  Navigator.pop(dialogContext, parsed);
                },
                child: const Text('تأكيد التوزيع'),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    if (!mounted || amount == null) return;
    setState(() => _busy = true);
    try {
      await _ledger.transferFunds(
        unit: unit,
        source: FinancialFund.unallocated,
        destination: destination,
        amountMicros: amount,
        occurredAt: DateTime.now(),
        note: 'توزيع الرصيد غير المصنف',
      );
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم توزيع المبلغ بدون إضافة دخل جديد.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'تعذر توزيع المبلغ. تحقق من الرصيد وحاول مجدداً.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final balances = _unallocated;
    return Scaffold(
      appBar: AppBar(title: const Text('توزيع الأرصدة القديمة')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: <Widget>[
            const Text(
              'الأموال غير الموزعة',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'هذه الأموال مسجلة في رصيدك الحقيقي، لكنها ليست مصنفة بعد '
              'كمدخرات أو كمبلغ متاح للصرف. وزّعها حسب الواقع فقط. '
              'الخانات المكتملة في تحديات الادخار القديمة ليست دليلاً '
              'تلقائياً على وجود مال مدخر.',
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              )),
            ],
            const SizedBox(height: 16),
            if (balances == null)
              const Center(child: CircularProgressIndicator())
            else if (balances.values.every((amount) => amount == 0))
              const ListTile(
                leading: Icon(Icons.check_circle_outline),
                title: Text('ما في أرصدة غير موزعة حالياً'),
                subtitle: Text('أي أموال غير مصنفة مستقبلاً بتظهر هون.'),
              )
            else
              ...FinancialUnit.values.map((unit) {
                final amount = balances[unit] ?? 0;
                if (amount == 0) return const SizedBox.shrink();
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(FinancialFormat.unitLabel(unit)),
                        const SizedBox(height: 6),
                        Text(
                          FinancialFormat.assetBalance(amount, unit),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (amount < 0)
                          const Text(
                            'هذا رصيد تاريخي سالب يحتاج تصحيح الحركات '
                            'قبل توزيع أي مبلغ منه.',
                          )
                        else ...<Widget>[
                          const SizedBox(height: 10),
                          FilledButton.tonal(
                            onPressed: _busy
                                ? null
                                : () => _allocate(
                                    unit, FinancialFund.savings, amount),
                            child: const Text('تخصيص للادخار'),
                          ),
                          if (unit != FinancialUnit.goldGram)
                            OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => _allocate(
                                      unit, FinancialFund.spending, amount),
                              child: const Text('تخصيص للمصاريف'),
                            ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
