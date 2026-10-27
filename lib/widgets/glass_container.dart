import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/theme_service.dart';

/// Reusable theme-aware surface for panels, cards, and floating controls.
/// Adapts genuinely to each of the 5 design styles:
///
/// - Glassmorphism: Translucent surface revealing background blur via [BackdropFilter],
///   subtle glass hairline border, top-edge highlight.
/// - Ambient UI: Smooth surface with soft border and subtle diffuse illumination.
/// - Neo-brutalism: Solid opaque surface with bold high-contrast border and hard offset drop shadow.
/// - Premium UI: Refined surface fill with restrained metallic/gold border and subtle depth.
/// - Cyberpunk / Neon: Dark futuristic surface with vivid neon border and selective neon glow.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.blur,
    this.radius,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final bool? blur;
  final double? radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final tokens = context.watch<ThemeService>().colors;
    final r = radius ?? tokens.radius;
    final shouldBlur = blur ?? tokens.useBlur;

    // Distinct decorations per style
    BoxDecoration decoration;
    if (tokens.useHardShadow) {
      // Neo-brutalism: bold black/dark borders and sharp, unblurred offset shadow
      decoration = BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(r),
        border: Border.all(
          color: tokens.border,
          width: tokens.borderWidth.clamp(1.5, 3.0),
        ),
        boxShadow: [
          BoxShadow(
            color: tokens.border,
            offset: const Offset(4, 4),
            blurRadius: 0,
          ),
        ],
      );
    } else if (tokens.useNeonGlow) {
      // Cyberpunk / Neon: High contrast dark card with neon-lit border & glow
      decoration = BoxDecoration(
        color: tokens.card.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(r),
        border: Border.all(
          color: tokens.border,
          width: tokens.borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: tokens.glow.withValues(alpha: 0.35),
            blurRadius: 10,
            spreadRadius: 0.5,
          ),
        ],
      );
    } else if (tokens.useBlur) {
      // Glassmorphism: Translucent frosted glass with hairline highlight border
      decoration = BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tokens.card.withValues(alpha: 0.70),
            tokens.surface.withValues(alpha: 0.82),
          ],
        ),
        border: Border.all(
          color: tokens.border,
          width: tokens.borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      );
    } else {
      // Ambient UI / Premium UI: Refined smooth card
      decoration = BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(r),
        border: Border.all(
          color: tokens.border,
          width: tokens.borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: tokens.isDark ? 0.2 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
          if (tokens.glowStrength > 0.8)
            BoxShadow(
              color: tokens.glow.withValues(alpha: 0.15 * tokens.glowStrength),
              blurRadius: 12,
            ),
        ],
      );
    }

    if (shouldBlur) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DecoratedBox(
            decoration: decoration,
            child: Padding(padding: padding, child: child),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: decoration,
      child: Padding(padding: padding, child: child),
    );
  }
}
