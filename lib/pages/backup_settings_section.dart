import 'package:flutter/material.dart';

import '../services/backup_service.dart';
import '../services/notification_preferences_storage.dart';
import '../services/notification_service.dart';

class BackupSettingsSection extends StatefulWidget {
  const BackupSettingsSection({
    super.key,
    this.onRestored,
  });

  final Future<void> Function()? onRestored;

  @override
  State<BackupSettingsSection> createState() => _BackupSettingsSectionState();
}

class _BackupSettingsSectionState extends State<BackupSettingsSection> {
  final BackupService _backupService = BackupService();
  final NotificationPreferencesStorage _notificationPreferencesStorage =
      NotificationPreferencesStorage();
  bool _isBusy = false;

  Future<void> _exportBackup() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      final bool saved = await _backupService.exportToFile();
      if (!mounted || !saved) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ النسخة الاحتياطية.')),
      );
    } on BackupException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إنشاء النسخة الاحتياطية.')),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _restoreBackup() async {
    if (_isBusy) return;

    BackupPickResult? picked;
    setState(() => _isBusy = true);
    try {
      picked = await _backupService.pickBackupFile();
    } on BackupException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر قراءة ملف النسخة الاحتياطية.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }

    if (!mounted || picked == null) return;
    final BackupPickResult selected = picked;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('استعادة النسخة الاحتياطية؟'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('الملف: ${selected.fileName}'),
                const SizedBox(height: 8),
                Text(
                  'تاريخ النسخة: ${_formatDateTime(selected.summary.createdAt)}',
                ),
                Text('الحركات المالية: ${selected.summary.transactionCount}'),
                Text('أهداف الادخار: ${selected.summary.challengeCount}'),
                Text(
                  'بنود خطة المصاريف: ${selected.summary.expensePlanCount}',
                ),
                const SizedBox(height: 14),
                const Text(
                  'سيتم استبدال كل البيانات المحلية الحالية بمحتوى هذه النسخة. لا يمكن التراجع عن ذلك إلا إذا كنت تملك نسخة احتياطية أخرى.',
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.restore),
              label: const Text('استبدال واستعادة'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isBusy = true);
    try {
      await _backupService.restoreBackupBytes(selected.bytes);
      await _refreshRestoredNotifications();
      await widget.onRestored?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت استعادة النسخة الاحتياطية بنجاح.')),
      );
    } on BackupException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذرت الاستعادة. لم يتم اعتماد استعادة جزئية لقاعدة البيانات.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _refreshRestoredNotifications() async {
    try {
      NotificationPreferences preferences =
          await _notificationPreferencesStorage.load();
      if (preferences.anyEnabled) {
        final bool granted =
            await NotificationService.instance.requestPermission();
        if (!granted) {
          preferences = NotificationPreferences.disabled;
          await _notificationPreferencesStorage.save(preferences);
        }
      }
      await NotificationService.instance.rescheduleAll();
    } catch (_) {
      // Financial restore is already complete. Notification scheduling remains
      // optional and can be retried later from Settings.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'النسخ الاحتياطي والاستعادة',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'احفظ ملفاً يحتوي الإعدادات والسجل المالي والتحديات وخطة المصاريف. يمكنك استعادته على تثبيت جديد.',
            ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: _isBusy ? null : _exportBackup,
              icon: const Icon(Icons.download_outlined),
              label: const Text('تصدير نسخة احتياطية'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _isBusy ? null : _restoreBackup,
              icon: const Icon(Icons.restore_outlined),
              label: const Text('استعادة من ملف'),
            ),
            if (_isBusy) ...<Widget>[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 8),
            Text(
              'الاستعادة تستبدل البيانات الحالية كاملة ولا تدمج سجلين مختلفين.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDateTime(DateTime value) {
    final DateTime local = value.toLocal();
    return '${local.day}/${local.month}/${local.year} '
        '${_two(local.hour)}:${_two(local.minute)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
