import 'dart:async';

import 'package:flutter/material.dart';

import '../models/financial_event.dart';
import '../services/financial_ledger_storage.dart';
import '../services/spending_analytics_service.dart';
import '../ui/ux_components.dart';
import '../utils/financial_format.dart';
import 'transaction_history_page.dart';

/// Read-only analytics. Every displayed paid amount is reconciled to a
/// balance-decreasing expense entry, not a transfer or expected bill.
class SpendingAnalyticsPage extends StatefulWidget {
  const SpendingAnalyticsPage({
    super.key,
    required this.initialMonth,
    this.service,
  });

  final DateTime initialMonth;
  final SpendingAnalyticsService? service;

  @override
  State<SpendingAnalyticsPage> createState() => _SpendingAnalyticsPageState();
}

class _SpendingAnalyticsPageState extends State<SpendingAnalyticsPage> {
  late final SpendingAnalyticsService _service;
  late DateTime _month;
  FinancialUnit _unit = FinancialUnit.syp;
  String _fundChoice = 'all';
  String _kindChoice = 'all';
  MonthlySpendingAnalytics? _report;
  StreamSubscription<void>? _ledgerChanges;
  bool _loading = true;
  String? _error;
  int _generation = 0;

  static const List<FinancialUnit> _units = <FinancialUnit>[
    FinancialUnit.syp, FinancialUnit.usd, FinancialUnit.sypNew,
  ];

  static const List<String> _monthNames = <String>[
    '', 'كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران',
    'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول',
  ];

  FinancialFund? get _chosenFund => _fundChoice == 'all'
      ? null : FinancialFund.values.byName(_fundChoice);

  bool? get _chosenRecurring => switch (_kindChoice) {
    'recurring' => true,
    'oneOff' => false,
    _ => null,
  };

  String _fundName(FinancialFund fund) => switch (fund) {
    FinancialFund.savings => 'الادخار',
    FinancialFund.spending => 'المصاريف',
    FinancialFund.unallocated => 'غير موزع',
  };

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? SpendingAnalyticsService();
    _month = DateTime(widget.initialMonth.year, widget.initialMonth.month);
    _ledgerChanges = FinancialLedgerStorage.changes.listen((_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _generation++;
    _ledgerChanges?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final request = ++_generation;
    try {
      final result = await _service.loadMonth(_month);
      if (!mounted || request != _generation) return;
      setState(() {
        _report = result;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || request != _generation) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل التحليلات. حاول مجدداً.';
      });
    }
  }

