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

    await _saveChange(previous, updated, 'تعذر حفظ تقدم الهدف.');
  }

  Future<void> _changeSequence(ChallengeSequence sequence) async {
    if (_isSaving || sequence == _challenge.sequence) return;
    final SavingChallenge previous = _challenge;
    final SavingChallenge updated = _challenge.resequence(sequence);
    await _saveChange(previous, updated, 'تعذر حفظ ترتيب الخانات.');
  }

  Future<void> _showSequenceSheet() async {
    final ChallengeSequence? selected = await showModalBottomSheet<ChallengeSequence>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('ترتيب الخانات', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'التغيير يعيد ترتيب الخانات فقط ويحافظ على تقدمك الحالي.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ...ChallengeSequence.values.map(
              (sequence) => RadioListTile<ChallengeSequence>(
                value: sequence,
                groupValue: _challenge.sequence,
                title: Text(ChallengeFormat.sequenceLabel(sequence)),
                onChanged: (value) => Navigator.of(context).pop(value),
              ),
            ),
          ],
        ),
      ),
    );

    if (selected != null) await _changeSequence(selected);
  }

  Future<void> _editGoalDetails() async {
    if (_isSaving) return;

    final TextEditingController noteController = TextEditingController(
      text: _challenge.goalNote ?? '',
    );
    DateTime? deadline = _challenge.deadline;

    final _GoalDetailsDraft? draft = await showDialog<_GoalDetailsDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تفاصيل الهدف'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  controller: noteController,
                  maxLines: 3,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة (اختياري)',
                    hintText: 'لماذا هذا الهدف مهم لك؟',
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () async {
                    final DateTime now = DateTime.now();
                    final DateTime today = DateTime(now.year, now.month, now.day);
                    final DateTime initial =
                        deadline == null || deadline!.isBefore(today)
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
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    deadline == null
                        ? 'إضافة موعد نهائي'
                        : FinancialFormat.date(deadline!),
                  ),
                ),
                if (deadline != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => setDialogState(() => deadline = null),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('إزالة الموعد'),
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
              onPressed: () => Navigator.of(dialogContext).pop(
                _GoalDetailsDraft(
                  deadline: deadline,
                  note: noteController.text.trim(),
                ),
              ),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
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

    await _saveChange(previous, updated, 'تعذر حفظ تفاصيل الهدف.');
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  onPressed: widget.onBack,
                  icon: const BackButtonIcon(),
                  tooltip: 'رجوع',
                ),
                Expanded(
                  child: Text(
                    _challenge.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'خيارات الهدف',
                  onSelected: (value) {
                    if (value == 'edit') _editGoalDetails();
                    if (value == 'sequence') _showSequenceSheet();
                  },
                  itemBuilder: (_) => const <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.edit_outlined),
                          SizedBox(width: 10),
                          Text('تفاصيل الهدف'),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'sequence',
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.sort_rounded),
                          SizedBox(width: 10),
                          Text('ترتيب الخانات'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            _GoalHero(
              challenge: _challenge,
              pace: pace,
              overdue: overdue,
              completedCells: completedCells,
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'خانات الادخار',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text(
                  '$completedCells/${_challenge.cellCount}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              'اضغط على الخانة عند ادخار مبلغها. اضغط مرة أخرى للتراجع.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
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
                            : constraints.maxWidth < 800
                                ? 6
                                : 8;
                    return GridView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1.2,
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

class _GoalHero extends StatelessWidget {
  const _GoalHero({
    required this.challenge,
    required this.pace,
    required this.overdue,
    required this.completedCells,
  });

  final SavingChallenge challenge;
  final GoalPace? pace;
  final bool overdue;
  final int completedCells;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: Text(
                    ChallengeFormat.amount(
                      challenge.savedAmount,
                      challenge.currency,
                    ),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                Text(
                  FinancialFormat.progress(challenge.progress),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              'من ${ChallengeFormat.amount(challenge.targetAmount, challenge.currency)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: challenge.progress,
              minHeight: 9,
              borderRadius: BorderRadius.circular(99),
            ),
            if (challenge.isComplete) ...<Widget>[
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Icon(Icons.check_circle_rounded, color: colors.primary),
                  const SizedBox(width: 8),
                  const Text('تم إكمال الهدف'),
                ],
              ),
            ] else if (challenge.deadline != null) ...<Widget>[
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Icon(
                    overdue ? Icons.warning_amber_rounded : Icons.event_outlined,
                    size: 19,
                    color: overdue ? colors.error : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      overdue
                          ? 'متأخر عن ${FinancialFormat.date(challenge.deadline!)}'
                          : 'الموعد ${FinancialFormat.date(challenge.deadline!)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: overdue ? colors.error : colors.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
              if (pace case final GoalPace goalPace) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  'للوصول بالموعد: ${ChallengeFormat.amount(goalPace.weeklyAmount, challenge.currency)} أسبوعياً',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
            if (challenge.goalNote != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                challenge.goalNote!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
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

    return Semantics(
      button: true,
      checked: cell.isCompleted,
      label:
          '${ChallengeFormat.amount(cell.value, currency)}${cell.isCompleted ? ' محفوظة' : ' غير محفوظة'}',
      child: Material(
        color: cell.isCompleted
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  cell.isCompleted
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  size: 20,
                  color: cell.isCompleted
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
                const SizedBox(height: 5),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    ChallengeFormat.amount(cell.value, currency),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
