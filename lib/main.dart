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
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
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
    final ColorScheme colors = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool useRail = constraints.maxWidth >= 760;
        final bool extendedRail = constraints.maxWidth >= 1080;

        if (useRail) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: colors.outlineVariant.withValues(alpha: 0.75),
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: NavigationRail(
                          selectedIndex: _selectedIndex,
                          onDestinationSelected: _selectDestination,
                          extended: extendedRail,
                          labelType: extendedRail
                              ? NavigationRailLabelType.none
                              : NavigationRailLabelType.selected,
                          leading: Padding(
                            padding: const EdgeInsets.only(top: 18, bottom: 22),
                            child: extendedRail
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: colors.primary,
                                          borderRadius:
                                              BorderRadius.circular(13),
                                        ),
                                        alignment: Alignment.center,
                                        child: Icon(
                                          Icons.savings_rounded,
                                          color: colors.onPrimary,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Mo Save',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                    ],
                                  )
                                : Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: colors.primary,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.savings_rounded,
                                      color: colors.onPrimary,
                                      size: 23,
                                    ),
                                  ),
                          ),
                          destinations: _railDestinations,
                        ),
                      ),
                    ),
                  ),
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
            minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _selectDestination,
                  destinations: _bottomDestinations,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
