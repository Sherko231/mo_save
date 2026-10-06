import '../models/expected_income.dart';
import '../models/financial_balance_snapshot.dart';
import '../models/financial_event.dart';
import '../models/saving_challenge.dart';
import 'balance_valuation_service.dart';
import 'challenge_storage.dart';
import 'expense_service.dart';
import 'recurring_income_service.dart';

class HomeDashboardSnapshot {
  HomeDashboardSnapshot({
    required this.balances,
    required List<ExpectedIncome> incomeOccurrences,
    required this.expenses,
    required this.nextIncome,
    required List<SavingChallenge> goals,
  })  : incomeOccurrences = List<ExpectedIncome>.unmodifiable(incomeOccurrences),
        goals = List<SavingChallenge>.unmodifiable(goals);

  final FinancialBalanceSnapshot balances;
  final List<ExpectedIncome> incomeOccurrences;
  final ExpenseMonthSnapshot expenses;
  final ExpectedIncome? nextIncome;
  final List<SavingChallenge> goals;

  int expectedIncomeMicros(FinancialUnit unit) {
    return incomeOccurrences
        .where((income) => income.unit == unit)
        .fold<int>(0, (sum, income) => sum + income.expectedAmountMicros);
  }

  int receivedIncomeMicros(FinancialUnit unit) {
    return incomeOccurrences
        .where((income) => income.unit == unit && income.isReceived)
        .fold<int>(
          0,
          (sum, income) => sum + (income.receivedAmountMicros ?? 0),
        );
  }

  int plannedExpenseMicros(FinancialUnit unit) =>
      expenses.plannedTotalsMicros[unit] ?? 0;

  int actualExpenseMicros(FinancialUnit unit) =>
      expenses.actualTotalsMicros[unit] ?? 0;
}

class HomeDashboardService {
  HomeDashboardService({
    RecurringIncomeService? incomeService,
    BalanceValuationService? balanceService,
    ExpenseService? expenseService,
    ChallengeStorage? challengeStorage,
  })  : _incomeService = incomeService ?? RecurringIncomeService(),
        _balanceService = balanceService ?? BalanceValuationService(),
        _expenseService = expenseService ?? ExpenseService(),
        _challengeStorage = challengeStorage ?? ChallengeStorage();

  final RecurringIncomeService _incomeService;
  final BalanceValuationService _balanceService;
  final ExpenseService _expenseService;
  final ChallengeStorage _challengeStorage;

  Future<HomeDashboardSnapshot> loadMonth(DateTime month) async {
    final List<ExpectedIncome> incomeOccurrences =
        await _incomeService.loadMonth(month);
    final FinancialBalanceSnapshot balances =
        await _balanceService.loadSnapshot();
    final ExpenseMonthSnapshot expenses = await _expenseService.loadMonth(month);
    final ExpectedIncome? nextIncome = await _incomeService.loadNextExpected();
    final List<SavingChallenge> goals =
        List<SavingChallenge>.from(await _challengeStorage.loadChallenges());

    goals.sort(_compareGoals);

    return HomeDashboardSnapshot(
      balances: balances,
      incomeOccurrences: incomeOccurrences,
      expenses: expenses,
      nextIncome: nextIncome,
      goals: goals,
    );
  }

  static int _compareGoals(SavingChallenge a, SavingChallenge b) {
    if (a.isComplete != b.isComplete) {
      return a.isComplete ? 1 : -1;
    }

    final bool aOverdue = a.isDeadlineOverdue();
    final bool bOverdue = b.isDeadlineOverdue();
    if (aOverdue != bOverdue) {
      return aOverdue ? -1 : 1;
    }

    final DateTime? aDeadline = a.deadline;
    final DateTime? bDeadline = b.deadline;
    if (aDeadline != null && bDeadline != null) {
      final int deadlineCompare = aDeadline.compareTo(bDeadline);
      if (deadlineCompare != 0) return deadlineCompare;
    } else if (aDeadline != null) {
      return -1;
    } else if (bDeadline != null) {
      return 1;
    }

    final int progressCompare = b.progress.compareTo(a.progress);
    if (progressCompare != 0) return progressCompare;
    return a.name.compareTo(b.name);
  }
}
