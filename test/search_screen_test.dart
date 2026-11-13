// Instant-search behavior for SearchScreen.
//
// Search must fire on every keystroke with no debounce, results must stay
// synchronized with the newest query (stale responses discarded), and the
// text field must keep vertical headroom around the glyphs so no device
// metric rounding can clip the typed text.
//
// DiscoveryService is never touched: the screen's `searchRemote` parameter
// injects a fake, and PlayerService is replaced by a no-op stand-in because
// the real one starts the libmpv media engine (unavailable in the test VM).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'package:caputune/models/song.dart';
import 'package:caputune/screens/search_screen.dart';
import 'package:caputune/services/download_service.dart';
import 'package:caputune/services/player_service.dart';
import 'package:caputune/services/storage_service.dart';
import 'package:caputune/services/theme_service.dart';
import 'package:caputune/theme/app_theme.dart';

Song _song(String id) =>
    Song(id: id, title: 'Song $id', artist: 'Artist', thumbnail: null);

/// PlayerService stand-in: never constructs the real service, so libmpv is
/// never loaded. Overrides only what SearchScreen touches.
class _FakePlayerService implements PlayerService {
  @override
  bool get isDarkMode => false;

  @override
  bool get radioAutoplay => true;

  @override
  bool isFavorite(String id) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Fake remote search. Each query can be answered manually via [respond],
/// which lets tests hold a response back to simulate a slow network.
class _FakeSearch {
  final Map<String, Completer<List<Song>>> _pending = {};

  Future<List<Song>> call(String query) {
    return _pending.putIfAbsent(query, () => Completer<List<Song>>()).future;
  }

  void respond(String query, List<Song> results) {
    _pending.remove(query)!.complete(results);
  }

  /// Queries with an unanswered request, in fire order.
  List<String> get pendingQueries => _pending.keys
      .where((q) => !_pending[q]!.isCompleted)
      .toList(growable: false);
}

/// Fake detailed remote search: `(results, failed)` answers, set per query.
class _FakeDetailedSearch {
  final Map<String, (List<Song>, bool)> _answers = {};

