import 'dart:async';

import 'package:flutter/material.dart';

import '../models/saving_challenge.dart';
import '../services/challenge_storage.dart';
import '../services/financial_ledger_storage.dart';
import '../services/goal_forecast_service.dart';
import '../ui/ux_components.dart';
import '../utils/financial_format.dart';
import 'goal_forecast_page.dart';
import 'savings_motivation_page.dart';

/// Read-only, front-page summary. An old checked cell never becomes assets or
/// verified progress merely because it is displayed in this widget.
class SavingsGoalsPreview extends StatefulWidget {
  const SavingsGoalsPreview({
    super.key,
    required this.onOpenGoals,
    this.forecastService,
    this.goalStorage,
  });

  final VoidCallback onOpenGoals;
  final GoalForecastService? forecastService;
  final ChallengeStorage? goalStorage;

  @override
  State<SavingsGoalsPreview> createState() => _SavingsGoalsPreviewState();
}

class _SavingsGoalsPreviewState extends State<SavingsGoalsPreview> {
  late final GoalForecastService _forecastService;
  late final ChallengeStorage _storage;
  StreamSubscription<void>? _changes;
  GoalForecastSnapshot? _forecast;
  List<SavingChallenge> _goals = const <SavingChallenge>[];
  bool _loading = true;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _forecastService = widget.forecastService ?? GoalForecastService();
    _storage = widget.goalStorage ?? ChallengeStorage();
    _changes = FinancialLedgerStorage.changes.listen((_) => _reload());
    _reload();
  }

  @override
  void dispose() {
    _generation++;
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    try {
      final goals = await _storage.loadChallenges();
      if (!mounted || generation != _generation) return;
      setState(() {
        _goals = goals;
        _loading = false;
        _error = null;
      });
      try {
        final forecast = await _forecastService.load();
        if (!mounted || generation != _generation) return;
        setState(() => _forecast = forecast);
      } catch (_) {
        // A missing salary plan or forecast must not hide real saved goals.
        if (mounted && generation == _generation) {
          setState(() => _forecast = null);
        }
      }
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل أهدافك الحالية. أعد المحاولة.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _goals.where((goal) => !goal.isVerifiedComplete).take(2);
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const UxSectionHeader(
          title: 'الأهداف وتوقع الوصول',
          subtitle: 'التقدم المثبّت فقط؛ التاريخ تقديري وليس مضموناً',
        ),
        const SizedBox(height: 9),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          UxSoftCard(child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(_error!),
              TextButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ))
        else if (_goals.isEmpty)
          UxSoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text('ما في أهداف بعد. أضف هدف وحدّد قديش بدك تحجزله من الادخار الحقيقي.'),
                const SizedBox(height: 9),
                FilledButton.icon(
                  onPressed: widget.onOpenGoals,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('إنشاء هدف'),
                ),
              ],
            ),
          )
        else ...<Widget>[
          for (final goal in items) ...<Widget>[
            UxSoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(child: Text(goal.name,
                        style: Theme.of(context).textTheme.titleMedium)),
                      Text('${(goal.verifiedProgress * 100).floor()}٪ موثّق'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: goal.verifiedProgress,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  const SizedBox(height: 8),
                  Text(goal.isBackingVerified
                      ? 'المبلغ المحجوز: ${goal.currency.formatAmount(goal.verifiedSavedAmount)}'
                      : 'خانات قديمة غير موثّقة، مو رصيد ادخار.'),
                  const SizedBox(height: 4),
                  if (!goal.isBackingVerified)
                    Text('لا يمكن تقدير وصول هدف بلا رصيد مثبّت.',
                      style: TextStyle(color: colors.error))
                  else
                    Text(_forecast?.forGoal(goal.id)?.planDate == null
                      ? 'موعد الوصول غير متاح من البيانات والخطة الحالية.'
                      : 'الوصول حسب الخطة: ${FinancialFormat.date(_forecast!.forGoal(goal.id)!.planDate!)} — مشروط'),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (items.isEmpty)
            const UxSoftCard(
              child: Text('كل أهدافك مكتملة بأموال ادخار مثبتة.'),
            ),
          OutlinedButton.icon(
            onPressed: widget.onOpenGoals,
            icon: const Icon(Icons.flag_outlined),
            label: const Text('إدارة كل أهداف الادخار'),
          ),
        ],
        const SizedBox(height: 7),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const GoalForecastPage(),
            ),
          ),
          icon: const Icon(Icons.query_stats_outlined),
          label: const Text('التوقعات والسيناريوهات'),
        ),
        const SizedBox(height: 7),
        TextButton.icon(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const SavingsMotivationPage(),
            ),
          ),
          icon: const Icon(Icons.verified_outlined),
          label: const Text('محطات التقدم الحقيقي'),
        ),
      ],
    );
  }
}
