import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/financial_settings.dart';
import '../models/saving_challenge.dart';
import 'challenge_storage.dart';
import 'financial_settings_storage.dart';
import 'notification_preferences_storage.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String _payloadPrefix = 'mo_save:';
  static const String _goalPayloadPrefix = '${_payloadPrefix}goal:';
  static const int _weeklyIncomeId = 22001;
  static const int _monthlyIncomeBaseId = 22100;
  static const int _goalBaseId = 30000;
  static const int _reminderHour = 9;

  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
    'mo_save_reminders',
    'تذكيرات Mo Save',
    channelDescription: 'تذكيرات الرواتب ومواعيد أهداف الادخار',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static const NotificationDetails _notificationDetails = NotificationDetails(
    android: _androidDetails,
  );

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final NotificationPreferencesStorage _preferencesStorage =
      NotificationPreferencesStorage();
  final FinancialSettingsStorage _settingsStorage = FinancialSettingsStorage();
  final ChallengeStorage _challengeStorage = ChallengeStorage();

  bool _initialized = false;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() async {
    if (_initialized || !_isAndroid) return;

    tz_data.initializeTimeZones();
    try {
      final timezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezone.name));
    } catch (_) {
      // The timezone package defaults to Etc/UTC. Scheduling still remains
      // functional if a device returns an unrecognized timezone identifier.
    }

    const InitializationSettings settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_launcher'),
    );
    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    if (!_isAndroid) return true;
    await initialize();
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final bool? granted = await android?.requestNotificationsPermission();
    return granted ?? true;
  }

  Future<void> rescheduleAll() async {
    if (!_isAndroid) return;
    await initialize();

    final NotificationPreferences preferences =
        await _preferencesStorage.load();
    final FinancialSettings settings = await _settingsStorage.loadSettings();

    await _cancelManagedNotifications();

    if (preferences.weeklyIncomeEnabled && settings.weeklySypIncome > 0) {
      await _scheduleWeeklyIncome(settings);
    }
    if (preferences.monthlyIncomeEnabled && settings.monthlyUsdIncome > 0) {
      await _scheduleMonthlyIncome(settings);
    }
    if (preferences.goalDeadlinesEnabled) {
      await _scheduleGoalReminders();
    }
  }

  Future<void> rescheduleGoalNotifications() async {
    if (!_isAndroid) return;
    await initialize();

    await _cancelPendingWhere(
      (request) => request.payload?.startsWith(_goalPayloadPrefix) ?? false,
    );

    final NotificationPreferences preferences =
        await _preferencesStorage.load();
    if (!preferences.goalDeadlinesEnabled) return;
    await _scheduleGoalReminders();
  }

  Future<void> _scheduleWeeklyIncome(FinancialSettings settings) async {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime next = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      _reminderHour,
    );

    while (next.weekday != settings.weeklyPayday || !next.isAfter(now)) {
      next = tz.TZDateTime(
        tz.local,
        next.year,
        next.month,
        next.day + 1,
        _reminderHour,
      );
    }

    await _plugin.zonedSchedule(
      id: _weeklyIncomeId,
      title: 'موعد راتب الأسبوع',
      body:
          'راتب الأسبوع اليوم (${_formatAmount(settings.weeklySypIncome)} ل.س). '
          'أكد الاستلام بعد القبض.',
      scheduledDate: next,
      notificationDetails: _notificationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      payload: '${_payloadPrefix}weekly-income',
    );
  }

  Future<void> _scheduleMonthlyIncome(FinancialSettings settings) async {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    int scheduledCount = 0;

    // Schedule a rolling year instead of using a repeating day-of-month alarm.
    // This preserves the app's payday rule where days 29-31 clamp to the last
    // real calendar day in shorter months.
    for (int offset = 0; offset < 14 && scheduledCount < 12; offset++) {
      final int year = now.year + ((now.month - 1 + offset) ~/ 12);
      final int month = ((now.month - 1 + offset) % 12) + 1;
      final int daysInMonth = DateTime(year, month + 1, 0).day;
      final int day = settings.monthlyPayday.clamp(1, daysInMonth).toInt();
      final tz.TZDateTime candidate = tz.TZDateTime(
        tz.local,
        year,
        month,
        day,
        _reminderHour,
      );
      if (!candidate.isAfter(now)) continue;

      await _plugin.zonedSchedule(
        id: _monthlyIncomeBaseId + scheduledCount,
        title: 'موعد الراتب الشهري',
        body:
            'موعد راتب الشهر اليوم (${_formatUsd(settings.monthlyUsdIncome)}). '
            'أكد الاستلام بعد القبض.',
        scheduledDate: candidate,
        notificationDetails: _notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload:
            '${_payloadPrefix}monthly-income:${candidate.year}-${candidate.month}-${candidate.day}',
      );
      scheduledCount++;
    }
  }

  Future<void> _scheduleGoalReminders() async {
    final List<SavingChallenge> challenges =
        await _challengeStorage.loadChallenges();
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    int notificationIndex = 0;

    for (final SavingChallenge challenge in challenges) {
      final DateTime? deadline = challenge.deadline;
      if (deadline == null || challenge.isComplete) continue;

      final DateTime localDeadline = deadline.toLocal();
      final tz.TZDateTime due = tz.TZDateTime(
        tz.local,
        localDeadline.year,
        localDeadline.month,
        localDeadline.day,
        _reminderHour,
      );
      if (!due.isAfter(now)) continue;

      final tz.TZDateTime weekBefore = due.subtract(const Duration(days: 7));
      if (weekBefore.isAfter(now)) {
        await _plugin.zonedSchedule(
          id: _goalBaseId + notificationIndex++,
          title: 'بقي أسبوع على هدف ${challenge.name}',
          body:
              'المتبقي ${challenge.currency.formatAmount(challenge.remainingAmount)}. '
              'راجع تقدم الهدف قبل الموعد.',
          scheduledDate: weekBefore,
          notificationDetails: _notificationDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: '$_goalPayloadPrefix${challenge.id}:week',
        );
      }

      await _plugin.zonedSchedule(
        id: _goalBaseId + notificationIndex++,
        title: 'موعد هدف ${challenge.name}',
        body:
            'اليوم الموعد المحدد للهدف. المتبقي '
            '${challenge.currency.formatAmount(challenge.remainingAmount)}.',
        scheduledDate: due,
        notificationDetails: _notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: '$_goalPayloadPrefix${challenge.id}:due',
      );
    }
  }

  Future<void> _cancelManagedNotifications() async {
    await _cancelPendingWhere(
      (request) => request.payload?.startsWith(_payloadPrefix) ?? false,
    );
  }

  Future<void> _cancelPendingWhere(
    bool Function(PendingNotificationRequest request) predicate,
  ) async {
    final List<PendingNotificationRequest> pending =
        await _plugin.pendingNotificationRequests();
    for (final PendingNotificationRequest request in pending) {
      if (predicate(request)) {
        await _plugin.cancel(id: request.id);
      }
    }
  }

  static String _formatAmount(num amount) {
    final String digits = amount.round().toString();
    final StringBuffer output = StringBuffer();
    for (int index = 0; index < digits.length; index++) {
      final int remaining = digits.length - index;
      output.write(digits[index]);
      if (remaining > 1 && remaining % 3 == 1) output.write(',');
    }
    return output.toString();
  }

  static String _formatUsd(double amount) {
    final String value = amount == amount.roundToDouble()
        ? amount.toInt().toString()
        : amount.toStringAsFixed(2);
    return '\$$value';
  }
}
