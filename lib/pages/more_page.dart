import 'package:flutter/material.dart';

import '../ui/ux_components.dart';
import 'challenges_page.dart';
import 'fund_transfer_page.dart';
import 'goal_forecast_page.dart';
import 'home_page.dart';
import 'manual_inflow_page.dart';
import 'savings_motivation_page.dart';
import 'settings_shell_page.dart';
import 'spending_analytics_page.dart';
import 'transaction_history_page.dart';
import 'unallocated_funds_page.dart';

/// Secondary navigation: every existing financial tool remains accessible,
/// without making people understand all of them on the first screen.
class MorePage extends StatelessWidget {
  const MorePage({super.key, this.onDataRestored});

  final Future<void> Function()? onDataRestored;

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(builder: (_) => page),
    );
  }

  Widget _item(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget page,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: UxActionTile(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: () => _open(context, page),
      ),
    );
  }

  Widget _detail(String title, HomeFinancialView view) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: HomePage(view: view, isActive: true),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final month = DateTime.now();
    return SingleChildScrollView(
      key: const PageStorageKey<String>('more-tools'),
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const UxPageHeader(
            title: 'المزيد',
            subtitle: 'كل الأدوات موجودة هون، افتح اللي بتحتاجه فقط',
          ),
          const SizedBox(height: 22),
          Text('إدارة الأموال', style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          _item(
            context,
            icon: Icons.savings_outlined,
            title: 'تفاصيل الادخار',
            subtitle: 'الأرصدة والذهب والتحويلات وتاريخ الادخار',
            page: _detail('تفاصيل الادخار', HomeFinancialView.savings),
          ),
          _item(
            context,
            icon: Icons.wallet_outlined,
            title: 'تفاصيل المصاريف والرواتب',
            subtitle: 'الرواتب المتأخرة والفواتير والمدفوعات',
            page: _detail('المصاريف والرواتب', HomeFinancialView.spending),
          ),
          _item(
            context,
            icon: Icons.add_circle_outline,
            title: 'إضافة دخل أو مال قديم',
            subtitle: 'هدية أو راتب إضافي أو رصيد موجود سابقاً',
            page: const ManualInflowPage(),
          ),
          _item(
            context,
            icon: Icons.swap_horiz_rounded,
            title: 'نقل مال بين الادخار والصرف',
            subtitle: 'نقل داخلي، مو دخل جديد أو مصروف',
            page: const FundTransferPage(),
          ),
          _item(
            context,
            icon: Icons.call_split_outlined,
            title: 'توزيع مال غير مصنّف',
            subtitle: 'تحديد مكان الأموال القديمة غير الموزعة',
            page: const UnallocatedFundsPage(),
          ),
          const SizedBox(height: 15),
          Text('الأهداف والمتابعة', style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          _item(
            context,
            icon: Icons.flag_outlined,
            title: 'أهداف الادخار',
            subtitle: 'إنشاء الأهداف ومتابعة تقدمها',
            page: const ChallengesPage(isActive: true),
          ),
          _item(
            context,
            icon: Icons.query_stats_outlined,
            title: 'إيمتى بوصل لهدفي؟',
            subtitle: 'توقعات حسب الدخل والمصاريف الفعلية',
            page: const GoalForecastPage(),
          ),
          _item(
            context,
            icon: Icons.verified_outlined,
            title: 'إنجازات الادخار',
            subtitle: 'المراحل اللي حققتها بمال حقيقي',
            page: const SavingsMotivationPage(),
          ),
          const SizedBox(height: 15),
          Text('السجل والتحليل', style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          _item(
            context,
            icon: Icons.history_rounded,
            title: 'كل الحركات',
            subtitle: 'البحث والتعديل ومراجعة العمليات السابقة',
            page: const TransactionHistoryPage(),
          ),
          _item(
            context,
            icon: Icons.bar_chart_outlined,
            title: 'وين راحت المصاري؟',
            subtitle: 'تحليل المصاريف ومقارنتها بالخطة',
            page: SpendingAnalyticsPage(
              initialMonth: DateTime(month.year, month.month),
            ),
          ),
          const SizedBox(height: 15),
          Text('إعدادات التطبيق', style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          _item(
            context,
            icon: Icons.settings_outlined,
            title: 'الرواتب والخطة والإعدادات',
            subtitle: 'تعديل الرواتب والفواتير والأسعار والتنبيهات',
            page: Scaffold(
              appBar: AppBar(title: const Text('الإعدادات')),
              body: SettingsShellPage(onDataRestored: onDataRestored),
            ),
          ),
          _item(
            context,
            icon: Icons.backup_outlined,
            title: 'النسخ الاحتياطي',
            subtitle: 'من الإعدادات: حفظ البيانات واستعادتها بأمان',
            page: Scaffold(
              appBar: AppBar(title: const Text('الإعدادات والنسخ')),
              body: SettingsShellPage(onDataRestored: onDataRestored),
            ),
          ),
        ],
      ),
    );
  }
}
