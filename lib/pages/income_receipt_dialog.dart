import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/expected_income.dart';
import '../models/financial_event.dart';
import '../models/financial_settings.dart';
import '../models/receipt_fund_allocation.dart';
import '../services/financial_settings_storage.dart';
import '../utils/financial_format.dart';

class IncomeReceiptDraft {
  const IncomeReceiptDraft({
    required this.amountMicros,
    required this.receivedAt,
    required this.alreadySpentMicros,
    required this.savingsMicros,
    required this.spendingMicros,
    required this.spentAt,
    required this.spentCategory,
    required this.spentNote,
  });

  final int amountMicros;
  final DateTime receivedAt;
  final int alreadySpentMicros;
  final int savingsMicros;
  final int spendingMicros;
  final DateTime spentAt;
  final String spentCategory;
  final String spentNote;
}

/// The real receipt and any previous spending are separate ledger events.
/// Nothing is posted until the caller confirms an atomic receipt operation.
Future<IncomeReceiptDraft?> showIncomeReceiptDialog(
  BuildContext context,
  ExpectedIncome occurrence,
) async {
  FinancialSettings? settings;
  try {
    settings = await FinancialSettingsStorage().loadSettings();
  } catch (_) {
    // Manual allocation stays available when suggestions cannot be loaded.
  }
  if (!context.mounted) return null;
  final FinancialUnit unit = occurrence.unit;
  final bool isWhole = unit == FinancialUnit.syp ||
      unit == FinancialUnit.sypNew;
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  DateTime receiptDate = occurrence.scheduledDate;
  DateTime spentDate = occurrence.scheduledDate;

  final amountController = TextEditingController(
    text: FinancialFormat.editableAmount(
      occurrence.expectedAmountMicros,
      unit,
    ),
  );
  final spentController = TextEditingController(text: '0');
  final savingsController = TextEditingController(text: '0');
  final spendingController = TextEditingController(text: '0');
  final categoryController = TextEditingController();
  final noteController = TextEditingController();

  try {
    return await showDialog<IncomeReceiptDraft>(
      context: context,
      builder: (dialogContext) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('تسجيل استلام الدفعة'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'سجّل المبلغ الذي استلمته فعلياً، وليس مجرد الراتب المتوقع. '
                    'إذا كانت الدفعة قديمة وصُرفت، أدخل ما صُرف منها حتى '
                    'لا يظهر في الرصيد وكأنه ما زال معك.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'موعد الدفعة: ${FinancialFormat.date(occurrence.scheduledDate)}',
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: !isWhole,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(
                        isWhole ? r'[0-9]' : r'[0-9.]',
                      )),
                    ],
                    decoration: InputDecoration(
                      labelText: 'المبلغ المستلم فعلياً',
                      suffixText: FinancialFormat.unitShort(unit),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final chosen = await showDatePicker(
                        context: dialogContext,
                        initialDate: receiptDate,
                        firstDate: DateTime(2000),
                        lastDate: today,
                      );
                      if (chosen != null) update(() => receiptDate = chosen);
                    },
                    icon: const Icon(Icons.event),
                    label: Text(
                      'تاريخ الاستلام: ${FinancialFormat.date(receiptDate)}',
                    ),
                  ),
                  const Divider(),
                  TextField(
                    controller: spentController,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: !isWhole,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(
                        isWhole ? r'[0-9]' : r'[0-9.]',
                      )),
                    ],
                    decoration: InputDecoration(
                      labelText: 'كم صرفت من هالدفعة مسبقاً؟',
                      helperText: 'اتركه 0 إذا لم تصرف منها أو سجّلت مصاريفها سابقاً، '
                          'حتى لا تتكرر المصاريف.',
                      suffixText: FinancialFormat.unitShort(unit),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final chosen = await showDatePicker(
                        context: dialogContext,
                        initialDate: spentDate,
                        firstDate: DateTime(2000),
                        lastDate: today,
                      );
                      if (chosen != null) update(() => spentDate = chosen);
                    },
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: Text(
                      'تاريخ المصروف السابق: ${FinancialFormat.date(spentDate)}',
                    ),
                  ),
                  const Divider(),
                  Text(
                    'توزيع المبلغ المتبقي على الصناديق',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'كل مبلغ مخصص للادخار أو للمصاريف هو جزء من '
                    'نفس الدفعة، مو دخل إضافي. والجزء الباقي بيضل '
                    'غير موزّع. المصروف السابق ما بينحسب مرتين.',
                  ),
                  if (settings != null) ...<Widget>[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () {
                        final received = _parseMoneyMicros(
                          amountController.text, unit,
                        );
                        final spent = _parseMoneyMicros(
                          spentController.text, unit,
                        );
                        if (received == null || spent == null ||
                            spent > received) {
                          update(() => errorText =
                              'صحح المبلغ والمصروف قبل تطبيق الاقتراح.');
                          return;
                        }
                        final available = received - spent;
                        int savings;
                        int spending;
                        if (unit == FinancialUnit.syp) {
                          final wantedSpending = LedgerEntry.amountToMicros(
                            settings!.weeklyExpensesAllocation,
                          );
                          final wantedSavings = LedgerEntry.amountToMicros(
                            settings.weeklySavingsAllocation,
                          );
                          spending = wantedSpending > available
                              ? available : wantedSpending;
                          final left = available - spending;
                          savings = wantedSavings > left ? left : wantedSavings;
                        } else {
                          // Monthly USD income historically favored savings;
                          // this is a suggestion, not a forced allocation.
                          savings = available;
                          spending = 0;
                        }
                        update(() {
                          spendingController.text =
                              FinancialFormat.editableAmount(spending, unit);
                          savingsController.text =
                              FinancialFormat.editableAmount(savings, unit);
                          errorText = null;
                        });
                      },
                      icon: const Icon(Icons.auto_fix_high_outlined),
                      label: const Text('تطبيق التقسيم المقترح (اختياري)'),
                    ),
                  ],
                  const SizedBox(height: 9),
                  TextField(
                    controller: spendingController,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: !isWhole,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(
                        isWhole ? r'[0-9]' : r'[0-9.]',
                      )),
                    ],
                    onChanged: (_) => update(() => errorText = null),
                    decoration: InputDecoration(
                      labelText: 'إلى صندوق المصاريف',
                      suffixText: FinancialFormat.unitShort(unit),
                    ),
                  ),
                  const SizedBox(height: 9),
                  TextField(
                    controller: savingsController,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: !isWhole,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(
                        isWhole ? r'[0-9]' : r'[0-9.]',
                      )),
                    ],
                    onChanged: (_) => update(() => errorText = null),
                    decoration: InputDecoration(
                      labelText: 'إلى صندوق الادخار',
                      suffixText: FinancialFormat.unitShort(unit),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Builder(builder: (context) {
                    final received = _parseMoneyMicros(
                      amountController.text, unit,
                    );
                    final spent = _parseMoneyMicros(
                      spentController.text, unit,
                    );
                    final savings = _parseMoneyMicros(
                      savingsController.text, unit,
                    );
                    final spending = _parseMoneyMicros(
                      spendingController.text, unit,
                    );
                    if (received == null || spent == null ||
                        savings == null || spending == null) {
                      return const Text('أدخل مبالغ صحيحة لعرض الباقي.');
                    }
                    try {
                      final split = ReceiptFundAllocation(
                        receivedMicros: received,
                        savingsMicros: savings,
                        spendingMicros: spending,
                        alreadySpentMicros: spent,
                      );
                      return Text(
                        'المتبقي غير الموزّع: '
                        '${FinancialFormat.assetBalance(
                          split.remainingUnallocatedMicros, unit,
                        )}',
                      );
                    } on ArgumentError {
                      return const Text('مجموع التخصيص تجاوز المبلغ المتاح.');
                    }
                  }),
                  const Divider(),
                  TextField(
                    controller: categoryController,
                    decoration: const InputDecoration(
                      labelText: 'تصنيف المصروف السابق (اختياري)',
                    ),
                  ),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'سبب أو ملاحظة (اختياري)',
                    ),
                  ),
                  if (errorText != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () {
                  final received = _parseMoneyMicros(
                    amountController.text, unit,
                  );
                  final spent = _parseMoneyMicros(
                    spentController.text, unit,
                  );
                  final savings = _parseMoneyMicros(
                    savingsController.text, unit,
                  );
                  final spending = _parseMoneyMicros(
                    spendingController.text, unit,
                  );
                  if (received == null ||
                      received <= 0 ||
                      spent == null ||
                      savings == null ||
                      spending == null ||
                      spent < 0 ||
                      spent > received ||
                      savings > received - spent ||
                      spending > received - spent - savings) {
                    update(() => errorText =
                        'تأكد أن المبلغ المستلم موجب، وأن المصروف السابق '
                        'بين صفر والمبلغ المستلم.');
                    return;
                  }
                  Navigator.pop(
                    dialogContext,
                    IncomeReceiptDraft(
                      amountMicros: received,
                      receivedAt: receiptDate,
                      alreadySpentMicros: spent,
                      spentAt: spentDate,
                      spentCategory: categoryController.text,
                      spentNote: noteController.text,
                    ),
                  );
                },
                child: const Text('تسجيل الاستلام'),
              ),
            ],
          ),
        );
      },
    );
  } finally {
    amountController.dispose();
    spentController.dispose();
    savingsController.dispose();
    spendingController.dispose();
    categoryController.dispose();
    noteController.dispose();
  }
}

int? _parseMoneyMicros(String value, FinancialUnit unit) {
  final String input = value.trim();
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(input)) return null;
  final parts = input.split('.');
  final maxFraction = switch (unit) {
    FinancialUnit.usd => 2,
    FinancialUnit.syp || FinancialUnit.sypNew => 0,
    FinancialUnit.goldGram => 3,
  };
  if (parts.length > 1 &&
      (maxFraction == 0 || parts.last.length > maxFraction)) {
    return null;
  }
  final whole = int.tryParse(parts.first);
  final fraction = parts.length == 1
      ? 0
      : int.tryParse(parts.last.padRight(6, '0'));
  if (whole == null || fraction == null) return null;
  // Reject quantities whose fixed-point value would overflow signed SQLite.
  if (whole > (9223372036854775807 - fraction) ~/ 1000000) {
    return null;
  }
  return whole * 1000000 + fraction;
}
