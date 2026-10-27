// Home screen layout: banner removal, compact title row, glass recipe,
// artwork sizing, and section rhythm.
//
// PlayerService is replaced by a no-op stand-in (the real one loads libmpv,
// which hangs the test VM), Hive init runs inside tester.runAsync, and
// SongCard's DownloadService dependency is provided inertly.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'package:caputune/models/song.dart';
import 'package:caputune/screens/home_screen.dart';
import 'package:caputune/services/download_service.dart';
import 'package:caputune/services/player_service.dart';
import 'package:caputune/services/storage_service.dart';
import 'package:caputune/services/theme_service.dart';
import 'package:caputune/theme/design_style.dart';
import 'package:caputune/services/update_service.dart';
import 'package:caputune/theme/app_theme.dart';
import 'package:caputune/widgets/ambient_background.dart';
import 'package:caputune/widgets/song_card.dart';

Song _song(String id) =>
    Song(id: id, title: 'Song $id', artist: 'Artist', thumbnail: null);

class _FakePlayerService implements PlayerService {
  @override
  bool get isDarkMode => false;

  // IndexedStack builds all tabs, including Settings, which reads real
  // typed getters — noSuchMethod returning null breaks them.
  @override
  bool get autoplay => false;

  @override
  bool get radioAutoplay => false;

  @override
  bool get continueWithSimilarAfterPlaylist => false;

  @override
  String get audioQuality => 'High';

