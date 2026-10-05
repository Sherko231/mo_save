import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/financial_settings.dart';
import '../services/financial_settings_storage.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final FinancialSettingsStorage _storage = FinancialSettingsStorage();

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
      if (!mounted) {
        return;
      }

      _weeklyIncomeController.text = settings.weeklySypIncome.toString();
      _monthlyIncomeController.text = _formatEditableDouble(settings.monthlyUsdIncome);
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
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحميل الإعدادات المالية.')),
      );
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final int weeklyIncome = int.parse(_weeklyIncomeController.text.trim());
    final int expensesAllocation =
        int.parse(_expensesAllocationController.text.trim());
    final int savingsAllocation =
        int.parse(_savingsAllocationController.text.trim());

    if (expensesAllocation + savingsAllocation > weeklyIncome) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('مجموع الظرفين لا يمكن أن يكون أكبر من راتب الخميس.'),
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

    setState(() {
      _isSaving = true;
    });

    try {
      await _storage.saveSettings(settings);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الإعدادات.')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ الإعدادات.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
          children: <Widget>[
            Text(
              'الإعدادات المالية',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              'هذه القيم هي افتراضات للعمليات القادمة ويمكن تعديلها بأي وقت.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            _SectionCard(
              title: 'الدخل',
              children: <Widget>[
                TextFormField(
                  controller: _weeklyIncomeController,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: 'راتب الأسبوع',
                    suffixText: 'ل.س',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateNonNegativeInteger,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  value: _weeklyPayday,
                  decoration: const InputDecoration(
                    labelText: 'يوم استلام راتب الأسبوع',
                    border: OutlineInputBorder(),
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
                    if (value != null) {
                      setState(() {
                        _weeklyPayday = value;
                      });
                    }
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
                    labelText: 'راتب أول الشهر',
                    prefixText: '\$ ',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateNonNegativeDouble,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  value: _monthlyPayday,
                  decoration: const InputDecoration(
                    labelText: 'يوم استلام الراتب الشهري',
                    border: OutlineInputBorder(),
                  ),
                  items: List<DropdownMenuItem<int>>.generate(
                    31,
                    (index) => DropdownMenuItem<int>(
                      value: index + 1,
                      child: Text('اليوم ${index + 1} من الشهر'),
                    ),
                  ),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _monthlyPayday = value;
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: 'التقييم التقريبي',
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
                    helperText: 'عدد الليرات السورية مقابل 1 دولار',
                    suffixText: 'ل.س / USD',
                    border: OutlineInputBorder(),
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
                    helperText: 'السعر المرجعي بالدولار لكل غرام',
                    suffixText: 'USD / g',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateOptionalPositiveDouble,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: 'تقسيم راتب الأسبوع',
              children: <Widget>[
                TextFormField(
                  controller: _expensesAllocationController,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: 'ظرف المصاريف والالتزامات',
                    suffixText: 'ل.س',
                    border: OutlineInputBorder(),
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
                    labelText: 'ظرف الفائض والادخار',
                    suffixText: 'ل.س',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateNonNegativeInteger,
                ),
                const SizedBox(height: 10),
                Text(
                  'الافتراضي الحالي: 540,000 ل.س للمصاريف و345,000 ل.س للادخار.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isSaving ? null : _saveSettings,
              icon: _isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ الإعدادات'),
            ),
          ],
        ),
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
      return 'أدخل رقماً صحيحاً يساوي صفر أو أكبر.';
    }
    return null;
  }

  static String? _validateOptionalPositiveDouble(String? value) {
    final String text = (value ?? '').trim();
    if (text.isEmpty) {
      return null;
    }
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}
