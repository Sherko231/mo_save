import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'pages/challenges_page.dart';
import 'pages/home_page.dart';
import 'pages/settings_shell_page.dart';
import 'services/app_setup_storage.dart';
import 'services/notification_service.dart';
import 'ui/app_theme.dart';

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
  late bool _setupComplete;

  @override
  void initState() {
    super.initState();
    _setupComplete = widget.initialSetupComplete;
  }

  Future<void> _completeInitialSetup() async {
    await widget.setupStorage.markComplete();
    if (!mounted) return;
    setState(() => _setupComplete = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mo Save',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const <Locale>[Locale('ar')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      theme: AppTheme.light(),
      home: _setupComplete
          ? const AppShell()
          : Scaffold(
              body: SafeArea(
                child: SettingsShellPage(
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
  int _dataRevision = 0;

  static const List<NavigationDestination> _bottomDestinations =
      <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'الرئيسية',
    ),
    NavigationDestination(
      icon: Icon(Icons.flag_outlined),
      selectedIcon: Icon(Icons.flag_rounded),
      label: 'الأهداف',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings_rounded),
      label: 'الإعدادات',
    ),
  ];

  static const List<NavigationRailDestination> _railDestinations =
      <NavigationRailDestination>[
    NavigationRailDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: Text('الرئيسية'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.flag_outlined),
      selectedIcon: Icon(Icons.flag_rounded),
      label: Text('الأهداف'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings_rounded),
      label: Text('الإعدادات'),
    ),
  ];

  Future<void> _handleDataRestored() async {
    if (!mounted) return;
    setState(() => _dataRevision++);
  }

  void _selectDestination(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
  }

  Widget _content() {
    return IndexedStack(
      index: _selectedIndex,
      children: <Widget>[
        HomePage(
          key: ValueKey<String>('home-$_dataRevision'),
          isActive: _selectedIndex == 0,
        ),
        ChallengesPage(
          key: ValueKey<String>('challenges-$_dataRevision'),
          isActive: _selectedIndex == 1,
        ),
        SettingsShellPage(
          key: ValueKey<String>('settings-$_dataRevision'),
          onDataRestored: _handleDataRestored,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool useRail = constraints.maxWidth >= 760;
        final bool extendedRail = constraints.maxWidth >= 1080;

        if (useRail) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: <Widget>[
                  NavigationRail(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: _selectDestination,
                    extended: extendedRail,
                    labelType: extendedRail
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.selected,
                    leading: Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 18),
                      child: extendedRail
                          ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(Icons.savings_outlined),
                                SizedBox(width: 10),
                                Text('Mo Save'),
                              ],
                            )
                          : const Icon(Icons.savings_outlined),
                    ),
                    destinations: _railDestinations,
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: _content()),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          body: SafeArea(bottom: false, child: _content()),
          bottomNavigationBar: SafeArea(
            top: false,
            child: NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _selectDestination,
              destinations: _bottomDestinations,
            ),
          ),
        );
      },
    );
  }
}
