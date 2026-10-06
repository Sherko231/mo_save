import 'package:flutter/material.dart';

import '../ui/ux_components.dart';
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
    return SettingsPage(
      initialSetup: initialSetup,
      onInitialSetupComplete: onInitialSetupComplete,
      onOpenBackup: () => _openBackup(context),
    );
  }
}

class _BackupPage extends StatelessWidget {
  const _BackupPage({this.onRestored});

  final Future<void> Function()? onRestored;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('النسخ الاحتياطي')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: <Widget>[
            const UxInfoBanner(
              icon: Icons.shield_outlined,
              title: 'احتفظ بنسخة خارج الهاتف',
              body:
                  'الاستعادة تستبدل البيانات المحلية الحالية بالكامل. احفظ الملف في مكان آمن مثل الكمبيوتر أو مساحة تخزين سحابية.',
            ),
            const SizedBox(height: 12),
            BackupSettingsSection(onRestored: onRestored),
          ],
        ),
      ),
    );
  }
}
