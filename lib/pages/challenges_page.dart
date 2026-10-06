import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/saving_challenge.dart';
import '../services/challenge_storage.dart';
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
      builder: (context) => const _CreateChallengeSheet(),
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
        const SnackBar(content: Text('تعذر حفظ هدف الادخار محلياً.')),
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
        floatingActionButton: openedChallenge == null
            ? FloatingActionButton(
                onPressed: _createChallenge,
                tooltip: 'إضافة هدف ادخار',
                child: const Icon(Icons.add),
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
      return const Center(child: Text('لا توجد أهداف ادخار بعد.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: _challenges.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final SavingChallenge challenge = _challenges[index];

        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openChallenge(challenge),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
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
                              '${ChallengeFormat.currencyLabel(challenge.currency)} • '
                              '${challenge.cellCount} خانة',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            if (challenge.deadline != null) ...<Widget>[
                              const SizedBox(height: 4),
                              Text(
                                challenge.isDeadlineOverdue()
                                    ? 'الموعد ${FinancialFormat.date(challenge.deadline!)} • متأخر'
                                    : 'الموعد ${FinancialFormat.date(challenge.deadline!)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _deleteChallenge(challenge),
                        tooltip: 'حذف الهدف',
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${ChallengeFormat.amount(challenge.savedAmount, challenge.currency)} من '
                          '${ChallengeFormat.amount(challenge.targetAmount, challenge.currency)}',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(FinancialFormat.progress(challenge.progress)),
                    ],
                  ),
                  const SizedBox(height: 7),
                  LinearProgressIndicator(
                    value: challenge.progress,
                    minHeight: 7,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CreateChallengeSheet extends StatefulWidget {
  const _CreateChallengeSheet();

  @override
  State<_CreateChallengeSheet> createState() => _CreateChallengeSheetState();
}

class _CreateChallengeSheetState extends State<_CreateChallengeSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _targetController = TextEditingController();
  final TextEditingController _cellCountController =
      TextEditingController(text: '50');
  final TextEditingController _noteController = TextEditingController();

  ChallengeCurrency _currency = ChallengeCurrency.usd;
  ChallengeSequence _sequence = ChallengeSequence.ordered;
  DateTime? _deadline;

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

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final int target = int.parse(_targetController.text.trim());
    final int cellCount = int.parse(_cellCountController.text.trim());
    final String id = DateTime.now().microsecondsSinceEpoch.toString();

    Navigator.of(context).pop(
      SavingChallenge.create(
        id: id,
        name: _nameController.text.trim(),
        targetAmount: target.toDouble(),
        currency: _currency,
        sequence: _sequence,
        cellCount: cellCount,
        deadline: _deadline,
        goalNote: _noteController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int step = _currency.cellStep;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'هدف ادخار جديد',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'اسم الهدف',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'أدخل اسم الهدف.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              Text(
                'العملة',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              SegmentedButton<ChallengeCurrency>(
                showSelectedIcon: false,
                segments: ChallengeCurrency.values
                    .map(
                      (currency) => ButtonSegment<ChallengeCurrency>(
                        value: currency,
                        label: Text(ChallengeFormat.currencyShort(currency)),
                      ),
                    )
                    .toList(growable: false),
                selected: <ChallengeCurrency>{_currency},
                onSelectionChanged: (selection) {
                  setState(() => _currency = selection.first);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _targetController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: 'المبلغ المستهدف',
                  suffixText: ChallengeFormat.currencyShort(_currency),
                  helperText: step == 1
                      ? 'أدخل وحدات صحيحة فقط.'
                      : 'يجب أن يكون المبلغ من مضاعفات ${ChallengeFormat.cellStep(_currency)}.',
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  final int? amount = int.tryParse((value ?? '').trim());
                  if (amount == null || amount <= 0) {
                    return 'أدخل مبلغاً صحيحاً أكبر من صفر.';
                  }
                  if (amount % step != 0) {
                    return 'يجب أن يكون المبلغ من مضاعفات ${ChallengeFormat.cellStep(_currency)}.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cellCountController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'عدد الخانات',
                  helperText: 'عدد خانات الادخار التي ستظهر في الشبكة.',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final int? count = int.tryParse((value ?? '').trim());
                  if (count == null || count <= 0) {
                    return 'أدخل خانة واحدة على الأقل.';
                  }
                  if (count > 500) {
                    return 'الحد الأقصى 500 خانة.';
                  }

                  final int? target =
                      int.tryParse(_targetController.text.trim());
                  if (target != null && target > 0 && target % step == 0) {
                    final int maxCells = target ~/ step;
                    if (count > maxCells) {
                      return 'هذا المبلغ يسمح بحد أقصى $maxCells خانة.';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'موعد الهدف (اختياري)',
                  border: OutlineInputBorder(),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        _deadline == null
                            ? 'بدون موعد'
                            : FinancialFormat.date(_deadline!),
                      ),
                    ),
                    if (_deadline != null)
                      IconButton(
                        onPressed: () => setState(() => _deadline = null),
                        tooltip: 'إزالة الموعد',
                        icon: const Icon(Icons.close),
                      ),
                    IconButton(
                      onPressed: _pickDeadline,
                      tooltip: 'اختيار موعد',
                      icon: const Icon(Icons.calendar_today_outlined),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _noteController,
                maxLines: 2,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة الهدف (اختياري)',
                  hintText: 'مثال: قسط الجامعة، الزواج، رأس مال مشروع',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'ترتيب الخانات',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
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
                selected: <ChallengeSequence>{_sequence},
                onSelectionChanged: (selection) {
                  setState(() => _sequence = selection.first);
                },
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submit,
                child: const Text('إنشاء الهدف'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
