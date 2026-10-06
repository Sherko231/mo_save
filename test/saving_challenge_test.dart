import 'package:flutter_test/flutter_test.dart';
import 'package:mo_save/models/saving_challenge.dart';

void main() {
  group('SavingChallenge', () {
    test('generated cells exactly match target and denomination step', () {
      final cases = <(ChallengeCurrency, int, int)>[
        (ChallengeCurrency.usd, 5000, 50),
        (ChallengeCurrency.syp, 3600000, 60),
        (ChallengeCurrency.sypNew, 5000, 50),
      ];

      for (final (currency, target, count) in cases) {
        final challenge = SavingChallenge.create(
          id: 'case-${currency.name}',
          name: 'اختبار',
          targetAmount: target.toDouble(),
          currency: currency,
          sequence: ChallengeSequence.ordered,
          cellCount: count,
        );

        expect(challenge.cells, hasLength(count));
        expect(
          challenge.cells.fold<int>(0, (sum, cell) => sum + cell.value),
          target,
        );
        expect(
          challenge.cells.every(
            (cell) => cell.value > 0 && cell.value % currency.cellStep == 0,
          ),
          isTrue,
        );
      }
    });

    test('ordered and reversed sequences are monotonic', () {
      final ordered = SavingChallenge.create(
        id: 'ordered',
        name: 'مرتب',
        targetAmount: 1000,
        currency: ChallengeCurrency.usd,
        sequence: ChallengeSequence.ordered,
        cellCount: 25,
      );
      final reversed = SavingChallenge.create(
        id: 'reversed',
        name: 'عكسي',
        targetAmount: 1000,
        currency: ChallengeCurrency.usd,
        sequence: ChallengeSequence.reversed,
        cellCount: 25,
      );

      for (int i = 1; i < ordered.cells.length; i++) {
        expect(ordered.cells[i - 1].value <= ordered.cells[i].value, isTrue);
        expect(reversed.cells[i - 1].value >= reversed.cells[i].value, isTrue);
      }
    });

    test('resequence preserves target and completed savings', () {
      final base = SavingChallenge.create(
        id: 'resequence',
        name: 'إعادة ترتيب',
        targetAmount: 2000,
        currency: ChallengeCurrency.usd,
        sequence: ChallengeSequence.ordered,
        cellCount: 20,
      );
      final completedCells = <ChallengeCell>[
        for (int i = 0; i < base.cells.length; i++)
          base.cells[i].copyWith(isCompleted: i == 1 || i == 7),
      ];
      final withProgress = base.copyWith(cells: completedCells);
      final savedBefore = withProgress.savedAmount;

      final result = withProgress.resequence(ChallengeSequence.reversed);

      expect(result.savedAmount, savedBefore);
      expect(
        result.cells.fold<int>(0, (sum, cell) => sum + cell.value),
        base.targetAmount.toInt(),
      );
      expect(result.sequence, ChallengeSequence.reversed);
    });

    test('goal pace rounds up to the currency denomination step', () {
      final challenge = SavingChallenge.create(
        id: 'pace',
        name: 'جامعة',
        targetAmount: 3600000,
        currency: ChallengeCurrency.syp,
        sequence: ChallengeSequence.ordered,
        cellCount: 60,
        deadline: DateTime.utc(2026, 12, 31),
      );

      final pace = challenge.goalPace(DateTime.utc(2026, 10, 1));

      expect(pace, isNotNull);
      expect(pace!.daysRemaining, 92);
      expect(pace.weeklyAmount % ChallengeCurrency.syp.cellStep, 0);
      expect(pace.monthlyAmount % ChallengeCurrency.syp.cellStep, 0);
      expect(pace.weeklyAmount, greaterThan(0));
      expect(pace.monthlyAmount, greaterThan(0));
    });
  });
}
