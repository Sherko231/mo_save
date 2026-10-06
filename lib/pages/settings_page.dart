import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/financial_settings.dart';
import '../services/financial_settings_storage.dart';
import '../services/notification_preferences_storage.dart';
import '../services/notification_service.dart';
import '../ui/ux_components.dart';
import 'expense_plan_sheet.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.initialSetup = false,
    this.onInitialSetupComplete,
    this.onOpenBackup,
  });

  final bool initialSetup;
  final Future<void> Function()? onInitialSetupComplete;
  final Future<void> Function()? onOpenBackup;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final FinancialSettingsStorage _storage = FinancialSettingsStorage();
  final NotificationPreferencesStorage _notificationPreferencesStorage =
      NotificationPreferencesStorage();
  final NotificationService _notificationService = NotificationService.instance;

  final TextEditingController _weeklyIncomeController = TextEditingController();
  final TextEditingController _monthlyIncomeController = TextEditingController();
  final TextEditingController _exchangeRateController = TextEditingController();
  final TextEditingController _goldPriceController = TextEditingController();
  final TextEditingController _expensesAllocationController =
      TextEditingController();
  final TextEditingController _savingsAllocationController =
      TextEditingController();

  int _weeklyPayday = DateTime.thursday;
  int _monthlyPayday = 1;
  bool _weeklyIncomeNotificationEnabled = false;
  bool _monthlyIncomeNotificationEnabled = false;
  bool _goalDeadlineNotificationEnabled = false;
  bool _isLoading = true;
  bool _isSaving = false;

  static const Map<int, String> _weekdayLabels = <int, String>{
    DateTime.monday: 'الاثنين',
    DateTime.tuesday: 'الثلاثاء',
    DateTime.wednesday: 'الأربعاء',
    DateTime.thursday: 'الخميس',
    DateTime.friday: 'الجمعة',
    DateTime.saturday: 'السبت',
    DateTime.sunday: 'الأحد',
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _weeklyIncomeController.dispose();
    _monthlyIncomeController.dispose();
    _exchangeRateController.dispose();
    _goldPriceController.dispose();
    _expensesAllocationController.dispose();
    _savingsAllocationController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final FinancialSettings settings = await _storage.loadSettings();
      final NotificationPreferences notifications =
          await _notificationPreferencesStorage.load();
      if (!mounted) return;

      _weeklyIncomeController.text = settings.weeklySypIncome.toString();
      _monthlyIncomeController.text =
          _formatEditableDouble(settings.monthlyUsdIncome);
      _exchangeRateController.text = settings.referenceSypPerUsd == 0
          ? ''
          : _formatEditableDouble(settings.referenceSypPerUsd);
      _goldPriceController.text = settings.goldUsdPerGram == 0
          ? ''
          : _formatEditableDouble(settings.goldUsdPerGram);
      _expensesAllocationController.text =
          settings.weeklyExpensesAllocation.toString();
      _savingsAllocationController.text =
          settings.weeklySavingsAllocation.toString();

      setState(() {
        _weeklyPayday = settings.weeklyPayday;
        _monthlyPayday = settings.monthlyPayday;
        _weeklyIncomeNotificationEnabled = notifications.weeklyIncomeEnabled;
        _monthlyIncomeNotificationEnabled = notifications.monthlyIncomeEnabled;
        _goalDeadlineNotificationEnabled = notifications.goalDeadlinesEnabled;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحميل الإعدادات المالية.')),
      );
    }
  }

  Future<void> _manageExpensePlan() async {
    final bool? changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.92,
        child: ExpensePlanSheet(),
      ),
    );

    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث خطة المصاريف الشهرية.')),
      );
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    final int weeklyIncome = int.parse(_weeklyIncomeController.text.trim());
    final int expensesAllocation =
        int.parse(_expensesAllocationController.text.trim());
    final int savingsAllocation =
        int.parse(_savingsAllocationController.text.trim());

    if (expensesAllocation + savingsAllocation > weeklyIncome) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('مجموع التقسيم لا يمكن أن يتجاوز راتب الأسبوع.'),
        ),
      );
      return;
    }

    final FinancialSettings settings = FinancialSettings(
      weeklySypIncome: weeklyIncome,
      weeklyPayday: _weeklyPayday,
      monthlyUsdIncome: double.parse(_monthlyIncomeController.text.trim()),
      monthlyPayday: _monthlyPayday,
      referenceSypPerUsd: _parseOptionalDouble(_exchangeRateController.text),
      goldUsdPerGram: _parseOptionalDouble(_goldPriceController.text),
      weeklyExpensesAllocation: expensesAllocation,
      weeklySavingsAllocation: savingsAllocation,
    );
    NotificationPreferences notificationPreferences = NotificationPreferences(
      weeklyIncomeEnabled: _weeklyIncomeNotificationEnabled,
      monthlyIncomeEnabled: _monthlyIncomeNotificationEnabled,
      goalDeadlinesEnabled: _goalDeadlineNotificationEnabled,
    );

    setState(() => _isSaving = true);

    try {
      await _storage.saveSettings(settings);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ الإعدادات المالية.')),
      );
      return;
    }

    String message = widget.initialSetup
        ? 'تم حفظ الإعداد الأول.'
        : 'تم حفظ الإعدادات.';

    try {
      if (notificationPreferences.anyEnabled) {
        final bool granted = await _notificationService.requestPermission();
        if (!granted) {
          notificationPreferences = NotificationPreferences.disabled;
          if (mounted) {
            setState(() {
              _weeklyIncomeNotificationEnabled = false;
              _monthlyIncomeNotificationEnabled = false;
              _goalDeadlineNotificationEnabled = false;
            });
          }
          message = widget.initialSetup
              ? 'تم حفظ الإعداد الأول، لكن صلاحية الإشعارات غير ممنوحة فتم إيقاف التنبيهات.'
              : 'تم حفظ الإعدادات، لكن صلاحية الإشعارات غير ممنوحة فتم إيقاف التنبيهات.';
        }
      }

      await _notificationPreferencesStorage.save(notificationPreferences);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر حفظ تفضيلات التنبيهات. أعد المحاولة.'),
        ),
      );
      return;
    }

    try {
      await _notificationService.rescheduleAll();
    } catch (_) {
      message = widget.initialSetup
          ? 'تم حفظ الإعداد الأول، لكن تعذر تحديث مواعيد التنبيهات الآن.'
          : 'تم حفظ الإعدادات، لكن تعذر تحديث مواعيد التنبيهات الآن.';
    }

    if (widget.initialSetup && widget.onInitialSetupComplete != null) {
      try {
        await widget.onInitialSetupComplete!();
      } catch (_) {
        if (!mounted) return;
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ القيم، لكن تعذر إنهاء الإعداد الأول. أعد المحاولة.'),
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 112),
        children: <Widget>[
          if (widget.initialSetup)
            UxHeroCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.tune_rounded,
                      color: Colors.white,
                      size: 25,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'جهّز خطتك',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'راجع الأساسيات فقط. كل خيار تستطيع تغييره لاحقاً بدون المساس بتاريخك المالي.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.78),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            const UxPageHeader(
              title: 'الإعدادات',
              subtitle: 'خطتك المستقبلية، التنبيهات وأدوات البيانات',
            ),
          const SizedBox(height: 16),
          UxInfoBanner(
            icon: Icons.history_rounded,
            title: 'التغييرات للمستقبل فقط',
            body:
                'تعديل الراتب أو المواعيد أو أسعار التقييم هنا لا يغيّر الحركات المالية المسجلة سابقاً.',
          ),
          const SizedBox(height: 14),
          _SettingsGroup(
            icon: Icons.payments_outlined,
            title: 'الدخل ومواعيد القبض',
            subtitle: 'راتب الأسبوع، راتب الشهر ومواعيد الاستلام',
            initiallyExpanded: true,
            children: <Widget>[
              TextFormField(
                controller: _weeklyIncomeController,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'راتب الأسبوع',
                  helperText: 'ضع 0 إذا لم يكن لديك دخل أسبوعي.',
                  suffixText: 'ل.س',
                ),
                validator: _validateNonNegativeInteger,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                value: _weeklyPayday,
                decoration: const InputDecoration(
                  labelText: 'يوم استلام راتب الأسبوع',
                ),
                items: _weekdayLabels.entries
                    .map(
                      (entry) => DropdownMenuItem<int>(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) setState(() => _weeklyPayday = value);
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _monthlyIncomeController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'الدخل الشهري بالدولار',
                  helperText: 'ضع 0 إذا لم يكن لديك دخل شهري بالدولار.',
                  prefixText: '\$ ',
                ),
                validator: _validateNonNegativeDouble,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                value: _monthlyPayday,
                decoration: const InputDecoration(
                  labelText: 'يوم استلام الدخل الشهري',
                ),
                items: List<DropdownMenuItem<int>>.generate(
                  31,
                  (index) => DropdownMenuItem<int>(
                    value: index + 1,
                    child: Text('اليوم ${index + 1} من الشهر'),
                  ),
                ),
                onChanged: (value) {
                  if (value != null) setState(() => _monthlyPayday = value);
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ActionSettingsCard(
            icon: Icons.receipt_long_outlined,
            title: 'خطة المصاريف الشهرية',
            subtitle: 'أضف أو عدّل أو احذف البنود المتكررة',
            onTap: _manageExpensePlan,
          ),
          const SizedBox(height: 10),
          _SettingsGroup(
            icon: Icons.call_split_outlined,
            title: 'تقسيم راتب الأسبوع',
            subtitle: 'اقتراح افتراضي للمصاريف والادخار',
            children: <Widget>[
              TextFormField(
                controller: _expensesAllocationController,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'للمصاريف والالتزامات',
                  suffixText: 'ل.س',
                ),
                validator: _validateNonNegativeInteger,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _savingsAllocationController,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'للفائض والادخار',
                  suffixText: 'ل.س',
                ),
                validator: _validateNonNegativeInteger,
              ),
              const SizedBox(height: 8),
              Text(
                'هذا اقتراح لكل راتب أسبوعي جديد، ويمكن تعديله لكل دفعة قبل التأكيد.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SettingsGroup(
            icon: Icons.auto_graph_outlined,
            title: 'التقييم التقريبي',
            subtitle: 'سعر الصرف وسعر الذهب للعرض فقط',
            children: <Widget>[
              TextFormField(
                controller: _exchangeRateController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'سعر الصرف المرجعي',
                  helperText:
                      'عدد الليرات السورية مقابل 1 دولار. اتركه فارغاً إذا لا تريد تقييماً إجمالياً.',
                  suffixText: 'ل.س / USD',
                ),
                validator: _validateOptionalPositiveDouble,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _goldPriceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'سعر غرام الذهب',
                  helperText: 'السعر المرجعي بالدولار لكل غرام.',
                  suffixText: 'USD / g',
                ),
                validator: _validateOptionalPositiveDouble,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SettingsGroup(
            icon: Icons.notifications_none_rounded,
            title: 'التنبيهات',
            subtitle: 'كلها محلية ويمكن إيقافها',
            children: <Widget>[
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _weeklyIncomeNotificationEnabled,
                onChanged: (value) => setState(
                  () => _weeklyIncomeNotificationEnabled = value,
                ),
                title: const Text('تذكير دخل الأسبوع'),
                subtitle: const Text('في يوم القبض الأسبوعي المحدد.'),
              ),
              const Divider(),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _monthlyIncomeNotificationEnabled,
                onChanged: (value) => setState(
                  () => _monthlyIncomeNotificationEnabled = value,
                ),
                title: const Text('تذكير الدخل الشهري'),
                subtitle: const Text('في يوم القبض الشهري المحدد.'),
              ),
              const Divider(),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _goalDeadlineNotificationEnabled,
                onChanged: (value) => setState(
                  () => _goalDeadlineNotificationEnabled = value,
                ),
                title: const Text('مواعيد أهداف الادخار'),
                subtitle: const Text('قبل أسبوع وفي يوم الموعد.'),
              ),
            ],
          ),
          if (widget.onOpenBackup != null) ...<Widget>[
            const SizedBox(height: 10),
            _ActionSettingsCard(
              icon: Icons.backup_outlined,
              title: 'النسخ الاحتياطي',
              subtitle: 'تصدير نسخة أو استعادتها من ملف',
              onTap: () {
                widget.onOpenBackup?.call();
              },
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _isSaving ? null : _saveSettings,
            icon: _isSaving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(
              _isSaving
                  ? 'جاري الحفظ...'
                  : widget.initialSetup
                      ? 'حفظ وبدء الاستخدام'
                      : 'حفظ التغييرات',
            ),
          ),
        ],
      ),
    );
  }

  static String? _validateNonNegativeInteger(String? value) {
    final int? parsed = int.tryParse((value ?? '').trim());
    if (parsed == null || parsed < 0) {
      return 'أدخل رقماً صحيحاً يساوي صفر أو أكبر.';
    }
    return null;
  }

  static String? _validateNonNegativeDouble(String? value) {
    final double? parsed = double.tryParse((value ?? '').trim());
    if (parsed == null || parsed < 0) {
      return 'أدخل رقماً يساوي صفر أو أكبر.';
    }
    return null;
  }

  static String? _validateOptionalPositiveDouble(String? value) {
    final String text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final double? parsed = double.tryParse(text);
    if (parsed == null || parsed <= 0) {
      return 'أدخل قيمة أكبر من صفر أو اترك الحقل فارغاً.';
    }
    return null;
  }

  static double _parseOptionalDouble(String value) {
    final String text = value.trim();
    return text.isEmpty ? 0 : double.parse(text);
  }

  static String _formatEditableDouble(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
    this.initiallyExpanded = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        maintainState: true,
        initiallyExpanded: initiallyExpanded,
        leading: UxIconBadge(
          icon: icon,
          size: 42,
          iconSize: 21,
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
        ),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionSettingsCard extends StatelessWidget {
  const _ActionSettingsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return UxActionTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
    );
  }
}
