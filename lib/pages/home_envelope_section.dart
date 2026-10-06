import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/expected_income.dart';
import '../models/financial_event.dart';
import '../models/weekly_envelope_allocation.dart';
import '../services/recurring_income_service.dart';
import '../services/weekly_envelope_service.dart';
import '../ui/ux_components.dart';
import '../utils/financial_format.dart';

class HomeEnvelopeSection extends StatefulWidget {
  const HomeEnvelopeSection({
    super.key,
    required this.month,
    required this.refreshToken,
  });

  final DateTime month;
  final int refreshToken;

  @override
  State<HomeEnvelopeSection> createState() => _HomeEnvelopeSectionState();
}

class _HomeEnvelopeSectionState extends State<HomeEnvelopeSection> {
  final RecurringIncomeService _incomeService = RecurringIncomeService();
  final WeeklyEnvelopeService _envelopeService = WeeklyEnvelopeService();

  List<ExpectedIncome> _receivedWeekly = const <ExpectedIncome>[];
  Map<String, WeeklyEnvelopeAllocation?> _allocations =
      const <String, WeeklyEnvelopeAllocation?>{};
  bool _isLoading = true;
  String? _allocatingKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HomeEnvelopeSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month.year != widget.month.year ||
        oldWidget.month.month != widget.month.month ||
        oldWidget.refreshToken != widget.refreshToken) {
      _load(showLoading: false);
    }
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final List<ExpectedIncome> occurrences =
          await _incomeService.loadMonth(widget.month);
      final List<ExpectedIncome> receivedWeekly = occurrences
          .where(
            (item) =>
                item.kind == RecurringIncomeKind.weeklySyp && item.isReceived,
          )
          .toList(growable: false);

      final Map<String, WeeklyEnvelopeAllocation?> allocations =
          <String, WeeklyEnvelopeAllocation?>{};
      for (final ExpectedIncome occurrence in receivedWeekly) {
        allocations[occurrence.recurrenceKey] =
            await _envelopeService.loadAllocation(occurrence);
      }

      if (!mounted) return;
      setState(() {
        _receivedWeekly = receivedWeekly;
        _allocations = allocations;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحميل تقسيم راتب الخميس.')),
      );
    }
  }

  Future<void> _allocate(ExpectedIncome occurrence) async {
    final WeeklyEnvelopeSuggestion suggestion;
    try {
      suggestion = await _envelopeService.suggestedSplit(occurrence);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحميل إعدادات التقسيم.')),
      );
      return;
    }

    if (!mounted) return;

    final TextEditingController expensesController = TextEditingController(
      text: _wholeSyp(suggestion.expensesMicros).toString(),
    );
    final TextEditingController savingsController = TextEditingController(
      text: _wholeSyp(suggestion.savingsMicros).toString(),
    );

    final _EnvelopeInput? input = await showDialog<_EnvelopeInput>(
      context: context,
      builder: (dialogContext) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final int expenses = int.tryParse(expensesController.text) ?? 0;
            final int savings = int.tryParse(savingsController.text) ?? 0;
            final int received = _wholeSyp(suggestion.receivedMicros);
            final int unallocated = received - expenses - savings;

            return AlertDialog(
              title: const Text('تقسيم راتب الخميس'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'المبلغ المستلم: ${FinancialFormat.assetBalance(suggestion.receivedMicros, FinancialUnit.syp)}',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: expensesController,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: (_) => setDialogState(() => errorText = null),
                      decoration: const InputDecoration(
                        labelText: 'المصاريف والالتزامات',
                        suffixText: 'ل.س',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: savingsController,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: (_) => setDialogState(() => errorText = null),
                      decoration: const InputDecoration(
                        labelText: 'الادخار',
                        suffixText: 'ل.س',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      unallocated >= 0
                          ? 'غير موزع: ${FinancialFormat.amount(unallocated, FinancialUnit.syp)}'
                          : 'التوزيع أكبر من الراتب بـ ${FinancialFormat.amount(-unallocated, FinancialUnit.syp)}',
                    ),
                    if (errorText != null) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      'هذا التقسيم يخصص راتب الليرة فقط ولا يسحب شيئاً من مدخرات الدولار.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () {
                    final int? parsedExpenses =
                        int.tryParse(expensesController.text.trim());
                    final int? parsedSavings =
                        int.tryParse(savingsController.text.trim());
                    if (parsedExpenses == null || parsedSavings == null) {
                      setDialogState(() {
                        errorText = 'أدخل أرقاماً صحيحة.';
                      });
                      return;
                    }
                    if (parsedExpenses < 0 || parsedSavings < 0) {
                      setDialogState(() {
                        errorText = 'المبالغ لا يمكن أن تكون سالبة.';
                      });
                      return;
                    }
                    if (parsedExpenses == 0 && parsedSavings == 0) {
                      setDialogState(() {
                        errorText = 'خصص جزءاً من الراتب على الأقل.';
                      });
                      return;
                    }
                    if (parsedExpenses + parsedSavings > received) {
                      setDialogState(() {
                        errorText =
                            'مجموع التقسيم لا يمكن أن يتجاوز الراتب المستلم.';
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(
                      _EnvelopeInput(
                        expenses: parsedExpenses,
                        savings: parsedSavings,
                      ),
                    );
                  },
                  child: const Text('تأكيد التقسيم'),
                ),
              ],
            );
          },
        );
      },
    );

    expensesController.dispose();
    savingsController.dispose();

    if (input == null || !mounted) return;

    setState(() => _allocatingKey = occurrence.recurrenceKey);

    try {
      await _envelopeService.allocate(
        occurrence: occurrence,
        expensesMicros: LedgerEntry.amountToMicros(input.expenses),
        savingsMicros: LedgerEntry.amountToMicros(input.savings),
      );
      await _load(showLoading: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ تقسيم راتب الخميس.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر حفظ التقسيم أو تم تقسيم الراتب مسبقاً.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _allocatingKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final int totalExpenses = _receivedWeekly.fold<int>(
      0,
      (sum, item) =>
          sum + (_allocations[item.recurrenceKey]?.expensesMicros ?? 0),
    );
    final int totalSavings = _receivedWeekly.fold<int>(
      0,
      (sum, item) =>
          sum + (_allocations[item.recurrenceKey]?.savingsMicros ?? 0),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'تقسيم راتب الخميس',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'وزّع كل راتب مستلم بين المصاريف والادخار. يمكنك تعديل القيم قبل التأكيد.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 10),
        if (totalExpenses > 0 || totalSavings > 0)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              UxStatusPill(
                icon: Icons.receipt_long_outlined,
                label:
                    'للمصاريف: ${FinancialFormat.assetBalance(totalExpenses, FinancialUnit.syp)}',
                color: Theme.of(context).colorScheme.tertiary,
              ),
              UxStatusPill(
                icon: Icons.savings_outlined,
                label:
                    'للادخار: ${FinancialFormat.assetBalance(totalSavings, FinancialUnit.syp)}',
              ),
            ],
          ),
        if (totalExpenses > 0 || totalSavings > 0)
          const SizedBox(height: 10),
        if (_receivedWeekly.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'بعد تأكيد استلام أول راتب أسبوعي سيظهر هنا خيار تقسيمه.',
              ),
            ),
          )
        else
          ..._receivedWeekly.map(
            (occurrence) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AllocationCard(
                occurrence: occurrence,
                allocation: _allocations[occurrence.recurrenceKey],
                isAllocating: _allocatingKey == occurrence.recurrenceKey,
                onAllocate: () => _allocate(occurrence),
              ),
            ),
          ),
      ],
    );
  }
}