  void _changeMonth(int offset) {
    setState(() {
      _month = DateTime(_month.year, _month.month + offset);
      _loading = true;
      _report = null;
    });
    _refresh();
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TransactionHistoryPage(
          initialMonth: _month,
          initialFund: _chosenFund,
          initialUnit: _unit,
          initialType: FinancialEventType.expense,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _drillDown(SpendingCategoryTotal category) async {
    final colors = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (dialogContext) => FractionallySizedBox(
        heightFactor: 0.86,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
          children: <Widget>[
            Text(
              'تفاصيل: ${category.category}',
              style: Theme.of(dialogContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              '${category.lines.length} قيد فعلي • '
              '${FinancialFormat.assetBalance(category.amountMicros, _unit)}',
            ),
            const SizedBox(height: 10),
            for (final line in category.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: UxSoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(children: <Widget>[
                        Expanded(
                          child: Text(FinancialFormat.date(line.event.occurredAt),
                            style: Theme.of(dialogContext).textTheme.titleSmall),
                        ),
                        Text(
                          FinancialFormat.assetBalance(line.paidMicros, line.unit),
                          style: Theme.of(dialogContext).textTheme.titleMedium,
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        'المصدر: ${_fundName(line.fund)} • '
                        '${line.isRecurringPayment ? 'قسط متكرر مؤكد' : 'مصروف منفرد / غير مرتبط بقسط'}',
                      ),
                      if (line.event.note?.trim().isNotEmpty ?? false) ...<Widget>[
                        const SizedBox(height: 5),
                        Text('الملاحظة: ${line.event.note}'),
                      ],
                      const SizedBox(height: 7),
                      SelectableText(
                        'رقم الحركة: ${line.event.id} • القيد: ${line.entryIndex + 1}',
                        style: Theme.of(dialogContext).textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _openHistory();
              },
              icon: const Icon(Icons.history_rounded),
              label: const Text('فتح سجل الحركات والتصحيحات'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final colors = Theme.of(context).colorScheme;
    final actualAll = report?.actualMicros(_unit) ?? 0;
    final plannedAll = report?.planMicros(_unit) ?? 0;
    final paidFiltered = report?.actualMicros(_unit,
      fund: _chosenFund, recurring: _chosenRecurring) ?? 0;
    final previousFiltered = report?.previousActualMicros(_unit,
      fund: _chosenFund, recurring: _chosenRecurring) ?? 0;
    final categories = report?.categories(_unit,
      fund: _chosenFund, recurring: _chosenRecurring)
        ?? <SpendingCategoryTotal>[];
    final maxCategory = categories.isEmpty ? 0 : categories.first.amountMicros;

    return Scaffold(
      appBar: AppBar(title: const Text('تحليلات المصاريف الشهرية')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
            children: <Widget>[
              UxSoftCard(
                child: Row(
                  children: <Widget>[
                    IconButton(
                      tooltip: 'الشهر السابق',
                      onPressed: () => _changeMonth(-1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                    Expanded(
                      child: Text(
                        '${_monthNames[_month.month]} ${_month.year}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'الشهر التالي',
                      onPressed: () => _changeMonth(1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<FinancialUnit>(
                value: _unit,
                decoration: const InputDecoration(
                  labelText: 'العملة — بدون دمج العملات',
                  border: OutlineInputBorder(),
                ),
                items: _units.map((unit) => DropdownMenuItem(
                  value: unit, child: Text(FinancialFormat.unitLabel(unit)),
                )).toList(growable: false),
                onChanged: (unit) {
                  if (unit != null) setState(() => _unit = unit);
                },
              ),
              const SizedBox(height: 12),
              if (_loading) const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              ) else if (report == null) ...<Widget>[
                Text(_error ?? 'لا يمكن عرض التحليلات حالياً.',
                  style: TextStyle(color: colors.error)),
                TextButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ] else ...<Widget>[
                const UxSectionHeader(
                  title: 'المخطط مقابل المدفوع',
                  subtitle: 'المبالغ الفعلية من كل الصناديق، وليست أرصدة متاحة',
                ),
                const SizedBox(height: 8),
                UxSoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _AnalyticsMetric(
                        label: 'الخطة الكاملة لهذا الشهر',
                        amount: plannedAll, unit: _unit,
                      ),
                      const SizedBox(height: 7),
                      _AnalyticsMetric(
                        label: 'إجمالي المصاريف الفعلية',
                        amount: actualAll, unit: _unit,
                      ),
                      const SizedBox(height: 8),
                      if (plannedAll > 0)
                        LinearProgressIndicator(
                          value: (actualAll / plannedAll).clamp(0.0, 1.0).toDouble(),
                          minHeight: 7,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        plannedAll == 0
                          ? 'لا توجد خطة لهذه العملة. المصروف الفعلي محفوظ كما هو.'
                          : actualAll > plannedAll
                            ? 'تجاوز الفعلي الخطة بمقدار '
                                '${FinancialFormat.assetBalance(actualAll - plannedAll, _unit)}.'
                            : 'الفرق الحسابي عن الخطة: '
                                '${FinancialFormat.assetBalance(plannedAll - actualAll, _unit)}.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'الفرق بين الخطة والفعلي لا يعني فواتير غير مدفوعة. '
                        'بعض المصاريف المسجلة سابقاً قد لا تكون مرتبطة بالقسط المخطط.',
                        style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const UxSectionHeader(
                  title: 'من وين اندفعت المصاريف؟',
                  subtitle: 'كل مصدر دفع مستقل — التحويلات ليست مصاريف',
                ),
                const SizedBox(height: 8),
                UxSoftCard(
                  child: Column(
                    children: <Widget>[
                      for (final fund in FinancialFund.values) ...<Widget>[
                        _AnalyticsMetric(
                          label: _fundName(fund),
                          amount: report.actualMicros(_unit, fund: fund),
                          unit: _unit,
                        ),
                        if (fund != FinancialFund.values.last)
                          const Divider(height: 18),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const UxSectionHeader(
                  title: 'متكرر مقابل منفرد',
                  subtitle: 'المتكرر يعني قسطاً رُبط بالدفع صراحةً، لا مجرد تشابه اسم',
                ),
                const SizedBox(height: 8),
                UxSoftCard(
                  child: Column(children: <Widget>[
                    _AnalyticsMetric(
                      label: 'دفعات خطط متكررة مؤكدة',
                      amount: report.actualMicros(_unit, recurring: true),
                      unit: _unit,
                    ),
                    const Divider(height: 16),
                    _AnalyticsMetric(
                      label: 'مصاريف فردية أو غير مرتبطة',
                      amount: report.actualMicros(_unit, recurring: false),
                      unit: _unit,
                    ),
                  ]),
                ),
                const SizedBox(height: 18),
                const UxSectionHeader(
                  title: 'التصنيفات والتفاصيل',
                  subtitle: 'اضغط التصنيف لعرض الحركات الأصلية وملاحظاتها',
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _fundChoice,
                  decoration: const InputDecoration(
                    labelText: 'تصفية حسب مصدر الدفع',
                    border: OutlineInputBorder(),
                  ),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem(value: 'all', child: Text('كل الصناديق')),
                    DropdownMenuItem(value: 'spending', child: Text('المصاريف')),
                    DropdownMenuItem(value: 'savings', child: Text('الادخار')),
                    DropdownMenuItem(value: 'unallocated', child: Text('غير موزع')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _fundChoice = value);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _kindChoice,
                  decoration: const InputDecoration(
                    labelText: 'نوع الدفع الفعلي',
                    border: OutlineInputBorder(),
                  ),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem(value: 'all', child: Text('كل المصاريف')),
                    DropdownMenuItem(value: 'recurring', child: Text('الأقساط المتكررة المؤكدة')),
                    DropdownMenuItem(value: 'oneOff', child: Text('المنفردة أو غير المرتبطة')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _kindChoice = value);
                  },
                ),
                const SizedBox(height: 10),
                UxSoftCard(
                  tone: colors.primary,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _AnalyticsMetric(
                        label: 'المصروف ضمن الفلاتر الحالية',
                        amount: paidFiltered, unit: _unit,
                      ),
                      const SizedBox(height: 8),
                      _AnalyticsMetric(
                        label: 'نفس الفلاتر بالشهر السابق',
                        amount: previousFiltered, unit: _unit,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        paidFiltered == previousFiltered
                            ? 'لا فرق عن الشهر السابق.'
                            : paidFiltered > previousFiltered
                              ? 'أعلى من الشهر السابق بـ '
                                  '${FinancialFormat.assetBalance(paidFiltered - previousFiltered, _unit)}'
                              : 'أقل من الشهر السابق بـ '
                                  '${FinancialFormat.assetBalance(previousFiltered - paidFiltered, _unit)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (categories.isEmpty)
                  const UxEmptyState(
                    icon: Icons.pie_chart_outline_rounded,
                    title: 'ما في مصاريف مطابقة',
                    body: 'لا توجد مدفوعات فعلية ضمن هذا الشهر والعملة والفلاتر.',
                  )
                else
                  for (final category in categories)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: UxSoftCard(
                        child: InkWell(
                          onTap: () => _drillDown(category),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Row(children: <Widget>[
                                Expanded(
                                  child: Text(category.category,
                                    style: Theme.of(context).textTheme.titleMedium),
                                ),
                                Text(FinancialFormat.assetBalance(
                                  category.amountMicros, _unit,
                                )),
                                const Icon(Icons.chevron_left_rounded),
                              ]),
                              const SizedBox(height: 7),
                              LinearProgressIndicator(
                                value: maxCategory == 0 ? 0 :
                                  category.amountMicros / maxCategory,
                                minHeight: 6,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '${category.lines.length} قيد • اضغط للتفاصيل',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _openHistory,
                  icon: const Icon(Icons.history_rounded),
                  label: const Text('عرض المصاريف في سجل الحركات'),
                ),
                const SizedBox(height: 14),
                Text(
                  'التحليلات مبنية على المصاريف الفعلية فقط، مع الحفاظ '
                  'على العملة والصندوق والملاحظة الأصلية. لا نضيف '
                  'الأموال غير المصروفة أو التحويلات الداخلية أو '
                  'أرصدة البداية للمصروف الشهري.',
                  style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalyticsMetric extends StatelessWidget {
  const _AnalyticsMetric({
    required this.label,
    required this.amount,
    required this.unit,
  });
  final String label;
  final int amount;
  final FinancialUnit unit;

  @override
  Widget build(BuildContext context) {
    return Row(children: <Widget>[
      Expanded(child: Text(label,
        style: Theme.of(context).textTheme.bodyMedium)),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          FinancialFormat.assetBalance(amount, unit),
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
    ]);
  }
}
