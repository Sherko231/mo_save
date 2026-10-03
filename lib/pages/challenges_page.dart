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

  void _openChallenge(SavingChallenge challenge) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ChallengeDetailPage(challenge: challenge),
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
                          '${challenge.sequence.label}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
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

  ChallengeSequence _sequence = ChallengeSequence.ordered;

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final double target = double.parse(
      _targetController.text.trim().replaceAll(',', '.'),
    );

    Navigator.of(context).pop(
      SavingChallenge(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: _nameController.text.trim(),
        targetAmount: target,
        sequence: _sequence,
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Target',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final double? amount = double.tryParse(
                    (value ?? '').trim().replaceAll(',', '.'),
                  );
                  if (amount == null || amount <= 0) {
                    return 'Enter a target greater than 0.';
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