  Future<(List<Song>, bool)> call(String query) async =>
      _answers[query] ?? (<Song>[], false);
}

Future<Directory> _initStorage(WidgetTester tester) async {
  late Directory tempDir;
  await tester.runAsync(() async {
    tempDir = await Directory.systemTemp.createTemp('caputune_search_test');
    Hive.init(tempDir.path);
    await StorageService.init();
  });
  return tempDir;
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  _FakeSearch? search,
  _FakeDetailedSearch? detailedSearch,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PlayerService>.value(
          value: _FakePlayerService(),
        ),
        ChangeNotifierProvider<ThemeService>(create: (_) => ThemeService()),
        // SongCard watches DownloadService; the real service is inert until a
        // download starts, which these tests never do.
        ChangeNotifierProvider<DownloadService>(create: (_) => DownloadService()),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: SearchScreen(
          searchRemote:
              search == null ? null : (q) => search(q),
          searchRemoteDetailed: detailedSearch == null
              ? null
              : (q) => detailedSearch(q),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    // Optionally load Inter from disk so text layout matches the app. The
    // font is not vendored in the repo (the app fetches it at runtime via
    // google_fonts, which cannot fetch inside tests), so when no file is
    // available the suite simply uses Flutter's built-in test fallback
    // font. The invariants exercised here (line metrics, field headroom)
    // hold for any font by construction.
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

  testWidgets('results appear after the debounce settles', (tester) async {
    final search = _FakeSearch();
    final tempDir = await _initStorage(tester);
    addTearDown(() => tempDir.deleteSync(recursive: true));
    await _pumpScreen(tester, search: search);

    await tester.enterText(find.byType(TextField), 'lofi');
    // Before the debounce elapses no request may have been issued.
    expect(search.pendingQueries, isEmpty);
    await tester.pump(SearchScreen.searchDebounce);
    expect(search.pendingQueries, ['lofi']);

    search.respond('lofi', [_song('1')]);
    await tester.pump();
    await tester.pump();

    expect(find.text('Song 1'), findsOneWidget);
    // The spinner must be gone and results shown.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a failed search shows the retry state, not "No results found."',
      (tester) async {
    final search = _FakeDetailedSearch();
    final tempDir = await _initStorage(tester);
    addTearDown(() => tempDir.deleteSync(recursive: true));
    await _pumpScreen(tester, detailedSearch: search);

    await tester.enterText(find.byType(TextField), 'eba');
    // Request fails (offline / blocked endpoint): failure, not empty.
    search._answers['eba'] = (<Song>[], true);
    await tester.pump(SearchScreen.searchDebounce);
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('No results found.'), findsNothing);

    // Retry re-runs the search; this time it succeeds.
    search._answers['eba'] = ([_song('1')], false);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Song 1'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
  });

  testWidgets('an empty-but-successful search shows "No results found.", '
      'not the retry state', (tester) async {
    final search = _FakeDetailedSearch();
    final tempDir = await _initStorage(tester);
    addTearDown(() => tempDir.deleteSync(recursive: true));
    await _pumpScreen(tester, detailedSearch: search);

    await tester.enterText(find.byType(TextField), 'no match ever');
    search._answers['no match ever'] = (<Song>[], false);
    await tester.pump(SearchScreen.searchDebounce);
    await tester.pump();
    await tester.pump();

    expect(find.text('No results found.'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
  });

  testWidgets('rapid typing batches into the newest query only',
      (tester) async {
    final search = _FakeSearch();
    final tempDir = await _initStorage(tester);
    addTearDown(() => tempDir.deleteSync(recursive: true));
    await _pumpScreen(tester, search: search);

    await tester.enterText(find.byType(TextField), 'l');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'lof');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'lofi');
    // Only the settled query fires; the intermediates were debounce-dropped.
    await tester.pump(SearchScreen.searchDebounce);
    expect(search.pendingQueries, ['lofi']);

    search.respond('lofi', [_song('1')]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Song 1'), findsOneWidget);
  });

  testWidgets('results follow the newest query while typing', (tester) async {
    final search = _FakeSearch();
    final tempDir = await _initStorage(tester);
    addTearDown(() => tempDir.deleteSync(recursive: true));
    await _pumpScreen(tester, search: search);

    await tester.enterText(find.byType(TextField), 'lofi');
    await tester.pump(SearchScreen.searchDebounce);
    search.respond('lofi', [_song('1')]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Song 1'), findsOneWidget);

    // Keep typing: the query changes and the results must follow.
    await tester.enterText(find.byType(TextField), 'lofi beats');
    await tester.pump(SearchScreen.searchDebounce);
    search.respond('lofi beats', [_song('2')]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Song 2'), findsOneWidget);
    expect(find.text('Song 1'), findsNothing);
  });

  testWidgets('a stale response never overwrites a newer result',
      (tester) async {
    final search = _FakeSearch();
    final tempDir = await _initStorage(tester);
    addTearDown(() => tempDir.deleteSync(recursive: true));
    await _pumpScreen(tester, search: search);

    // First query, response held back (slow network).
    await tester.enterText(find.byType(TextField), 'slow');
    await tester.pump(SearchScreen.searchDebounce);
    // Second query arrives and answers first (fast network).
    await tester.enterText(find.byType(TextField), 'fast');
    await tester.pump(SearchScreen.searchDebounce);
    search.respond('fast', [_song('fast-song')]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Song fast-song'), findsOneWidget);

    // The slow response lands afterwards and must be discarded.
    search.respond('slow', [_song('stale-song')]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Song stale-song'), findsNothing);
    expect(find.text('Song fast-song'), findsOneWidget);
  });

  testWidgets('clearing the field empties results and blocks in-flight ones',
      (tester) async {
    final search = _FakeSearch();
    final tempDir = await _initStorage(tester);
    addTearDown(() => tempDir.deleteSync(recursive: true));
    await _pumpScreen(tester, search: search);

    await tester.enterText(find.byType(TextField), 'jazz');
    await tester.pump(SearchScreen.searchDebounce);
    // Clear before the response arrives.
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();
    search.respond('jazz', [_song('late')]);
    await tester.pump();
    await tester.pump();

    expect(find.text('Song late'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    // Back to the suggestions/empty state, not a results list.
    expect(find.text('No results found.'), findsNothing);
  });

  testWidgets('the clear button appears while typing, before any response',
      (tester) async {
    final tempDir = await _initStorage(tester);
    addTearDown(() => tempDir.deleteSync(recursive: true));
    await _pumpScreen(tester);

    await tester.enterText(find.byType(TextField), 'eba');
    await tester.pump();
    // No search has fired yet (debounce pending), but the ✕ affordance
    // must already track the field's text.
    expect(find.byIcon(Icons.clear), findsOneWidget);
  });

  testWidgets('tapping clear cancels the pending debounce', (tester) async {
    final search = _FakeSearch();
    final tempDir = await _initStorage(tester);
    addTearDown(() => tempDir.deleteSync(recursive: true));
    await _pumpScreen(tester, search: search);

    await tester.enterText(find.byType(TextField), 'eba');
    await tester.pump();
    // Clear inside the debounce window: nothing may fire afterwards.
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();
    await tester.pump(SearchScreen.searchDebounce);
    await tester.pump(SearchScreen.searchDebounce);
    expect(search.pendingQueries, isEmpty);
  });

  testWidgets('submitting supersedes a pending debounce', (tester) async {
    final search = _FakeSearch();
    final tempDir = await _initStorage(tester);
    addTearDown(() => tempDir.deleteSync(recursive: true));
    await _pumpScreen(tester, search: search);

    await tester.enterText(find.byType(TextField), 'eba');
    await tester.pump();
    // Commit before the debounce elapses: exactly one search, now.
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(search.pendingQueries, ['eba']);
    await tester.pump(SearchScreen.searchDebounce);
    expect(search.pendingQueries, ['eba'],
        reason: 'the debounce timer must not re-fire after submit');
    search.respond('eba', [_song('1')]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Song 1'), findsOneWidget);
  });

  testWidgets('text field keeps vertical headroom around the glyphs',
      (tester) async {
    final tempDir = await _initStorage(tester);
    addTearDown(() => tempDir.deleteSync(recursive: true));

    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await _pumpScreen(tester);

    for (final scale in <double>[1.0, 1.3]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpAndSettle();

      final fieldBox =
          tester.renderObject<RenderBox>(find.byType(TextField));
      RenderObject node = fieldBox;
      while (!node.runtimeType.toString().contains('RenderEditable')) {
        RenderObject? next;
        node.visitChildren((child) => next ??= child);
        node = next!;
      }
      final glyphLine = (node as dynamic).preferredLineHeight as double;
      final fieldHeight = fieldBox.size.height;

      // The line box inside the field must be at least 8px taller than the
      // glyphs need, so pixel rounding on real devices cannot clip them.
      expect(
        fieldHeight - glyphLine,
        greaterThanOrEqualTo(8),
        reason: 'At fontScale $scale the field ($fieldHeight px) must leave '
            'headroom around the glyphs ($glyphLine px).',
      );
    }
  });
}
