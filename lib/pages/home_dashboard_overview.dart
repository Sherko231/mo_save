import 'package:flutter/material.dart';

import '../models/expected_income.dart';
import '../models/financial_event.dart';
import '../models/saving_challenge.dart';
import '../services/home_dashboard_service.dart';
import '../ui/ux_components.dart';
import '../utils/challenge_format.dart';
import '../utils/financial_format.dart';

class HomeDashboardOverview extends StatelessWidget {
  const HomeDashboardOverview({
    super.key,
    required this.snapshot,
    required this.month,
    required this.onPreviousMonth,
    required this.onNextMonth,
  });

  final HomeDashboardSnapshot snapshot;
  final DateTime month;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;

  static const List<String> _monthNames = <String>[
    '',
    'كانون الثاني',
    'شباط',
    'آذار',
    'نيسان',
    'أيار',
    'حزيران',
    'تموز',
    'آب',
    'أيلول',
    'تشرين الأول',
    'تشرين الثاني',
    'كانون الأول',
  ];

  @override
  Widget build(BuildContext context) {
    final String monthLabel = '${_monthNames[month.month]} ${month.year}';
    final SavingChallenge? focusGoal =
        snapshot.goals.where((goal) => !goal.isComplete).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        UxPageHeader(
          title: 'نظرة عامة',
          subtitle: 'أهم أرقامك بدون تفاصيل زائدة',
          trailing: _MonthControl(
            label: monthLabel,
            onPrevious: onPreviousMonth,
            onNext: onNextMonth,
          ),
        ),
        const SizedBox(height: 16),
        _NetWorthCard(snapshot: snapshot),
        const SizedBox(height: 12),
        _MonthPulse(snapshot: snapshot),
        if (snapshot.nextIncome != null || focusGoal != null) ...<Widget>[
          const SizedBox(height: 16),
          const UxSectionHeader(
            title: 'التالي',
            subtitle: 'ما يستحق انتباهك قريباً',
          ),
          const SizedBox(height: 8),
          if (snapshot.nextIncome != null)
            _UpcomingIncomeCard(income: snapshot.nextIncome!),
          if (snapshot.nextIncome != null && focusGoal != null)
            const SizedBox(height: 8),
          if (focusGoal != null) _FocusGoalCard(goal: focusGoal),
        ],
      ],
    );
  }
}

class _MonthControl extends StatelessWidget {
  const _MonthControl({
    required this.label,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: 'الشهر السابق',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          IconButton(
            tooltip: 'الشهر التالي',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
        ],
      ),
    );
  }
}

class _NetWorthCard extends StatelessWidget {
  const _NetWorthCard({required this.snapshot});

  final HomeDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final double? estimatedTotal = snapshot.balances.estimatedTotalUsd;
    final int syp = snapshot.balances.balanceMicros(FinancialUnit.syp);
    final int usd = snapshot.balances.balanceMicros(FinancialUnit.usd);
    final int gold = snapshot.balances.balanceMicros(FinancialUnit.goldGram);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'قيمة أموالك التقريبية',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.onPrimaryContainer,
                ),
          ),
          const SizedBox(height: 5),
          Text(
            estimatedTotal == null
                ? 'التقدير غير مكتمل'
                : FinancialFormat.estimatedUsd(estimatedTotal),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 18),
          _HeroBalanceRow(
            label: 'الليرة',
            value: FinancialFormat.assetBalance(syp, FinancialUnit.syp),
          ),
          const SizedBox(height: 8),
          _HeroBalanceRow(
            label: 'الدولار',
            value: FinancialFormat.assetBalance(usd, FinancialUnit.usd),
          ),
          if (gold != 0) ...<Widget>[
            const SizedBox(height: 8),
            _HeroBalanceRow(
              label: 'الذهب',
              value: FinancialFormat.assetBalance(
                gold,
                FinancialUnit.goldGram,
              ),
            ),
          ],
          if (snapshot.balances.valuationWarnings.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            Text(
              snapshot.balances.valuationWarnings.first,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onPrimaryContainer.withValues(alpha: 0.8),
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroBalanceRow extends StatelessWidget {
  const _HeroBalanceRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final Color color = Theme.of(context).colorScheme.onPrimaryContainer;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _MonthPulse extends StatelessWidget {
  const _MonthPulse({required this.snapshot});

  final HomeDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final int expectedSyp = snapshot.expectedIncomeMicros(FinancialUnit.syp);
    final int receivedSyp = snapshot.receivedIncomeMicros(FinancialUnit.syp);
    final int expectedUsd = snapshot.expectedIncomeMicros(FinancialUnit.usd);
    final int receivedUsd = snapshot.receivedIncomeMicros(FinancialUnit.usd);
    final int plannedSyp = snapshot.plannedExpenseMicros(FinancialUnit.syp);
    final int actualSyp = snapshot.actualExpenseMicros(FinancialUnit.syp);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('هذا الشهر', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            UxStat(
              icon: Icons.south_west_rounded,
              label: 'دخل ليرة مستلم / متوقع',
              value:
                  '${FinancialFormat.assetBalance(receivedSyp, FinancialUnit.syp)} / ${FinancialFormat.assetBalance(expectedSyp, FinancialUnit.syp)}',
            ),
            if (expectedUsd != 0 || receivedUsd != 0) ...<Widget>[
              const SizedBox(height: 10),
              UxStat(
                icon: Icons.attach_money_rounded,
                label: 'دخل دولار مستلم / متوقع',
                value:
                    '${FinancialFormat.assetBalance(receivedUsd, FinancialUnit.usd)} / ${FinancialFormat.assetBalance(expectedUsd, FinancialUnit.usd)}',
              ),
            ],
            const SizedBox(height: 10),
            UxStat(
              icon: Icons.north_east_rounded,
              label: 'مصروف فعلي / مخطط',
              value:
                  '${FinancialFormat.assetBalance(actualSyp, FinancialUnit.syp)} / ${FinancialFormat.assetBalance(plannedSyp, FinancialUnit.syp)}',
            ),
            if (plannedSyp > 0) ...<Widget>[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: (actualSyp / plannedSyp).clamp(0.0, 1.0).toDouble(),
                minHeight: 7,
                borderRadius: BorderRadius.circular(99),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UpcomingIncomeCard extends StatelessWidget {
  const _UpcomingIncomeCard({required this.income});

  final ExpectedIncome income;

  @override
  Widget build(BuildContext context) {
    final String title = income.kind == RecurringIncomeKind.weeklySyp
        ? 'راتب الأسبوع'
        : 'راتب الشهر';

    return Card(
      child: ListTile(
        minTileHeight: 68,
        leading: const Icon(Icons.event_available_outlined),
        title: Text(title),
        subtitle: Text(FinancialFormat.date(income.scheduledDate)),
        trailing: Text(
          FinancialFormat.assetBalance(
            income.expectedAmountMicros,
            income.unit,
          ),
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
    );
  }
}

class _FocusGoalCard extends StatelessWidget {
  const _FocusGoalCard({required this.goal});

  final SavingChallenge goal;

  @override
  Widget build(BuildContext context) {
    final String deadline = goal.deadline == null
        ? 'بدون موعد نهائي'
        : goal.isDeadlineOverdue()
            ? 'متأخر منذ ${FinancialFormat.date(goal.deadline!)}'
            : 'الموعد ${FinancialFormat.date(goal.deadline!)}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.flag_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    goal.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  FinancialFormat.progress(goal.progress),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: goal.progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(99),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${ChallengeFormat.amount(goal.savedAmount, goal.currency)} من ${ChallengeFormat.amount(goal.targetAmount, goal.currency)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Text(deadline, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
