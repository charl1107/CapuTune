import 'package:flutter/material.dart';

/// The five named design styles CapuTune ships.
enum DesignStyle { glassmorphism, ambient, neobrutalism, premium, cyberpunk }

extension DesignStyleMeta on DesignStyle {
  String get label => switch (this) {
        DesignStyle.glassmorphism => 'Glassmorphism',
        DesignStyle.ambient => 'Ambient UI',
        DesignStyle.neobrutalism => 'Neo-brutalism',
        DesignStyle.premium => 'Premium UI',
        DesignStyle.cyberpunk => 'Cyberpunk',
      };
}

/// Central design tokens for one visual identity. Themed widgets read from
/// here (via ThemeService) instead of static constants, so a preset — or a
/// user recolor of one — restyles the app through a single object.
@immutable
class StyleColors {
  final Color background;
  final Color surface;
  final Color card;
  final Color accent;
  final Color highlight;
  final Color border;

  /// Ambient glow color + intensity multiplier (0 disables glows).
  final Color glow;
  final double glowStrength;

  final Color textPrimary;
  final Color textSecondary;

  /// Drives Brightness and dark-branch decisions app-wide.
  final bool isDark;

  /// Corner radius scale (neo-brutalism: small).
  final double radius;

  /// Card/panel border width (0 = none).
  final double borderWidth;

  /// Distinct visual treatment characteristics
  final bool useBlur;
  final bool useHardShadow;
  final bool useNeonGlow;

  const StyleColors({
    required this.background,
    required this.surface,
    required this.card,
    required this.accent,
    required this.highlight,
    required this.border,
    required this.glow,
    this.glowStrength = 1.0,
    required this.textPrimary,
    required this.textSecondary,
    required this.isDark,
    this.radius = 16.0,
    this.borderWidth = 0.5,
    this.useBlur = false,
    this.useHardShadow = false,
    this.useNeonGlow = false,
  });

  StyleColors copyWith({
    Color? background,
    Color? surface,
    Color? card,
    Color? accent,
    Color? highlight,
    Color? border,
    Color? glow,
    double? glowStrength,
    Color? textPrimary,
    Color? textSecondary,
    bool? isDark,
    double? radius,
    double? borderWidth,
    bool? useBlur,
    bool? useHardShadow,
    bool? useNeonGlow,
  }) {
    return StyleColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      accent: accent ?? this.accent,
      highlight: highlight ?? this.highlight,
      border: border ?? this.border,
      glow: glow ?? this.glow,
      glowStrength: glowStrength ?? this.glowStrength,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      isDark: isDark ?? this.isDark,
      radius: radius ?? this.radius,
      borderWidth: borderWidth ?? this.borderWidth,
      useBlur: useBlur ?? this.useBlur,
      useHardShadow: useHardShadow ?? this.useHardShadow,
      useNeonGlow: useNeonGlow ?? this.useNeonGlow,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'background': background.toARGB32(),
        'surface': surface.toARGB32(),
        'card': card.toARGB32(),
        'accent': accent.toARGB32(),
        'highlight': highlight.toARGB32(),
        'border': border.toARGB32(),
        'glow': glow.toARGB32(),
        'glowStrength': glowStrength,
        'textPrimary': textPrimary.toARGB32(),
        'textSecondary': textSecondary.toARGB32(),
        'isDark': isDark,
        'radius': radius,
        'borderWidth': borderWidth,
        'useBlur': useBlur,
        'useHardShadow': useHardShadow,
        'useNeonGlow': useNeonGlow,
      };

  /// Defensive decode: any missing/invalid field falls back to [base].
  ///
  /// The structural identity fields ([useBlur], [useHardShadow],
  /// [useNeonGlow], [radius], [borderWidth]) are *always* taken from [base]
  /// and never from [json]. That way a hand-edited or stale persisted payload
  /// cannot strip a preset's identity (e.g. turn Glassmorphism into a flat
  /// card), which is the same guarantee [ThemeService.updateColor] enforces
  /// at edit time.
  static StyleColors fromJson(Map<String, dynamic> json, StyleColors base) {
    Color? c(Object? v) => v is int ? Color(v) : null;
    double? n(Object? v) => v is num ? v.toDouble() : null;
    return base.copyWith(
      background: c(json['background']),
      surface: c(json['surface']),
      card: c(json['card']),
      accent: c(json['accent']),
      highlight: c(json['highlight']),
      border: c(json['border']),
      glow: c(json['glow']),
      glowStrength: n(json['glowStrength']),
      textPrimary: c(json['textPrimary']),
      textSecondary: c(json['textSecondary']),
      isDark: json['isDark'] is bool ? json['isDark'] as bool : null,
    );
  }
}

/// A saved custom theme: preset identity + user recolor + display name.
@immutable
class CustomTheme {
  final String id;
  final String name;
  final DesignStyle preset;
  final StyleColors colors;

