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

enum ChallengeCurrency {
  usd,
  syp,
  sypNew;

  String get code => switch (this) {
        ChallengeCurrency.usd => 'USD',
        ChallengeCurrency.syp => 'SYP',
        ChallengeCurrency.sypNew => 'SYP (N)',
      };

  String get label => switch (this) {
        ChallengeCurrency.usd => 'US Dollar',
        ChallengeCurrency.syp => 'Syrian Pound',
        ChallengeCurrency.sypNew => 'New Syrian Pound',
      };

  int get cellStep => switch (this) {
        ChallengeCurrency.usd => 1,
        ChallengeCurrency.syp => 1000,
        ChallengeCurrency.sypNew => 10,
      };

  String get cellStepLabel => switch (this) {
        ChallengeCurrency.usd => '1',
        ChallengeCurrency.syp => '1,000',
        ChallengeCurrency.sypNew => '10',
      };

  String formatAmount(num amount) {
    final double value = amount.toDouble();
    final bool isWhole = value == value.roundToDouble();
    final String raw =
        isWhole ? value.toInt().toString() : value.toStringAsFixed(2);
    final List<String> parts = raw.split('.');
    final String grouped = _groupDigits(parts.first);
    final String formatted =
        parts.length == 1 ? grouped : '$grouped.${parts.last}';

    return switch (this) {
      ChallengeCurrency.usd => '\$$formatted',
      ChallengeCurrency.syp => '$formatted SYP',
      ChallengeCurrency.sypNew => '$formatted SYP (N)',
    };
  }

