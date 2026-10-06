# Mo Save — Local notifications

Issue #22 adds optional Android reminders without any backend or network dependency.

## Reminder types

Settings exposes three independent toggles, all disabled by default:

- weekly income reminder;
- monthly USD income reminder;
- saving-goal deadline reminders.

Enabling any reminder and saving Settings requests Android notification permission when the OS requires it. If permission is denied, Mo Save leaves all reminder toggles disabled instead of presenting notifications as active when the OS will block them.

## Scheduling rules

Reminders are scheduled at approximately 09:00 in the device's current local timezone. Android inexact alarms are used deliberately; Mo Save does not request exact-alarm permission.

### Weekly income

The reminder follows the editable weekly payday from financial Settings. It repeats on that weekday and includes the current configured weekly income amount. Saving a changed payday or amount cancels and recreates the reminder.

### Monthly income

The reminder follows the editable monthly payday and income amount. Mo Save schedules a rolling twelve future occurrences instead of using a fixed repeating day-of-month alarm. This preserves the recurring-income rule for paydays 29–31: when a configured day does not exist in a shorter month, that month's reminder moves to the final real calendar day.

The rolling schedule is refreshed whenever the app starts and whenever Settings are saved.

### Saving goals

For every incomplete challenge/goal that has a deadline, Mo Save schedules:

- one reminder seven days before the deadline when that time is still in the future;
- one reminder on the deadline date.

Goal reminders are recalculated from the current challenge rows. Challenge/ledger mutations trigger an app-lifetime refresh so changing progress, deadline or deleting/completing a goal removes stale pending reminders.

## Android integration

The Android app declares notification and boot-completed permissions and registers the scheduled-notification receivers required by `flutter_local_notifications`. Core-library desugaring is enabled for scheduled notification compatibility.

Boot/package-replacement receivers allow the notification plugin to restore pending schedules after supported Android reboot/update flows.

## Persistence

The three enable/disable switches are small local preferences stored with `SharedPreferencesAsync`. Financial payday/amount values remain in the existing SQLite financial settings record, and goal deadlines remain in the existing challenge rows. Notifications never become a second source of financial truth.

## Failure behavior

Notification initialization or scheduling failure must never block Mo Save from starting or prevent financial settings from being saved. Settings reports a warning if financial values were saved but the local reminder schedule could not be updated.
