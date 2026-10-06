import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/saving_challenge.dart';
import '../services/challenge_storage.dart';
import '../ui/ux_components.dart';
import '../utils/challenge_format.dart';
import '../utils/financial_format.dart';
import 'challenge_detail_page.dart';

class ChallengesPage extends StatefulWidget {
  const ChallengesPage({
    super.key,
    required this.isActive,
  });

  final bool isActive;

  @override
  State<ChallengesPage> createState() => _ChallengesPageState();
}

class _ChallengesPageState extends State<ChallengesPage> {
  final ChallengeStorage _storage = ChallengeStorage();

  List<SavingChallenge> _challenges = <SavingChallenge>[];
  bool _isLoading = true;
  String? _openedChallengeId;

  SavingChallenge? get _openedChallenge {
    final String? id = _openedChallengeId;
    if (id == null) return null;
    for (final SavingChallenge challenge in _challenges) {
      if (challenge.id == id) return challenge;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadChallenges();
  }

  Future<void> _loadChallenges() async {
    try {
      final List<SavingChallenge> challenges = await _storage.loadChallenges();
      if (!mounted) return;
      setState(() {
        _challenges = challenges;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحميل أهداف الادخار.')),
      );
    }
  }

  Future<void> _createChallenge() async {
    final SavingChallenge? challenge =
        await showModalBottomSheet<SavingChallenge>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.92,
        child: _CreateChallengeSheet(),
      ),
    );

    if (challenge == null || !mounted) return;

    try {
      await _storage.addChallenge(challenge);
      if (!mounted) return;
      setState(() {
        _challenges = <SavingChallenge>[..._challenges, challenge];
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ هدف الادخار.')),
      );
    }
  }

  Future<bool> _updateChallenge(SavingChallenge challenge) async {
    final int index = _challenges.indexWhere((item) => item.id == challenge.id);
    if (index == -1) return false;

    try {
      await _storage.updateChallenge(challenge);
      if (!mounted) return false;
      final List<SavingChallenge> updated =
          List<SavingChallenge>.from(_challenges);
      updated[index] = challenge;
      setState(() => _challenges = updated);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _deleteChallenge(SavingChallenge challenge) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف هدف الادخار؟'),
        content: Text(
          'سيتم حذف «${challenge.name}» وكل تقدمه. لا يمكن التراجع عن هذه العملية.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _storage.deleteChallenge(challenge.id);
      if (!mounted) return;
      setState(() {
        _challenges = _challenges
            .where((item) => item.id != challenge.id)
            .toList(growable: false);
        if (_openedChallengeId == challenge.id) {
          _openedChallengeId = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حذف هدف الادخار.')),
      );
    }
  }

  void _openChallenge(SavingChallenge challenge) {
    setState(() => _openedChallengeId = challenge.id);
  }

  void _closeChallenge() {
    setState(() => _openedChallengeId = null);
  }

  @override
  Widget build(BuildContext context) {
    final SavingChallenge? openedChallenge = _openedChallenge;

    return PopScope(
      canPop: !widget.isActive || openedChallenge == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && widget.isActive && openedChallenge != null) {
          _closeChallenge();
        }
      },
      child: Scaffold(
        body: openedChallenge != null
            ? ChallengeDetailPage(
                challenge: openedChallenge,
                onChanged: _updateChallenge,
                onBack: _closeChallenge,
              )
            : _buildChallengeList(),
        floatingActionButton: openedChallenge == null && !_isLoading
            ? FloatingActionButton.extended(
                onPressed: _createChallenge,
                icon: const Icon(Icons.add_rounded),
                label: const Text('هدف جديد'),
              )
            : null,
      ),
    );
  }

  Widget _buildChallengeList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_challenges.isEmpty) {
      return UxEmptyState(
        icon: Icons.flag_outlined,
        title: 'ابدأ بهدف واحد',
        body:
            'اختر شيئاً تريد الادخار له. سنحوّل المبلغ إلى خانات بسيطة تتابع تقدمك منها.',
        action: FilledButton.icon(
          onPressed: _createChallenge,
          icon: const Icon(Icons.add_rounded),
          label: const Text('إنشاء أول هدف'),
        ),
      );
    }

    final int completed = _challenges.where((item) => item.isComplete).length;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 112),
      itemCount: _challenges.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: UxPageHeader(
              title: 'أهداف الادخار',
              subtitle: '$completed من ${_challenges.length} مكتملة',
            ),
          );
        }

        final SavingChallenge challenge = _challenges[index - 1];
        return _GoalCard(
          challenge: challenge,
          onOpen: () => _openChallenge(challenge),
          onDelete: () => _deleteChallenge(challenge),
        );
      },
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.challenge,
    required this.onOpen,
    required this.onDelete,
  });

  final SavingChallenge challenge;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool overdue = challenge.isDeadlineOverdue();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          challenge.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ChallengeFormat.currencyLabel(challenge.currency),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'خيارات الهدف',
                    onSelected: (value) {
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (_) => const <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          children: <Widget>[
                            Icon(Icons.delete_outline),
                            SizedBox(width: 10),
                            Text('حذف الهدف'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
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
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'من ${ChallengeFormat.amount(challenge.targetAmount, challenge.currency)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: challenge.progress,
                minHeight: 8,
                borderRadius: BorderRadius.circular(99),
              ),
              if (challenge.deadline != null) ...<Widget>[
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Icon(
                      overdue ? Icons.warning_amber_rounded : Icons.event_outlined,
                      size: 18,
                      color: overdue ? colors.error : colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      overdue
                          ? 'متأخر عن ${FinancialFormat.date(challenge.deadline!)}'
                          : 'الموعد ${FinancialFormat.date(challenge.deadline!)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: overdue ? colors.error : colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateChallengeSheet extends StatefulWidget {
  const _CreateChallengeSheet();

  @override
  State<_CreateChallengeSheet> createState() => _CreateChallengeSheetState();
}

class _CreateChallengeSheetState extends State<_CreateChallengeSheet> {
  final GlobalKey<FormState> _essentialFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _detailsFormKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _targetController = TextEditingController();
  final TextEditingController _cellCountController =
      TextEditingController(text: '50');
  final TextEditingController _noteController = TextEditingController();

  ChallengeCurrency _currency = ChallengeCurrency.usd;
  ChallengeSequence _sequence = ChallengeSequence.ordered;
  DateTime? _deadline;
  int _step = 0;

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    _cellCountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? today.add(const Duration(days: 30)),
      firstDate: today,
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _deadline = picked);
    }
  }

  void _goNext() {
    if (!_essentialFormKey.currentState!.validate()) return;
    final int target = int.parse(_targetController.text.trim());
    final int maxCells = target ~/ _currency.cellStep;
    final int current = int.tryParse(_cellCountController.text) ?? 50;
    _cellCountController.text = min(max(1, current), min(500, maxCells)).toString();
    setState(() => _step = 1);
  }

  void _submit() {
    if (!_detailsFormKey.currentState!.validate()) return;

    final int target = int.parse(_targetController.text.trim());
    final int cellCount = int.parse(_cellCountController.text.trim());
    final String id = DateTime.now().microsecondsSinceEpoch.toString();

    try {
      final SavingChallenge challenge = SavingChallenge.create(
        id: id,
        name: _nameController.text.trim(),
        targetAmount: target.toDouble(),
        currency: _currency,
        sequence: _sequence,
        cellCount: cellCount,
        deadline: _deadline,
        goalNote: _noteController.text,
      );
      Navigator.of(context).pop(challenge);
    } on ArgumentError catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('راجع المبلغ وعدد الخانات ثم حاول مجدداً.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final int denominationStep = _currency.cellStep;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'هدف ادخار جديد',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                _step == 0
                    ? 'أولاً: ما الهدف وكم تريد أن تدخر؟'
                    : 'ثانياً: خصّص طريقة المتابعة إذا أردت.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(child: _StepBar(active: _step >= 0)),
                  const SizedBox(width: 8),
                  Expanded(child: _StepBar(active: _step >= 1)),
                ],
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 24,
            ),
            child: _step == 0
                ? Form(
                    key: _essentialFormKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        TextFormField(
                          controller: _nameController,
                          maxLength: 80,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'اسم الهدف',
                            hintText: 'مثال: الجامعة أو رحلة أو مشروع',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'أدخل اسماً للهدف.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        Text('العملة', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        SegmentedButton<ChallengeCurrency>(
                          showSelectedIcon: false,
                          segments: ChallengeCurrency.values
                              .map(
                                (currency) => ButtonSegment<ChallengeCurrency>(
                                  value: currency,
                                  label: Text(
                                    ChallengeFormat.currencyShort(currency),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          selected: <ChallengeCurrency>{_currency},
                          onSelectionChanged: (selection) {
                            setState(() => _currency = selection.first);
                            _essentialFormKey.currentState?.validate();
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _targetController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            labelText: 'المبلغ المستهدف',
                            suffixText: ChallengeFormat.currencyShort(_currency),
                            helperText: denominationStep == 1
                                ? 'أدخل المبلغ الكامل الذي تريد الوصول إليه.'
                                : 'المبلغ يجب أن يكون من مضاعفات ${ChallengeFormat.cellStep(_currency)}.',
                          ),
                          validator: (value) {
                            final int? amount =
                                int.tryParse((value ?? '').trim());
                            if (amount == null || amount <= 0) {
                              return 'أدخل مبلغاً أكبر من صفر.';
                            }
                            if (amount % denominationStep != 0) {
                              return 'استخدم مضاعفات ${ChallengeFormat.cellStep(_currency)}.';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  )
                : Form(
                    key: _detailsFormKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        UxInfoBanner(
                          icon: Icons.auto_awesome_outlined,
                          title: 'يمكنك ترك الإعدادات الافتراضية',
                          body:
                              'هذه الخيارات تغيّر شكل المتابعة فقط، وليست مطلوبة لإنشاء الهدف.',
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _cellCountController,
                          keyboardType: TextInputType.number,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'عدد خانات الادخار',
                            helperText:
                                'خانات أقل = مبالغ أكبر لكل ضغطة. خانات أكثر = خطوات أصغر.',
                          ),
                          validator: (value) {
                            final int? count = int.tryParse((value ?? '').trim());
                            if (count == null || count <= 0) {
                              return 'أدخل خانة واحدة على الأقل.';
                            }
                            if (count > 500) return 'الحد الأقصى 500 خانة.';
                            final int target =
                                int.parse(_targetController.text.trim());
                            final int maxCells = target ~/ denominationStep;
                            if (count > maxCells) {
                              return 'هذا المبلغ يسمح بحد أقصى $maxCells خانة.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        Text('ترتيب الخانات',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        SegmentedButton<ChallengeSequence>(
                          showSelectedIcon: false,
                          segments: ChallengeSequence.values
                              .map(
                                (sequence) => ButtonSegment<ChallengeSequence>(
                                  value: sequence,
                                  label: Text(
                                    ChallengeFormat.sequenceLabel(sequence),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          selected: <ChallengeSequence>{_sequence},
                          onSelectionChanged: (selection) {
                            setState(() => _sequence = selection.first);
                          },
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _pickDeadline,
                          icon: const Icon(Icons.event_outlined),
                          label: Text(
                            _deadline == null
                                ? 'إضافة موعد نهائي'
                                : 'الموعد ${FinancialFormat.date(_deadline!)}',
                          ),
                        ),
                        if (_deadline != null)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(
                              onPressed: () => setState(() => _deadline = null),
                              icon: const Icon(Icons.close_rounded),
                              label: const Text('إزالة الموعد'),
                            ),
                          ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _noteController,
                          maxLines: 3,
                          maxLength: 300,
                          decoration: const InputDecoration(
                            labelText: 'ملاحظة (اختياري)',
                            hintText: 'لماذا هذا الهدف مهم لك؟',
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Row(
            children: <Widget>[
              if (_step == 1) ...<Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _step = 0),
                    child: const Text('رجوع'),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _step == 0 ? _goNext : _submit,
                  icon: Icon(
                    _step == 0 ? Icons.arrow_back_rounded : Icons.check_rounded,
                  ),
                  label: Text(_step == 0 ? 'التالي' : 'إنشاء الهدف'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 5,
      decoration: BoxDecoration(
        color: active
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}