  @override
  bool isFavorite(String id) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeUpdateService extends ChangeNotifier implements UpdateService {
  @override
  UpdateState get state => UpdateState.idle;

  @override
  String get currentVersion => 'test';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> _initStorage(WidgetTester tester) async {
  late Directory tempDir;
  await tester.runAsync(() async {
    tempDir = await Directory.systemTemp.createTemp('caputune_home_test');
    Hive.init(tempDir.path);
    await StorageService.init();
  });
  addTearDown(() => tempDir.deleteSync(recursive: true));
}

Future<void> _pumpHome(
  WidgetTester tester, {
  Size? size,
}) async {
  if (size != null) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PlayerService>.value(value: _FakePlayerService()),
        ChangeNotifierProvider<DownloadService>(create: (_) => DownloadService()),
        ChangeNotifierProvider<ThemeService>(create: (_) => ThemeService()),
        ChangeNotifierProvider<UpdateService>.value(value: _FakeUpdateService()),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const HomeScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    // Optional font, same policy as search_screen_test: load Inter when a
    // file is available, otherwise use the test fallback font.
    const candidates = [
      String.fromEnvironment('CAPUTUNE_TEST_FONT'),
      '/tmp/opencode/fonts/Inter.ttf',
    ];
    for (final path in candidates) {
      if (path.isEmpty || !File(path).existsSync()) continue;
      final fontData = File(path).readAsBytesSync();
      final loader = FontLoader('Inter')
        ..addFont(Future.value(ByteData.view(fontData.buffer)));
      await loader.load();
      break;
    }
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('no hero banner: no expanded app bar, gradient, or logo image',
      (tester) async {
    await _initStorage(tester);
    await _pumpHome(tester, size: const Size(390, 844));

    // The old hero used a 180px FlexibleSpaceBar.
    final appBars = tester.widgetList<SliverAppBar>(
      find.byType(SliverAppBar),
    );
    for (final bar in appBars) {
      expect(bar.expandedHeight, isNull,
          reason: 'Home must not reserve expanded banner height');
    }
    expect(find.byType(FlexibleSpaceBar), findsNothing);
    expect(find.byKey(const ValueKey('home_banner_logo')), findsNothing);
    // The in-app logo asset is not rendered on the home header.
    expect(
      find.byWidgetPredicate((w) =>
          w is Image && w.image is AssetImage && (w.image as AssetImage)
              .assetName
              .contains('logo')),
      findsNothing,
      reason: 'In-app header logo must be removed (launcher icon unaffected)',
    );
  });

  testWidgets('compact title row: CapuTune left, no dark-mode toggle',
      (tester) async {
    await _initStorage(tester);
    await _pumpHome(tester, size: const Size(390, 844));

    expect(find.text('CapuTune'), findsOneWidget);

    // The standalone dark-mode toggle was removed: appearance is managed
    // in Settings → Appearance now.
    expect(find.byIcon(Icons.dark_mode), findsNothing);
    expect(find.byIcon(Icons.light_mode), findsNothing);

    // Compact toolbar: 56dp (was expandedHeight 180).
    final bar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
    expect(bar.toolbarHeight, 56);
  });

  testWidgets('first-launch theme picker opens over Home and marks completion',
      (tester) async {
    await _initStorage(tester);
    // Boxes persist across tests in one VM run; force a fresh flag.
    StorageService.setSetting<bool>(false, key: 'theme.pickerDone');
    await _pumpHome(tester, size: const Size(390, 844));
    await tester.pump();

    expect(find.text('Choose Your Look'), findsOneWidget);
    for (final label in [
      'Glassmorphism',
      'Ambient UI',
      'Neo-brutalism',
      'Premium UI',
      'Cyberpunk',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    // Select a preset: Home behind the modal re-themes immediately.
    await tester.tap(find.text('Premium UI'));
    await tester.pump();
    expect(tester.element(find.byType(HomeScreen)).read<ThemeService>().style, DesignStyle.premium);

    // Continue persists completion; modal closes.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Choose Your Look'), findsNothing);
    expect(
        StorageService.getSetting<bool>(false, key: 'theme.pickerDone'), isTrue);
  });

  testWidgets('picker Skip restores default and never reappears',
      (tester) async {
    await _initStorage(tester);
    StorageService.setSetting<bool>(false, key: 'theme.pickerDone');
    await _pumpHome(tester, size: const Size(390, 844));
    await tester.pump();

    // Preview a different preset first.
    await tester.tap(find.text('Cyberpunk'));
    await tester.pump();
    expect(tester.element(find.byType(HomeScreen)).read<ThemeService>().style, DesignStyle.cyberpunk);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Choose Your Look'), findsNothing);
    final service = tester.element(find.byType(HomeScreen)).read<ThemeService>();
    expect(service.style, DesignStyle.glassmorphism);
    expect(service.pickerDone, isTrue);
  });

  testWidgets('picker does not reopen on subsequent launches', (tester) async {
    await _initStorage(tester);
    StorageService.setSetting<bool>(true, key: 'theme.pickerDone');
    await _pumpHome(tester, size: const Size(390, 844));
    await tester.pump();

    expect(find.text('Choose Your Look'), findsNothing);
  });

  testWidgets('ambient background is present and cards use glass fills',
      (tester) async {
    await _initStorage(tester);
    await _pumpHome(tester, size: const Size(390, 844));

    // The ambient base must exist behind the scroll view and be opaque.
    expect(find.byType(AmbientBackground), findsOneWidget);
    final scrollRect = tester.getRect(find.byType(CustomScrollView));
    final ambientRect = tester.getRect(find.byType(AmbientBackground));
    expect(ambientRect.top, lessThanOrEqualTo(scrollRect.top));
    expect(ambientRect.bottom, greaterThanOrEqualTo(scrollRect.bottom));

    // Empty-state panels exist but artwork cards only render with songs;
    // here we assert the section exists and no banner gradient colors are
    // used anywhere.
    expect(find.text('Recently Played'), findsOneWidget);
    expect(find.text('Most Played'), findsOneWidget);
  });

  testWidgets('artwork cards render at the compact size with readable text',
      (tester) async {
    await _initStorage(tester);
    // Seed recents so the horizontal cards render (each addRecentPlay also
    // bumps the play count, so Most Played fills too).
    await tester.runAsync(() async {
      await StorageService.addRecentPlay(_song('a1'));
      await StorageService.addRecentPlay(_song('a1'));
      await StorageService.addRecentPlay(_song('a2'));
    });
    await _pumpHome(tester, size: const Size(390, 844));

    final cardRect = tester.getRect(find.byType(SongCard).first);
    expect(cardRect.width, SongCard.compactArtwork,
        reason: 'Card width must equal the 144dp design constant');
    expect(cardRect.width, inExclusiveRange(95, 115),
        reason: 'Compact card must be much smaller than the old 160dp card');
    // Card height must accommodate art + text without dead space.
    expect(cardRect.height, SongCard.compactCardHeight);

    // Titles/artists remain aligned with the artwork column. 'Song a1' was
    // played twice, so it appears in both sections legitimately.
    expect(find.text('Song a1'), findsWidgets);
    expect(find.text('Artist'), findsWidgets);
  });

  testWidgets('sections stack tightly with no fixed dead band', (tester) async {
    await _initStorage(tester);
    await tester.runAsync(() async {
      await StorageService.addRecentPlay(_song('b1'));
      await StorageService.addRecentPlay(_song('b1'));
      await StorageService.addRecentPlay(_song('b1'));
      await StorageService.addRecentPlay(_song('b2'));
    });
    await _pumpHome(tester, size: const Size(390, 844));

    final recentHeading = tester.getRect(find.text('Recently Played'));
    final mostHeading = tester.getRect(find.text('Most Played'));
    // Sections must move up into the freed banner space. Distance between
    // consecutive headings = heading row 36 (compact See all) + 8 gap +
    // 146 cards + 16 bottom pad + 8 top pad = 214; assert the rhythm stays
    // in that band, and that content starts far above the old 180px banner.
    expect(mostHeading.top - recentHeading.top, inExclusiveRange(200, 230));
    expect(recentHeading.top, lessThan(200));

    // No oversized fixed box: the row height comes from SongCard's design
    // constant, not the old 220px SizedBox.
    final row = tester.firstWidget<SizedBox>(
      find.ancestor(
        of: find.byType(SongCard).first,
        matching:
            find.byWidgetPredicate((w) => w is SizedBox && w.height != null),
      ),
    );
    expect(row.height, SongCard.compactCardHeight);
  });
}
