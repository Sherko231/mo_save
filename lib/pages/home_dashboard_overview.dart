import 'package:flutter/material.dart';

import '../models/expected_income.dart';
import '../models/financial_event.dart';
import '../models/saving_challenge.dart';
import '../services/home_dashboard_service.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _DashboardHeader(
          title: '${_monthNames[month.month]} ${month.year}',
          onPreviousMonth: onPreviousMonth,
          onNextMonth: onNextMonth,
        ),
        const SizedBox(height: 12),
        _NetWorthHero(snapshot: snapshot),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final bool twoColumns = constraints.maxWidth >= 560;
            final double cardWidth = twoColumns
                ? (constraints.maxWidth - 10) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _MetricCard(
                  width: cardWidth,
                  icon: Icons.calendar_month_outlined,
                  title: 'الدخل المتوقع',
                  lines: _incomeLines(snapshot, received: false),
                ),
                _MetricCard(
                  width: cardWidth,
                  icon: Icons.task_alt,
                  title: 'الدخل المستلم',
                  lines: _incomeLines(snapshot, received: true),
                ),
                _MetricCard(
                  width: cardWidth,
                  icon: Icons.receipt_long_outlined,
                  title: 'مصاريف الشهر',
                  lines: _expenseLines(snapshot),
                ),
                _MetricCard(
                  width: cardWidth,
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'المتاح الآن',
                  lines: <_MetricLine>[
                    _MetricLine(
                      'نقد سوري',
                      FinancialFormat.assetBalance(
                        snapshot.balances.balanceMicros(FinancialUnit.syp),
                        FinancialUnit.syp,
                      ),
                    ),
                    _MetricLine(
                      'ادخار بالدولار',
                      FinancialFormat.assetBalance(
                        snapshot.balances.balanceMicros(FinancialUnit.usd),
                        FinancialUnit.usd,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _GoldSummary(snapshot: snapshot),
        if (snapshot.nextIncome != null) ...<Widget>[
          const SizedBox(height: 12),
          _UpcomingIncomeCard(income: snapshot.nextIncome!),
        ],
        const SizedBox(height: 18),
        _GoalSection(goals: snapshot.goals),
      ],
    );
  }

  static List<_MetricLine> _incomeLines(
    HomeDashboardSnapshot snapshot, {
    required bool received,
  }) {
    int amount(FinancialUnit unit) => received
        ? snapshot.receivedIncomeMicros(unit)
        : snapshot.expectedIncomeMicros(unit);

    return <_MetricLine>[
      _MetricLine(
        'الليرة السورية',
        FinancialFormat.assetBalance(
          amount(FinancialUnit.syp),
          FinancialUnit.syp,
        ),
      ),
      _MetricLine(
        'الدولار',
        FinancialFormat.assetBalance(
          amount(FinancialUnit.usd),
          FinancialUnit.usd,
        ),
      ),
    ];
  }

  static List<_MetricLine> _expenseLines(HomeDashboardSnapshot snapshot) {
    final List<_MetricLine> lines = <_MetricLine>[
      _MetricLine(
        'المخطط',
        FinancialFormat.assetBalance(
          snapshot.plannedExpenseMicros(FinancialUnit.syp),
          FinancialUnit.syp,
        ),
      ),
      _MetricLine(
        'المصروف فعلياً',
        FinancialFormat.assetBalance(
          snapshot.actualExpenseMicros(FinancialUnit.syp),
          FinancialUnit.syp,
        ),
      ),
    ];

    final int plannedUsd = snapshot.plannedExpenseMicros(FinancialUnit.usd);
    final int actualUsd = snapshot.actualExpenseMicros(FinancialUnit.usd);
    if (plannedUsd != 0 || actualUsd != 0) {
      lines.add(
        _MetricLine(
          'الدولار: مخطط / فعلي',
          '${FinancialFormat.assetBalance(plannedUsd, FinancialUnit.usd)} / '
          '${FinancialFormat.assetBalance(actualUsd, FinancialUnit.usd)}',
        ),
      );
    }
    return lines;
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.title,
    required this.onPreviousMonth,
    required this.onNextMonth,
  });

  final String title;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'لوحة التحكم',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 2),
              Text(title, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        IconButton(
          tooltip: 'الشهر السابق',
          onPressed: onPreviousMonth,
          icon: const Icon(Icons.chevron_right),
        ),
        IconButton(
          tooltip: 'الشهر التالي',
          onPressed: onNextMonth,
          icon: const Icon(Icons.chevron_left),
        ),
      ],
    );
  }
}

