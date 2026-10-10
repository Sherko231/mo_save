import 'dart:async';

import 'package:flutter/material.dart';

import '../models/financial_event.dart';
import '../services/expense_service.dart';
import '../services/financial_ledger_storage.dart';
import '../ui/ux_components.dart';
import '../utils/financial_format.dart';
import 'expense_plan_sheet.dart';
import 'spending_quick_expense_page.dart';

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
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const SpendingQuickExpensePage(),
      ),
    );
    if (!mounted || saved != true) return;
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تسجيل المصروف الفعلي.')),
    );
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
                onPressed: _logExpense,
                icon: const Icon(Icons.add_card_rounded),
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

const List<FinancialUnit> _cashUnits = <FinancialUnit>[
  FinancialUnit.syp,
  FinancialUnit.usd,
  FinancialUnit.sypNew,
];
