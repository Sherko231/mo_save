import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/expected_income.dart';
import '../models/financial_event.dart';
import '../services/financial_ledger_storage.dart';
import '../services/home_dashboard_service.dart';
import '../services/recurring_income_service.dart';
import '../utils/financial_format.dart';
import 'home_balance_section.dart';
import 'home_dashboard_overview.dart';
import 'home_envelope_section.dart';
import 'home_expenses_section.dart';
import 'transaction_history_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.isActive,
  });

  final bool isActive;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final RecurringIncomeService _incomeService = RecurringIncomeService();
  final HomeDashboardService _dashboardService = HomeDashboardService();

  StreamSubscription<void>? _ledgerSubscription;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  HomeDashboardSnapshot? _dashboard;
  List<ExpectedIncome> _occurrences = const <ExpectedIncome>[];
  bool _isLoading = true;
  String? _confirmingKey;
  int _incomeRefreshToken = 0;

  @override
  void initState() {
    super.initState();
    _ledgerSubscription = FinancialLedgerStorage.changes.listen((_) {
      if (mounted && widget.isActive && _confirmingKey == null) {
        _reload(showLoading: false, showError: false);
      }
    });
    _reload();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _reload(showLoading: false);
    }
  }

  @override
  void dispose() {
    _ledgerSubscription?.cancel();
    super.dispose();
  }

  Future<void> _reload({
    bool showLoading = true,
    bool showError = true,
  }) async {
    if (showLoading && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final HomeDashboardSnapshot dashboard =
          await _dashboardService.loadMonth(_selectedMonth);
      if (!mounted) return;

      setState(() {
        _dashboard = dashboard;
        _occurrences = dashboard.incomeOccurrences;
        _isLoading = false;
        _incomeRefreshToken++;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (showError) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحميل لوحة التحكم المالية.')),
        );
      }
    }
  }

  Future<void> _changeMonth(int delta) async {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
    });
    await _reload();
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const TransactionHistoryPage(),
      ),
    );
    if (mounted) {
      await _reload(showLoading: false, showError: false);
    }
  }

  Future<void> _confirmReceived(ExpectedIncome occurrence) async {
    final bool isSyp = occurrence.unit == FinancialUnit.syp;
    final TextEditingController controller = TextEditingController(
      text: FinancialFormat.editableAmount(
        occurrence.expectedAmountMicros,
        occurrence.unit,
      ),
    );

    final num? amount = await showDialog<num>(
      context: context,
      builder: (dialogContext) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('تأكيد استلام الدخل'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(_incomeTitle(occurrence)),
                  const SizedBox(height: 6),
                  Text('موعده: ${FinancialFormat.date(occurrence.scheduledDate)}'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      isSyp
                          ? FilteringTextInputFormatter.digitsOnly
                          : FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.]'),
                            ),
                    ],
                    decoration: InputDecoration(
                      labelText: 'المبلغ المستلم فعلياً',
                      suffixText: FinancialFormat.unitShort(occurrence.unit),
                      errorText: errorText,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () {
                    final String raw = controller.text.trim();
                    final num? parsed = isSyp
                        ? int.tryParse(raw)
                        : double.tryParse(raw);
                    if (parsed == null || parsed <= 0) {
                      setDialogState(() {
                        errorText = 'أدخل مبلغاً أكبر من صفر.';
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(parsed);
                  },
                  child: const Text('تأكيد'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();

    if (amount == null || !mounted) return;

    setState(() => _confirmingKey = occurrence.recurrenceKey);

    try {
      await _incomeService.confirmReceived(
        occurrence: occurrence,
        amountMicros: LedgerEntry.amountToMicros(amount),
      );
      await _reload(showLoading: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل الدخل المستلم.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تسجيل الدخل أو تم تسجيله مسبقاً.')),
      );
    } finally {
      if (mounted) setState(() => _confirmingKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _dashboard == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final HomeDashboardSnapshot? dashboard = _dashboard;
    if (dashboard == null) {
      return Center(
        child: FilledButton.icon(
          onPressed: _reload,
          icon: const Icon(Icons.refresh),
          label: const Text('إعادة تحميل لوحة التحكم'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _reload(showLoading: false),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
        children: <Widget>[
          HomeDashboardOverview(
            snapshot: dashboard,
            month: _selectedMonth,
            onPreviousMonth: () => _changeMonth(-1),
            onNextMonth: () => _changeMonth(1),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _openHistory,
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('سجل الحركات والتصحيحات'),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          HomeBalanceSection(refreshToken: _incomeRefreshToken),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'تفاصيل الدخل',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          _MonthSummary(occurrences: _occurrences),
          const SizedBox(height: 12),
          if (_occurrences.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('لا يوجد دخل متكرر متوقع في هذا الشهر.'),
              ),
            )
          else
            ..._occurrences.map(
              (occurrence) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _IncomeOccurrenceCard(
                  occurrence: occurrence,
                  isConfirming: _confirmingKey == occurrence.recurrenceKey,
                  onConfirm: () => _confirmReceived(occurrence),
                ),
              ),
            ),
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 12),
          HomeEnvelopeSection(
            month: _selectedMonth,
            refreshToken: _incomeRefreshToken,
          ),
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 12),
          HomeExpensesSection(month: _selectedMonth),
        ],
      ),
    );
  }

  static String _incomeTitle(ExpectedIncome occurrence) {
    return occurrence.kind == RecurringIncomeKind.weeklySyp
        ? 'راتب الخميس'
        : 'راتب الشهر';
  }
}

class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.occurrences});

  final List<ExpectedIncome> occurrences;

  @override
  Widget build(BuildContext context) {
    final int weeklyCount = occurrences
        .where((item) => item.kind == RecurringIncomeKind.weeklySyp)
        .length;
    final int receivedCount = occurrences.where((item) => item.isReceived).length;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        Chip(label: Text('$weeklyCount دفعات أسبوعية')),
        Chip(label: Text('${occurrences.length} دفعات متوقعة')),
        Chip(label: Text('$receivedCount مستلمة')),
      ],
    );
  }
}

