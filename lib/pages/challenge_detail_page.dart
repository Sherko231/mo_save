import 'package:flutter/material.dart';

import '../models/saving_challenge.dart';

class ChallengeDetailPage extends StatelessWidget {
  const ChallengeDetailPage({
    super.key,
    required this.challenge,
  });

  final SavingChallenge challenge;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
              ),
              const SizedBox(height: 24),
              Text(
                challenge.name,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 24),
              _InfoRow(
                label: 'Target',
                value: '\$${_formatAmount(challenge.targetAmount)}',
              ),
              const SizedBox(height: 12),
              _InfoRow(
                label: 'Sequence',
                value: challenge.sequence.label,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatAmount(double amount) {
    return amount == amount.truncateToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}
