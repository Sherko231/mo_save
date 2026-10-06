import 'package:flutter/material.dart';

class AppPalette {
  const AppPalette._();

  static const Color emerald = Color(0xFF0B7A66);
  static const Color emeraldDeep = Color(0xFF07584C);
  static const Color forest = Color(0xFF123A34);
  static const Color mint = Color(0xFFDDF4EC);
  static const Color mintSoft = Color(0xFFF0F8F5);
  static const Color gold = Color(0xFFC89232);
  static const Color goldSoft = Color(0xFFF8EEDB);
  static const Color ink = Color(0xFF16201D);
  static const Color muted = Color(0xFF66736F);
  static const Color canvas = Color(0xFFF4F7F5);
  static const Color surface = Color(0xFFFBFCFA);
  static const Color danger = Color(0xFFB94C4C);

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: <Color>[
      Color(0xFF0B7A66),
      Color(0xFF07584C),
      Color(0xFF123A34),
    ],
  );

  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: <Color>[
      Color(0xFFF6DFB0),
      Color(0xFFE8C675),
    ],
  );
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(
        brightness: Brightness.light,
        scaffold: AppPalette.canvas,
        surface: AppPalette.surface,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        scaffold: const Color(0xFF0E1513),
        surface: const Color(0xFF151E1B),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color scaffold,
    required Color surface,
  }) {
    final bool dark = brightness == Brightness.dark;
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppPalette.emerald,
      brightness: brightness,
    ).copyWith(
      primary: dark ? const Color(0xFF79D8BE) : AppPalette.emerald,
      onPrimary: dark ? const Color(0xFF00382E) : Colors.white,
      primaryContainer:
          dark ? const Color(0xFF0F4A40) : const Color(0xFFD8F1E9),
      onPrimaryContainer:
          dark ? const Color(0xFFB6F3E1) : const Color(0xFF073A32),
      secondary: dark ? const Color(0xFFB8C9C3) : const Color(0xFF4C635C),
      secondaryContainer:
          dark ? const Color(0xFF31443E) : const Color(0xFFDDE9E5),
      onSecondaryContainer:
          dark ? const Color(0xFFDDEAE5) : const Color(0xFF24362F),
      tertiary: dark ? const Color(0xFFE8C879) : AppPalette.gold,
      tertiaryContainer:
          dark ? const Color(0xFF4D3A13) : const Color(0xFFF8EBCF),
      onTertiaryContainer:
          dark ? const Color(0xFFFFE8AD) : const Color(0xFF4B3510),
      error: dark ? const Color(0xFFFFB4AB) : AppPalette.danger,
      surface: surface,
      onSurface: dark ? const Color(0xFFE8EEEB) : AppPalette.ink,
      onSurfaceVariant:
          dark ? const Color(0xFFB9C6C1) : const Color(0xFF5E6A66),
      outline: dark ? const Color(0xFF7C8A85) : const Color(0xFF87948F),
      outlineVariant:
          dark ? const Color(0xFF3B4844) : const Color(0xFFD5DEDA),
    );

    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
    );

    final TextTheme text = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        height: 1.15,
      ),
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
        height: 1.18,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        height: 1.2,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        height: 1.22,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.55),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
      bodySmall: base.textTheme.bodySmall?.copyWith(height: 1.45),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      labelMedium: base.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    );

    return base.copyWith(
      textTheme: text,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: dark ? 0.24 : 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: dark ? 0.7 : 0.8),
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.72),
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark
            ? scheme.surfaceContainerHigh.withValues(alpha: 0.42)
            : const Color(0xFFF6F9F7),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary, width: 1.7),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.error, width: 1.7),
        ),
        labelStyle: text.bodyMedium,
        helperStyle: text.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        helperMaxLines: 3,
        errorMaxLines: 3,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 54),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 0,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 3,
        highlightElevation: 5,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return text.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        useIndicator: true,
        minWidth: 78,
        minExtendedWidth: 206,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        selectedLabelTextStyle: text.labelLarge?.copyWith(
          color: scheme.primary,
        ),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: scheme.surfaceContainerLow,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        labelStyle: text.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 2,
        backgroundColor:
            dark ? const Color(0xFF23302C) : const Color(0xFF20302B),
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 8,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        iconColor: scheme.primary,
        collapsedIconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        elevation: 6,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }
}
