import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/financial_event.dart';
import '../models/saving_challenge.dart';
import '../services/challenge_storage.dart';
import '../services/financial_ledger_storage.dart';
import '../services/transaction_history_service.dart';
import '../ui/app_theme.dart';
import '../ui/ux_components.dart';
import '../utils/financial_format.dart';

class TransactionHistoryPage extends StatefulWidget {
  const TransactionHistoryPage({
    super.key,
    this.initialFund,
    this.initialMonth,
    this.initialUnit,
    this.initialType,
    this.initialGoalId,
    this.historyService,
    this.goalStorage,
  });

  /// Open directly on an auditable filtered month, retaining all filters.
  final FinancialFund? initialFund;
  final FinancialUnit? initialUnit;
  final FinancialEventType? initialType;
  final DateTime? initialMonth;
  final String? initialGoalId;
  final TransactionHistoryService? historyService;
  final ChallengeStorage? goalStorage;

  @override
  State<TransactionHistoryPage> createState() => _TransactionHistoryPageState();
}

class _TransactionHistoryPageState extends State<TransactionHistoryPage> {
  late final TransactionHistoryService _service;
  late final ChallengeStorage _goalsStorage;

  StreamSubscription<void>? _ledgerSubscription;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  String _typeFilter = 'all';
  String _unitFilter = 'all';
  String _fundFilter = 'all';
  String _goalFilter = 'all';
  String _search = '';
  List<SavingChallenge> _goals = const <SavingChallenge>[];
  ExpectedCommitmentsSnapshot? _expected;
  int _loadGeneration = 0;
  List<TransactionHistoryRecord> _records = const <TransactionHistoryRecord>[];
  bool _isLoading = true;

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
    _service = widget.historyService ?? TransactionHistoryService();
    _goalsStorage = widget.goalStorage ?? ChallengeStorage();
    _goalFilter = widget.initialGoalId ?? 'all';
    _loadGoals();
    _fundFilter = widget.initialFund?.name ?? 'all';
    _unitFilter = widget.initialUnit?.name ?? 'all';
    _typeFilter = widget.initialType?.name ?? 'all';
    if (widget.initialMonth != null) {
      _selectedMonth = DateTime(
        widget.initialMonth!.year, widget.initialMonth!.month,
      );
    }
    _ledgerSubscription = FinancialLedgerStorage.changes.listen((_) {
      if (mounted) _load(showLoading: false);
    });
    _load();
  }

  @override
  void dispose() {
    _loadGeneration++;
    _ledgerSubscription?.cancel();
    super.dispose();
  }

  FinancialEventType? get _selectedType {
    if (_typeFilter == 'all') return null;
    return FinancialEventType.values.firstWhere(
      (type) => type.name == _typeFilter,
    );
  }

  FinancialFund? get _selectedFund => _fundFilter == 'all'
      ? null : FinancialFund.values.byName(_fundFilter);

  FinancialUnit? get _selectedUnit {
    if (_unitFilter == 'all') return null;
    return FinancialUnit.values.firstWhere(
      (unit) => unit.name == _unitFilter,
    );
  }

  Future<void> _load({bool showLoading = true}) async {
    final generation = ++_loadGeneration;
    if (showLoading && mounted) setState(() => _isLoading = true);
    try {
      final List<TransactionHistoryRecord> records = await _service.loadMonth(
        _selectedMonth,
        type: _selectedType,
        unit: _selectedUnit,
        fund: _selectedFund,
        goalId: _goalFilter == 'all' ? null : _goalFilter,
        search: _search,
      );
      ExpectedCommitmentsSnapshot? commitments;
      try {
        commitments = await _service.loadExpectedMonth(_selectedMonth);
      } catch (_) {
        // A broken plan cannot hide the canonical posted audit history.
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _records = records;
        _expected = commitments;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحميل سجل الحركات.')),
      );
    }
  }

  Future<void> _loadGoals() async {
    try {
      final goals = await _goalsStorage.loadChallenges();
      if (mounted) setState(() => _goals = goals);
    } catch (_) {
      // Historical goal IDs remain discoverable using the text search.
    }
  }

  Future<void> _changeMonth(int delta) async {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
    });
    await _load();
  }

  Future<void> _openDetail(TransactionHistoryRecord record) async {
    final bool? changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: _TransactionDetailSheet(
          record: record,
          service: _service,
        ),
      ),
    );
    if (changed == true) await _load(showLoading: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _load(showLoading: false),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  IconButton(
                    tooltip: 'رجوع',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const BackButtonIcon(),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: UxPageHeader(
                      title: 'سجل الحركات',
                      subtitle: 'كل حركة محفوظة وقابلة للتدقيق',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _MonthSelector(
                title:
                    '${_monthNames[_selectedMonth.month]} ${_selectedMonth.year}',
                onPrevious: () => _changeMonth(-1),
                onNext: () => _changeMonth(1),
              ),
              const SizedBox(height: 12),
              _FilterRow(
                typeFilter: _typeFilter,
                unitFilter: _unitFilter,
                fundFilter: _fundFilter,
                onFundChanged: (value) {
                  setState(() => _fundFilter = value);
                  _load(showLoading: false);
                },
                onTypeChanged: (value) {
                  setState(() => _typeFilter = value);
                  _load(showLoading: false);
                },
                onUnitChanged: (value) {
                  setState(() => _unitFilter = value);
                  _load(showLoading: false);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'بحث بالملاحظة أو التصنيف أو رقم الحركة أو الهدف',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
                onChanged: (text) {
                  _search = text;
                  _load(showLoading: false);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _goalFilter,
                decoration: const InputDecoration(
                  labelText: 'الهدف المرتبط',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem(value: 'all',
                    child: Text('كل الأهداف والحركات')),
                  if (_goalFilter != 'all' &&
                      !_goals.any((goal) => goal.id == _goalFilter))
                    DropdownMenuItem(value: _goalFilter,
                      child: const Text('هدف تاريخي أو محذوف')),
                  for (final goal in _goals)
                    DropdownMenuItem(value: goal.id, child: Text(goal.name)),
                ],
                onChanged: (id) {
                  if (id == null) return;
                  setState(() => _goalFilter = id);
                  _load(showLoading: false);
                },
              ),
              const SizedBox(height: 13),
              _CommitmentSection(commitments: _expected),
              const SizedBox(height: 16),
              Text('الحركات المسجلة فعلياً',
                style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              const Text(
                'الحركات النقدية الفعلية فقط بتغيّر الرصيد. تقسيم '
                'الراتب وتقدم الخانات إشارات غير نقدية، والالتزامات '
                'أعلاه مجرد خطة. المحذوفات ظاهرة للتدقيق فقط.',
              ),
              const SizedBox(height: 12),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_records.isEmpty)
                const UxEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'لا توجد حركات',
                  body: 'لا توجد حركات مطابقة للشهر والفلاتر المحددة.',
                )
              else ...<Widget>[
                Text(
                  '${_records.length} حركة',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                ..._records.map(
                  (record) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _TransactionCard(
                      record: record,
                      onTap: () => _openDetail(record),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Expected schedules are never merged into the true transaction count.
class _CommitmentSection extends StatelessWidget {
  const _CommitmentSection({required this.commitments});
  final ExpectedCommitmentsSnapshot? commitments;

  @override
  Widget build(BuildContext context) {
    final snapshot = commitments;
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.event_note_outlined),
        title: const Text('المخطط والمتوقع — ليس مالاً منفذاً'),
        subtitle: Text(snapshot == null
            ? 'تعذر تحميل خطة هذا الشهر، ولا يؤثر ذلك على سجل المال'
            : '${snapshot.plannedBills.length} فواتير مخططة • '
              '${snapshot.expectedIncome.length} مواعيد دخل متوقعة'),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: <Widget>[
          const Text('القيم أدناه ليست خصماً أو إضافة للرصيد حتى '
              'تسجّل حركة فعلية. مواعيد الدخل تستخدم إعدادات '
              'الجدول الحالية؛ قد تختلف عن افتراضات شهر قديم.'),
          if (snapshot != null) ...<Widget>[
            const SizedBox(height: 9),
            if (snapshot.plannedBills.isEmpty &&
                snapshot.expectedIncome.isEmpty)
              const Text('ما في التزامات متوقعة بهذا الشهر.')
            else ...<Widget>[
              for (final bill in snapshot.plannedBills)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_repeat_outlined),
                  title: Text(bill.name),
                  subtitle: const Text('فاتورة مخططة فقط — ليست مدفوعة'),
                  trailing: Text(FinancialFormat.assetBalance(
                    bill.amountMicros, bill.unit,
                  )),
                ),
              for (final income in snapshot.expectedIncome)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: Text('راتب متوقع: ${FinancialFormat.date(income.scheduledDate)}'),
                  subtitle: Text(income.isReceived
                    ? 'مستلم — حركته الفعلية مستقلة تحت'
                    : income.isIgnored
                      ? 'تم تجاهله — ما انضاف أي مال'
                      : 'غير مؤكد الاستلام — ليس دخلاً فعلياً'),
                  trailing: Text(FinancialFormat.assetBalance(
                    income.expectedAmountMicros, income.unit,
                  )),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({
    required this.title,
    required this.onPrevious,
    required this.onNext,
  });

  final String title;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return UxSoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'الشهر السابق',
            onPressed: onPrevious,
            icon: const Icon(
              Icons.chevron_right_rounded,
              textDirection: TextDirection.ltr,
            ),
          ),
          Expanded(
            child: Column(
              children: <Widget>[
                Text(
                  'الفترة',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 1),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'الشهر التالي',
            onPressed: onNext,
            icon: const Icon(
              Icons.chevron_left_rounded,
              textDirection: TextDirection.ltr,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.typeFilter,
    required this.unitFilter,
    required this.fundFilter,
    required this.onFundChanged,
    required this.onTypeChanged,
    required this.onUnitChanged,
  });

  final String typeFilter;
  final String unitFilter;
  final String fundFilter;
  final ValueChanged<String> onFundChanged;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onUnitChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final Widget type = DropdownButtonFormField<String>(
          value: typeFilter,
          decoration: const InputDecoration(
            labelText: 'نوع الحركة',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: <DropdownMenuItem<String>>[
            const DropdownMenuItem<String>(
              value: 'all',
              child: Text('كل الأنواع'),
            ),
            ...FinancialEventType.values.map(
              (type) => DropdownMenuItem<String>(
                value: type.name,
                child: Text(_eventTypeLabel(type)),
              ),
            ),
          ],
          onChanged: (value) {
            if (value != null) onTypeChanged(value);
          },
        );
        final Widget unit = DropdownButtonFormField<String>(
          value: unitFilter,
          decoration: const InputDecoration(
            labelText: 'العملة / الأصل',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: <DropdownMenuItem<String>>[
            const DropdownMenuItem<String>(
              value: 'all',
              child: Text('كل العملات والأصول'),
            ),
            ...FinancialUnit.values.map(
              (unit) => DropdownMenuItem<String>(
                value: unit.name,
                child: Text(FinancialFormat.unitLabel(unit)),
              ),
            ),
          ],
          onChanged: (value) {
            if (value != null) onUnitChanged(value);
          },
        );

        final Widget fund = DropdownButtonFormField<String>(
          value: fundFilter,
          decoration: const InputDecoration(
            labelText: 'الصندوق',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem(value: 'all', child: Text('كل الصناديق')),
            DropdownMenuItem(value: 'spending', child: Text('المصاريف')),
            DropdownMenuItem(value: 'savings', child: Text('الادخار')),
            DropdownMenuItem(value: 'unallocated', child: Text('غير موزّع')),
          ],
          onChanged: (value) {
            if (value != null) onFundChanged(value);
          },
        );

        if (constraints.maxWidth >= 800) {
          return Row(children: <Widget>[
            Expanded(child: type),
            const SizedBox(width: 10),
            Expanded(child: unit),
            const SizedBox(width: 10),
            Expanded(child: fund),
          ]);
        }
        if (constraints.maxWidth >= 520) {
          return Column(children: <Widget>[
            Row(children: <Widget>[
              Expanded(child: type),
              const SizedBox(width: 10),
              Expanded(child: unit),
            ]),
            const SizedBox(height: 10),
            fund,
          ]);
        }
        return Column(
          children: <Widget>[
            type,
            const SizedBox(height: 10),
            unit,
            const SizedBox(height: 10),
            fund,
          ],
        );
      },
    );
  }
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({required this.record, required this.onTap});

  final TransactionHistoryRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final FinancialEvent event = record.event;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color tone = record.isDeleted
        ? colors.error
        : _eventTone(event.type, colors);

    return UxSoftCard(
      tone: tone,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          UxIconBadge(
            icon: _eventIcon(event.type),
            tone: tone,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        _eventTypeLabel(event.type),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (record.isDeleted)
                      UxStatusPill(
                        label: 'محذوفة',
                        icon: Icons.delete_outline,
                        color: colors.error,
                      )
                    else if (record.revisionCount > 0)
                      UxStatusPill(
                        label: 'معدّلة ${record.revisionCount}×',
                        icon: Icons.history_rounded,
                        color: colors.tertiary,
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  _eventSummary(event),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: tone,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${FinancialFormat.dateTime(event.occurredAt)}'
                  '${event.category == null ? '' : ' • ${event.category}'}'
                  '${event.type == FinancialEventType.savingContribution
                      ? ' • تقدم هدف غير نقدي' : ''}'
                  '${event.type != FinancialEventType.expense
                      ? ''
                      : ' • من ${_fundLabel(event.entries.first.fund)}'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.chevron_left_rounded,
            color: colors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _TransactionDetailSheet extends StatefulWidget {
  const _TransactionDetailSheet({
    required this.record,
    required this.service,
  });

  final TransactionHistoryRecord record;
  final TransactionHistoryService service;

  @override
  State<_TransactionDetailSheet> createState() =>
      _TransactionDetailSheetState();
}

class _TransactionDetailSheetState extends State<_TransactionDetailSheet> {
  List<FinancialEventRevision> _revisions = const <FinancialEventRevision>[];
  bool _loadingRevisions = true;
  bool _isMutating = false;

  FinancialEvent get event => widget.record.event;

  @override
  void initState() {
    super.initState();
    _loadRevisions();
  }

  Future<void> _loadRevisions() async {
    try {
      final List<FinancialEventRevision> revisions =
          await widget.service.loadRevisions(event.id);
      if (!mounted) return;
      setState(() {
        _revisions = revisions;
        _loadingRevisions = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingRevisions = false);
    }
  }

  Future<void> _editMetadata() async {
    final TextEditingController categoryController = TextEditingController(
      text: event.category ?? '',
    );
    final TextEditingController noteController = TextEditingController(
      text: event.note ?? '',
    );
    DateTime selectedDate = event.occurredAt.toLocal();

    final _MetadataDraft? draft = await showDialog<_MetadataDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تعديل تفاصيل الحركة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  controller: categoryController,
                  decoration: const InputDecoration(
                    labelText: 'التصنيف (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: event.recurrenceKey != null &&
                    !event.recurrenceKey!.startsWith('manual-cash:')
                      ? null
                      : () async {
                          final DateTime? picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() => selectedDate = picked);
                          }
                        },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    event.recurrenceKey != null &&
                        !event.recurrenceKey!.startsWith('manual-cash:')
                        ? 'التاريخ مرتبط بالحركة الدورية'
                        : FinancialFormat.date(selectedDate),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _MetadataDraft(
                  date: selectedDate,
                  category: categoryController.text,
                  note: noteController.text,
                ),
              ),
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    );
    categoryController.dispose();
    noteController.dispose();
    if (draft == null || !mounted) return;

    final bool confirmed = await _confirm(
      title: 'تأكيد تعديل التفاصيل؟',
      message: 'سيتم حفظ النسخة السابقة في سجل المراجعات.',
      confirmLabel: 'حفظ التعديل',
    );
    if (!confirmed || !mounted) return;

    await _runMutation(
      () => widget.service.updateMetadata(
        eventId: event.id,
        occurredAt: draft.date,
        category: draft.category,
        note: draft.note,
      ),
      successMessage: 'تم تعديل تفاصيل الحركة.',
    );
  }

  Future<void> _correctAmounts() async {
    final List<TextEditingController> controllers = event.entries
        .map(
          (entry) => TextEditingController(
            text: FinancialFormat.editableAmount(
              entry.amountMicros.abs(),
              entry.unit,
            ),
          ),
        )
        .toList(growable: false);
    String? errorText;

    final List<int>? amounts = await showDialog<List<int>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تصحيح مبالغ الحركة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  'عدّل القيمة فقط. اتجاه الحركة والعملات يبقيان كما هما.',
                ),
                const SizedBox(height: 12),
                for (int index = 0;
                    index < event.entries.length;
                    index++) ...<Widget>[
                  TextField(
                    controller: controllers[index],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: InputDecoration(
                      labelText: _entryEditLabel(event.entries[index], index),
                      suffixText:
                          FinancialFormat.unitShort(event.entries[index].unit),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (index != event.entries.length - 1)
                    const SizedBox(height: 10),
                ],
                if (errorText != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final List<int> parsed = <int>[];
                for (final TextEditingController controller in controllers) {
                  final double? amount =
                      double.tryParse(controller.text.trim());
                  if (amount == null || amount <= 0) {
                    setDialogState(() {
                      errorText = 'أدخل قيمة موجبة لكل مبلغ.';
                    });
                    return;
                  }
                  parsed.add(LedgerEntry.amountToMicros(amount));
                }
                Navigator.pop(dialogContext, parsed);
              },
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    );
    for (final TextEditingController controller in controllers) {
      controller.dispose();
    }
    if (amounts == null || !mounted) return;

    final bool confirmed = await _confirm(
      title: 'تأكيد تصحيح المبالغ؟',
      message:
          'سيعاد حساب الأرصدة من السجل المالي وستُحفظ النسخة السابقة في سجل المراجعات.',
      confirmLabel: 'تأكيد التصحيح',
    );
    if (!confirmed || !mounted) return;

    await _runMutation(
      () => widget.service.correctAmounts(
        eventId: event.id,
        absoluteAmountsMicros: amounts,
      ),
      successMessage: 'تم تصحيح الحركة وإعادة حساب الأرصدة.',
    );
  }

  Future<void> _delete() async {
    final bool confirmed = await _confirm(
      title: 'حذف الحركة؟',
      message:
          'سيتم حذفها من السجل المالي الحالي مع الاحتفاظ بنسخة تدقيق محذوفة. لن يسمح التطبيق بالحذف إذا أدى لرصيد سالب أو كسر حركة مرتبطة.',
      confirmLabel: 'حذف الحركة',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    await _runMutation(
      () => widget.service.deleteEvent(event.id),
      successMessage: 'تم حذف الحركة مع حفظ نسخة التدقيق.',
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        foregroundColor: Theme.of(context).colorScheme.onError,
                      )
                    : null,
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _runMutation(
    Future<void> Function() operation, {
    required String successMessage,
  }) async {
    setState(() => _isMutating = true);
    try {
      await operation();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
      Navigator.of(context).pop(true);
    } on GoalBackingInsufficientException catch (_) {
      if (!mounted) return;
      setState(() => _isMutating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'هالحركة مرتبطة بمال محجوز لأهداف الادخار. '
          'حرّر خانات الحجز أولاً، وما تغير أي رصيد.',
        )),
      );
    } on TransactionMutationException catch (error) {
      if (!mounted) return;
      setState(() => _isMutating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isMutating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تعديل الحركة.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool workflowManaged = widget.service.isWorkflowManaged(event);
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: <Widget>[
              CircleAvatar(child: Icon(_eventIcon(event.type))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _eventTypeLabel(event.type),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(FinancialFormat.dateTime(event.occurredAt)),
                  ],
                ),
              ),
              if (widget.record.isDeleted)
                const Chip(label: Text('محذوفة')),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _DetailCard(
                title: 'القيم',
                children: <Widget>[
                  for (int index = 0;
                      index < event.entries.length;
                      index++)
                    _EntryRow(entry: event.entries[index],
                      eventType: event.type),
                ],
              ),
              const SizedBox(height: 10),
              _DetailCard(
                title: 'التفاصيل',
                children: <Widget>[
                  _KeyValue('التصنيف', event.category ?? '—'),
                  _KeyValue('الملاحظة', event.note ?? '—'),
                  if (event.executedSypPerUsd != null)
                    _KeyValue(
                      'سعر التنفيذ',
                      FinancialFormat.referenceRate(event.executedSypPerUsd!),
                    ),
                  if (event.recurrenceKey != null)
                    const _KeyValue('حركة دورية', 'نعم'),
                  if (event.sourceEventId != null)
                    _KeyValue('رقم الحركة الأصلية', event.sourceEventId!),
                  if (event.relatedGoalId != null ||
                      event.relatedChallengeId != null)
                    _KeyValue('معرّف الهدف المرتبط',
                      event.relatedGoalId ?? event.relatedChallengeId!),
                  if (event.recurrenceKey != null)
                    _KeyValue('معرّف الدورية', event.recurrenceKey!),
                  _KeyValue('معرّف الحركة', event.id),
                  _KeyValue(
                    'أنشئت',
                    FinancialFormat.dateTime(event.createdAt),
                  ),
                  _KeyValue(
                    'آخر تعديل',
                    FinancialFormat.dateTime(event.updatedAt),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _DetailCard(
                title: 'سجل المراجعات',
                children: <Widget>[
                  if (_loadingRevisions)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_revisions.isEmpty)
                    const Text('لا توجد تعديلات سابقة على هذه الحركة.')
                  else
                    ..._revisions.map(
                      (revision) => ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 12),
                        leading: Icon(revision.isDelete
                          ? Icons.delete_outline : Icons.history_rounded),
                        title: Text(revision.isDelete
                          ? 'نسخة قبل الإلغاء' : 'نسخة قبل التعديل'),
                        subtitle: Text(FinancialFormat.dateTime(
                          revision.changedAt)),
                        children: <Widget>[
                          _KeyValue('المبلغ القديم',
                            _eventSummary(revision.snapshot)),
                          _KeyValue('تاريخ الحركة الأصلي',
                            FinancialFormat.dateTime(
                              revision.snapshot.occurredAt)),
                          _KeyValue('التصنيف السابق',
                            revision.snapshot.category ?? '—'),
                          _KeyValue('الملاحظة السابقة',
                            revision.snapshot.note ?? '—'),
                          if (revision.snapshot.executedSypPerUsd != null)
                            _KeyValue('سعر التنفيذ التاريخي',
                              FinancialFormat.referenceRate(
                                revision.snapshot.executedSypPerUsd!)),
                          if (revision.snapshot.relatedGoalId != null)
                            _KeyValue('الهدف المرتبط سابقاً',
                              revision.snapshot.relatedGoalId!),
                          for (final entry in revision.snapshot.entries)
                            _EntryRow(entry: entry,
                              eventType: revision.snapshot.type),
                        ],
                      ),
                    ),
                ],
              ),
              if (!widget.record.isDeleted) ...<Widget>[
                const SizedBox(height: 16),
                if (workflowManaged)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'هذه مساهمة ادخار مرتبطة بشبكة التحدي. لتغييرها عدّل الخانات داخل التحدي حتى يبقى التقدم متطابقاً مع السجل المالي.',
                      ),
                    ),
                  )
                else ...<Widget>[
                  OutlinedButton.icon(
                    onPressed: _isMutating ? null : _editMetadata,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('تعديل التفاصيل'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _isMutating ? null : _correctAmounts,
                    icon: const Icon(Icons.calculate_outlined),
                    label: const Text('تصحيح المبالغ'),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _isMutating ? null : _delete,
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('إلغاء أثر الحركة مع حفظ نسخة التدقيق'),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.eventType});

  final LedgerEntry entry;
  final FinancialEventType eventType;

  @override
  Widget build(BuildContext context) {
    final String role =
        entry.role == null ? '' : ' • ${_roleLabel(entry.role!)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '${eventType == FinancialEventType.fundTransfer
                ? (entry.amountMicros < 0 ? 'من صندوق' : 'إلى صندوق')
                : eventType == FinancialEventType.savingContribution
                  ? 'تقدم هدف (لا يغير الرصيد)'
                  : entry.affectsBalance ? 'رصيد فعلي' : 'تخصيص غير نقدي'}'
              ' • ${_fundLabel(entry.fund)}$role',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Text(
            _formatSignedEntry(entry),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _MetadataDraft {
  const _MetadataDraft({
    required this.date,
    required this.category,
    required this.note,
  });

  final DateTime date;
  final String category;
  final String note;
}

Color _eventTone(FinancialEventType type, ColorScheme colors) {
  return switch (type) {
    FinancialEventType.income => colors.primary,
    FinancialEventType.expense => colors.error,
    FinancialEventType.savingContribution => const Color(0xFF4C6E9C),
    FinancialEventType.weeklyAllocation => colors.secondary,
    FinancialEventType.currencyConversion => const Color(0xFF6C5AA6),
    FinancialEventType.goldPurchase => AppPalette.gold,
    FinancialEventType.goldSale => const Color(0xFF9A7A34),
    FinancialEventType.manualAdjustment => colors.onSurfaceVariant,
    FinancialEventType.fundTransfer => colors.secondary,
    FinancialEventType.openingBalance => colors.tertiary,
  };
}

String _eventTypeLabel(FinancialEventType type) {
  return switch (type) {
    FinancialEventType.income => 'دخل',
    FinancialEventType.expense => 'مصروف',
    FinancialEventType.savingContribution => 'مساهمة ادخار',
    FinancialEventType.weeklyAllocation => 'تقسيم راتب الخميس',
    FinancialEventType.currencyConversion => 'تحويل عملة',
    FinancialEventType.goldPurchase => 'شراء ذهب',
    FinancialEventType.goldSale => 'بيع ذهب',
    FinancialEventType.manualAdjustment => 'تصحيح يدوي',
    FinancialEventType.fundTransfer => 'تحويل بين الصناديق',
    FinancialEventType.openingBalance => 'رصيد افتتاحي (ليس دخلاً)',
  };
}

IconData _eventIcon(FinancialEventType type) {
  return switch (type) {
    FinancialEventType.income => Icons.south_west,
    FinancialEventType.expense => Icons.north_east,
    FinancialEventType.savingContribution => Icons.savings_outlined,
    FinancialEventType.weeklyAllocation => Icons.call_split,
    FinancialEventType.currencyConversion => Icons.currency_exchange,
    FinancialEventType.goldPurchase => Icons.diamond_outlined,
    FinancialEventType.goldSale => Icons.sell_outlined,
    FinancialEventType.manualAdjustment => Icons.tune,
    FinancialEventType.fundTransfer => Icons.swap_horiz,
    FinancialEventType.openingBalance => Icons.account_balance_wallet_outlined,
  };
}

String _eventSummary(FinancialEvent event) {
  if (event.type == FinancialEventType.fundTransfer &&
      event.entries.length == 2) {
    final source = event.entries.first;
    final destination = event.entries.last;
    return 'من ${_fundLabel(source.fund)} إلى '
        '${_fundLabel(destination.fund)} • '
        '${FinancialFormat.assetBalance(
          source.amountMicros.abs(), source.unit,
        )}';
  }
  if (event.type == FinancialEventType.currencyConversion ||
      event.type == FinancialEventType.fundTransfer ||
      event.type == FinancialEventType.goldPurchase ||
      event.type == FinancialEventType.goldSale) {
    final LedgerEntry? source = _firstEntry(event, negative: true);
    final LedgerEntry? destination = _firstEntry(event, negative: false);
    if (source != null && destination != null) {
      return '${FinancialFormat.assetBalance(source.amountMicros.abs(), source.unit)} ← '
          '${FinancialFormat.assetBalance(destination.amountMicros.abs(), destination.unit)}';
    }
  }
  if (event.type == FinancialEventType.weeklyAllocation) {
    return event.entries
        .map(
          (entry) => '${_roleLabel(entry.role)} '
              '${FinancialFormat.assetBalance(entry.amountMicros.abs(), entry.unit)}',
        )
        .join(' + ');
  }
  if (event.entries.length == 1) {
    return _formatSignedEntry(event.entries.single);
  }
  return event.entries.map(_formatSignedEntry).join(' • ');
}

LedgerEntry? _firstEntry(FinancialEvent event, {required bool negative}) {
  for (final LedgerEntry entry in event.entries) {
    if (negative ? entry.amountMicros < 0 : entry.amountMicros > 0) {
      return entry;
    }
  }
  return null;
}

String _formatSignedEntry(LedgerEntry entry) {
  final String amount =
      FinancialFormat.assetBalance(entry.amountMicros.abs(), entry.unit);
  if (!entry.affectsBalance) return amount;
  return entry.amountMicros < 0 ? '− $amount' : '+ $amount';
}

String _entryEditLabel(LedgerEntry entry, int index) {
  final String direction = entry.amountMicros < 0 ? 'خصم' : 'إضافة';
  final String role =
      entry.role == null ? '' : ' — ${_roleLabel(entry.role)}';
  return 'المبلغ ${index + 1} ($direction)$role';
}

String _fundLabel(FinancialFund fund) => switch (fund) {
  FinancialFund.savings => 'الادخار',
  FinancialFund.spending => 'المصاريف',
  FinancialFund.unallocated => 'غير موزّع',
};

String _roleLabel(LedgerEntryRole? role) {
  return switch (role) {
    LedgerEntryRole.weeklyExpensesEnvelope => 'المصاريف',
    LedgerEntryRole.weeklySavingsEnvelope => 'الادخار',
    null => 'تخصيص',
  };
}
