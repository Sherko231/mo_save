import 'dart:async';

import 'package:flutter/material.dart';

import '../models/expected_income.dart';
import '../services/financial_ledger_storage.dart';
import '../services/home_dashboard_service.dart';
import '../services/recurring_income_service.dart';
import '../ui/ux_components.dart';
import '../utils/financial_format.dart';
import 'home_balance_section.dart';
import 'home_dashboard_overview.dart';
import 'home_expenses_section.dart';
import 'home_spending_fund_section.dart';
import 'income_receipt_dialog.dart';
import 'manual_inflow_page.dart';
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

  Future<void> _openManualInflow() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const ManualInflowPage(),
      ),
    );
    if (!mounted || saved != true) return;
    await _reload(showLoading: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تسجيل المبلغ في سجل الحركات.')),
    );
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
      return occurrence.needsAction && !scheduled.isAfter(today);
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

    final IncomeReceiptDraft? draft =
        await showIncomeReceiptDialog(context, occurrence);

    if (draft == null || !mounted) return;
    setState(() => _confirmingKey = occurrence.recurrenceKey);

    try {
      await _incomeService.confirmReceived(
        occurrence: occurrence,
        amountMicros: draft.amountMicros,
        receivedAt: draft.receivedAt,
        alreadySpentMicros: draft.alreadySpentMicros,
        savingsMicros: draft.savingsMicros,
        spendingMicros: draft.spendingMicros,
        spentAt: draft.spentAt,
        spentCategory: draft.spentCategory,
        spentNote: draft.spentNote,
      );
      await _reload(showLoading: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل الدخل.')),
      );
    } on StateError catch (error) {
      if (!mounted) return;
      final bool future = error.message.toString().contains('Future');
      final bool ignored = error.message.toString().contains('ignored');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            future
                ? 'يمكن تأكيد الدخل في موعده فقط.'
                : ignored
                    ? 'هذه الدفعة متجاهلة. ألغِ التجاهل أولاً.'
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

  Future<void> _ignoreOccurrence(ExpectedIncome occurrence) async {
    if (_confirmingKey != null) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تجاهل هذه الدفعة؟'),
        content: const Text(
          'لن تُعتبر هذه الدفعة مستلمة، ولن يُضاف أي مبلغ لرصيدك. '
          'لن تظهر مجدداً ضمن الرواتب المتأخرة، ويمكنك إلغاء التجاهل '
          'من تفاصيل الدخل لاحقاً.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تجاهل هذه الدفعة'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _confirmingKey = occurrence.recurrenceKey);
    try {
      await _incomeService.ignoreOccurrence(occurrence);
      await _reload(showLoading: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تجاهل الدفعة دون تغيير الرصيد.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تجاهل الدفعة. أعد المحاولة.')),
      );
    } finally {
      if (mounted) setState(() => _confirmingKey = null);
    }
  }

  Future<void> _undoIgnore(ExpectedIncome occurrence) async {
    if (_confirmingKey != null) return;
    setState(() => _confirmingKey = occurrence.recurrenceKey);
    try {
      await _incomeService.undoIgnore(occurrence);
      await _reload(showLoading: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إلغاء التجاهل. يمكنك تسجيل الدفعة.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إلغاء التجاهل.')),
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
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 112),
        children: <Widget>[
          HomeDashboardOverview(
            snapshot: dashboard,
            month: _selectedMonth,
            onPreviousMonth: () => _changeMonth(-1),
            onNextMonth: () => _changeMonth(1),
          ),
          const SizedBox(height: 18),
          HomeSpendingFundSection(refreshToken: _incomeRefreshToken),
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
                  onIgnore: () => _ignoreOccurrence(occurrence),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          UxActionTile(
            icon: Icons.add_circle_outline,
            title: 'إضافة دخل أو رصيد سابق',
            subtitle: 'هدية، مكافأة، عمل جانبي، بيع غرض أو مال موجود سابقاً',
            onTap: _openManualInflow,
          ),
          const SizedBox(height: 10),
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
              onIgnore: _ignoreOccurrence,
              onUndoIgnore: _undoIgnore,
            ),
          ),
          const SizedBox(height: 8),
          UxDisclosureCard(
            title: 'المصاريف',
            subtitle: 'الخطة الشهرية والتسجيل الفعلي',
            icon: Icons.receipt_long_outlined,
            child: HomeExpensesSection(
              month: _selectedMonth,
              onPlanChanged: () => _reload(showLoading: false),
            ),
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
    return UxActionTile(
      icon: Icons.history_rounded,
      title: 'سجل الحركات',
      subtitle: 'كل الدخل والمصاريف والتحويلات والتصحيحات في مكان واحد',
      onTap: onTap,
    );
  }
}

class _AttentionIncomeCard extends StatelessWidget {
  const _AttentionIncomeCard({
    required this.occurrence,
    required this.isConfirming,
    required this.onConfirm,
    required this.onIgnore,
  });

  final ExpectedIncome occurrence;
  final bool isConfirming;
  final VoidCallback onConfirm;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime scheduled = DateTime(
      occurrence.scheduledDate.year,
      occurrence.scheduledDate.month,
      occurrence.scheduledDate.day,
    );
    final bool late = scheduled.isBefore(today);
    final String timing = late ? 'متأخر' : 'موعده اليوم';

    return UxSoftCard(
      tone: late ? colors.error : colors.tertiary,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              UxIconBadge(
                icon: late
                    ? Icons.notification_important_rounded
                    : Icons.today_rounded,
                tone: late ? colors.error : colors.tertiary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _HomePageState._incomeTitle(occurrence),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$timing • ${FinancialFormat.date(occurrence.scheduledDate)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: late
                                ? colors.error
                                : colors.onSurfaceVariant,
                          ),
                    ),
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
            label: Text(isConfirming ? 'جاري التسجيل...' : 'تسجيل الاستلام'),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: isConfirming ? null : onIgnore,
            icon: const Icon(Icons.visibility_off_outlined),
            label: const Text('تجاهل هذه الدفعة'),
          ),
        ],
      ),
    );
  }
}

