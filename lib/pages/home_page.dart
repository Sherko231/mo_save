import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/expected_income.dart';
import '../models/financial_event.dart';
import '../services/financial_ledger_storage.dart';
import '../services/home_dashboard_service.dart';
import '../services/recurring_income_service.dart';
import '../ui/ux_components.dart';
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
          const SnackBar(content: Text('تعذر تحميل بياناتك المالية.')),
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

  List<ExpectedIncome> get _incomeNeedingAttention {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    return _occurrences.where((occurrence) {
      final DateTime scheduled = DateTime(
        occurrence.scheduledDate.year,
        occurrence.scheduledDate.month,
        occurrence.scheduledDate.day,
      );
      return !occurrence.isReceived && !scheduled.isAfter(today);
    }).toList(growable: false);
  }

  Future<void> _confirmReceived(ExpectedIncome occurrence) async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime scheduled = DateTime(
      occurrence.scheduledDate.year,
      occurrence.scheduledDate.month,
      occurrence.scheduledDate.day,
    );
    if (scheduled.isAfter(today)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يمكن تأكيد الدخل في موعده فقط.')),
      );
      return;
    }

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
          builder: (context, setDialogState) => AlertDialog(
            title: Text(_incomeTitle(occurrence)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'أكد المبلغ الذي استلمته فعلياً. يمكنك تعديله إذا اختلف عن المتوقع.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.numberWithOptions(decimal: !isSyp),
                  inputFormatters: <TextInputFormatter>[
                    if (isSyp)
                      FilteringTextInputFormatter.digitsOnly
                    else
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  onChanged: (_) => setDialogState(() => errorText = null),
                  decoration: InputDecoration(
                    labelText: 'المبلغ المستلم',
                    suffixText: FinancialFormat.unitShort(occurrence.unit),
                    helperText:
                        'موعد الدفعة ${FinancialFormat.date(occurrence.scheduledDate)}',
                    errorText: errorText,
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
                  final num? parsed =
                      isSyp ? int.tryParse(raw) : double.tryParse(raw);
                  if (parsed == null || parsed <= 0) {
                    setDialogState(() {
                      errorText = 'أدخل مبلغاً أكبر من صفر.';
                    });
                    return;
                  }
                  Navigator.of(dialogContext).pop(parsed);
                },
                child: const Text('تأكيد الاستلام'),
              ),
            ],
          ),
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
        const SnackBar(content: Text('تم تسجيل الدخل.')),
      );
    } on StateError catch (error) {
      if (!mounted) return;
      final bool future = error.message.toString().contains('Future');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            future
                ? 'يمكن تأكيد الدخل في موعده فقط.'
                : 'تم تسجيل هذه الدفعة مسبقاً.',
          ),
        ),
      );
    } on ArgumentError catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المبلغ غير صالح.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تسجيل الدخل.')),
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
      return UxEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'تعذر تحميل بياناتك',
        body: 'جرّب إعادة التحميل. بياناتك المحلية لن تتأثر.',
        action: FilledButton.icon(
          onPressed: _reload,
          icon: const Icon(Icons.refresh),
          label: const Text('إعادة المحاولة'),
        ),
      );
    }

    final List<ExpectedIncome> attention = _incomeNeedingAttention;

    return RefreshIndicator(
      onRefresh: () => _reload(showLoading: false),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 104),
        children: <Widget>[
          HomeDashboardOverview(
            snapshot: dashboard,
            month: _selectedMonth,
            onPreviousMonth: () => _changeMonth(-1),
            onNextMonth: () => _changeMonth(1),
          ),
          if (attention.isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            const UxSectionHeader(
              title: 'يحتاج انتباهك',
              subtitle: 'دفعات حان موعدها ولم تُسجل بعد',
            ),
            const SizedBox(height: 8),
            ...attention.map(
              (occurrence) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _AttentionIncomeCard(
                  occurrence: occurrence,
                  isConfirming: _confirmingKey == occurrence.recurrenceKey,
                  onConfirm: () => _confirmReceived(occurrence),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          _HistoryShortcut(onTap: _openHistory),
          const SizedBox(height: 16),
          const UxSectionHeader(
            title: 'التفاصيل والإجراءات',
            subtitle: 'افتح فقط القسم الذي تحتاجه',
          ),
          const SizedBox(height: 8),
          UxDisclosureCard(
            title: 'الأرصدة والتحويلات',
            subtitle: 'تفاصيل الأصول، تحويل العملة وشراء الذهب',
            icon: Icons.account_balance_wallet_outlined,
            child: HomeBalanceSection(refreshToken: _incomeRefreshToken),
          ),
          const SizedBox(height: 8),
          UxDisclosureCard(
            title: 'الدخل',
            subtitle: '${_occurrences.length} دفعات ضمن الشهر المحدد',
            icon: Icons.payments_outlined,
            initiallyExpanded: attention.isNotEmpty,
            child: _IncomeDetails(
              occurrences: _occurrences,
              confirmingKey: _confirmingKey,
              onConfirm: _confirmReceived,
            ),
          ),
          const SizedBox(height: 8),
          UxDisclosureCard(
            title: 'تقسيم راتب الأسبوع',
            subtitle: 'المصاريف والادخار لكل دفعة أسبوعية',
            icon: Icons.call_split_outlined,
            child: HomeEnvelopeSection(
              month: _selectedMonth,
              refreshToken: _incomeRefreshToken,
            ),
          ),
          const SizedBox(height: 8),
          UxDisclosureCard(
            title: 'المصاريف',
            subtitle: 'الخطة الشهرية والتسجيل الفعلي',
            icon: Icons.receipt_long_outlined,
            child: HomeExpensesSection(month: _selectedMonth),
          ),
        ],
      ),
    );
  }

  static String _incomeTitle(ExpectedIncome occurrence) {
    return occurrence.kind == RecurringIncomeKind.weeklySyp
        ? 'راتب الأسبوع'
        : 'راتب الشهر';
  }
}

