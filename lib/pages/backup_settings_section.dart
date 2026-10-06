import 'package:flutter/material.dart';

import '../services/backup_service.dart';
import '../services/notification_preferences_storage.dart';
import '../services/notification_service.dart';
import '../ui/ux_components.dart';

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
    final ColorScheme colors = Theme.of(context).colorScheme;

    return UxSoftCard(
      tone: colors.primary,
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              UxIconBadge(
                icon: Icons.shield_rounded,
                tone: colors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'حماية بياناتك',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ملف واحد يحفظ الإعدادات والسجل والأهداف وخطة المصاريف.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isBusy ? null : _exportBackup,
            icon: const Icon(Icons.download_rounded),
            label: const Text('تصدير نسخة احتياطية'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _isBusy ? null : _restoreBackup,
            icon: const Icon(Icons.restore_rounded),
            label: const Text('استعادة من ملف'),
          ),
          if (_isBusy) ...<Widget>[
            const SizedBox(height: 14),
            const LinearProgressIndicator(minHeight: 6),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.info_outline_rounded,
                size: 17,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'الاستعادة تستبدل البيانات الحالية كاملة ولا تدمج سجلين مختلفين.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        ],
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
