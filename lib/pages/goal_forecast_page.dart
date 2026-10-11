import 'dart:async';

import 'package:flutter/material.dart';

import '../models/financial_event.dart';
import '../models/saving_challenge.dart';
import '../services/financial_ledger_storage.dart';
import '../services/goal_forecast_service.dart';
import '../ui/ux_components.dart';
import '../utils/financial_format.dart';

/// An advisory planning view. Does not modify funds, goal checkmarks,
/// expected salary settings, budgets or historical receipts.
class GoalForecastPage extends StatefulWidget {
  const GoalForecastPage({
    super.key,
    this.initialGoalId,
    this.service,
  });

  final String? initialGoalId;
  final GoalForecastService? service;

  @override
  State<GoalForecastPage> createState() => _GoalForecastPageState();
}

class _GoalForecastPageState extends State<GoalForecastPage> {
  late final GoalForecastService _service;
  StreamSubscription<void>? _changes;
  GoalForecastSnapshot? _snapshot;
  bool _loading = true;
  String? _error;
  int _generation = 0;
  bool _customUsd = false;
  double _usdPercentage = 50;
  bool _hypotheticalFx = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? GoalForecastService();
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
    final request = ++_generation;
    try {
      final result = await _service.load(
        usdShareOverride: _customUsd ? _usdPercentage / 100 : null,
        includeHypotheticalSypToUsd: _hypotheticalFx,
      );
      if (!mounted || request != _generation) return;
      setState(() {
        _snapshot = result;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || request != _generation) return;
      setState(() {
        _loading = false;
        _error = 'تعذر حساب السيناريو. تحقق من الراتب والخطط والمحفظة.';
      });
    }
  }

  static FinancialUnit _unit(SavingChallenge goal) => switch (goal.currency) {
    ChallengeCurrency.usd => FinancialUnit.usd,
    ChallengeCurrency.syp => FinancialUnit.syp,
    ChallengeCurrency.sypNew => FinancialUnit.sypNew,
  };

  static String _date(DateTime? date) =>
      date == null ? 'لا توجد بيانات كافية لتحديد تاريخ'
      : FinancialFormat.date(date);

