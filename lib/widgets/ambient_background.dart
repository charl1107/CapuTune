import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Full-screen ambient background: near-black charcoal base with restrained,
/// softly blurred violet/indigo lighting.
///
/// Cost model: one opaque base + three low-alpha radial blobs, painted once
/// per frame with zero saveLayers and zero BackdropFilters — cheap enough to
/// sit behind every tab. The page background stays continuous across screens
/// (§3: no separate colorful banner).
///
/// RepaintBoundary keeps the effect out of the content's repaint path:
/// scrolling content repaints on top of it without repainting the gradient.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? AppColors.charcoalDeep : AppColors.surfaceLight;
    final violet = isDark
        ? AppColors.ambientViolet.withValues(alpha: 0.10)
        : AppColors.ambientViolet.withValues(alpha: 0.06);
    final indigo = isDark
        ? AppColors.ambientIndigo.withValues(alpha: 0.12)
        : AppColors.ambientIndigo.withValues(alpha: 0.05);

    return DecoratedBox(
      decoration: BoxDecoration(color: base),
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _AmbientPainter(violet: violet, indigo: indigo),
          child: child,
        ),
      ),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter({required this.violet, required this.indigo});

  final Color violet;
  final Color indigo;

  @override
  void paint(Canvas canvas, Size size) {
    // Lighting is anchored to the top of the screen where the content is
    // sparsest (title row / section headings); artwork stays unobstructed.
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

    blob(
      Offset(size.width * 0.85, size.height * 0.06),
      size.width * 0.75,
      violet,
    );
    blob(
      Offset(size.width * 0.1, size.height * 0.22),
      size.width * 0.65,
      indigo,
    );
    // Faint floor glow ties the lower half to the palette without forming a
    // bright shape behind the artwork grid.
    blob(
      Offset(size.width * 0.5, size.height * 1.05),
      size.width * 0.9,
      violet.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(_AmbientPainter old) =>
      old.violet != violet || old.indigo != indigo;
}

/// Softly blurred violet halo rendered *behind* a glass panel. This is the
/// "ambient lighting behind selected areas" from the design brief — placed
/// behind selected glass (not behind artwork), limited to two halo layers
/// per screen, painted as one radial gradient each (no saveLayer, no blur).
///
/// [haloColor] derives from the ambient palette; [haloOpacity] keeps it
/// restrained by contract.
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark
        ? AppColors.ambientViolet.withValues(alpha: haloOpacity)
        : AppColors.ambientViolet.withValues(alpha: haloOpacity * 0.5);

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
          maxDim * 0.9,
          [color, color.withValues(alpha: 0)],
        ),
    );
  }

  @override
  bool shouldRepaint(_HaloPainter old) => old.color != color;
}
