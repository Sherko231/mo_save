import 'package:flutter/material.dart';

import 'pages/challenges_page.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'services/app_setup_storage.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final AppSetupStorage setupStorage = AppSetupStorage();
  final bool initialSetupComplete = await setupStorage.loadIsComplete();

  try {
    await NotificationService.instance.initialize();
    if (initialSetupComplete) {
      await NotificationService.instance.rescheduleAll();
    }
  } catch (_) {
    // Notifications are optional and must never prevent the finance app from
    // starting. Settings can retry scheduling later after user interaction.
  }
  NotificationService.instance.startAutomaticRefresh();

  runApp(
    MoSaveApp(
      initialSetupComplete: initialSetupComplete,
      setupStorage: setupStorage,
    ),
  );
}

class MoSaveApp extends StatefulWidget {
  const MoSaveApp({
    super.key,
    required this.initialSetupComplete,
    required this.setupStorage,
  });

  final bool initialSetupComplete;
  final AppSetupStorage setupStorage;

  @override
  State<MoSaveApp> createState() => _MoSaveAppState();
}

class _MoSaveAppState extends State<MoSaveApp> {
  late bool _setupComplete = widget.initialSetupComplete;

  Future<void> _completeInitialSetup() async {
    await widget.setupStorage.markComplete();
    if (!mounted) return;
    setState(() => _setupComplete = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: _setupComplete
          ? const AppShell()
          : Scaffold(
              body: SafeArea(
                child: SettingsPage(
                  initialSetup: true,
                  onInitialSetupComplete: _completeInitialSetup,
                ),
              ),
            ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _selectedIndex,
          children: <Widget>[
            HomePage(isActive: _selectedIndex == 0),
            ChallengesPage(isActive: _selectedIndex == 1),
            const SettingsPage(),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          destinations: const <NavigationDestination>[
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'الرئيسية',
            ),
            NavigationDestination(
              icon: Icon(Icons.emoji_events_outlined),
              selectedIcon: Icon(Icons.emoji_events),
              label: 'التحديات',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'الإعدادات',
            ),
          ],
        ),
      ),
    );
  }
}
