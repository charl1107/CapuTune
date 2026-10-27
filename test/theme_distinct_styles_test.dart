import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'package:caputune/models/song.dart';
import 'package:caputune/theme/design_style.dart';
import 'package:caputune/widgets/glass_container.dart';
import 'package:caputune/widgets/song_card.dart';
import 'package:caputune/widgets/ambient_background.dart';
import 'package:caputune/services/theme_service.dart';
import 'package:caputune/services/storage_service.dart';

Future<void> _initTestStorage(WidgetTester tester) async {
  late Directory tempDir;
  await tester.runAsync(() async {
    tempDir = await Directory.systemTemp.createTemp('caputune_theme_styles_test');
    Hive.init(tempDir.path);
    await StorageService.init();
  });
  addTearDown(() => tempDir.deleteSync(recursive: true));
}

/// Pumps [child] with the given preset active.
Future<void> _pumpWithStyle(
  WidgetTester tester,
  DesignStyle style,
  Widget child,
) async {
  final themeService = ThemeService();
  themeService.selectPreset(style);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeService>.value(
      value: themeService,
      child: MaterialApp(
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Collects every BoxDecoration applied in the subtree.
List<BoxDecoration> _decorations(WidgetTester tester) {
  final result = <BoxDecoration>[];
  for (final widget in tester.widgetList(find.byType(DecoratedBox))) {
    final decoration = (widget as DecoratedBox).decoration;
    if (decoration is BoxDecoration) result.add(decoration);
  }
  return result;
}

void main() {
  test('Each of the five presets has distinct styling tokens', () {
    const glass = DesignStylePalettes.glassmorphism;
    const ambient = DesignStylePalettes.ambient;
    const neo = DesignStylePalettes.neobrutalism;
    const premium = DesignStylePalettes.premium;
    const cyberpunk = DesignStylePalettes.cyberpunk;

    // Glassmorphism: blur enabled, translucent surface
    expect(glass.useBlur, isTrue);
    expect(glass.useHardShadow, isFalse);
    expect(glass.useNeonGlow, isFalse);

    // Ambient UI: diffuse ambient glow, rich glow strength
    expect(ambient.useBlur, isFalse);
    expect(ambient.glowStrength, greaterThan(1.0));

    // Neo-brutalism: hard drop shadow, thick border, zero glow
    expect(neo.useHardShadow, isTrue);
    expect(neo.borderWidth, greaterThanOrEqualTo(2.0));
    expect(neo.glowStrength, equals(0.0));

    // Premium UI: subtle metallic gold, restrained glow
    expect(premium.useHardShadow, isFalse);
    expect(premium.glowStrength, inInclusiveRange(0.2, 0.6));

    // Cyberpunk: neon edge glow, high glow strength
    expect(cyberpunk.useNeonGlow, isTrue);
    expect(cyberpunk.glowStrength, greaterThan(1.5));
  });

  test('Every preset uses a unique palette (no two styles share colors)', () {
    final palettes = {
      for (final style in DesignStyle.values)
        style: DesignStylePalettes.of(style),
    };

    final fingerprints = <String, DesignStyle>{};
    for (final entry in palettes.entries) {
      final t = entry.value;
      final fingerprint = [
        t.background.toARGB32(),
        t.surface.toARGB32(),
        t.card.toARGB32(),
        t.accent.toARGB32(),
        t.highlight.toARGB32(),
        t.border.toARGB32(),
        t.glow.toARGB32(),
        t.glowStrength,
        t.textPrimary.toARGB32(),
        t.textSecondary.toARGB32(),
        t.isDark,
        t.radius,
        t.borderWidth,
        t.useBlur,
        t.useHardShadow,
        t.useNeonGlow,
      ].join('|');
      expect(
        fingerprints.containsKey(fingerprint),
        isFalse,
        reason: '${entry.key} collides with ${fingerprints[fingerprint]}',
      );
      fingerprints[fingerprint] = entry.key;
    }
    expect(fingerprints, hasLength(DesignStyle.values.length));
  });

  group('Recoloring preserves preset identity', () {
    testWidgets('updateColor keeps the base preset structural flags',
        (tester) async {
      await _initTestStorage(tester);
      final service = ThemeService();

      for (final style in DesignStyle.values) {
        service.selectPreset(style);
        final base = DesignStylePalettes.of(style);

        service.updateColor(
          (t) => t.copyWith(
            accent: const Color(0xFF123456),
            background: const Color(0xFF654321),
            border: const Color(0xFFABCDEF),
            glow: const Color(0xFF00FF00),
          ),
        );

        final updated = service.colors;
        expect(updated.accent, const Color(0xFF123456));
        expect(updated.background, const Color(0xFF654321));
        // Structural identity must be untouched by the recolor.
        expect(updated.useBlur, base.useBlur);
        expect(updated.useHardShadow, base.useHardShadow);
        expect(updated.useNeonGlow, base.useNeonGlow);
        expect(updated.radius, base.radius);
        expect(updated.borderWidth, base.borderWidth);
      }
    });
  });

  testWidgets('Neo-brutalism surfaces use a hard shadow and no blur',
      (tester) async {
    await _initTestStorage(tester);
    await _pumpWithStyle(
      tester,
      DesignStyle.neobrutalism,
      const GlassContainer(child: Text('Card Content')),
    );

    expect(find.text('Card Content'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);

    final shadows = _decorations(tester).expand((d) => d.boxShadow ?? []);
    expect(shadows, isNotEmpty);
    expect(
      shadows.any((s) => s.blurRadius == 0 && s.offset != Offset.zero),
      isTrue,
      reason: 'Neo-brutalism needs a sharp offset shadow',
    );
  });

  testWidgets('Glassmorphism surfaces use a real BackdropFilter',
      (tester) async {
    await _initTestStorage(tester);
    await _pumpWithStyle(
      tester,
      DesignStyle.glassmorphism,
      const GlassContainer(child: Text('Card Content')),
    );

    expect(find.text('Card Content'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(ClipRRect), findsWidgets);
  });

  testWidgets('Cyberpunk surfaces use a neon glow, not a blur',
      (tester) async {
    await _initTestStorage(tester);
    await _pumpWithStyle(
      tester,
      DesignStyle.cyberpunk,
      const GlassContainer(child: Text('Card Content')),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    final shadows = _decorations(tester).expand((d) => d.boxShadow ?? []);
    expect(
      shadows.any((s) => s.blurRadius > 0),
      isTrue,
      reason: 'Cyberpunk needs a luminous edge glow',
    );
  });

  testWidgets('Neo-brutalism background is flat (no painted glow layer)',
      (tester) async {
    await _initTestStorage(tester);
    await _pumpWithStyle(
      tester,
      DesignStyle.neobrutalism,
      const AmbientBackground(child: Text('Body')),
    );

    expect(find.text('Body'), findsOneWidget);
    // The flat branch never installs the ambient painter: the only
    // CustomPaint present is Material's internal ink splash.
    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<AmbientBackgroundPainter>()
        .toList();
    expect(painters, isEmpty);
  });

  testWidgets('Ambient and Cyberpunk backgrounds paint distinct glow layers',
      (tester) async {
    await _initTestStorage(tester);

    await _pumpWithStyle(
      tester,
      DesignStyle.ambient,
      const AmbientBackground(child: Text('Body')),
    );
    final ambientPainters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<AmbientBackgroundPainter>()
        .toList();
    expect(ambientPainters, isNotEmpty);
    expect(ambientPainters.first.isCyberpunk, isFalse);

    await _pumpWithStyle(
      tester,
      DesignStyle.cyberpunk,
      const AmbientBackground(child: Text('Body')),
    );
    final cyberPainters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<AmbientBackgroundPainter>()
        .toList();
    expect(cyberPainters, isNotEmpty);
    expect(cyberPainters.first.isCyberpunk, isTrue);
  });

  testWidgets('GlassContainer and AmbientBackground render with neo-brutalism without glow',
      (tester) async {
    await _initTestStorage(tester);
    await _pumpWithStyle(
      tester,
      DesignStyle.neobrutalism,
      const AmbientBackground(
        child: GlassContainer(
          child: Text('Card Content'),
        ),
      ),
    );

    expect(find.text('Card Content'), findsOneWidget);
    expect(find.byType(GlassContainer), findsOneWidget);
  });

  testWidgets('Compact song cards never overflow for any preset or width',
      (tester) async {
    await _initTestStorage(tester);

    // Phone (the app's target), the wide-screen breakpoint that steps the
    // artwork up 12dp, and a desktop window. The card used to size its
    // artwork as a fixed square, so the title and artist were pushed past
    // the card edge and Flutter painted the overflow stripes.
    const widths = [340.0, 420.0, 900.0, 1280.0];

    for (final style in DesignStyle.values) {
      for (final width in widths) {
        final themeService = ThemeService();
        themeService.selectPreset(style);

        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ChangeNotifierProvider<ThemeService>.value(
            value: themeService,
            child: MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    height: SongCard.compactCardHeight,
                    child: SongCard(
                      isCompact: true,
                      song: Song(
                        id: 'a',
                        title: 'Paralumbay',
                        artist: 'Artist Name',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(
          tester.takeException(),
          isNull,
          reason:
              '${style.label} @ ${width.toInt()}dp must not overflow the '
              'compact card',
        );
        themeService.dispose();
      }
    }
  });
}
