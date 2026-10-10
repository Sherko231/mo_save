import 'dart:async';

import 'package:flutter/material.dart';

import '../models/financial_event.dart';
import '../services/financial_ledger_storage.dart';
import '../services/spending_fund_service.dart';
import '../ui/ux_components.dart';
import '../utils/financial_format.dart';
import 'spending_quick_expense_page.dart';
import 'transaction_history_page.dart';
import 'unallocated_funds_page.dart';

/// Always describes NOW, independent of the month selected in the historical
/// Home overview. Plans are clearly hypothetical and cannot debit balances.
class HomeSpendingFundSection extends StatefulWidget {
  const HomeSpendingFundSection({super.key});

  @override
  State<HomeSpendingFundSection> createState() =>
      _HomeSpendingFundSectionState();
}

class _HomeSpendingFundSectionState extends State<HomeSpendingFundSection> {
  final SpendingFundService _service = SpendingFundService();
  StreamSubscription<void>? _ledgerChanges;
  SpendingFundSnapshot? _snapshot;
  bool _loading = true;
  String? _error;
  int _refreshSequence = 0;

  @override
  void initState() {
    super.initState();
    _ledgerChanges = FinancialLedgerStorage.changes.listen((_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _refreshSequence++;
    _ledgerChanges?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final int request = ++_refreshSequence;
    try {
      final snapshot = await _service.loadCurrentMonth();
      if (!mounted || request != _refreshSequence) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || request != _refreshSequence) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل رصيد الصندوق. أعد المحاولة.';
      });
    }
  }

  Future<void> _openExpense() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const SpendingQuickExpensePage(),
      ),
    );
    if (!mounted) return;
    if (changed == true) {
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل مصروف من صندوق المصاريف.')),
      );
    }
  }

  Future<void> _openFundHistory() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const TransactionHistoryPage(
          initialFund: FinancialFund.spending,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _reconcile() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const UnallocatedFundsPage(),
      ),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final snapshot = _snapshot;
    final bool unallocatedExists = snapshot != null &&
        SpendingFundSnapshot.cashUnits.any((unit) =>
            snapshot.unallocatedBalanceMicros(unit) != 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const UxSectionHeader(
          title: 'صندوق المصاريف',
          subtitle: 'المال المتاح للصرف الآن — منفصل عن الادخار',
        ),
        const SizedBox(height: 10),
        if (_loading && snapshot == null)
          const Padding(
            padding: EdgeInsets.all(26),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (snapshot == null) ...<Widget>[
          UxSoftCard(
            child: Column(
              children: <Widget>[
                Text(_error ?? 'تعذر عرض رصيد الصندوق.'),
                TextButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ] else ...<Widget>[
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!,
                  style: TextStyle(color: colors.error)),
            ),
          for (final unit in SpendingFundSnapshot.cashUnits)
            if (unit != FinancialUnit.sypNew ||
                snapshot.spendableMicros(unit) != 0 ||
                snapshot.unallocatedBalanceMicros(unit) != 0 ||
                snapshot.plannedCommitmentsMicros(unit) != 0 ||
                snapshot.actualPaidAcrossAllFundsMicros(unit) != 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _SpendingCurrencyCard(
                  unit: unit,
                  snapshot: snapshot,
                ),
              ),
          if (unallocatedExists)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: UxSoftCard(
                tone: colors.tertiary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text(
                      'في أموال غير موزّعة — ليست ضمن المتاح للصرف.',
                    ),
                    const SizedBox(height: 6),
                    for (final unit in SpendingFundSnapshot.cashUnits)
                      if (snapshot.unallocatedBalanceMicros(unit) != 0)
                        Text(
                          FinancialFormat.assetBalance(
                            snapshot.unallocatedBalanceMicros(unit), unit,
                          ),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: _reconcile,
                        icon: const Icon(Icons.call_split_outlined),
                        label: const Text('توزيع الأرصدة غير المصنّفة'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'الأرصدة أعلاه لحظة العرض. المصروف الفعلي مسجل مرة واحدة '
            'عند الدفع، وليس عند إعداد الخطة. تقدير ما بعد الخطة '
            'يفترض دفع كامل البنود الشهرية من الآن وقد يشمل '
            'بنوداً دفعتها سابقاً، لأن الربط بين الفواتير والمدفوعات '
            'غير متوفر بعد.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: snapshot == null ? null : _openExpense,
          icon: const Icon(Icons.add_card_rounded),
          label: const Text('إضافة مصروف من الصندوق'),
        ),
        const SizedBox(height: 7),
        OutlinedButton.icon(
          onPressed: _openFundHistory,
          icon: const Icon(Icons.history_rounded),
          label: const Text('سجل حركات صندوق المصاريف'),
        ),
      ],
    );
  }
}

class _SpendingCurrencyCard extends StatelessWidget {
  const _SpendingCurrencyCard({
    required this.unit,
    required this.snapshot,
  });

  final FinancialUnit unit;
  final SpendingFundSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hypothetical = snapshot.hypotheticalAfterFullPlanMicros(unit);
    final spentFromFund = snapshot.paidFromSpendingMicros(unit);
    final paidAll = snapshot.actualPaidAcrossAllFundsMicros(unit);

    return UxSoftCard(
      tone: colors.primary,
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            FinancialFormat.unitLabel(unit),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 3),
          Text(
            'متاح للصرف الآن',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
          Text(
            FinancialFormat.assetBalance(snapshot.spendableMicros(unit), unit),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          _SpendingMetric(
            label: 'التزامات الخطة الشهرية',
            value: snapshot.plannedCommitmentsMicros(unit),
            unit: unit,
          ),
          const SizedBox(height: 5),
          _SpendingMetric(
            label: 'دُفع من صندوق المصاريف هذا الشهر',
            value: spentFromFund,
            unit: unit,
          ),
          if (paidAll != spentFromFund) ...<Widget>[
            const SizedBox(height: 5),
            _SpendingMetric(
              label: 'إجمالي المصروف الفعلي من كل الصناديق',
              value: paidAll,
              unit: unit,
            ),
          ],
          const Divider(height: 22),
          _SpendingMetric(
            label: 'تقدير افتراضي بعد دفع كامل الخطة من الآن',
            value: hypothetical,
            unit: unit,
            accent: hypothetical < 0 ? colors.error : colors.tertiary,
          ),
          if (hypothetical < 0)
            Text('الفرق الافتراضي المطلوب: '
                '${FinancialFormat.assetBalance(-hypothetical, unit)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.error,
                )),
        ],
      ),
    );
  }
}

class _SpendingMetric extends StatelessWidget {
  const _SpendingMetric({
    required this.label,
    required this.value,
    required this.unit,
    this.accent,
  });

  final String label;
  final int value;
  final FinancialUnit unit;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            FinancialFormat.assetBalance(value, unit),
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: accent),
          ),
        ),
      ],
    );
  }
}
