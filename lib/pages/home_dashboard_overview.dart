import 'package:flutter/material.dart';

import '../models/expected_income.dart';
import '../models/financial_event.dart';
import '../models/saving_challenge.dart';
import '../services/home_dashboard_service.dart';
import '../ui/app_theme.dart';
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
        LayoutBuilder(
          builder: (context, constraints) {
            final Widget monthControl = _MonthControl(
              label: monthLabel,
              onPrevious: onPreviousMonth,
              onNext: onNextMonth,
            );

            if (constraints.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const UxPageHeader(
                    title: 'مساحتك المالية',
                    subtitle: 'أهم ما تحتاج معرفته الآن، والباقي عند الطلب',
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: monthControl,
                  ),
                ],
              );
            }

            return UxPageHeader(
              title: 'مساحتك المالية',
              subtitle: 'أهم ما تحتاج معرفته الآن، والباقي عند الطلب',
              trailing: monthControl,
            );
          },
        ),
        const SizedBox(height: 18),
        _NetWorthCard(snapshot: snapshot),
        const SizedBox(height: 14),
        _MonthPulse(snapshot: snapshot),
        if (snapshot.nextIncome != null || focusGoal != null) ...<Widget>[
          const SizedBox(height: 22),
          const UxSectionHeader(
            title: 'القادم',
            subtitle: 'الشيء التالي الذي يستحق انتباهك',
          ),
          const SizedBox(height: 10),
          if (snapshot.nextIncome != null)
            _UpcomingIncomeCard(income: snapshot.nextIncome!),
          if (snapshot.nextIncome != null && focusGoal != null)
            const SizedBox(height: 10),
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
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: 'الشهر السابق',
            onPressed: onPrevious,
            icon: const Icon(
              Icons.chevron_right_rounded,
              textDirection: TextDirection.ltr,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 98),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          IconButton(
            tooltip: 'الشهر التالي',
            onPressed: onNext,
            icon: const Icon(
              Icons.chevron_left_rounded,
              textDirection: TextDirection.ltr,
            ),
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
    final double? estimatedTotal = snapshot.balances.estimatedTotalUsd;
    final int syp = snapshot.balances.balanceMicros(FinancialUnit.syp);
    final int usd = snapshot.balances.balanceMicros(FinancialUnit.usd);
    final int gold = snapshot.balances.balanceMicros(FinancialUnit.goldGram);
    final int sypNew = snapshot.balances.balanceMicros(FinancialUnit.sypNew);

    return UxHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'إجمالي القيمة التقريبية',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                ),
              ),
              const UxStatusPill(
                label: 'مباشر',
                icon: Icons.bolt_rounded,
                color: Color(0xFFF2D082),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            estimatedTotal == null
                ? 'التقدير غير مكتمل'
                : FinancialFormat.estimatedUsd(estimatedTotal),
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            estimatedTotal == null
                ? 'أدخل سعر الصرف وسعر الذهب من الإعدادات لعرض الإجمالي.'
                : 'قيمة تقريبية للعرض، لا تغيّر أرصدتك الفعلية.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.72),
                ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _HeroAssetChip(
                icon: Icons.payments_rounded,
                label: 'ليرة',
                value: FinancialFormat.assetBalance(syp, FinancialUnit.syp),
              ),
              _HeroAssetChip(
                icon: Icons.attach_money_rounded,
                label: 'دولار',
                value: FinancialFormat.assetBalance(usd, FinancialUnit.usd),
              ),
              if (gold != 0)
                _HeroAssetChip(
                  icon: Icons.diamond_rounded,
                  label: 'ذهب',
                  value: FinancialFormat.assetBalance(
                    gold,
                    FinancialUnit.goldGram,
                  ),
                ),
              if (sypNew != 0)
                _HeroAssetChip(
                  icon: Icons.currency_exchange_rounded,
                  label: 'ليرة جديدة',
                  value: FinancialFormat.assetBalance(
                    sypNew,
                    FinancialUnit.sypNew,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroAssetChip extends StatelessWidget {
  const _HeroAssetChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.86)),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.72),
                ),
          ),
          const SizedBox(width: 7),
          Text(
            value,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                ),
          ),
        ],
      ),
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
    final double expenseProgress =
        plannedSyp <= 0 ? 0 : (actualSyp / plannedSyp).clamp(0.0, 1.0).toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool wide = constraints.maxWidth >= 620;
        final double width =
            wide ? (constraints.maxWidth - 20) / 3 : constraints.maxWidth;

        final List<Widget> cards = <Widget>[
          _PulseCard(
            width: width,
            icon: Icons.south_west_rounded,
            tone: Theme.of(context).colorScheme.primary,
            title: 'دخل الليرة',
            primary:
                FinancialFormat.assetBalance(receivedSyp, FinancialUnit.syp),
            secondary:
                'من ${FinancialFormat.assetBalance(expectedSyp, FinancialUnit.syp)}',
          ),
          _PulseCard(
            width: width,
            icon: Icons.north_east_rounded,
            tone: AppPalette.gold,
            title: 'مصروف الشهر',
            primary:
                FinancialFormat.assetBalance(actualSyp, FinancialUnit.syp),
            secondary:
                'من ${FinancialFormat.assetBalance(plannedSyp, FinancialUnit.syp)}',
            progress: plannedSyp > 0 ? expenseProgress : null,
          ),
          _PulseCard(
            width: width,
            icon: Icons.attach_money_rounded,
            tone: const Color(0xFF4C6E9C),
            title: 'دخل الدولار',
            primary:
                FinancialFormat.assetBalance(receivedUsd, FinancialUnit.usd),
            secondary:
                'من ${FinancialFormat.assetBalance(expectedUsd, FinancialUnit.usd)}',
          ),
        ];

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards,
        );
      },
    );
  }
}

