import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary palette
  static const Color primaryLight = Color(0xFF6750A4);
  static const Color primaryDark = Color(0xFFD0BCFF);
  static const Color secondaryLight = Color(0xFF625B71);
  static const Color secondaryDark = Color(0xFFCCC2DC);

  // Accent colors
  static const Color accentPink = Color(0xFFE91E63);
  static const Color accentPurple = Color(0xFF9C27B0);
  static const Color accentBlue = Color(0xFF2196F3);

  // Surface colors
  static const Color surfaceLight = Color(0xFFFFFBFE);
  // Purple-tinted charcoal so cards read as lifted glass, not gray plastic.
  static const Color surfaceDark = Color(0xFF171221);
  static const Color surfaceVariantLight = Color(0xFFE7E0EC);
  static const Color surfaceVariantDark = Color(0xFF49454F);

  // Premium ambient palette: near-black charcoal base with deep-purple /
  // midnight-indigo lift. Used by the page background, never as a banner.
  static const Color charcoalDeep = Color(0xFF0B0912);
  static const Color charcoalMid = Color(0xFF141120);
  static const Color ambientViolet = Color(0xFF7C4DFF);
  static const Color ambientIndigo = Color(0xFF3F51B5);

  // Glass surfaces. Fills are gradients (top edge slightly brighter for the
  // gentle edge highlight); borders are low-contrast hairlines; shadow is
  // deliberately restrained. No heavy glows, no thick borders.
  static const List<Color> glassFillDark = [
    Color(0x2E201A33), // ~18% purple-charcoal at the top edge
    Color(0x1F171226), // ~12% at the bottom edge
  ];
  static const List<Color> glassFillLight = [
    Color(0xE6FFFFFF), // ~90% white at the top edge
    Color(0xCCFFFFFF), // ~80% at the bottom edge
  ];
  static const Color glassBorderDark = Color(0x24FFFFFF);
  static const Color glassBorderLight = Color(0x1A6750A4);

  static const LinearGradient glassGradientDark = LinearGradient(
    colors: glassFillDark,
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  static const LinearGradient glassGradientLight = LinearGradient(
    colors: glassFillLight,
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Status colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryLight, accentPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkGradient = LinearGradient(
    colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF2a2a3e), Color(0xFF1a1a2e)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Shadows
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.15),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get elevatedShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.25),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  // Spacing (8px grid)
  static const double spacingXS = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 16.0;
  static const double spacingL = 24.0;
  static const double spacingXL = 32.0;
  static const double spacingXXL = 48.0;

  // Border radius
  static const double radiusS = 8.0;
  static const double radiusM = 12.0;
  static const double radiusL = 16.0;
  static const double radiusXL = 24.0;
  static const double radiusFull = 999.0;
}
