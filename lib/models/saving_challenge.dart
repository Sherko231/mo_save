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

class SavingChallenge {
  const SavingChallenge({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.sequence,
  });

  final String id;
  final String name;
  final double targetAmount;
  final ChallengeSequence sequence;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'targetAmount': targetAmount,
        'sequence': sequence.name,
      };

  factory SavingChallenge.fromJson(Map<String, dynamic> json) {
    return SavingChallenge(
      id: json['id'] as String,
      name: json['name'] as String,
      targetAmount: (json['targetAmount'] as num).toDouble(),
      sequence: ChallengeSequence.values.firstWhere(
        (value) => value.name == json['sequence'],
        orElse: () => ChallengeSequence.ordered,
      ),
    );
  }
}
