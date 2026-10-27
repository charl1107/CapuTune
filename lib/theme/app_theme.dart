import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'design_style.dart';

class AppTheme {
  /// Builds a MaterialApp theme from the active [StyleColors] tokens.
  ///
  /// [dark] selects the brightness branch; [tokens.isDark] decides which one
  /// MaterialApp actually uses, so a light preset (neo-brutalism) renders its
  /// light branch and dark presets render theirs.
  static ThemeData fromTokens(StyleColors tokens, {required bool dark}) {
    final scheme = ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: tokens.accent,
      onPrimary: tokens.isDark ? tokens.background : Colors.white,
      secondary: tokens.highlight,
      onSecondary: tokens.isDark ? tokens.background : Colors.white,
      error: const Color(0xFFCF6679),
      onError: Colors.black,
      surface: tokens.surface,
      onSurface: tokens.textPrimary,
      surfaceContainerHighest: tokens.card,
      onSurfaceVariant: tokens.textSecondary,
      outline: tokens.border,
      outlineVariant: tokens.border,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.background,
      textTheme: GoogleFonts.interTextTheme(
        dark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        },
      ),
      cardTheme: CardThemeData(
        elevation: tokens.useHardShadow ? 3 : 0,
        color: tokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius),
          side: tokens.borderWidth > 0
              ? BorderSide(color: tokens.border, width: tokens.borderWidth)
              : BorderSide.none,
        ),
        shadowColor: tokens.useHardShadow
            ? tokens.border
            : (tokens.useNeonGlow
                ? tokens.glow.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.1)),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: tokens.background,
        foregroundColor: tokens.textPrimary,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tokens.surface,
        indicatorColor: tokens.accent.withValues(
            alpha: tokens.useNeonGlow ? 0.35 : (tokens.useHardShadow ? 0.2 : 0.25)),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? tokens.accent
                  : tokens.textSecondary,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? (tokens.useHardShadow ? FontWeight.w700 : FontWeight.w600)
                  : FontWeight.normal,
              color: states.contains(WidgetState.selected)
                  ? tokens.accent
                  : tokens.textSecondary,
            )),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: tokens.surface,
        contentTextStyle: TextStyle(color: tokens.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusM),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius),
          side: tokens.borderWidth > 0
              ? BorderSide(color: tokens.border, width: tokens.borderWidth)
              : BorderSide.none,
        ),
      ),
      dividerTheme: DividerThemeData(color: tokens.border),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.accent
              : tokens.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.accent.withValues(alpha: 0.4)
              : tokens.border,
        ),
      ),
    );
  }

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: AppColors.primaryLight,
    textTheme: GoogleFonts.interTextTheme(),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
      },
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppColors.radiusL)),
      ),
      shadowColor: Colors.black.withValues(alpha: 0.1),
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusM),
      ),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorSchemeSeed: AppColors.primaryDark,
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
      },
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppColors.radiusL)),
      ),
      shadowColor: Colors.black.withValues(alpha: 0.3),
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusM),
      ),
    ),
  );
}
