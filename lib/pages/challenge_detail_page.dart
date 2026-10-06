import 'package:flutter/material.dart';

import '../models/saving_challenge.dart';
import '../utils/challenge_format.dart';
import '../utils/financial_format.dart';

typedef ChallengeChanged = Future<bool> Function(SavingChallenge challenge);

class ChallengeDetailPage extends StatefulWidget {
  const ChallengeDetailPage({
    super.key,
    required this.challenge,
    required this.onChanged,
    required this.onBack,
  });

  final SavingChallenge challenge;
  final ChallengeChanged onChanged;
  final VoidCallback onBack;

  @override
  State<ChallengeDetailPage> createState() => _ChallengeDetailPageState();
}

class _ChallengeDetailPageState extends State<ChallengeDetailPage> {
  late SavingChallenge _challenge;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _challenge = widget.challenge;
  }

  @override
  void didUpdateWidget(covariant ChallengeDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isSaving && oldWidget.challenge != widget.challenge) {
      _challenge = widget.challenge;
    }
  }

  Future<void> _toggleCell(int index) async {
    if (_isSaving) return;

    final SavingChallenge previous = _challenge;
    final List<ChallengeCell> updatedCells =
        List<ChallengeCell>.from(_challenge.cells);
    final ChallengeCell cell = updatedCells[index];
    updatedCells[index] = cell.copyWith(isCompleted: !cell.isCompleted);
    final SavingChallenge updated = _challenge.copyWith(cells: updatedCells);

    await _saveChange(previous, updated, 'تعذر حفظ تقدم الهدف محلياً.');
  }

  Future<void> _changeSequence(ChallengeSequence sequence) async {
    if (_isSaving || sequence == _challenge.sequence) return;

    final SavingChallenge previous = _challenge;
    final SavingChallenge updated = _challenge.resequence(sequence);

    await _saveChange(
      previous,
      updated,
      'تعذر حفظ ترتيب الخانات.',
    );
  }

  Future<void> _editGoalDetails() async {
    if (_isSaving) return;

    final TextEditingController noteController = TextEditingController(
      text: _challenge.goalNote ?? '',
    );
    DateTime? deadline = _challenge.deadline;

    final _GoalDetailsDraft? draft = await showDialog<_GoalDetailsDraft>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('تفاصيل هدف الادخار'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    TextField(
                      controller: noteController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظة الهدف (اختياري)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'الموعد النهائي (اختياري)',
                        border: OutlineInputBorder(),
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              deadline == null
                                  ? 'بدون موعد'
                                  : FinancialFormat.date(deadline!),
                            ),
                          ),
                          if (deadline != null)
                            IconButton(
                              onPressed: () {
                                setDialogState(() => deadline = null);
                              },
                              tooltip: 'إزالة الموعد',
                              icon: const Icon(Icons.close),
                            ),
                          IconButton(
                            onPressed: () async {
                              final DateTime now = DateTime.now();
                              final DateTime today =
                                  DateTime(now.year, now.month, now.day);
                              final DateTime initial = deadline == null ||
                                      deadline!.isBefore(today)
                                  ? today
                                  : deadline!;
                              final DateTime? picked = await showDatePicker(
                                context: dialogContext,
                                initialDate: initial,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setDialogState(() => deadline = picked);
                              }
                            },
                            tooltip: 'اختيار موعد',
                            icon: const Icon(Icons.calendar_today_outlined),
                          ),
                        ],
                      ),
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
                    Navigator.of(dialogContext).pop(
                      _GoalDetailsDraft(
                        deadline: deadline,
                        note: noteController.text.trim(),
                      ),
                    );
                  },
                  child: const Text('حفظ'),
                ),
              ],
            );
          },
        );
      },
    );
    noteController.dispose();

    if (draft == null || !mounted) return;

    final SavingChallenge previous = _challenge;
    final SavingChallenge updated = _challenge.copyWith(
      deadline: draft.deadline,
      clearDeadline: draft.deadline == null,
      goalNote: draft.note.isEmpty ? null : draft.note,
      clearGoalNote: draft.note.isEmpty,
    );

    await _saveChange(
      previous,
      updated,
      'تعذر حفظ تفاصيل الهدف.',
    );
  }

  Future<void> _saveChange(
    SavingChallenge previous,
    SavingChallenge updated,
    String errorMessage,
  ) async {
    setState(() {
      _challenge = updated;
      _isSaving = true;
    });

    final bool saved = await widget.onChanged(updated);
    if (!mounted) return;

    if (!saved) {
      setState(() {
        _challenge = previous;
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
      return;
    }

    setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    final GoalPace? pace = _challenge.goalPace();
    final bool overdue = _challenge.isDeadlineOverdue();
    final int completedCells =
        _challenge.cells.where((cell) => cell.isCompleted).length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  onPressed: widget.onBack,
                  icon: const BackButtonIcon(),
                  tooltip: 'رجوع',
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _challenge.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '${ChallengeFormat.amount(_challenge.savedAmount, _challenge.currency)} من '
              '${ChallengeFormat.amount(_challenge.targetAmount, _challenge.currency)} محفوظ',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _challenge.progress),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text('${FinancialFormat.progress(_challenge.progress)} مكتمل'),
                Text('$completedCells/${_challenge.cellCount} خانات'),
              ],
            ),
            const SizedBox(height: 14),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'هدف الادخار',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          onPressed: _isSaving ? null : _editGoalDetails,
                          tooltip: 'تعديل تفاصيل الهدف',
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ],
                    ),
                    if (_challenge.goalNote != null) ...<Widget>[
                      Text(_challenge.goalNote!),
                      const SizedBox(height: 8),
                    ],
                    if (_challenge.deadline == null)
                      const Text('بدون موعد نهائي')
                    else ...<Widget>[
                      Text(
                        'الموعد: ${FinancialFormat.date(_challenge.deadline!)}'
                        '${overdue ? ' • متأخر' : ''}',
                      ),
                      if (pace != null && !_challenge.isComplete) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          'باقي ${pace.daysRemaining} يوم • '
                          '${ChallengeFormat.amount(pace.weeklyAmount, _challenge.currency)} أسبوعياً • '
                          '${ChallengeFormat.amount(pace.monthlyAmount, _challenge.currency)} شهرياً',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ],
                    if (_challenge.isComplete) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        'تم إكمال الهدف',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'ترتيب الخانات',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SegmentedButton<ChallengeSequence>(
              showSelectedIcon: false,
              segments: ChallengeSequence.values
                  .map(
                    (sequence) => ButtonSegment<ChallengeSequence>(
                      value: sequence,
                      label: Text(ChallengeFormat.sequenceLabel(sequence)),
                    ),
                  )
                  .toList(growable: false),
              selected: <ChallengeSequence>{_challenge.sequence},
              onSelectionChanged: _isSaving
                  ? null
                  : (selection) => _changeSequence(selection.first),
            ),
            const SizedBox(height: 16),
            if (_challenge.cells.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'هذا الهدف قديم ولا يمكن تطبيق قواعد الشبكة الحالية عليه.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final int columns = constraints.maxWidth < 340
                        ? 3
                        : constraints.maxWidth < 520
                            ? 4
                            : 6;
                    return GridView.builder(
                      padding: const EdgeInsets.only(bottom: 20),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1.25,
                      ),
                      itemCount: _challenge.cells.length,
                      itemBuilder: (context, index) {
                        final ChallengeCell cell = _challenge.cells[index];
                        return _SavingCell(
                          cell: cell,
                          currency: _challenge.currency,
                          enabled: !_isSaving,
                          onTap: () => _toggleCell(index),
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GoalDetailsDraft {
  const _GoalDetailsDraft({
    required this.deadline,
    required this.note,
  });

  final DateTime? deadline;
  final String note;
}

class _SavingCell extends StatelessWidget {
  const _SavingCell({
    required this.cell,
    required this.currency,
    required this.enabled,
    required this.onTap,
  });

  final ChallengeCell cell;
  final ChallengeCurrency currency;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Material(
      color: cell.isCompleted
          ? colors.primaryContainer
          : colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (cell.isCompleted)
                Icon(
                  Icons.check_circle,
                  size: 20,
                  color: colors.primary,
                )
              else
                const SizedBox(height: 20),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  ChallengeFormat.amount(cell.value, currency),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: cell.isCompleted
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
