import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/expected_income.dart';
import '../models/financial_event.dart';
import '../services/recurring_income_service.dart';

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

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  List<ExpectedIncome> _occurrences = const <ExpectedIncome>[];
  ExpectedIncome? _nextExpected;
  bool _isLoading = true;
  String? _confirmingKey;

  static const List<String> _monthNames = <String>[
    '',
    'كانون الثاني',
    'شباط',
    'آذار',
    'نيسان',
    'أيار',
    'حزيران',
    'تموز',
    'آب',
    'أيلول',
    'تشرين الأول',
    'تشرين الثاني',
    'كانون الأول',
  ];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _reload(showLoading: false);
    }
  }

  Future<void> _reload({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final List<ExpectedIncome> occurrences =
          await _incomeService.loadMonth(_selectedMonth);
      final ExpectedIncome? nextExpected =
          await _incomeService.loadNextExpected();
      if (!mounted) {
        return;
      }
      setState(() {
        _occurrences = occurrences;
        _nextExpected = nextExpected;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحميل بيانات الدخل.')),
      );
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

  Future<void> _confirmReceived(ExpectedIncome occurrence) async {
    final bool isSyp = occurrence.unit == FinancialUnit.syp;
    final TextEditingController controller = TextEditingController(
      text: _editableAmount(occurrence.expectedAmountMicros, occurrence.unit),
    );

    final num? amount = await showDialog<num>(
      context: context,
      builder: (dialogContext) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text('تأكيد استلام الدخل'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(_incomeTitle(occurrence)),
                    const SizedBox(height: 6),
                    Text('موعده: ${_formatDate(occurrence.scheduledDate)}'),
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
                        suffixText: isSyp ? 'ل.س' : 'USD',
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
              ),
            );
          },
        );
      },
    );
    controller.dispose();

    if (amount == null || !mounted) {
      return;
    }

    setState(() {
      _confirmingKey = occurrence.recurrenceKey;
    });

    try {
      await _incomeService.confirmReceived(
        occurrence: occurrence,
        amountMicros: LedgerEntry.amountToMicros(amount),
      );
      await _reload(showLoading: false);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل الدخل المستلم.')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تسجيل الدخل أو تم تسجيله مسبقاً.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _confirmingKey = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
        onRefresh: () => _reload(showLoading: false),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
          children: <Widget>[
            Text(
              'الرئيسية',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 18),
            if (_nextExpected != null) _UpcomingIncomeCard(income: _nextExpected!),
            if (_nextExpected != null) const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'دخل ${_monthNames[_selectedMonth.month]} ${_selectedMonth.year}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'الشهر السابق',
                  onPressed: () => _changeMonth(-1),
                  icon: const Icon(Icons.chevron_right),
                ),
                IconButton(
                  tooltip: 'الشهر التالي',
                  onPressed: () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_left),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _MonthSummary(occurrences: _occurrences),
            const SizedBox(height: 14),
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
          ],
        ),
      ),
    );
  }

  static String _incomeTitle(ExpectedIncome occurrence) {
    return occurrence.kind == RecurringIncomeKind.weeklySyp
        ? 'راتب الخميس'
        : 'راتب الشهر';
  }

  static String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  static String _editableAmount(int micros, FinancialUnit unit) {
    final double value = micros / LedgerEntry.microsPerUnit;
    if (unit == FinancialUnit.syp || unit == FinancialUnit.sypNew) {
      return value.round().toString();
    }
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
  }
}

class _UpcomingIncomeCard extends StatelessWidget {
  const _UpcomingIncomeCard({required this.income});

  final ExpectedIncome income;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            const CircleAvatar(child: Icon(Icons.event_available_outlined)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'الدخل القادم',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_HomePageState._incomeTitle(income)} • '
                    '${_HomePageState._formatDate(income.scheduledDate)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            Text(
              _formatMoney(income.expectedAmountMicros, income.unit),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
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
                      Text(_HomePageState._formatDate(occurrence.scheduledDate)),
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
                    value: _formatMoney(
                      occurrence.expectedAmountMicros,
                      occurrence.unit,
                    ),
                  ),
                ),
                if (occurrence.isReceived)
                  Expanded(
                    child: _AmountColumn(
                      label: 'المستلم فعلياً',
                      value: _formatMoney(
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

String _formatMoney(int micros, FinancialUnit unit) {
  final double value = micros / LedgerEntry.microsPerUnit;
  final bool whole = value == value.roundToDouble();
  final String number = _withThousandsSeparators(
    whole ? value.toInt().toString() : value.toStringAsFixed(2),
  );

  switch (unit) {
    case FinancialUnit.usd:
      return '\$$number';
    case FinancialUnit.syp:
      return '$number ل.س';
    case FinancialUnit.sypNew:
      return '$number ل.س جديدة';
    case FinancialUnit.goldGram:
      return '$number غ';
  }
}

String _withThousandsSeparators(String input) {
  final List<String> parts = input.split('.');
  final String digits = parts.first;
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    final int remaining = digits.length - i;
    buffer.write(digits[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }
  if (parts.length > 1) {
    buffer.write('.${parts[1]}');
  }
  return buffer.toString();
}
