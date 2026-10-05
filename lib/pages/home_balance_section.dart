import 'dart:async';

import 'package:flutter/material.dart';

import '../models/financial_balance_snapshot.dart';
import '../models/financial_event.dart';
import '../services/balance_valuation_service.dart';
import '../services/financial_ledger_storage.dart';
import '../utils/financial_format.dart';

class HomeBalanceSection extends StatefulWidget {
  const HomeBalanceSection({
    super.key,
    required this.refreshToken,
  });

  final int refreshToken;

  @override
  State<HomeBalanceSection> createState() => _HomeBalanceSectionState();
}

class _HomeBalanceSectionState extends State<HomeBalanceSection> {
  final BalanceValuationService _service = BalanceValuationService();

  StreamSubscription<void>? _ledgerSubscription;
  FinancialBalanceSnapshot? _snapshot;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _ledgerSubscription = FinancialLedgerStorage.changes.listen((_) {
      _load(showLoading: false);
    });
    _load();
  }

  @override
  void didUpdateWidget(covariant HomeBalanceSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _load(showLoading: false);
    }
  }

  @override
  void dispose() {
    _ledgerSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final FinancialBalanceSnapshot snapshot = await _service.loadSnapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحميل الأرصدة الحالية.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final FinancialBalanceSnapshot? snapshot = _snapshot;
    if (snapshot == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('لا يمكن عرض الأرصدة حالياً.'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'الأرصدة الحالية',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        _EstimatedTotalCard(snapshot: snapshot),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final bool twoColumns = constraints.maxWidth >= 520;
            final double width = twoColumns
                ? (constraints.maxWidth - 10) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _AssetCard(
                  width: width,
                  icon: Icons.attach_money,
                  label: 'الدولار',
                  value: FinancialFormat.assetBalance(
                    snapshot.balanceMicros(FinancialUnit.usd),
                    FinancialUnit.usd,
                  ),
                ),
                _AssetCard(
                  width: width,
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'الليرة السورية',
                  value: FinancialFormat.assetBalance(
                    snapshot.balanceMicros(FinancialUnit.syp),
                    FinancialUnit.syp,
                  ),
                  estimate: snapshot.estimatedSypUsd == null
                      ? null
                      : FinancialFormat.estimatedUsd(snapshot.estimatedSypUsd!),
                ),
                _AssetCard(
                  width: width,
                  icon: Icons.currency_exchange,
                  label: 'الليرة السورية الجديدة',
                  value: FinancialFormat.assetBalance(
                    snapshot.balanceMicros(FinancialUnit.sypNew),
                    FinancialUnit.sypNew,
                  ),
                ),
                _AssetCard(
                  width: width,
                  icon: Icons.diamond_outlined,
                  label: 'الذهب',
                  value: FinancialFormat.assetBalance(
                    snapshot.balanceMicros(FinancialUnit.goldGram),
                    FinancialUnit.goldGram,
                  ),
                  estimate: snapshot.estimatedGoldUsd == null
                      ? null
                      : FinancialFormat.estimatedUsd(snapshot.estimatedGoldUsd!),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          'الأرصدة محسوبة من سجل الحركات الفعلي. تغيير سعر الصرف أو سعر الذهب يغيّر التقدير فقط ولا يغيّر الأرصدة.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _EstimatedTotalCard extends StatelessWidget {
  const _EstimatedTotalCard({required this.snapshot});

  final FinancialBalanceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final double? total = snapshot.estimatedTotalUsd;
    final List<String> warnings = snapshot.valuationWarnings;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const CircleAvatar(
                  child: Icon(Icons.pie_chart_outline),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'القيمة الإجمالية التقريبية',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        total == null
                            ? 'غير متاحة بالكامل'
                            : FinancialFormat.estimatedUsd(total),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (snapshot.referenceSypPerUsd > 0 ||
                snapshot.goldUsdPerGram > 0) ...<Widget>[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  if (snapshot.referenceSypPerUsd > 0)
                    Chip(
                      label: Text(
                        'الصرف: ${FinancialFormat.referenceRate(snapshot.referenceSypPerUsd)}',
                      ),
                    ),
                  if (snapshot.goldUsdPerGram > 0)
                    Chip(
                      label: Text(
                        'الذهب: ${FinancialFormat.goldReference(snapshot.goldUsdPerGram)}',
                      ),
                    ),
                ],
              ),
            ],
            if (warnings.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              ...warnings.map(
                (warning) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          warning,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AssetCard extends StatelessWidget {
  const _AssetCard({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    this.estimate,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;
  final String? estimate;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Icon(icon),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(label, style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 3),
                    Text(value, style: Theme.of(context).textTheme.titleMedium),
                    if (estimate != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        estimate!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