class _NetWorthHero extends StatelessWidget {
  const _NetWorthHero({required this.snapshot});

  final HomeDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final double? total = snapshot.balances.estimatedTotalUsd;
    final int sypNewMicros =
        snapshot.balances.balanceMicros(FinancialUnit.sypNew);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'القيمة الإجمالية التقريبية',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Text(
              total == null
                  ? 'التقدير غير مكتمل'
                  : FinancialFormat.estimatedUsd(total),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _SummaryChip(
                  icon: Icons.account_balance_wallet_outlined,
                  label: FinancialFormat.assetBalance(
                    snapshot.balances.balanceMicros(FinancialUnit.syp),
                    FinancialUnit.syp,
                  ),
                ),
                _SummaryChip(
                  icon: Icons.attach_money,
                  label: FinancialFormat.assetBalance(
                    snapshot.balances.balanceMicros(FinancialUnit.usd),
                    FinancialUnit.usd,
                  ),
                ),
                _SummaryChip(
                  icon: Icons.diamond_outlined,
                  label: FinancialFormat.assetBalance(
                    snapshot.balances.balanceMicros(FinancialUnit.goldGram),
                    FinancialUnit.goldGram,
                  ),
                ),
                if (sypNewMicros != 0)
                  _SummaryChip(
                    icon: Icons.currency_exchange,
                    label: FinancialFormat.assetBalance(
                      sypNewMicros,
                      FinancialUnit.sypNew,
                    ),
                  ),
              ],
            ),
            if (snapshot.balances.valuationWarnings.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                snapshot.balances.valuationWarnings.join(' '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.icon,
    required this.title,
    required this.lines,
  });

  final double width;
  final IconData icon;
  final String title;
  final List<_MetricLine> lines;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...lines.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          line.label,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          line.value,
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ],
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

class _GoldSummary extends StatelessWidget {
  const _GoldSummary({required this.snapshot});

  final HomeDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final int grams = snapshot.balances.balanceMicros(FinancialUnit.goldGram);
    final double? estimate = snapshot.balances.estimatedGoldUsd;

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.diamond_outlined)),
        title: const Text('الذهب'),
        subtitle: Text(
          estimate == null
              ? 'أدخل سعر غرام الذهب في الإعدادات لعرض القيمة التقديرية.'
              : 'القيمة التقديرية ${FinancialFormat.estimatedUsd(estimate)}',
        ),
        trailing: Text(
          FinancialFormat.assetBalance(grams, FinancialUnit.goldGram),
          style: Theme.of(context).textTheme.titleMedium,
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
        ? 'راتب الخميس'
        : 'راتب الشهر';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            const CircleAvatar(child: Icon(Icons.event_available_outlined)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'الدخل القادم',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$title • ${FinancialFormat.date(income.scheduledDate)}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            ),
            Text(
              FinancialFormat.assetBalance(
                income.expectedAmountMicros,
                income.unit,
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalSection extends StatelessWidget {
  const _GoalSection({required this.goals});

  final List<SavingChallenge> goals;

  @override
  Widget build(BuildContext context) {
    final List<SavingChallenge> visibleGoals =
        goals.take(3).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(Icons.flag_outlined, size: 21),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'أهداف الادخار',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (goals.isNotEmpty)
              Text(
                '${goals.where((goal) => goal.isComplete).length}/${goals.length} مكتملة',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (visibleGoals.isEmpty)
          const Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'لا توجد أهداف ادخار بعد. أنشئ هدفاً من تبويب التحديات.',
              ),
            ),
          )
        else
          ...visibleGoals.map(
            (goal) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _GoalCard(goal: goal),
            ),
          ),
        if (goals.length > visibleGoals.length)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'يوجد ${goals.length - visibleGoals.length} أهداف أخرى في تبويب التحديات.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal});

  final SavingChallenge goal;

  @override
  Widget build(BuildContext context) {
    final DateTime? deadline = goal.deadline;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    goal.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  FinancialFormat.progress(goal.progress),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: goal.progress),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${ChallengeFormat.amount(goal.savedAmount, goal.currency)} من '
                    '${ChallengeFormat.amount(goal.targetAmount, goal.currency)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (deadline != null)
                  Text(
                    goal.isDeadlineOverdue()
                        ? 'متأخر • ${FinancialFormat.date(deadline)}'
                        : 'حتى ${FinancialFormat.date(deadline)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _MetricLine {
  const _MetricLine(this.label, this.value);

  final String label;
  final String value;
}
