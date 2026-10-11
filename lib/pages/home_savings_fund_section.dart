import 'dart:async';

import 'package:flutter/material.dart';

import '../models/financial_event.dart';
import '../services/financial_ledger_storage.dart';
import '../services/savings_fund_service.dart';
import '../ui/ux_components.dart';
import '../utils/financial_format.dart';
import 'fund_transfer_page.dart';
import 'transaction_history_page.dart';
import 'unallocated_funds_page.dart';

/// A live read-only Savings view. Goal earmarks and forecast dates are
/// intentionally NOT inferred from challenge grids (MS-13/14).
class HomeSavingsFundSection extends StatefulWidget {
  const HomeSavingsFundSection({
    super.key,
    required this.refreshToken,
    this.service,
  });
  final int refreshToken;
  final SavingsFundService? service;

  @override
  State<HomeSavingsFundSection> createState() =>
      _HomeSavingsFundSectionState();
}

class _HomeSavingsFundSectionState extends State<HomeSavingsFundSection> {
  late final SavingsFundService _service;
  SavingsFundSnapshot? _snapshot;
  StreamSubscription<void>? _changes;
  FinancialUnit _trendUnit = FinancialUnit.usd;
  int _requestId = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? SavingsFundService();
    _changes = FinancialLedgerStorage.changes.listen((_) => _reload());
    _reload();
  }

  @override
  void didUpdateWidget(covariant HomeSavingsFundSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _reload();
  }

  @override
  void dispose() {
    _requestId++;
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final request = ++_requestId;
    try {
      final current = await _service.loadCurrent();
      if (!mounted || request != _requestId) return;
      setState(() {
        _snapshot = current;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || request != _requestId) return;
      setState(() {
        _loading = false;
        _error = 'تعذّر تحميل أموال الادخار. أعد المحاولة.';
      });
    }
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => const TransactionHistoryPage(
        initialFund: FinancialFund.savings,
      ),
    ));
    if (mounted) await _reload();
  }

  Future<void> _moveFunds() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const FundTransferPage(),
      ),
    );
    if (mounted && saved == true) await _reload();
  }

  Future<void> _reconcile() async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => const UnallocatedFundsPage(),
    ));
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final colors = Theme.of(context).colorScheme;
    final warnings = snapshot?.valuation.valuationWarnings ?? <String>[];
    final value = snapshot?.valuation.estimatedTotalUsd;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const UxSectionHeader(
          title: 'صندوق الادخار الحقيقي',
          subtitle: 'المملوك والمصنّف للادخار الآن، وليس مجموع الدخل أو التحديات',
        ),
        const SizedBox(height: 10),
        if (_loading && snapshot == null)
          const Padding(
            padding: EdgeInsets.all(26),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (snapshot == null)
          UxSoftCard(child: Column(
            children: <Widget>[
              Text(_error ?? 'تعذّر تحميل رصيد الادخار.'),
              TextButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ))
        else ...<Widget>[
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: TextStyle(color: colors.error)),
            ),
          UxSoftCard(
            tone: colors.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('القيمة التقريبية للادخار فقط',
                  style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 3),
                Text(
                  value == null
                    ? 'لا يمكن حساب القيمة كاملة'
                    : FinancialFormat.estimatedUsd(value),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: colors.primary, fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'هذه قيمة مرجعية تقديرية بالدولار وليست مالاً جديداً '
                  'ولا قيمة ممتلكاتك كلها. تغيير سعر الصرف أو الذهب '
                  'لا يغيّر كمية الادخار.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (warnings.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  for (final warning in warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $warning',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.error,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          for (final unit in FinancialUnit.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SavedAssetRow(
                unit: unit,
                saved: snapshot.saved(unit),
                other: snapshot.notSaved(unit),
                isGold: unit == FinancialUnit.goldGram,
              ),
            ),
          const SizedBox(height: 6),
          UxSoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('حركة الادخار خلال الشهر الحالي',
                  style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  'الإضافات تشمل المبالغ المستلمة داخل الادخار والنقل إليه '
                  'من صندوق آخر. السحوبات تشمل المصروف منه والنقل خارجه. '
                  'نقل المال ليس دخلاً جديداً.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<FinancialUnit>(
                  value: _trendUnit,
                  decoration: const InputDecoration(
                    labelText: 'عملة عرض الحركة',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: FinancialUnit.values.map((unit) =>
                    DropdownMenuItem<FinancialUnit>(
                      value: unit,
                      child: Text(FinancialFormat.unitLabel(unit)),
                    ),
                  ).toList(growable: false),
                  onChanged: (unit) {
                    if (unit != null) setState(() => _trendUnit = unit);
                  },
                ),
                const SizedBox(height: 12),
                _SavingsMetric(
                  label: 'إضافات فعلية إلى الصندوق',
                  amount: snapshot.thisMonth.added(_trendUnit),
                  unit: _trendUnit,
                ),
                const SizedBox(height: 6),
                _SavingsMetric(
                  label: 'مصروف وسحب من الصندوق',
                  amount: snapshot.thisMonth.withdrawn(_trendUnit),
                  unit: _trendUnit,
                ),
                const Divider(height: 18),
                _SavingsMetric(
                  label: 'صافي الإضافات والسحوبات',
                  amount: snapshot.thisMonth.netFunding(_trendUnit),
                  unit: _trendUnit,
                ),
                if (snapshot.thisMonth.opening(_trendUnit) != 0) ...<Widget>[
                  const SizedBox(height: 6),
                  _SavingsMetric(
                    label: 'رصيد افتتاحي (مو دخل جديد)',
                    amount: snapshot.thisMonth.opening(_trendUnit),
                    unit: _trendUnit,
                  ),
                ],
                if (snapshot.thisMonth.converted(_trendUnit) != 0) ...<Widget>[
                  const SizedBox(height: 6),
                  _SavingsMetric(
                    label: 'تبديل أصول (مو ادخار جديد)',
                    amount: snapshot.thisMonth.converted(_trendUnit),
                    unit: _trendUnit,
                  ),
                ],
                if (snapshot.thisMonth.other(_trendUnit) != 0) ...<Widget>[
                  const SizedBox(height: 6),
                  _SavingsMetric(
                    label: 'تسويات وحركات أخرى',
                    amount: snapshot.thisMonth.other(_trendUnit),
                    unit: _trendUnit,
                  ),
                ],
                const SizedBox(height: 12),
                Text('آخر ستة أشهر — صافي حركة الصندوق',
                  style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                for (final monthly in snapshot.trend)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: _SavingsMetric(
                      label: '${monthly.month.month}/${monthly.month.year}',
                      amount: monthly.netFundMovement(_trendUnit),
                      unit: _trendUnit,
                    ),
                  ),
                const SizedBox(height: 5),
                Text(
                  'حركة كل شهر تشمل الإضافات والسحوبات والرصيد الافتتاحي '
                  'وتبديل الأصول والتسويات، وهي ليست أرباحاً من تغيّر الأسعار. '
                  'الرصيد المعروض فوق هو رصيد اليوم وليس رصيد شهر قديم.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          if (FinancialUnit.values.any((unit) =>
              snapshot.fundAmount(FinancialFund.unallocated, unit) != 0))
            UxSoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'في أموال غير موزّعة، ما بتنحسب ادخار لحتى تخصّصها أنت.',
                  ),
                  TextButton.icon(
                    onPressed: _reconcile,
                    icon: const Icon(Icons.call_split_outlined),
                    label: const Text('توزيع الأموال غير المصنّفة'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'تقدّم تحديات الادخار القديمة مو دليل على امتلاك نفس المبلغ. '
            'حجز الادخار للأهداف وربطه بأرصدة حقيقية ضمن المرحلة التالية.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _moveFunds,
          icon: const Icon(Icons.swap_horiz_rounded),
          label: const Text('نقل بين الادخار والمصاريف'),
        ),
        const SizedBox(height: 7),
        OutlinedButton.icon(
          onPressed: _openHistory,
          icon: const Icon(Icons.history_rounded),
          label: const Text('سجل حركات الادخار والسحوبات'),
        ),
      ],
    );
  }
}

class _SavedAssetRow extends StatelessWidget {
  const _SavedAssetRow({
    required this.unit,
    required this.saved,
    required this.other,
    required this.isGold,
  });

  final FinancialUnit unit;
  final int saved;
  final int other;
  final bool isGold;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return UxSoftCard(
      tone: isGold ? colors.tertiary : colors.primary,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(FinancialFormat.unitLabel(unit),
            style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 3),
          Text(
            FinancialFormat.assetBalance(saved, unit),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'من إجمالي ممتلكاتك بهالعملة: '
            '${FinancialFormat.assetBalance(saved + other, unit)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (isGold)
            Text(
              'ذهب محفوظ — ليس سيولة للصرف إلا بعد البيع الفعلي.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _SavingsMetric extends StatelessWidget {
  const _SavingsMetric({
    required this.label,
    required this.amount,
    required this.unit,
  });
  final String label;
  final int amount;
  final FinancialUnit unit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: Text(label,
          style: Theme.of(context).textTheme.bodySmall)),
        const SizedBox(width: 8),
        Flexible(child: Text(
          FinancialFormat.assetBalance(amount, unit),
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.titleSmall,
        )),
      ],
    );
  }
}
