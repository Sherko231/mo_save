import 'package:shared_preferences/shared_preferences.dart';

class NotificationPreferences {
  const NotificationPreferences({
    required this.weeklyIncomeEnabled,
    required this.monthlyIncomeEnabled,
    required this.goalDeadlinesEnabled,
  });

  static const NotificationPreferences disabled = NotificationPreferences(
    weeklyIncomeEnabled: false,
    monthlyIncomeEnabled: false,
    goalDeadlinesEnabled: false,
  );

  final bool weeklyIncomeEnabled;
  final bool monthlyIncomeEnabled;
  final bool goalDeadlinesEnabled;

  bool get anyEnabled =>
      weeklyIncomeEnabled || monthlyIncomeEnabled || goalDeadlinesEnabled;
}

class NotificationPreferencesStorage {
  NotificationPreferencesStorage({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  static const String _weeklyIncomeKey =
      'notifications_weekly_income_enabled';
  static const String _monthlyIncomeKey =
      'notifications_monthly_income_enabled';
  static const String _goalDeadlinesKey =
      'notifications_goal_deadlines_enabled';

  final SharedPreferencesAsync _preferences;

  Future<NotificationPreferences> load() async {
    return NotificationPreferences(
      weeklyIncomeEnabled:
          await _preferences.getBool(_weeklyIncomeKey) ?? false,
      monthlyIncomeEnabled:
          await _preferences.getBool(_monthlyIncomeKey) ?? false,
      goalDeadlinesEnabled:
          await _preferences.getBool(_goalDeadlinesKey) ?? false,
    );
  }

  Future<void> save(NotificationPreferences preferences) async {
    await Future.wait<void>(<Future<void>>[
      _preferences.setBool(
        _weeklyIncomeKey,
        preferences.weeklyIncomeEnabled,
      ),
      _preferences.setBool(
        _monthlyIncomeKey,
        preferences.monthlyIncomeEnabled,
      ),
      _preferences.setBool(
        _goalDeadlinesKey,
        preferences.goalDeadlinesEnabled,
      ),
    ]);
  }
}