  const CustomTheme({
    required this.id,
    required this.name,
    required this.preset,
    required this.colors,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'preset': preset.name,
        'colors': colors.toJson(),
      };

  /// Returns null for malformed payloads; the caller skips nulls instead of
  /// crashing theme construction.
  static CustomTheme? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final presetName = json['preset'];
    final colors = json['colors'];
    if (id is! String || name is! String || presetName is! String) return null;
    DesignStyle? preset;
    for (final s in DesignStyle.values) {
      if (s.name == presetName) preset = s;
    }
    if (preset == null || colors is! Map) return null;
    return CustomTheme(
      id: id,
      name: name,
      preset: preset,
      colors: StyleColors.fromJson(
        Map<String, dynamic>.from(colors),
        DesignStylePalettes.of(preset),
      ),
    );
  }
}

/// The five shipped palettes. Each has a deliberately distinct identity:
///
/// - glassmorphism: translucent charcoal glass with real blur, hairline borders, soft violet glow
/// - ambient: warm dark base, generous diffuse radial glow, soft visual depth
/// - neobrutalism: cream base, thick hard borders, solid surfaces, sharp offset shadows, zero glow
/// - premium: refined dark navy/slate, gold highlights, balanced spacing and restrained depth
/// - cyberpunk: near-black, electric cyan/magenta, luminous neon edge glow, high contrast
class DesignStylePalettes {
  DesignStylePalettes._();

  static const StyleColors glassmorphism = StyleColors(
    background: Color(0xFF0B0912),
    surface: Color(0xCC171221), // translucent
    card: Color(0xB8201A33),    // translucent
    accent: Color(0xFF7C4DFF),
    highlight: Color(0xFFB388FF),
    border: Color(0x33FFFFFF),  // hairline glass border
    glow: Color(0xFF7C4DFF),
    glowStrength: 0.9,
    textPrimary: Color(0xFFEDE7F6),
    textSecondary: Color(0xB3EDE7F6),
    isDark: true,
    radius: 16,
    borderWidth: 0.75,
    useBlur: true,
    useHardShadow: false,
    useNeonGlow: false,
  );

  static const StyleColors ambient = StyleColors(
    background: Color(0xFF12101E),
    surface: Color(0xFF1C1830),
    card: Color(0xFF241E3E),
    accent: Color(0xFF9575CD),
    highlight: Color(0xFF7986CB),
    border: Color(0x2EFFFFFF),
    glow: Color(0xFF9575CD),
    glowStrength: 1.5,
    textPrimary: Color(0xFFF3EFFB),
    textSecondary: Color(0x99F3EFFB),
    isDark: true,
    radius: 18,
    borderWidth: 0.5,
    useBlur: false,
    useHardShadow: false,
    useNeonGlow: false,
  );

  static const StyleColors neobrutalism = StyleColors(
    background: Color(0xFFF5F1E8),
    surface: Color(0xFFFDFAF3),
    card: Color(0xFFFFFFFF),
    accent: Color(0xFF1A1A1A),
    highlight: Color(0xFFFF5E5B),
    border: Color(0xFF111111),
    glow: Color(0x00000000),
    glowStrength: 0.0,
    textPrimary: Color(0xFF111111),
    textSecondary: Color(0xCC333333),
    isDark: false,
    radius: 4,
    borderWidth: 2.0,
    useBlur: false,
    useHardShadow: true,
    useNeonGlow: false,
  );

  static const StyleColors premium = StyleColors(
    background: Color(0xFF0E1016),
    surface: Color(0xFF151822),
    card: Color(0xFF1B1F2E),
    accent: Color(0xFFC9A96A),
    highlight: Color(0xFFE5CE9F),
    border: Color(0x2ECEB87C),
    glow: Color(0xFFC9A96A),
    glowStrength: 0.45,
    textPrimary: Color(0xFFF5F2EA),
    textSecondary: Color(0xA6F5F2EA),
    isDark: true,
    radius: 14,
    borderWidth: 0.5,
    useBlur: false,
    useHardShadow: false,
    useNeonGlow: false,
  );

  static const StyleColors cyberpunk = StyleColors(
    background: Color(0xFF060312),
    surface: Color(0xFF0E0A24),
    card: Color(0xFF151040),
    accent: Color(0xFF00E5FF),
    highlight: Color(0xFFFF2E88),
    border: Color(0xFF00E5FF),
    glow: Color(0xFF00E5FF),
    glowStrength: 1.8,
    textPrimary: Color(0xFFE0F7FF),
    textSecondary: Color(0x99E0F7FF),
    isDark: true,
    radius: 10,
    borderWidth: 1.2,
    useBlur: false,
    useHardShadow: false,
    useNeonGlow: true,
  );

  /// Palette for [style]; throws on unknown values, which cannot occur for
  /// the five-value enum.
  static StyleColors of(DesignStyle style) => switch (style) {
        DesignStyle.glassmorphism => glassmorphism,
        DesignStyle.ambient => ambient,
        DesignStyle.neobrutalism => neobrutalism,
        DesignStyle.premium => premium,
        DesignStyle.cyberpunk => cyberpunk,
      };
}