class _HistoryShortcut extends StatelessWidget {
  const _HistoryShortcut({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minTileHeight: 68,
        onTap: onTap,
        leading: const Icon(Icons.history_rounded),
        title: const Text('سجل الحركات'),
        subtitle: const Text('راجع كل الدخل والمصاريف والتحويلات والتصحيحات'),
        trailing: const Icon(Icons.chevron_left_rounded),
      ),
    );
  }
}

class _AttentionIncomeCard extends StatelessWidget {
  const _AttentionIncomeCard({
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
    final DateTime scheduled = DateTime(
      occurrence.scheduledDate.year,
      occurrence.scheduledDate.month,
      occurrence.scheduledDate.day,
    );
    final String timing = scheduled.isBefore(today) ? 'متأخر' : 'اليوم';

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
                      Text('$timing • ${FinancialFormat.date(occurrence.scheduledDate)}'),
                    ],
                  ),
                ),
                Text(
                  FinancialFormat.assetBalance(
                    occurrence.expectedAmountMicros,
                    occurrence.unit,
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: isConfirming ? null : onConfirm,
              icon: isConfirming
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(isConfirming ? 'جاري التسجيل...' : 'تأكيد الاستلام'),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomeDetails extends StatelessWidget {
  const _IncomeDetails({
    required this.occurrences,
    required this.confirmingKey,
    required this.onConfirm,
  });

  final List<ExpectedIncome> occurrences;
  final String? confirmingKey;
  final Future<void> Function(ExpectedIncome occurrence) onConfirm;

  @override
  Widget build(BuildContext context) {
    if (occurrences.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text('لا يوجد دخل متكرر متوقع في هذا الشهر.'),
      );
    }

    return Column(
      children: occurrences
          .map(
            (occurrence) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _IncomeOccurrenceRow(
                occurrence: occurrence,
                isConfirming: confirmingKey == occurrence.recurrenceKey,
                onConfirm: () => onConfirm(occurrence),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _IncomeOccurrenceRow extends StatelessWidget {
  const _IncomeOccurrenceRow({
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
    final DateTime scheduled = DateTime(
      occurrence.scheduledDate.year,
      occurrence.scheduledDate.month,
      occurrence.scheduledDate.day,
    );
    final bool isFuture = scheduled.isAfter(today);

    final String status = occurrence.isReceived
        ? 'مستلم'
        : isFuture
            ? 'قادم'
            : scheduled.isBefore(today)
                ? 'غير مستلم'
                : 'اليوم';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _HomePageState._incomeTitle(occurrence),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${FinancialFormat.date(occurrence.scheduledDate)} • $status',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  FinancialFormat.assetBalance(
                    occurrence.receivedAmountMicros ??
                        occurrence.expectedAmountMicros,
                    occurrence.unit,
                  ),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (!occurrence.isReceived && !isFuture)
                  TextButton(
                    onPressed: isConfirming ? null : onConfirm,
                    child: Text(isConfirming ? '...' : 'تأكيد'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