class _AllocationCard extends StatelessWidget {
  const _AllocationCard({
    required this.occurrence,
    required this.allocation,
    required this.isAllocating,
    required this.onAllocate,
  });

  final ExpectedIncome occurrence;
  final WeeklyEnvelopeAllocation? allocation;
  final bool isAllocating;
  final VoidCallback onAllocate;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final WeeklyEnvelopeAllocation? current = allocation;
    final int received = occurrence.receivedAmountMicros ?? 0;
    final int unallocated =
        current == null ? received : received - current.allocatedMicros;
    final Color tone = current == null ? colors.tertiary : colors.primary;

    return UxSoftCard(
      tone: tone,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              UxIconBadge(
                icon: current == null
                    ? Icons.call_split_rounded
                    : Icons.check_rounded,
                tone: tone,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'راتب ${FinancialFormat.date(occurrence.scheduledDate)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'المستلم: ${FinancialFormat.assetBalance(received, FinancialUnit.syp)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              UxStatusPill(
                label: current == null ? 'بانتظار التقسيم' : 'تم التوزيع',
                color: tone,
              ),
            ],
          ),
          if (current != null) ...<Widget>[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                UxStatusPill(
                  icon: Icons.receipt_long_outlined,
                  label:
                      'مصاريف ${FinancialFormat.assetBalance(current.expensesMicros, FinancialUnit.syp)}',
                  color: colors.tertiary,
                ),
                UxStatusPill(
                  icon: Icons.savings_outlined,
                  label:
                      'ادخار ${FinancialFormat.assetBalance(current.savingsMicros, FinancialUnit.syp)}',
                ),
                if (unallocated > 0)
                  UxStatusPill(
                    icon: Icons.more_horiz_rounded,
                    label:
                        'غير موزع ${FinancialFormat.assetBalance(unallocated, FinancialUnit.syp)}',
                    color: colors.onSurfaceVariant,
                  ),
              ],
            ),
          ] else ...<Widget>[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: isAllocating ? null : onAllocate,
              icon: isAllocating
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.call_split_rounded),
              label: const Text('توزيع الراتب'),
            ),
          ],
        ],
      ),
    );
  }
}

class _EnvelopeInput {
  const _EnvelopeInput({required this.expenses, required this.savings});

  final int expenses;
  final int savings;
}

int _wholeSyp(int micros) => (micros / LedgerEntry.microsPerUnit).round();
