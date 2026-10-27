import 'package:flutter/material.dart';

import '../theme/design_style.dart';

/// Compact visual thumbnail of a design style: a mini Home-card composition
/// painted from that style's palette. Used by the first-launch modal and the
/// Appearance settings; no screenshots, no network, cheap to build.
class StylePreview extends StatelessWidget {
  const StylePreview({super.key, required this.style, this.size = const Size(72, 48)});

  final DesignStyle style;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final t = DesignStylePalettes.of(style);

    BoxDecoration boxDecoration;
    if (t.useHardShadow) {
      boxDecoration = BoxDecoration(
        color: t.background,
        borderRadius: BorderRadius.circular(t.radius * 0.5),
        border: Border.all(color: t.border, width: t.borderWidth.clamp(1.5, 3.0)),
        boxShadow: [
          BoxShadow(
            color: t.border,
            offset: const Offset(2, 2),
            blurRadius: 0,
          ),
        ],
      );
    } else if (t.useNeonGlow) {
      boxDecoration = BoxDecoration(
        color: t.background,
        borderRadius: BorderRadius.circular(t.radius * 0.5),
        border: Border.all(color: t.border, width: t.borderWidth),
        boxShadow: [
          BoxShadow(
            color: t.glow.withValues(alpha: 0.35),
            blurRadius: 6,
          ),
        ],
      );
    } else {
      boxDecoration = BoxDecoration(
        color: t.background,
        borderRadius: BorderRadius.circular(t.radius * 0.5),
        border: Border.all(color: t.border, width: t.borderWidth.clamp(0.5, 2.0)),
      );
    }

    return Container(
      width: size.width,
      height: size.height,
      decoration: boxDecoration,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(t.radius * 0.5),
        child: Stack(
          children: [
            // ambient glow wash
            if (t.glowStrength > 0)
              Positioned(
                right: -size.width * 0.2,
                top: -size.height * 0.3,
                child: Container(
                  width: size.width * 0.7,
                  height: size.height * 0.9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        t.glow.withValues(alpha: 0.55 * t.glowStrength.clamp(0.0, 1.0)),
                        t.glow.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            // a "card"
            Positioned(
              left: 6,
              top: 8,
              child: Container(
                width: size.width * 0.42,
                height: size.height * 0.55,
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(t.radius * 0.45),
                  border: Border.all(color: t.border, width: t.borderWidth),
                  boxShadow: t.useHardShadow
                      ? [
                          BoxShadow(
                            color: t.border,
                            offset: const Offset(1.5, 1.5),
                            blurRadius: 0,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
            // accent bar + highlight dot (text stand-ins)
            Positioned(
              left: 8,
              bottom: 7,
              child: Container(
                width: size.width * 0.30,
                height: 3,
                decoration: BoxDecoration(
                  color: t.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 7,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: t.highlight, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
