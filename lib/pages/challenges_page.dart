import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/saving_challenge.dart';
import '../services/challenge_storage.dart';
import 'challenge_detail_page.dart';

class ChallengesPage extends StatefulWidget {
  const ChallengesPage({super.key});

  @override
  State<ChallengesPage> createState() => _ChallengesPageState();
}

class _ChallengesPageState extends State<ChallengesPage> {
  final ChallengeStorage _storage = ChallengeStorage();

  List<SavingChallenge> _challenges = <SavingChallenge>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChallenges();
  }

  Future<void> _loadChallenges() async {
    final List<SavingChallenge> challenges = await _storage.loadChallenges();
    if (!mounted) {
      return;
    }

    setState(() {
      _challenges = challenges;
      _isLoading = false;
    });
  }

  Future<void> _createChallenge() async {
    final SavingChallenge? challenge = await showModalBottomSheet<SavingChallenge>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => const _CreateChallengeSheet(),
    );

    if (challenge == null || !mounted) {
      return;
    }

    final List<SavingChallenge> updated = <SavingChallenge>[
      ..._challenges,
      challenge,
    ];

    try {
      await _storage.saveChallenges(updated);
      if (!mounted) {
        return;
      }
      setState(() {
        _challenges = updated;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the challenge locally.')),
      );
    }
  }

  Future<bool> _updateChallenge(SavingChallenge challenge) async {
    final int index = _challenges.indexWhere((item) => item.id == challenge.id);
    if (index == -1) {
      return false;
    }

    final List<SavingChallenge> updated = List<SavingChallenge>.from(_challenges);
    updated[index] = challenge;

    try {
      await _storage.saveChallenges(updated);
      if (!mounted) {
        return false;
      }
      setState(() {
        _challenges = updated;
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _deleteChallenge(SavingChallenge challenge) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete challenge?'),
        content: Text(
          'Delete "${challenge.name}"? This cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final List<SavingChallenge> updated = _challenges
        .where((item) => item.id != challenge.id)
        .toList(growable: false);

    try {
      await _storage.saveChallenges(updated);
      if (!mounted) {
        return;
      }
      setState(() {
        _challenges = updated;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete the challenge locally.')),
      );
    }
  }

  Future<void> _openChallenge(SavingChallenge challenge) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ChallengeDetailPage(
          challenge: challenge,
          onChanged: _updateChallenge,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _challenges.isEmpty
              ? const Center(child: Text('No challenges yet.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: _challenges.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final SavingChallenge challenge = _challenges[index];
                    return Card(
                      child: ListTile(
                        onTap: () => _openChallenge(challenge),
                        title: Text(challenge.name),
                        subtitle: Text(
                          '\$${_formatAmount(challenge.targetAmount)}  •  '
                          '${challenge.sequence.label}  •  '
                          '${challenge.cellCount} cells',
                        ),
                        trailing: IconButton(
                          onPressed: () => _deleteChallenge(challenge),
                          tooltip: 'Delete challenge',
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createChallenge,
        tooltip: 'Add challenge',
        child: const Icon(Icons.add),
      ),
    );
  }

  static String _formatAmount(double amount) {
    return amount == amount.truncateToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
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
  final TextEditingController _cellCountController = TextEditingController(text: '50');

  ChallengeSequence _sequence = ChallengeSequence.ordered;

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    _cellCountController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final int target = int.parse(_targetController.text.trim());
    final int cellCount = int.parse(_cellCountController.text.trim());
    final String id = DateTime.now().microsecondsSinceEpoch.toString();

    Navigator.of(context).pop(
      SavingChallenge.create(
        id: id,
        name: _nameController.text.trim(),
        targetAmount: target.toDouble(),
        sequence: _sequence,
        cellCount: cellCount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                'New challenge',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Challenge name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter a challenge name.';
                  }
                  return null;
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
                decoration: const InputDecoration(
                  labelText: 'Target',
                  prefixText: '\$ ',
                  helperText: 'Whole dollars only',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final int? amount = int.tryParse((value ?? '').trim());
                  if (amount == null || amount <= 0) {
                    return 'Enter a whole-dollar target greater than 0.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cellCountController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'Number of cells',
                  helperText: 'How many saving boxes to create',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final int? count = int.tryParse((value ?? '').trim());
                  if (count == null || count <= 0) {
                    return 'Enter at least 1 cell.';
                  }
                  if (count > 500) {
                    return 'Use 500 cells or fewer.';
                  }
                  final int? target = int.tryParse(_targetController.text.trim());
                  if (target != null && count > target) {
                    return 'Cells cannot exceed the target amount.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              Text(
                'Sequence',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              SegmentedButton<ChallengeSequence>(
                segments: ChallengeSequence.values
                    .map(
                      (sequence) => ButtonSegment<ChallengeSequence>(
                        value: sequence,
                        label: Text(sequence.label),
                      ),
                    )
                    .toList(growable: false),
                selected: <ChallengeSequence>{_sequence},
                onSelectionChanged: (selection) {
                  setState(() {
                    _sequence = selection.first;
                  });
                },
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submit,
                child: const Text('Create challenge'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
