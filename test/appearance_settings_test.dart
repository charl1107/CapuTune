import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'package:caputune/screens/customize_colors_screen.dart';
import 'package:caputune/screens/settings_screen.dart';
import 'package:caputune/services/player_service.dart';
import 'package:caputune/services/storage_service.dart';
import 'package:caputune/services/theme_service.dart';
import 'package:caputune/services/update_service.dart';
import 'package:caputune/theme/app_theme.dart';
import 'package:caputune/theme/design_style.dart';
import 'package:caputune/widgets/appearance_settings.dart';
import 'package:caputune/widgets/theme_live_preview_card.dart';
import 'package:caputune/widgets/visual_color_picker_sheet.dart';

class _FakePlayerService extends ChangeNotifier implements PlayerService {
  @override
  bool get autoplay => false;

  @override
  bool get radioAutoplay => false;

  @override
  bool get continueWithSimilarAfterPlaylist => false;

  @override
  String get audioQuality => 'High';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeUpdateService extends ChangeNotifier implements UpdateService {
  @override
  UpdateState get state => UpdateState.idle;

  @override
  String get currentVersion => '1.0.16';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> _initStorage(WidgetTester tester) async {
  late Directory tempDir;
  await tester.runAsync(() async {
    tempDir = await Directory.systemTemp.createTemp('caputune_appearance_test');
    Hive.init(tempDir.path);
    await StorageService.init();
  });
  addTearDown(() => tempDir.deleteSync(recursive: true));
}

void main() {
  Widget buildSettingsApp(ThemeService themeService) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeService>.value(value: themeService),
        ChangeNotifierProvider<PlayerService>.value(value: _FakePlayerService()),
        ChangeNotifierProvider<UpdateService>.value(value: _FakeUpdateService()),
      ],
      child: Consumer<ThemeService>(
        builder: (context, ts, _) {
          return MaterialApp(
            theme: AppTheme.fromTokens(ts.colors, dark: ts.colors.isDark),
            home: const SettingsScreen(),
          );
        },
      ),
    );
  }

  testWidgets('Appearance page displays five compact list rows and Customize Colors',
      (tester) async {
    await _initStorage(tester);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final themeService = ThemeService();
    themeService.selectPreset(DesignStyle.glassmorphism);

    await tester.pumpWidget(buildSettingsApp(themeService));
    await tester.pumpAndSettle();

    // Verify 5 theme presets exist in vertical list
    expect(find.text('Glassmorphism'), findsOneWidget);
    expect(find.text('Ambient UI'), findsOneWidget);
    expect(find.text('Neo-brutalism'), findsOneWidget);
    expect(find.text('Premium UI'), findsOneWidget);
    expect(find.text('Cyberpunk / Neon'), findsOneWidget);

    // Verify swatch widgets exist
    expect(find.byType(ThemeStyleSwatch), findsNWidgets(5));

    // Verify Customize Colors row exists with subtitle and navigation chevron
    expect(find.text('Customize Colors'), findsOneWidget);
    expect(find.byIcon(Icons.palette_outlined), findsOneWidget);

    // Verify selecting another style (e.g. Cyberpunk) updates themeService live
    await tester.tap(find.text('Cyberpunk / Neon'));
    await tester.pumpAndSettle();
    expect(themeService.style, DesignStyle.cyberpunk);

    // Verify tapping Customize Colors navigates to CustomizeColorsScreen
    await tester.tap(find.text('Customize Colors'));
    await tester.pumpAndSettle();
    expect(find.byType(CustomizeColorsScreen), findsOneWidget);
    expect(find.byType(ThemeLivePreviewCard), findsOneWidget);
    expect(find.text('Background'), findsOneWidget);
    expect(find.text('Surface'), findsOneWidget);
    expect(find.text('Card'), findsOneWidget);
    expect(find.text('Accent'), findsOneWidget);
    expect(find.text('Highlight'), findsOneWidget);
    expect(find.text('Border'), findsOneWidget);
    expect(find.text('Ambient Glow'), findsOneWidget);
  });

  testWidgets('Visual color picker supports swatches, cancel and apply',
      (tester) async {
    await _initStorage(tester);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final themeService = ThemeService();
    themeService.selectPreset(DesignStyle.glassmorphism);

    await tester.pumpWidget(buildSettingsApp(themeService));
    await tester.pumpAndSettle();

    // Navigate to Customize Colors
    await tester.tap(find.text('Customize Colors'));
    await tester.pumpAndSettle();

    // Open Accent color picker
    await tester.tap(find.text('Accent'));
    await tester.pumpAndSettle();

    expect(find.byType(VisualColorPickerSheet), findsOneWidget);
    expect(find.text('Quick Colors'), findsOneWidget);
    expect(find.text('Enter Hex Code (Advanced)'), findsOneWidget);

    // Test Cancel doesn't change themeService accent
    final initialAccent = themeService.colors.accent;
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(VisualColorPickerSheet), findsNothing);
    expect(themeService.colors.accent, initialAccent);

    // Reopen Accent picker and pick a quick swatch (e.g. Cyan: 0xFF00E5FF)
    await tester.tap(find.text('Accent'));
    await tester.pumpAndSettle();

    // Tap swatch circle for cyan and Apply
    final cyanSwatch = find.byWidgetPredicate(
      (w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == const Color(0xFF00E5FF),
    );
    expect(cyanSwatch, findsWidgets);
    await tester.tap(cyanSwatch.first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(themeService.colors.accent, const Color(0xFF00E5FF));
    expect(themeService.isCustomized, isTrue);

    // Test Reset restores original preset palette
    expect(find.text('Reset'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(themeService.colors.accent, DesignStylePalettes.glassmorphism.accent);
    expect(themeService.isCustomized, isFalse);
  });

  testWidgets('Advanced hex code input validates input format',
      (tester) async {
    await _initStorage(tester);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final themeService = ThemeService();
    await tester.pumpWidget(buildSettingsApp(themeService));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Customize Colors'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Highlight'));
    await tester.pumpAndSettle();

    // Expand Advanced hex input
    await tester.tap(find.text('Enter Hex Code (Advanced)'));
    await tester.pumpAndSettle();

    // Enter invalid hex
    final hexField = find.byType(TextField).first;
    await tester.enterText(hexField, 'XYZ123');
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid hex format. Use digits 0-9 and A-F.'), findsOneWidget);

    // Enter valid hex
    await tester.enterText(hexField, '#FF0055');
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid hex format. Use digits 0-9 and A-F.'), findsNothing);

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(themeService.colors.highlight, const Color(0xFFFF0055));
  });
}
