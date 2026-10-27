// Unit tests for ThemeService: preset selection, custom-theme CRUD, and
// persistence across service instances (the app-restart contract).
//
// Uses the real Hive settings box in a temp dir — same pattern as the
// home screen tests. No network, no widget tree.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:caputune/services/storage_service.dart';
import 'package:caputune/services/theme_service.dart';
import 'package:caputune/theme/design_style.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('caputune_theme_test');
    Hive.init(tempDir.path);
    await StorageService.init();
  });

  tearDownAll(() => tempDir.deleteSync(recursive: true));

  setUp(() {
    // Each test starts from an empty settings box: the CRUD/persistence
    // groups share one Hive box for the whole run.
    StorageService.setSetting<String?>(null, key: 'theme.customThemes');
    StorageService.setSetting<String?>(null, key: 'theme.colors');
    StorageService.setSetting<String?>(null, key: 'theme.activeCustomId');
    StorageService.setSetting<String>('glassmorphism', key: 'theme.style');
  });


  ThemeService fresh() => ThemeService();

  group('ThemeService — presets', () {
    test('defaults to glassmorphism with untouched palette', () {
      final service = fresh();
      expect(service.style, DesignStyle.glassmorphism);
      expect(service.isCustomized, isFalse);
      expect(service.activeCustomId, isNull);
      expect(service.pickerDone, isFalse);
    });

    test('selectPreset switches palette and clears customization', () {
      final service = fresh();
      service.selectPreset(DesignStyle.cyberpunk);
      expect(service.style, DesignStyle.cyberpunk);
      expect(service.colors.accent, DesignStylePalettes.cyberpunk.accent);
      expect(service.isCustomized, isFalse);
    });

    test('each preset has a distinct visual identity', () {
      final palettes = DesignStyle.values.map(DesignStylePalettes.of).toSet();
      expect(palettes.length, DesignStyle.values.length,
          reason: 'no two presets may share an identical palette');
      // Neo-brutalism is the light preset; the rest are dark.
      expect(DesignStylePalettes.neobrutalism.isDark, isFalse);
      for (final s in [
        DesignStyle.glassmorphism,
        DesignStyle.ambient,
        DesignStyle.premium,
        DesignStyle.cyberpunk,
      ]) {
        expect(DesignStylePalettes.of(s).isDark, isTrue);
      }
      // Neo-brutalism disables glow; cyberpunk maximizes it.
      expect(DesignStylePalettes.neobrutalism.glowStrength, 0.0);
      expect(DesignStylePalettes.cyberpunk.glowStrength,
          greaterThan(DesignStylePalettes.premium.glowStrength));
    });
  });

  group('ThemeService — color customization', () {
    test('updateColor applies immediately and flags customization', () {
      final service = fresh();
      service.updateColor((t) => t.copyWith(accent: const Color(0xFF123456)));
      expect(service.colors.accent, const Color(0xFF123456));
      expect(service.isCustomized, isTrue);
    });

    test('resetToDefault restores the preset palette', () {
      final service = fresh();
      service.selectPreset(DesignStyle.premium);
      service.updateColor((t) => t.copyWith(background: const Color(0xFF000000)));
      expect(service.isCustomized, isTrue);
      service.resetToDefault();
      expect(service.colors.background, DesignStylePalettes.premium.background);
      expect(service.isCustomized, isFalse);
    });

    test('updateColor clears any active custom-theme link', () {
      final service = fresh();
      service.updateColor((t) => t.copyWith(accent: const Color(0xFF111111)));
      service.saveCustomTheme('Temp');
      service.updateColor((t) => t.copyWith(accent: const Color(0xFF222222)));
      expect(service.activeCustomId, isNull);
    });
  });

  group('ThemeService — custom theme CRUD', () {
    test('save creates, selects, and persists a named theme', () {
      final service = fresh();
      service.selectPreset(DesignStyle.ambient);
      service.updateColor((t) => t.copyWith(accent: const Color(0xFFABCDEF)));
      final saved = service.saveCustomTheme('Night Shift');

      expect(service.customThemes, hasLength(1));
      expect(service.activeCustomId, saved.id);
      expect(saved.name, 'Night Shift');
      expect(saved.preset, DesignStyle.ambient);
      expect(saved.colors.accent, const Color(0xFFABCDEF));

      // Reload: survives restart.
      final reloaded = fresh();
      expect(reloaded.customThemes, hasLength(1));
      expect(reloaded.customThemes.first.name, 'Night Shift');
      expect(reloaded.customThemes.first.colors.accent, const Color(0xFFABCDEF));
    });

    test('saving an existing name overwrites that theme, not a duplicate',
        () {
      final service = fresh();
      service.saveCustomTheme('My Theme');
      service.updateColor((t) => t.copyWith(accent: const Color(0xFF0F0F0F)));
      final second = service.saveCustomTheme('  my theme ');
      expect(service.customThemes, hasLength(1));
      expect(service.customThemes.single.id, second.id);
      expect(service.customThemes.single.colors.accent, const Color(0xFF0F0F0F));
    });

    test('duplicate copies colors under a new id and name', () {
      final service = fresh();
      final original = service.saveCustomTheme('Origin');
      final copyId = service.duplicateCustomTheme(original.id);

      expect(copyId, isNotNull);
      expect(copyId, isNot(original.id));
      expect(service.customThemes, hasLength(2));
      final copy = service.customThemes.firstWhere((t) => t.id == copyId);
      expect(copy.name, 'Origin copy');
      expect(copy.colors, isNot(same(original.colors)));
      expect(copy.colors.accent, original.colors.accent);
    });

    test('rename keeps id and colors', () {
      final service = fresh();
      final t = service.saveCustomTheme('Old Name');
      service.renameCustomTheme(t.id, 'New Name');
      final renamed = service.customThemes.single;
      expect(renamed.id, t.id);
      expect(renamed.name, 'New Name');
      expect(renamed.colors.accent, t.colors.accent);
    });

    test('delete removes; deleting the active theme falls back to preset', () {
      final service = fresh();
      service.selectPreset(DesignStyle.cyberpunk);
      final t = service.saveCustomTheme('Doomed');
      expect(service.style, DesignStyle.cyberpunk);

      service.deleteCustomTheme(t.id);
      expect(service.customThemes, isEmpty);
      expect(service.activeCustomId, isNull);
      expect(service.style, DesignStyle.cyberpunk);
      expect(service.colors.accent, DesignStylePalettes.cyberpunk.accent);
    });

    test('selectCustomTheme applies its stored preset and colors', () {
      final service = fresh();
      service.selectPreset(DesignStyle.premium);
      final saved = service.saveCustomTheme('Gold');
      service.selectPreset(DesignStyle.cyberpunk);
      expect(service.style, DesignStyle.cyberpunk);

      service.selectCustomTheme(saved.id);
      expect(service.style, DesignStyle.premium);
      expect(service.activeCustomId, saved.id);
    });

    test('selectCustomTheme ignores unknown ids', () {
      final service = fresh();
      service.selectPreset(DesignStyle.ambient);
      service.selectCustomTheme('nope');
      expect(service.style, DesignStyle.ambient);
    });
  });

  group('ThemeService — persistence across restarts', () {
    test('style, colors, active custom id, and picker flag all survive', () {
      final service = fresh();
      service.selectPreset(DesignStyle.cyberpunk);
      service.updateColor((t) => t.copyWith(
            background: const Color(0xFF0A0A0A),
            accent: const Color(0xFF00FF00),
          ));
      service.completeFirstLaunchPicker();

      final reloaded = fresh();
      expect(reloaded.style, DesignStyle.cyberpunk);
      expect(reloaded.colors.background, const Color(0xFF0A0A0A));
      expect(reloaded.colors.accent, const Color(0xFF00FF00));
      expect(reloaded.pickerDone, isTrue);
      expect(reloaded.isCustomized, isTrue);
    });

    test('corrupt persisted JSON degrades to preset defaults', () {
      StorageService.setSetting<String>('{not json', key: 'theme.colors');
      StorageService.setSetting<String>('[oops', key: 'theme.customThemes');
      final service = fresh();
      expect(service.colors, DesignStylePalettes.of(service.style));
      expect(service.customThemes, isEmpty);
    });

    test('unknown persisted style name falls back to default preset', () {
      StorageService.setSetting<String>('steampunk', key: 'theme.style');
      final service = fresh();
      expect(service.style, DesignStyle.glassmorphism);
    });
  });

  group('CustomTheme — serialization round-trip', () {
    test('toJson/fromJson preserves everything', () {
      const theme = CustomTheme(
        id: 'ct_1',
        name: 'Roundtrip',
        preset: DesignStyle.premium,
        colors: StyleColors(
          background: Color(0xFF010203),
          surface: Color(0xFF040506),
          card: Color(0xFF070809),
          accent: Color(0xFF0A0B0C),
          highlight: Color(0xFF0D0E0F),
          border: Color(0xFF101112),
          glow: Color(0xFF131415),
          glowStrength: 0.7,
          textPrimary: Color(0xFF161718),
          textSecondary: Color(0xFF191A1B),
          isDark: true,
          radius: 10,
          borderWidth: 1.5,
        ),
      );
      // Color fields survive round-trip; structural fields (radius,
      // borderWidth, useBlur, useHardShadow, useNeonGlow) are defensively
      // pinned to the base preset so stale/hand-edited JSON cannot strip
      // the preset's identity.
      final restored = CustomTheme.fromJson(theme.toJson());
      expect(restored, isNotNull);
      expect(restored!.id, 'ct_1');
      expect(restored.name, 'Roundtrip');
      expect(restored.preset, DesignStyle.premium);
      expect(restored.colors.background, const Color(0xFF010203));
      expect(restored.colors.glowStrength, 0.7);
      expect(restored.colors.isDark, isTrue);
      expect(
        restored.colors.radius,
        DesignStylePalettes.premium.radius,
        reason: 'preset structural tokens must be enforced by fromJson',
      );
      expect(
        restored.colors.borderWidth,
        DesignStylePalettes.premium.borderWidth,
      );
      expect(restored.colors.useHardShadow, isFalse);
    });

    test('fromJson returns null for malformed payloads', () {
      expect(CustomTheme.fromJson({}), isNull);
      expect(CustomTheme.fromJson({'id': 'x'}), isNull);
      expect(CustomTheme.fromJson({
        'id': 'x',
        'name': 'n',
        'preset': 'not-a-style',
        'colors': <String, dynamic>{},
      }), isNull);
      expect(CustomTheme.fromJson({
        'id': 'x',
        'name': 'n',
        'preset': 'premium',
        'colors': 'not-a-map',
      }), isNull);
    });
  });
}