class _PulseCard extends StatelessWidget {
  const _PulseCard({
    required this.width,
    required this.icon,
    required this.tone,
    required this.title,
    required this.primary,
    required this.secondary,
    this.progress,
  });

  final double width;
  final IconData icon;
  final Color tone;
  final String title;
  final String primary;
  final String secondary;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return SizedBox(
      width: width,
      child: UxSoftCard(
        tone: tone,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                UxIconBadge(
                  icon: icon,
                  tone: tone,
                  size: 38,
                  iconSize: 19,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Text(
              primary,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 2),
            Text(
              secondary,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
            if (progress != null) ...<Widget>[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                color: tone,
                backgroundColor: tone.withValues(alpha: 0.12),
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

    return UxActionTile(
      icon: Icons.event_available_rounded,
      title: title,
      subtitle: 'موعده ${FinancialFormat.date(income.scheduledDate)}',
      onTap: null,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            FinancialFormat.assetBalance(
              income.expectedAmountMicros,
              income.unit,
            ),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 2),
          Text(
            'دخل قادم',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _FocusGoalCard extends StatelessWidget {
  const _FocusGoalCard({required this.goal});

  final SavingChallenge goal;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool overdue = goal.isDeadlineOverdue();
    final String deadline = goal.deadline == null
        ? 'بدون موعد نهائي'
        : overdue
            ? 'متأخر منذ ${FinancialFormat.date(goal.deadline!)}'
            : 'الموعد ${FinancialFormat.date(goal.deadline!)}';

    return UxSoftCard(
      tone: overdue ? colors.error : colors.primary,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              UxIconBadge(
                icon: overdue ? Icons.warning_amber_rounded : Icons.flag_rounded,
                tone: overdue ? colors.error : colors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      goal.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      deadline,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: overdue
                                ? colors.error
                                : colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              UxStatusPill(
                label: FinancialFormat.progress(goal.progress),
                color: overdue ? colors.error : colors.primary,
              ),
            ],
          ),
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: goal.progress,
            minHeight: 8,
            color: overdue ? colors.error : colors.primary,
            backgroundColor:
                (overdue ? colors.error : colors.primary).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(99),
          ),
          const SizedBox(height: 8),
          Text(
            '${ChallengeFormat.amount(goal.savedAmount, goal.currency)} من ${ChallengeFormat.amount(goal.targetAmount, goal.currency)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