class _IncomeOccurrenceCard extends StatelessWidget {
  const _IncomeOccurrenceCard({
    required this.occurrence,
    required this.isConfirming,
    required this.onConfirm,
  });

  final ExpectedIncome occurrence;
  final bool isConfirming;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final bool isPast = occurrence.scheduledDate.isBefore(today);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _HomePageState._incomeTitle(occurrence),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(FinancialFormat.date(occurrence.scheduledDate)),
                    ],
                  ),
                ),
                _StatusChip(
                  label: occurrence.isReceived
                      ? 'تم الاستلام'
                      : isPast
                          ? 'غير مستلم'
                          : 'متوقع',
                  received: occurrence.isReceived,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: _AmountColumn(
                    label: 'المتوقع',
                    value: FinancialFormat.assetBalance(
                      occurrence.expectedAmountMicros,
                      occurrence.unit,
                    ),
                  ),
                ),
                if (occurrence.isReceived)
                  Expanded(
                    child: _AmountColumn(
                      label: 'المستلم فعلياً',
                      value: FinancialFormat.assetBalance(
                        occurrence.receivedAmountMicros ?? 0,
                        occurrence.unit,
                      ),
                    ),
                  ),
              ],
            ),
            if (!occurrence.isReceived) ...<Widget>[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: isConfirming ? null : onConfirm,
                icon: isConfirming
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: const Text('تأكيد الاستلام'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.received,
  });

  final String label;
  final bool received;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        received ? Icons.check_circle : Icons.schedule,
        size: 18,
      ),
      label: Text(label),
    );
  }
}

class _AmountColumn extends StatelessWidget {
  const _AmountColumn({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}
