import 'package:flutter/material.dart';

import 'backup_settings_section.dart';
import 'settings_page.dart';

class SettingsShellPage extends StatelessWidget {
  const SettingsShellPage({
    super.key,
    this.initialSetup = false,
    this.onInitialSetupComplete,
    this.onDataRestored,
  });

  final bool initialSetup;
  final Future<void> Function()? onInitialSetupComplete;
  final Future<void> Function()? onDataRestored;

  Future<void> _openBackup(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => _BackupPage(
          onRestored: initialSetup
              ? onInitialSetupComplete
              : onDataRestored,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        SettingsPage(
          initialSetup: initialSetup,
          onInitialSetupComplete: onInitialSetupComplete,
        ),
        PositionedDirectional(
          end: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: initialSetup ? 'initial-backup-fab' : 'settings-backup-fab',
            onPressed: () => _openBackup(context),
            icon: const Icon(Icons.backup_outlined),
            label: const Text('نسخ احتياطي'),
          ),
        ),
      ],
    );
  }
}

class _BackupPage extends StatelessWidget {
  const _BackupPage({this.onRestored});

  final Future<void> Function()? onRestored;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('النسخ الاحتياطي')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: <Widget>[
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'احفظ النسخة في مكان خارج الهاتف مثل Google Drive أو الكمبيوتر. الاستعادة من ملف تستبدل البيانات المحلية الحالية بالكامل.',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              BackupSettingsSection(onRestored: onRestored),
            ],
          ),
        ),
      ),
    );
  }
}
