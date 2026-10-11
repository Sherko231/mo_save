import 'package:flutter/material.dart';

import '../ui/ux_components.dart';
import 'challenges_page.dart';
import 'fund_transfer_page.dart';
import 'funds_at_glance.dart';
import 'home_page.dart';
import 'manual_inflow_page.dart';
import 'spending_quick_expense_page.dart';
import 'transaction_history_page.dart';

/// A calm daily starting point. Complex financial details are one tap away.
class SimpleHomePage extends StatelessWidget {
  const SimpleHomePage({super.key});

  Future<void> _open(BuildContext context, Widget page) =>
      Navigator.of(context).push<Object?>(
        MaterialPageRoute<Object?>(builder: (_) => page),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      key: const PageStorageKey<String>('simple-home'),
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const UxPageHeader(
            title: 'أموالك',
            subtitle: 'قديش مدّخر، وقديش فيك تصرف اليوم؟',
          ),
          const SizedBox(height: 18),
          const FundsAtGlance(refreshToken: 0),
          const SizedBox(height: 26),
          Text('شو بدك تعمل؟', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _open(context, const SpendingQuickExpensePage()),
            icon: const Icon(Icons.remove_circle_outline_rounded),
            label: const Text('تسجيل مصروف'),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _open(context, const ManualInflowPage()),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  label: const Text('إضافة مال'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _open(context, const FundTransferPage()),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('نقل مال'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('اختصارات', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          UxActionTile(
            icon: Icons.flag_outlined,
            title: 'أهداف الادخار',
            subtitle: 'شوف تقدمك أو ضيف هدف جديد',
            onTap: () => _open(context, const ChallengesPage(isActive: true)),
          ),
          const SizedBox(height: 10),
          UxActionTile(
            icon: Icons.payments_outlined,
            title: 'الراتب',
            subtitle: 'تسجيل استلام راتب أو تجاهل دفعة قديمة',
            onTap: () => _open(
              context,
              const _IncomeAccessPage(),
            ),
          ),
          const SizedBox(height: 10),
          UxActionTile(
            icon: Icons.history_rounded,
            title: 'السجل',
            subtitle: 'راجع كل حركة دخل أو صرف',
            onTap: () => _open(context, const TransactionHistoryPage()),
          ),
          const SizedBox(height: 20),
          Text(
            'الأرصدة الفعلية فقط، مو الرواتب المتوقعة. '
            'الخطط والتحليلات والتفاصيل بقسم «المزيد».',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _IncomeAccessPage extends StatelessWidget {
  const _IncomeAccessPage();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الراتب والمصاريف')),
        body: const HomePage(
          view: HomeFinancialView.spending,
          isActive: true,
          incomeOnly: true,
        ),
      );
}
