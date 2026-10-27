import 'package:flutter/material.dart';

import '../theme/design_style.dart';

/// Interactive live theme preview card that reflects current [StyleColors] tokens.
/// Shows how the colors, borders, cards, text, buttons, and glow interact in
/// a miniature mock UI without having to leave the customization screen.
class ThemeLivePreviewCard extends StatelessWidget {
  const ThemeLivePreviewCard({
    super.key,
    required this.tokens,
    required this.style,
  });

  final StyleColors tokens;
  final DesignStyle style;

  @override
  Widget build(BuildContext context) {
    BoxDecoration cardDecoration;
    if (tokens.useHardShadow) {
      cardDecoration = BoxDecoration(
        color: tokens.background,
        borderRadius: BorderRadius.circular(tokens.radius.clamp(4.0, 10.0)),
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
      cardDecoration = BoxDecoration(
        color: tokens.background,
        borderRadius: BorderRadius.circular(tokens.radius),
        border: Border.all(
          color: tokens.border,
          width: tokens.borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: tokens.glow.withValues(alpha: 0.35),
            blurRadius: 10,
          ),
        ],
      );
    } else {
      cardDecoration = BoxDecoration(
        color: tokens.background,
        borderRadius: BorderRadius.circular(tokens.radius.clamp(8.0, 20.0)),
        border: Border.all(
          color: tokens.border,
          width: tokens.borderWidth.clamp(1.0, 2.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: tokens.isDark ? 0.2 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 140,
      decoration: cardDecoration,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radius.clamp(4.0, 20.0)),
        child: Stack(
          children: [
            // Ambient glow blob if style supports glow
            if (tokens.glowStrength > 0 && !tokens.useHardShadow)
              Positioned(
                top: -30,
                right: -20,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        tokens.glow.withValues(
                          alpha: (0.45 * tokens.glowStrength).clamp(0.0, 1.0),
                        ),
                        tokens.glow.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),

            // Content mockup inside the preview
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top bar: mini app title & status pill
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: tokens.highlight,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'CapuTune — ${style.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: tokens.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.accent.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(
                            tokens.useHardShadow ? 2 : tokens.radius * 0.4,
                          ),
                          border: Border.all(
                            color: tokens.border,
                            width: tokens.borderWidth.clamp(0.5, 1.5),
                          ),
                        ),
                        child: Text(
                          'LIVE',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: tokens.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),

                  // Mock track / card row
                  Row(
                    children: [
                      // Card / Album artwork stand-in
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: tokens.card,
                          borderRadius: BorderRadius.circular(
                            tokens.useHardShadow ? 2.0 : (tokens.radius * 0.5).clamp(4.0, 12.0),
                          ),
                          border: Border.all(
                            color: tokens.border,
                            width: tokens.borderWidth,
                          ),
                          boxShadow: tokens.useHardShadow
                              ? [
                                  BoxShadow(
                                    color: tokens.border,
                                    offset: const Offset(2, 2),
                                    blurRadius: 0,
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          Icons.music_note,
                          size: 24,
                          color: tokens.accent,
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Track info stand-in
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Cosmic Harmony',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: tokens.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Sample Artist • Album',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: tokens.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Action button with Accent background
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: tokens.accent,
                          shape: tokens.useHardShadow
                              ? BoxShape.rectangle
                              : (tokens.radius > 10 ? BoxShape.circle : BoxShape.rectangle),
                          borderRadius: tokens.useHardShadow
                              ? BorderRadius.circular(2)
                              : (tokens.radius <= 10
                                  ? BorderRadius.circular(tokens.radius * 0.5)
                                  : null),
                          border: tokens.useHardShadow
                              ? Border.all(color: tokens.border, width: 1.5)
                              : null,
                          boxShadow: tokens.useHardShadow
                              ? [
                                  BoxShadow(
                                    color: tokens.border,
                                    offset: const Offset(2, 2),
                                    blurRadius: 0,
                                  ),
                                ]
                              : (tokens.glowStrength > 0
                                  ? [
                                      BoxShadow(
                                        color: tokens.glow.withValues(alpha: 0.4),
                                        blurRadius: 6,
                                      ),
                                    ]
                                  : null),
                        ),
                        child: Icon(
                          Icons.play_arrow,
                          size: 20,
                          color: tokens.isDark
                              ? tokens.background
                              : Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Mini progress line
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Container(
                      height: 3,
                      width: double.infinity,
                      color: tokens.surface,
                      child: Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: Container(color: tokens.accent),
                          ),
                          Expanded(
                            flex: 6,
                            child: Container(
                              color: tokens.border.withValues(alpha: 0.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
