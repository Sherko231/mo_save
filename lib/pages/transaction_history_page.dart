import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/financial_event.dart';
import '../services/financial_ledger_storage.dart';
import '../services/transaction_history_service.dart';
import '../utils/financial_format.dart';

class TransactionHistoryPage extends StatefulWidget {
  const TransactionHistoryPage({super.key});

  @override
  State<TransactionHistoryPage> createState() => _TransactionHistoryPageState();
}

class _TransactionHistoryPageState extends State<TransactionHistoryPage> {
  final TransactionHistoryService _service = TransactionHistoryService();

  StreamSubscription<void>? _ledgerSubscription;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  String _typeFilter = 'all';
  String _unitFilter = 'all';
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
    _ledgerSubscription = FinancialLedgerStorage.changes.listen((_) {
      if (mounted) _load(showLoading: false);
    });
    _load();
  }

  @override
  void dispose() {
    _ledgerSubscription?.cancel();
    super.dispose();
  }

  FinancialEventType? get _selectedType {
    if (_typeFilter == 'all') return null;
    return FinancialEventType.values.firstWhere(
      (type) => type.name == _typeFilter,
    );
  }

  FinancialUnit? get _selectedUnit {
    if (_unitFilter == 'all') return null;
    return FinancialUnit.values.firstWhere(
      (unit) => unit.name == _unitFilter,
    );
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading && mounted) setState(() => _isLoading = true);
    try {
      final List<TransactionHistoryRecord> records = await _service.loadMonth(
        _selectedMonth,
        type: _selectedType,
        unit: _selectedUnit,
      );
      if (!mounted) return;
      setState(() {
        _records = records;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحميل سجل الحركات.')),
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: <Widget>[
              Row(
                children: <Widget>[
                  IconButton(
                    tooltip: 'رجوع',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const BackButtonIcon(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'سجل الحركات',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text(
                          'كل حركة مالية محفوظة في السجل المالي.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
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
                onTypeChanged: (value) {
                  setState(() => _typeFilter = value);
                  _load(showLoading: false);
                },
                onUnitChanged: (value) {
                  setState(() => _unitFilter = value);
                  _load(showLoading: false);
                },
              ),
              const SizedBox(height: 16),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_records.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: <Widget>[
                        Icon(Icons.receipt_long_outlined, size: 36),
                        SizedBox(height: 10),
                        Text('لا توجد حركات مطابقة لهذا الشهر.'),
                      ],
                    ),
                  ),
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
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: <Widget>[
            IconButton(
              tooltip: 'الشهر السابق',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_right),
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'الشهر التالي',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_left),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.typeFilter,
    required this.unitFilter,
    required this.onTypeChanged,
    required this.onUnitChanged,
  });

  final String typeFilter;
  final String unitFilter;
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

        if (constraints.maxWidth >= 520) {
          return Row(
            children: <Widget>[
              Expanded(child: type),
              const SizedBox(width: 10),
              Expanded(child: unit),
            ],
          );
        }
        return Column(
          children: <Widget>[
            type,
            const SizedBox(height: 10),
            unit,
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
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(child: Icon(_eventIcon(event.type))),
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
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (record.isDeleted)
                          const Chip(
                            label: Text('محذوفة'),
                            visualDensity: VisualDensity.compact,
                          )
                        else if (record.revisionCount > 0)
                          Chip(
                            label: Text('معدّلة ${record.revisionCount}×'),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _eventSummary(event),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${FinancialFormat.dateTime(event.occurredAt)}'
                      '${event.category == null ? '' : ' • ${event.category}'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_left),
            ],
          ),
        ),
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
                  onPressed: event.recurrenceKey != null
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
                    event.recurrenceKey != null
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
                    _EntryRow(entry: event.entries[index]),
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
                    const _KeyValue('مرتبطة بحركة أصل', 'نعم'),
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
                      (revision) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(
                          revision.isDelete
                              ? Icons.delete_outline
                              : Icons.history,
                        ),
                        title: Text(
                          revision.isDelete
                              ? 'نسخة قبل الحذف'
                              : 'نسخة قبل التعديل',
                        ),
                        subtitle: Text(
                          FinancialFormat.dateTime(revision.changedAt),
                        ),
                        trailing: Text(_eventSummary(revision.snapshot)),
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
                    label: const Text('حذف الحركة'),
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
  const _EntryRow({required this.entry});

  final LedgerEntry entry;

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
              '${entry.affectsBalance ? 'رصيد' : 'تخصيص'}$role',
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
  };
}

String _eventSummary(FinancialEvent event) {
  if (event.type == FinancialEventType.currencyConversion ||
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

String _roleLabel(LedgerEntryRole? role) {
  return switch (role) {
    LedgerEntryRole.weeklyExpensesEnvelope => 'المصاريف',
    LedgerEntryRole.weeklySavingsEnvelope => 'الادخار',
    null => 'تخصيص',
  };
}
