import 'package:flutter/material.dart';

import '../models/saving_challenge.dart';

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
    if (_isSaving) {
      return;
    }

    final SavingChallenge previous = _challenge;
    final List<ChallengeCell> updatedCells =
        List<ChallengeCell>.from(_challenge.cells);
    final ChallengeCell cell = updatedCells[index];
    updatedCells[index] = cell.copyWith(isCompleted: !cell.isCompleted);
    final SavingChallenge updated = _challenge.copyWith(cells: updatedCells);

    setState(() {
      _challenge = updated;
      _isSaving = true;
    });

    final bool saved = await widget.onChanged(updated);
    if (!mounted) {
      return;
    }

    if (!saved) {
      setState(() {
        _challenge = previous;
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save progress locally.')),
      );
      return;
    }

    setState(() {
      _isSaving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back',
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
              '\$${_challenge.savedAmount} of '
              '\$${_formatAmount(_challenge.targetAmount)} saved',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _challenge.progress),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text('${(_challenge.progress * 100).round()}% complete'),
                Text(
                  '${_challenge.cells.where((cell) => cell.isCompleted).length}'
                  '/${_challenge.cellCount} cells',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _InfoChip(
                  label: 'Target',
                  value: '\$${_formatAmount(_challenge.targetAmount)}',
                ),
                _InfoChip(
                  label: 'Sequence',
                  value: _challenge.sequence.label,
                ),
                _InfoChip(
                  label: 'Cells',
                  value: '${_challenge.cellCount}',
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_challenge.cells.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'This older challenge has a fractional target and cannot '
                    'use a whole-number grid.',
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

  static String _formatAmount(double amount) {
    return amount == amount.truncateToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
  }
}

class _SavingCell extends StatelessWidget {
  const _SavingCell({
    required this.cell,
    required this.enabled,
    required this.onTap,
  });

  final ChallengeCell cell;
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
                  '\$${cell.value}',
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

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label: $value'));
  }
}
