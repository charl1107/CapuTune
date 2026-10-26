import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Reusable glass surface for panels, cards, and floating controls.
///
/// Cost model (deliberately minimal):
/// - No BackdropFilter by default — the tinted gradient fill, hairline
///   border, and top-edge highlight already read as glass over the ambient
///   background at near-zero rasterizer cost, keeping long lists smooth on
///   low-powered Android devices (§3 performance constraints).
/// - [blur] is opt-in for the few genuinely floating elements that sit over
///   scrolling content (update banner, mini-player chrome). Keep total live
///   BackdropFilters scarce and never stack them.
/// Fill/border tokens live in [AppColors] so both themes share one recipe.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.blur = false,
    this.radius = AppColors.radiusL,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final bool blur;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gradient =
        isDark ? AppColors.glassGradientDark : AppColors.glassGradientLight;
    final borderColor =
        isDark ? AppColors.glassBorderDark : AppColors.glassBorderLight;

    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: gradient,
      border: Border.all(color: borderColor, width: 0.5),
    );

    if (!blur) {
      return DecoratedBox(
        decoration: decoration,
        child: Padding(padding: padding, child: child),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: decoration,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