class _IncomeDetails extends StatelessWidget {
  const _IncomeDetails({
    required this.occurrences,
    required this.confirmingKey,
    required this.onConfirm,
    required this.onIgnore,
    required this.onUndoIgnore,
  });

  final List<ExpectedIncome> occurrences;
  final String? confirmingKey;
  final Future<void> Function(ExpectedIncome occurrence) onConfirm;
  final Future<void> Function(ExpectedIncome occurrence) onIgnore;
  final Future<void> Function(ExpectedIncome occurrence) onUndoIgnore;

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
                onIgnore: () => onIgnore(occurrence),
                onUndoIgnore: () => onUndoIgnore(occurrence),
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
    required this.onIgnore,
    required this.onUndoIgnore,
  });

  final ExpectedIncome occurrence;
  final bool isConfirming;
  final VoidCallback onConfirm;
  final VoidCallback onIgnore;
  final VoidCallback onUndoIgnore;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime scheduled = DateTime(
      occurrence.scheduledDate.year,
      occurrence.scheduledDate.month,
      occurrence.scheduledDate.day,
    );
    final bool isFuture = scheduled.isAfter(today);
    final bool isLate = occurrence.needsAction && scheduled.isBefore(today);

    final String status = occurrence.isReceived
        ? 'مستلم'
        : occurrence.isIgnored
            ? 'تم تجاهل الدفعة'
            : isFuture
            ? 'قادم'
            : isLate
                ? 'غير مستلم'
                : 'اليوم';

    final Color tone = occurrence.isReceived
        ? colors.primary
        : occurrence.isIgnored
            ? colors.secondary
            : isLate
            ? colors.error
            : colors.onSurfaceVariant;

    return UxSoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: <Widget>[
          UxIconBadge(
            icon: occurrence.isReceived
                ? Icons.check_rounded
                : occurrence.isIgnored
                    ? Icons.visibility_off_outlined
                    : isFuture
                    ? Icons.schedule_rounded
                    : Icons.payments_outlined,
            tone: tone,
            size: 38,
            iconSize: 19,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _HomePageState._incomeTitle(occurrence),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  '${FinancialFormat.date(occurrence.scheduledDate)} • $status',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tone,
                      ),
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
              if (occurrence.isIgnored)
                TextButton(
                  onPressed: isConfirming ? null : onUndoIgnore,
                  child: const Text('إلغاء التجاهل'),
                )
              else if (!occurrence.isReceived && !isFuture)
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 2,
                  children: <Widget>[
                    TextButton(
                      onPressed: isConfirming ? null : onConfirm,
                      child: Text(isConfirming ? '...' : 'تسجيل'),
                    ),
                    TextButton(
                      onPressed: isConfirming ? null : onIgnore,
                      child: const Text('تجاهل'),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
