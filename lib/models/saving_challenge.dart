import 'dart:math';

enum ChallengeSequence {
  ordered,
  random,
  reversed;

  String get label => switch (this) {
        ChallengeSequence.ordered => 'Ordered',
        ChallengeSequence.random => 'Random',
        ChallengeSequence.reversed => 'Reversed',
      };
}

class ChallengeCell {
  const ChallengeCell({
    required this.value,
    this.isCompleted = false,
  });

  final int value;
  final bool isCompleted;

  ChallengeCell copyWith({bool? isCompleted}) {
    return ChallengeCell(
      value: value,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'value': value,
        'isCompleted': isCompleted,
      };

  factory ChallengeCell.fromJson(Map<String, dynamic> json) {
    return ChallengeCell(
      value: (json['value'] as num).toInt(),
      isCompleted: json['isCompleted'] as bool? ?? false,
    );
  }
}

class SavingChallenge {
  const SavingChallenge({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.sequence,
    required this.cellCount,
    required this.cells,
  });

  final String id;
  final String name;
  final double targetAmount;
  final ChallengeSequence sequence;
  final int cellCount;
  final List<ChallengeCell> cells;

  int get savedAmount => cells
      .where((cell) => cell.isCompleted)
      .fold<int>(0, (sum, cell) => sum + cell.value);

  double get progress {
    if (targetAmount <= 0) {
      return 0;
    }
    return (savedAmount / targetAmount).clamp(0.0, 1.0);
  }

  SavingChallenge copyWith({List<ChallengeCell>? cells}) {
    return SavingChallenge(
      id: id,
      name: name,
      targetAmount: targetAmount,
      sequence: sequence,
      cellCount: cellCount,
      cells: cells ?? this.cells,
    );
  }

  factory SavingChallenge.create({
    required String id,
    required String name,
    required double targetAmount,
    required ChallengeSequence sequence,
    required int cellCount,
  }) {
    if (targetAmount <= 0 || targetAmount != targetAmount.roundToDouble()) {
      throw ArgumentError('Target must be a positive whole-dollar amount.');
    }

    final int total = targetAmount.toInt();
    if (cellCount <= 0 || cellCount > total) {
      throw ArgumentError('Cell count must be between 1 and the target amount.');
    }

    final List<int> values = _generateValues(
      total: total,
      count: cellCount,
      sequence: sequence,
      seedSource: id,
    );

    return SavingChallenge(
      id: id,
      name: name,
      targetAmount: targetAmount,
      sequence: sequence,
      cellCount: cellCount,
      cells: values.map((value) => ChallengeCell(value: value)).toList(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'targetAmount': targetAmount,
        'sequence': sequence.name,
        'cellCount': cellCount,
        'cells': cells.map((cell) => cell.toJson()).toList(growable: false),
      };

  factory SavingChallenge.fromJson(Map<String, dynamic> json) {
    final String id = json['id'] as String;
    final double targetAmount = (json['targetAmount'] as num).toDouble();
    final ChallengeSequence sequence = ChallengeSequence.values.firstWhere(
      (value) => value.name == json['sequence'],
      orElse: () => ChallengeSequence.ordered,
    );

    final List<dynamic>? rawCells = json['cells'] as List<dynamic>?;
    if (rawCells != null && rawCells.isNotEmpty) {
      final List<ChallengeCell> cells = rawCells
          .map(
            (item) => ChallengeCell.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false);
      return SavingChallenge(
        id: id,
        name: json['name'] as String,
        targetAmount: targetAmount,
        sequence: sequence,
        cellCount: (json['cellCount'] as num?)?.toInt() ?? cells.length,
        cells: cells,
      );
    }

    // Backward compatibility for challenges created before grids existed.
    if (targetAmount > 0 && targetAmount == targetAmount.roundToDouble()) {
      final int total = targetAmount.toInt();
      final int requestedCount = (json['cellCount'] as num?)?.toInt() ?? min(50, total);
      final int safeCount = requestedCount.clamp(1, total);
      final List<int> values = _generateValues(
        total: total,
        count: safeCount,
        sequence: sequence,
        seedSource: id,
      );
      return SavingChallenge(
        id: id,
        name: json['name'] as String,
        targetAmount: targetAmount,
        sequence: sequence,
        cellCount: safeCount,
        cells: values.map((value) => ChallengeCell(value: value)).toList(),
      );
    }

    return SavingChallenge(
      id: id,
      name: json['name'] as String,
      targetAmount: targetAmount,
      sequence: sequence,
      cellCount: 0,
      cells: const <ChallengeCell>[],
    );
  }

  static List<int> _generateValues({
    required int total,
    required int count,
    required ChallengeSequence sequence,
    required String seedSource,
  }) {
    final Random random = Random(_stableSeed(seedSource));
    final List<int> values = List<int>.filled(count, 1);
    int remaining = total - count;

    if (remaining > 0) {
      final List<double> weights = List<double>.generate(
        count,
        (_) {
          final double value = random.nextDouble();
          return 0.15 + (value * value * 2.2);
        },
      );
      final double weightTotal = weights.fold<double>(0, (sum, value) => sum + value);

      int distributed = 0;
      for (int i = 0; i < count; i++) {
        final int extra = (remaining * weights[i] / weightTotal).floor();
        values[i] += extra;
        distributed += extra;
      }

      int leftovers = remaining - distributed;
      final List<int> indexes = List<int>.generate(count, (index) => index)..shuffle(random);
      int cursor = 0;
      while (leftovers > 0) {
        values[indexes[cursor % indexes.length]]++;
        leftovers--;
        cursor++;
      }
    }

    switch (sequence) {
      case ChallengeSequence.ordered:
        values.sort();
      case ChallengeSequence.reversed:
        values.sort((a, b) => b.compareTo(a));
      case ChallengeSequence.random:
        values.shuffle(random);
    }

    return values;
  }

  static int _stableSeed(String source) {
    int seed = 17;
    for (final int codeUnit in source.codeUnits) {
      seed = ((seed * 31) + codeUnit) & 0x7fffffff;
    }
    return seed;
  }
}
