import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/expected_income.dart';
import '../models/financial_event.dart';
import '../utils/financial_format.dart';

class IncomeReceiptDraft {
  const IncomeReceiptDraft({
    required this.amountMicros,
    required this.receivedAt,
    required this.alreadySpentMicros,
    required this.spentAt,
    required this.spentCategory,
    required this.spentNote,
  });

  final int amountMicros;
  final DateTime receivedAt;
  final int alreadySpentMicros;
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
                      helperText: 'اتركه 0 إذا ما صرفت منها شيء.',
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
                  if (received == null ||
                      received <= 0 ||
                      spent == null ||
                      spent < 0 ||
                      spent > received) {
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
