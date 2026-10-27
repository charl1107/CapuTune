import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/theme_service.dart';

/// Full-screen background that respects the selected design style's visual characteristics.
///
/// - Ambient UI: Rich atmospheric radial glow blobs, diffuse lighting.
/// - Glassmorphism: Subtle soft glow behind translucent glass surfaces.
/// - Cyberpunk / Neon: High-contrast void background with targeted vivid neon edge glow.
/// - Premium UI: Restrained subtle warm glow, rich deep dark base.
/// - Neo-brutalism: Flat solid architectural cream background, zero glow blobs.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.watch<ThemeService>().colors;
    final base = tokens.background;

    // Neo-brutalism relies on bold, solid, architectural surfaces without blur or glow.
    if (tokens.glowStrength <= 0.05 || tokens.useHardShadow) {
      return DecoratedBox(
        decoration: BoxDecoration(color: base),
        child: child,
      );
    }

    final glowColor = tokens.glow;
    final primaryGlow = glowColor.withValues(
      alpha: (0.12 * tokens.glowStrength).clamp(0.0, 0.4),
    );
    final secondaryGlow = tokens.highlight.withValues(
      alpha: (0.09 * tokens.glowStrength).clamp(0.0, 0.35),
    );

    return DecoratedBox(
      decoration: BoxDecoration(color: base),
      child: RepaintBoundary(
        child: CustomPaint(
          painter: AmbientBackgroundPainter(
            primaryGlow: primaryGlow,
            secondaryGlow: secondaryGlow,
            isCyberpunk: tokens.useNeonGlow,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Paints the ambient glow layer for the active design style.
///
/// Public so tests can assert that a flat style (neo-brutalism) never
/// installs a painter, while the atmospheric styles do.
class AmbientBackgroundPainter extends CustomPainter {
  const AmbientBackgroundPainter({
    required this.primaryGlow,
    required this.secondaryGlow,
    required this.isCyberpunk,
  });

  final Color primaryGlow;
  final Color secondaryGlow;
  final bool isCyberpunk;

  @override
  void paint(Canvas canvas, Size size) {
    void blob(Offset center, double radius, Color color) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(
            center,
            radius,
            [color, color.withValues(alpha: 0)],
          ),
      );
    }

    if (isCyberpunk) {
      // Cyberpunk: sharp, high-energy neon atmospheric bursts at the upper corner and bottom edge
      blob(
        Offset(size.width * 0.9, size.height * 0.04),
        size.width * 0.65,
        primaryGlow,
      );
      blob(
        Offset(size.width * 0.1, size.height * 0.25),
        size.width * 0.55,
        secondaryGlow,
      );
      blob(
        Offset(size.width * 0.5, size.height * 0.95),
        size.width * 0.7,
        primaryGlow.withValues(alpha: primaryGlow.a * 0.7),
      );
    } else {
      // Ambient UI / Glassmorphism / Premium UI: Smooth, broad atmospheric lighting
      blob(
        Offset(size.width * 0.85, size.height * 0.06),
        size.width * 0.75,
        primaryGlow,
      );
      blob(
        Offset(size.width * 0.1, size.height * 0.22),
        size.width * 0.65,
        secondaryGlow,
      );
      blob(
        Offset(size.width * 0.5, size.height * 1.05),
        size.width * 0.9,
        primaryGlow.withValues(alpha: primaryGlow.a * 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(AmbientBackgroundPainter old) =>
      old.primaryGlow != primaryGlow ||
      old.secondaryGlow != secondaryGlow ||
      old.isCyberpunk != isCyberpunk;
}

/// Softly blurred halo rendered behind selected cards/panels.
class AmbientHalo extends StatelessWidget {
  const AmbientHalo({
    super.key,
    required this.child,
    this.haloOpacity = 0.18,
  });

  final Widget child;
  final double haloOpacity;

  @override
  Widget build(BuildContext context) {
    final tokens = context.watch<ThemeService>().colors;
    if (tokens.glowStrength <= 0.05 || tokens.useHardShadow) {
      return child;
    }

    final color = tokens.glow.withValues(
      alpha: haloOpacity * tokens.glowStrength,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _HaloPainter(color: color),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _HaloPainter extends CustomPainter {
  const _HaloPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final maxDim = math.max(size.width, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          rect.center,
          maxDim * 0.75,
          [color, color.withValues(alpha: 0)],
        ),
    );
  }

  @override
  bool shouldRepaint(_HaloPainter old) => old.color != color;
}
