import '../models/saving_challenge.dart';

/// Only used by the existing opt-in deadline notification workflow.
/// Goal-grid checkmarks without verified Savings may never be reported
/// as actual saved funds, and reminders never post financial events.
class GoalReminderCopy {
  const GoalReminderCopy._();

  static String weekBefore(SavingChallenge goal) {
    if (!goal.isBackingVerified) {
      return 'هدف ${goal.name} فيه خانات قديمة غير مثبتة بأموال '
          'الادخار. افتح الهدف لتوثيقها أو إعادة البدء.';
    }
    if (goal.isVerifiedComplete) {
      return 'هدف ${goal.name} مكتمل ومغطّى فعلياً من الادخار.';
    }
    final remaining = _remaining(goal);
    return 'بقي أسبوع على الموعد الذي حددته لهدف ${goal.name}. '
        'المبلغ غير المحجوز بعد: ${goal.currency.formatAmount(remaining)}. '
        'راجع خطتك إذا تغيّر الدخل أو المصاريف.';
  }

  static String onDeadline(SavingChallenge goal) {
    if (!goal.isBackingVerified) {
      return 'اليوم موعد هدف ${goal.name}، لكن خاناته القديمة '
          'غير موثّقة بأموال. افتح الهدف لمراجعة الرصيد الحقيقي.';
    }
    if (goal.isVerifiedComplete) {
      return 'موعد هدف ${goal.name}، وقد خُصص كامل المبلغ '
          'من الادخار الحقيقي.';
    }
    return 'اليوم الموعد الذي حددته لهدف ${goal.name}. '
        'المبلغ غير المحجوز بعد: '
        '${goal.currency.formatAmount(_remaining(goal))}. '
        'يمكنك تعديل الخطة أو الموعد حسب ظروفك.';
  }

  static int _remaining(SavingChallenge goal) {
    final missing = goal.targetAmount.toInt() -
        goal.verifiedSavedAmount;
    return missing < 0 ? 0 : missing;
  }
}
