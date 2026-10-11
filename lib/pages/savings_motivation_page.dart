import 'dart:async';

import 'package:flutter/material.dart';

import '../models/financial_event.dart';
import '../models/saving_challenge.dart';
import '../services/financial_ledger_storage.dart';
import '../services/savings_motivation_service.dart';
import '../ui/ux_components.dart';
import '../utils/financial_format.dart';
import 'goal_forecast_page.dart';

/// Encouragement backed by existing goal reservations and completed
/// Savings history only. Badges are labels, never money or bank accounts.
class SavingsMotivationPage extends StatefulWidget {
  const SavingsMotivationPage({
    super.key,
    this.initialGoalId,
    this.service,
  });

  final String? initialGoalId;
  final SavingsMotivationService? service;

  @override
  State<SavingsMotivationPage> createState() => _SavingsMotivationPageState();
}

class _SavingsMotivationPageState extends State<SavingsMotivationPage> {
  late final SavingsMotivationService _service;
  SavingsMotivationSnapshot? _snapshot;
  StreamSubscription<void>? _changes;
  int _generation = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? SavingsMotivationService();
    _changes = FinancialLedgerStorage.changes.listen((_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _generation++;
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final id = ++_generation;
    try {
      final snapshot = await _service.load();
      if (!mounted || id != _generation) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || id != _generation) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل تقدم الادخار. حاول مجدداً.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final entries = widget.initialGoalId == null
        ? snapshot?.insights ?? <SavingsMotivationInsight>[]
        : (snapshot?.insights ?? <SavingsMotivationInsight>[])
            .where((e) => e.goal.id == widget.initialGoalId).toList();
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تقدم الادخار الحقيقي'),
        actions: <Widget>[
          IconButton(
            tooltip: 'تحديث تقدم الادخار',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
            children: <Widget>[
              const UxSectionHeader(
                title: 'إنجازات مبنية على أموال فعلية',
                subtitle: 'ما في نقاط أو أوسمة بتضيف أموال جديدة',
              ),
              const SizedBox(height: 12),
              UxSoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text(
                      'التقدم بيجي فقط من الأموال المحجوزة لهدفك '
                      'داخل صندوق الادخار الحقيقي. الخانات القديمة '
                      'غير الموثقة ما بتمنحك شارات إنجاز.',
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'المقارنة بين الوتيرة والخطة وتواريخ الوصول تقديرية '
                      'وبتتغير مع الاستلام والمصاريف. كل هدف معروض '
                      'كسيناريو مستقل، مو وعد باستخدام نفس الراتب عدة مرات.',
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'تذكيرات موعد الهدف اختيارية من الإعدادات، '
                      'ومو دليل على استلام مال أو إنجاز دفعة.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (_loading && snapshot == null)
                const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot == null) ...<Widget>[
                const SizedBox(height: 16),
                Text(_error ?? 'لا يمكن عرض التقدم.',
                    style: TextStyle(color: colors.error)),
                TextButton(
                  onPressed: _refresh,
                  child: const Text('إعادة المحاولة'),
                ),
              ] else ...<Widget>[
                if (_loading) const LinearProgressIndicator(minHeight: 3),
                if (_error != null)
                  Text(_error!, style: TextStyle(color: colors.error)),
                const SizedBox(height: 15),
                if (entries.isEmpty)
                  const UxSoftCard(
                    child: Text(
                      'ما في أهداف مطابقة. أضف هدفاً وخصصله من الادخار الحقيقي.',
                    ),
                  ),
                for (final item in entries) ...<Widget>[
                  _MotivationGoalCard(insight: item),
                  const SizedBox(height: 12),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MotivationGoalCard extends StatelessWidget {
  const _MotivationGoalCard({required this.insight});

  final SavingsMotivationInsight insight;

  static FinancialUnit _unit(ChallengeCurrency unit) => switch (unit) {
    ChallengeCurrency.usd => FinancialUnit.usd,
    ChallengeCurrency.syp => FinancialUnit.syp,
    ChallengeCurrency.sypNew => FinancialUnit.sypNew,
  };

  @override
  Widget build(BuildContext context) {
    final goal = insight.goal;
    final colors = Theme.of(context).colorScheme;
    final unit = _unit(goal.currency);
    final dateShift = insight.observedVsPlanDays;
    final amount = goal.backedAmountMicros ?? 0;
    final target = (goal.targetAmount * LedgerEntry.microsPerUnit).round();
    final next = insight.nextMilestone;
    final nextAmount = next == null ? null : (target * next ~/ 100);
    final remainingToMilestone = nextAmount == null
        ? 0 : (nextAmount - amount).clamp(0, target).toInt();

    return UxSoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(goal.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'المبلغ المثبّت: ${FinancialFormat.assetBalance(amount, unit)} '
            'من ${goal.currency.formatAmount(goal.targetAmount)}',
          ),
          const SizedBox(height: 9),
          LinearProgressIndicator(
            value: goal.verifiedProgress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(99),
          ),
          const SizedBox(height: 8),
          if (!insight.verified)
            Text(insight.guidance, style: TextStyle(color: colors.error))
          else ...<Widget>[
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: <Widget>[
                for (final threshold in SavingsMotivationService.milestones)
                  Chip(
                    avatar: Icon(
                      insight.achievedMilestones.contains(threshold)
                        ? Icons.verified_rounded
                        : Icons.lock_outline_rounded,
                      size: 17,
                    ),
                    label: Text('$threshold٪ '
                      '${insight.achievedMilestones.contains(threshold)
                        ? 'مثبّت' : 'غير مكتمل'}'),
                  ),
              ],
            ),
            if (next != null) ...<Widget>[
              const SizedBox(height: 7),
              Text(
                'المحطة التالية: $next٪ — '
                'باقي ${FinancialFormat.assetBalance(
                  remainingToMilestone, unit,
                )} لازم يتخصّص فعلياً للهدف.',
              ),
            ],
            const SizedBox(height: 9),
            Text(insight.guidance),
            if (insight.verifiedStreakMonths >= 2) ...<Widget>[
              const SizedBox(height: 9),
              Text(
                'سلسلة فعلية للصندوق: '
                '${insight.verifiedStreakMonths} أشهر مكتملة متتالية '
                'بصافي دخل ادخاري موجب بنفس العملة (مو لهذا الهدف لحاله).',
                style: TextStyle(color: colors.primary),
              ),
            ] else ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'ما في سلسلة أشهر مثبتة كفاية حتى نعرض شارة استمرارية.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (dateShift != null) ...<Widget>[
              const SizedBox(height: 9),
              Text(
                dateShift == 0
                  ? 'تاريخ الوصول المشروط حسب الواقع والخطة متطابق.'
                  : dateShift < 0
                    ? 'الوتيرة المرصودة ممكن توصلنا قبل الخطة الحالية '
                        'بحوالي ${-dateShift} يوم.'
                    : 'الوتيرة المرصودة ممكن تؤخر الوصول عن الخطة '
                        'بحوالي $dateShift يوم.',
              ),
            ] else if (!insight.complete) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'ما في مقارنة موثوقة بين تاريخ الخطة والفعلي حتى الآن.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
          const SizedBox(height: 11),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => GoalForecastPage(initialGoalId: goal.id),
              ),
            ),
            icon: const Icon(Icons.query_stats_rounded),
            label: const Text('عرض التوقعات والافتراضات'),
          ),
        ],
      ),
    );
  }
}