  static String _groupDigits(String digits) {
    final StringBuffer buffer = StringBuffer();
    for (int index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }
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
    required this.currency,
    required this.sequence,
    required this.cellCount,
    required this.cells,
  });

  final String id;
  final String name;
  final double targetAmount;
  final ChallengeCurrency currency;
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
    return (savedAmount / targetAmount).clamp(0.0, 1.0).toDouble();
  }

  SavingChallenge copyWith({
    ChallengeSequence? sequence,
    List<ChallengeCell>? cells,
  }) {
    return SavingChallenge(
      id: id,
      name: name,
      targetAmount: targetAmount,
      currency: currency,
      sequence: sequence ?? this.sequence,
      cellCount: cellCount,
      cells: cells ?? this.cells,
    );
  }

  SavingChallenge resequence(ChallengeSequence nextSequence) {
    final List<ChallengeCell> reordered = List<ChallengeCell>.from(cells);

    switch (nextSequence) {
      case ChallengeSequence.ordered:
        reordered.sort((a, b) => a.value.compareTo(b.value));
      case ChallengeSequence.reversed:
        reordered.sort((a, b) => b.value.compareTo(a.value));
      case ChallengeSequence.random:
        reordered.shuffle(Random(DateTime.now().microsecondsSinceEpoch));
    }

    return copyWith(
      sequence: nextSequence,
      cells: reordered,
    );
  }

  factory SavingChallenge.create({
    required String id,
    required String name,
    required double targetAmount,
    required ChallengeCurrency currency,
    required ChallengeSequence sequence,
    required int cellCount,
  }) {
    if (targetAmount <= 0 || targetAmount != targetAmount.roundToDouble()) {
      throw ArgumentError('Target must be a positive whole-unit amount.');
    }

    final int total = targetAmount.toInt();
    final int step = currency.cellStep;
    if (total % step != 0) {
      throw ArgumentError(
        'Target must be divisible by the currency cell step.',
      );
    }

    final int unitTotal = total ~/ step;
    if (cellCount <= 0 || cellCount > unitTotal) {
      throw ArgumentError(
        'Cell count must fit within the target and denomination step.',
      );
    }

    final List<int> unitValues = _generateValues(
      total: unitTotal,
      count: cellCount,
      sequence: sequence,
      seedSource: id,
    );
    final List<int> values =
        unitValues.map((value) => value * step).toList(growable: false);

    return SavingChallenge(
      id: id,
      name: name,
      targetAmount: targetAmount,
      currency: currency,
      sequence: sequence,
      cellCount: cellCount,
      cells: values.map((value) => ChallengeCell(value: value)).toList(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'targetAmount': targetAmount,
        'currency': currency.name,
        'sequence': sequence.name,
        'cellCount': cellCount,
        'cells': cells.map((cell) => cell.toJson()).toList(growable: false),
      };

  factory SavingChallenge.fromJson(Map<String, dynamic> json) {
    final String id = json['id'] as String;
    final double targetAmount = (json['targetAmount'] as num).toDouble();
    final ChallengeCurrency currency = ChallengeCurrency.values.firstWhere(
      (value) => value.name == json['currency'],
      orElse: () => ChallengeCurrency.usd,
    );
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
      final int count = (json['cellCount'] as num?)?.toInt() ?? cells.length;

      final List<ChallengeCell> migratedCells = _migrateCellsToStepIfNeeded(
        id: id,
        targetAmount: targetAmount,
        currency: currency,
        sequence: sequence,
        cellCount: count,
        currentCells: cells,
      );

      return SavingChallenge(
        id: id,
        name: json['name'] as String,
        targetAmount: targetAmount,
        currency: currency,
        sequence: sequence,
        cellCount: count,
        cells: migratedCells,
      );
    }

    // Backward compatibility for challenges created before grids existed.
    if (targetAmount > 0 && targetAmount == targetAmount.roundToDouble()) {
      final int total = targetAmount.toInt();
      final int step = currency.cellStep;
      if (total % step == 0) {
        final int unitTotal = total ~/ step;
        final int requestedCount =
            (json['cellCount'] as num?)?.toInt() ?? min(50, unitTotal);
        final int safeCount = requestedCount.clamp(1, unitTotal).toInt();
        final List<int> unitValues = _generateValues(
          total: unitTotal,
          count: safeCount,
          sequence: sequence,
          seedSource: id,
        );
        final List<int> values =
            unitValues.map((value) => value * step).toList(growable: false);

        return SavingChallenge(
          id: id,
          name: json['name'] as String,
          targetAmount: targetAmount,
          currency: currency,
          sequence: sequence,
          cellCount: safeCount,
          cells: values.map((value) => ChallengeCell(value: value)).toList(),
        );
      }
    }

    return SavingChallenge(
      id: id,
      name: json['name'] as String,
      targetAmount: targetAmount,
      currency: currency,
      sequence: sequence,
      cellCount: 0,
      cells: const <ChallengeCell>[],
    );
  }

  static List<ChallengeCell> _migrateCellsToStepIfNeeded({
    required String id,
    required double targetAmount,
    required ChallengeCurrency currency,
    required ChallengeSequence sequence,
    required int cellCount,
    required List<ChallengeCell> currentCells,
  }) {
    final int step = currency.cellStep;
    if (currentCells.every((cell) => cell.value % step == 0)) {
      return currentCells;
    }

    if (targetAmount != targetAmount.roundToDouble()) {
      return currentCells;
    }

    final int total = targetAmount.toInt();
    if (total <= 0 || total % step != 0) {
      return currentCells;
    }

    final int unitTotal = total ~/ step;
    if (cellCount <= 0 || cellCount > unitTotal) {
      return currentCells;
    }

    final List<int> unitValues = _generateValues(
      total: unitTotal,
      count: cellCount,
      sequence: sequence,
      seedSource: id,
    );

    return List<ChallengeCell>.generate(
      cellCount,
      (index) => ChallengeCell(
        value: unitValues[index] * step,
        isCompleted:
            index < currentCells.length && currentCells[index].isCompleted,
      ),
      growable: false,
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
    final int remaining = total - count;

    if (remaining > 0) {
      final List<double> weights = List<double>.generate(
        count,
        (_) {
          final double value = random.nextDouble();
          return 0.15 + (value * value * 2.2);
        },
      );
      final double weightTotal =
          weights.fold<double>(0, (sum, value) => sum + value);

      int distributed = 0;
      for (int i = 0; i < count; i++) {
        final int extra = (remaining * weights[i] / weightTotal).floor();
        values[i] += extra;
        distributed += extra;
      }

      int leftovers = remaining - distributed;
      final List<int> indexes = List<int>.generate(count, (index) => index)
        ..shuffle(random);
      int cursor = 0;
      while (leftovers > 0) {
        values[indexes[cursor % indexes.length]]++;
        leftovers--;
        cursor++;
      }
    }

    if (sequence == ChallengeSequence.ordered) {
      values.sort();
    } else if (sequence == ChallengeSequence.reversed) {
      values.sort((a, b) => b.compareTo(a));
    } else {
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
