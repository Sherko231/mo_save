import 'dart:async';

import 'package:flutter/material.dart';

import '../models/financial_event.dart';
import '../services/financial_ledger_storage.dart';
import '../ui/ux_components.dart';
import '../utils/financial_format.dart';

/// Fund-at-a-glance is per asset unit. It must never convert currencies,
/// mistake Unallocated for Savings, or count expected income as liquid cash.
class FundsAtGlance extends StatefulWidget {
  const FundsAtGlance({
    super.key,
    required this.refreshToken,
    this.ledger,
  });

  final int refreshToken;
  final FinancialLedgerStorage? ledger;

  @override
  State<FundsAtGlance> createState() => _FundsAtGlanceState();
}

class _FundsAtGlanceState extends State<FundsAtGlance> {
  late final FinancialLedgerStorage _ledger;
  StreamSubscription<void>? _changes;
  Map<FinancialFund, Map<FinancialUnit, int>>? _balances;
  int _request = 0;
  bool _loading = true;

  static const cashUnits = <FinancialUnit>[
    FinancialUnit.syp, FinancialUnit.usd, FinancialUnit.sypNew,
  ];

  @override
  void initState() {
    super.initState();
    _ledger = widget.ledger ?? FinancialLedgerStorage();
    _changes = FinancialLedgerStorage.changes.listen((_) => _reload());
    _reload();
  }

  @override
  void didUpdateWidget(covariant FundsAtGlance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _reload();
  }

  @override
  void dispose() {
    _request++;
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final request = ++_request;
    try {
      final balances = await _ledger.loadFundBalancesMicros();
      if (!mounted || request != _request) return;
      setState(() {
        _balances = balances;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _balances;
    if (_loading && b == null) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (b == null) {
      return const UxSoftCard(
        child: Text('تعذر تحميل الأرصدة حالياً. افتح تفاصيل الادخار وأعد المحاولة.'),
      );
    }
    final showUnits = cashUnits.where((unit) =>
      unit != FinancialUnit.sypNew ||
      FinancialFund.values.any((fund) => (b[fund]?[unit] ?? 0) != 0),
    );
    return UxSoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('رصيد اليوم حسب الصندوق',
            style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('الادخار غير المصاريف. ما منجمع الدولار والليرة بسعر مفترض.'),
          const SizedBox(height: 11),
          for (final unit in showUnits) ...<Widget>[
            Text(FinancialFormat.unitLabel(unit),
              style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 5),
            Row(children: <Widget>[
              Expanded(child: _FundAmount(
                label: 'ادخار حقيقي',
                amount: b[FinancialFund.savings]?[unit] ?? 0,
                unit: unit,
              )),
              const SizedBox(width: 9),
              Expanded(child: _FundAmount(
                label: 'متاح للمصاريف',
                amount: b[FinancialFund.spending]?[unit] ?? 0,
                unit: unit,
              )),
            ]),
            const SizedBox(height: 10),
          ],
          if (cashUnits.any((u) =>
              (b[FinancialFund.unallocated]?[u] ?? 0) != 0))
            const Text('في أموال غير موزّعة؛ ما بتنحسب ادخار أو مصاريف.'),
        ],
      ),
    );
  }
}

class _FundAmount extends StatelessWidget {
  const _FundAmount({
    required this.label,
    required this.amount,
    required this.unit,
  });
  final String label;
  final int amount;
  final FinancialUnit unit;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 3),
      FittedBox(
        alignment: AlignmentDirectional.centerStart,
        fit: BoxFit.scaleDown,
        child: Text(
          FinancialFormat.assetBalance(amount, unit),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    ],
  );
}