  @override
  Widget build(BuildContext context) {
    final report = _snapshot;
    final colors = Theme.of(context).colorScheme;
    final projected = report?.projections ?? <GoalProjection>[];
    final selectedGoal = widget.initialGoalId;
    final goals = selectedGoal == null
      ? projected
      : projected.where((p) => p.goal.id == selectedGoal).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('توقعات أهداف الادخار'),
        actions: <Widget>[
          IconButton(
            tooltip: 'إعادة الحساب',
            onPressed: () {
              setState(() => _loading = true);
              _reload();
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 42),
            children: <Widget>[
              const UxSectionHeader(
                title: 'متى ممكن أوصل لهدفي؟',
                subtitle: 'تقديرات مشروطة، مو ضمان دخل أو تاريخ وصول',
              ),
              const SizedBox(height: 10),
              UxSoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text(
                      'نقارن مسارين: الخطة من الراتب ومواعيده والفواتير '
                      'المجدولة، والفعلي من صافي حركة الادخار بأشهر مكتملة. '
                      'المبالغ المحجوزة للأهداف هي نقطة البداية، وما منضيف '
                      'أموال حالية حرة تلقائياً لأي هدف.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'كل تقدير يفترض تخصيص كامل وتيرة الادخار المستقبلية '
                      'لهدف واحد فقط. لا تجمع تواريخ عدة أهداف وكأن نفس '
                      'الراتب رح ينصرف عليها كلها.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              UxSoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _customUsd,
                      title: const Text('افتراض نسبة ادخار بالدولار'),
                      subtitle: const Text(
                        'بدون اختيارك نستخدم نسبة آخر راتب دولار مستلم '
                        'فعلياً. إذا ما في استلام، ما منفترض الراتب كله ادخار.',
                      ),
                      onChanged: (value) {
                        setState(() {
                          _customUsd = value;
                          if (value && report?.usdShare != null) {
                            _usdPercentage = report!.usdShare! * 100;
                          }
                          _loading = true;
                        });
                        _reload();
                      },
                    ),
                    if (_customUsd) ...<Widget>[
                      Text('الادخار المفترض: ${_usdPercentage.round()}٪ من الراتب الشهري'),
                      Slider(
                        value: _usdPercentage,
                        min: 0,
                        max: 100,
                        divisions: 100,
                        label: '${_usdPercentage.round()}٪',
                        onChanged: (value) =>
                            setState(() => _usdPercentage = value),
                        onChangeEnd: (_) {
                          setState(() => _loading = true);
                          _reload();
                        },
                      ),
                    ],
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _hypotheticalFx,
                      title: const Text('سيناريو تبديل فائض الليرة إلى دولار'),
                      subtitle: const Text(
                        'اختياري فقط وبالسعر المرجعي الحالي؛ لا ينفّذ '
                        'تحويل عملة ولا يحجز المال، ولا يوجد تحويل لليرة الجديدة.',
                      ),
                      onChanged: (value) {
                        setState(() {
                          _hypotheticalFx = value;
                          _loading = true;
                        });
                        _reload();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (_loading && report == null)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (report == null)
                UxSoftCard(
                  child: Column(
                    children: <Widget>[
                      Text(_error ?? 'لا يمكن حساب التوقع حالياً.',
                        style: TextStyle(color: colors.error)),
                      TextButton(
                        onPressed: _reload,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                )
              else ...<Widget>[
                if (_loading)
                  const LinearProgressIndicator(minHeight: 3),
                if (_error != null)
                  Text(_error!, style: TextStyle(color: colors.error)),
                UxSoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        report.usdShareSource == UsdSavingAssumption.unavailable
                          ? 'خطة ادخار الدولار: غير معروفة لغياب توزيع راتب مستلم.'
                          : 'نسبة الدولار بالسيناريو: '
                              '${((report.usdShare ?? 0) * 100).round()}٪ '
                              '${report.usdShareSource ==
                                UsdSavingAssumption.userDefined
                                  ? '(افتراض أدخلته أنت)'
                                  : '(من توزيع آخر راتب مستلم)'}',
                      ),
                      const SizedBox(height: 5),
                      Text(
                        report.assumedSypPerUsd != null
                          ? 'تحويل افتراضي فقط: '
                              '${FinancialFormat.referenceRate(report.assumedSypPerUsd!)} ل.س/دولار.'
                          : _hypotheticalFx
                            ? 'لا يمكن تطبيق سيناريو الصرف بدون سعر مرجعي موجب.'
                            : 'لا تحويل افتراضي بين العملات.',
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'وتيرة الفعلي محسوبة من ${report.observedMonths} '
                        'أشهر تقويمية مكتملة (الحد الأدنى شهران).',
                      ),
                      if (report.months.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          'الشهر القادم: ${report.months.first.weeklyPaydays} '
                          'مواعيد راتب أسبوعي، '
                          'ادخار ليرة مخطط '
                          '${FinancialFormat.assetBalance(
                            report.months.first.sypPlannedSavingsMicros,
                            FinancialUnit.syp,
                          )}، '
                          'فواتير ليرة مخططة '
                          '${FinancialFormat.assetBalance(
                            report.months.first.sypPlannedBillsMicros,
                            FinancialUnit.syp,
                          )}. '
                          '${report.months.first.monthlyUsdPayday == null
                            ? 'ما في راتب دولار مجدول.'
                            : 'يوم راتب الدولار المتوقع: '
                              '${FinancialFormat.date(report.months.first.monthlyUsdPayday!)}.'}',
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (goals.isEmpty)
                  const UxSoftCard(
                    child: Text('ما في أهداف مناسبة للعرض. أضف هدف ادخار أولاً.'),
                  ),
                for (final forecast in goals) ...<Widget>[
                  _ForecastGoalCard(forecast: forecast),
                  const SizedBox(height: 12),
                ],
                Text(
                  'الرواتب هنا افتراض مستقبلي مش دخل مؤكد، والفواتير المخططة '
                  'ليست مدفوعة. أي تأخير بالاستلام أو مصروف زائد أو تغيير '
                  'بتوزيع الراتب بيغير التاريخ. التقدير للشهر بنهايته، '
                  'ومحدود بخمس سنوات؛ إذا الوتيرة صفر أو سالبة ما في موعد. '
                  'ما في جمع آلي بين العملات ولا ادّعاء ربح من تغير أسعار الذهب.',
                  style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ForecastGoalCard extends StatelessWidget {
  const _ForecastGoalCard({required this.forecast});

  final GoalProjection forecast;

  static String _date(DateTime? date) =>
      date == null ? 'غير قابل للتحديد من المعطيات'
          : FinancialFormat.date(date);

  @override
  Widget build(BuildContext context) {
    final goal = forecast.goal;
    final unit = _GoalForecastPageState._unit(goal);
    final colors = Theme.of(context).colorScheme;
    final compare = forecast.planVsObservedMicros;
    return UxSoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(goal.name,
            style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 5),
          Text(
            'المثبّت: ${FinancialFormat.assetBalance(
              goal.backedAmountMicros ?? 0, unit,
            )} من ${goal.currency.formatAmount(goal.targetAmount)}',
          ),
          if (!goal.isBackingVerified) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'هدف قديم غير موثّق: ثبّت الخانات أو صفّرها أولاً. '
              'ما منقدر نتوقّع موعد بناءً على خانات بلا تغطية مالية.',
              style: TextStyle(color: colors.error),
            ),
          ] else if (goal.isVerifiedComplete)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('الهدف مكتمل ومغطّى بالادخار الحقيقي.'),
            )
          else ...<Widget>[
            const SizedBox(height: 10),
            _ForecastLine('وصول حسب الخطة', _date(forecast.planDate)),
            _ForecastLine('وصول حسب الفعلي', _date(forecast.observedDate)),
            _ForecastLine('سيناريو أبطأ 25٪', _date(forecast.slowerDate)),
            _ForecastLine('سيناريو أسرع 25٪', _date(forecast.fasterDate)),
            const Divider(height: 20),
            if (forecast.monthlyPlanAverageMicros != null)
              _ForecastLine(
                'الخطة الشهرية التقريبية',
                FinancialFormat.assetBalance(
                  forecast.monthlyPlanAverageMicros!, unit,
                ),
              ),
            if (forecast.monthlyObservedMicros != null)
              _ForecastLine(
                'الصافي الفعلي الشهري',
                FinancialFormat.assetBalance(
                  forecast.monthlyObservedMicros!, unit,
                ),
              )
            else
              const Text('الفعلي غير كافٍ: بدنا شهرين مكتملين على الأقل.'),
            if (compare != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                compare == 0
                  ? 'الفعلي مطابق للخطة الحالية.'
                  : compare > 0
                    ? 'الفعلي أسرع من الخطة بمقدار '
                      '${FinancialFormat.assetBalance(compare, unit)} شهرياً.'
                    : 'الفعلي أبطأ من الخطة بمقدار '
                      '${FinancialFormat.assetBalance(-compare, unit)} شهرياً.',
                style: TextStyle(
                  color: compare < 0 ? colors.error : colors.primary),
              ),
            ],
            if (goal.deadline != null) ...<Widget>[
              const SizedBox(height: 9),
              Text('موعد الهدف المطلوب: ${FinancialFormat.date(goal.deadline!)}'),
              Text(
                forecast.planDate == null
                  ? 'ما في وتيرة خطة موجبة وكافية لإثبات الوصول قبل الموعد.'
                  : forecast.planMissesDeadline
                    ? 'حسب الخطة الحالية ممكن نتأخر عن الموعد.'
                    : 'حسب الخطة الحالية ممكن نوصل قبل الموعد أو فيه.',
                style: TextStyle(
                  color: forecast.planMissesDeadline ?
                      colors.error : colors.primary,
                ),
              ),
              if (forecast.monthlyObservedMicros != null)
                Text(
                  forecast.observedMissesDeadline
                    ? 'حسب وتيرة الادخار الفعلية في خطر تأخير.'
                    : 'حسب الوتيرة الفعلية الحالية الوصول ممكن قبل الموعد.',
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ForecastLine extends StatelessWidget {
  const _ForecastLine(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: <Widget>[
      Expanded(child: Text(label)),
      const SizedBox(width: 8),
      Flexible(child: Text(value, textAlign: TextAlign.end)),
    ]),
  );
}
