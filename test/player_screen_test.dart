// Now Playing three-dot menu: the Download entry point, its downloaded and
// in-progress states, and the local-file exclusion.
//
// PlayerService is replaced by a no-op stand-in (the real one loads libmpv,
// which hangs the test VM). DownloadService is subclassed with deterministic
// state maps and call logs so no test touches the network or path_provider.
// ThemeService is real, so Hive init runs inside tester.runAsync.
import 'dart:io';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'package:caputune/models/song.dart';
import 'package:caputune/screens/player_screen.dart';
import 'package:caputune/services/download_service.dart';
import 'package:caputune/services/player_service.dart';
import 'package:caputune/services/storage_service.dart';
import 'package:caputune/services/theme_service.dart';
import 'package:caputune/theme/app_theme.dart';

Song _song(String id, {String? localPath}) => Song(
      id: id,
      title: 'Song $id',
      artist: 'Artist',
      thumbnail: null,
      localPath: localPath,
    );

class _FakePlayerService implements PlayerService {
  _FakePlayerService(this.song);

  final Song song;

  @override
  Song? get currentSong => song;

  @override
  bool get isPlaying => false;

  @override
  bool get radioAutoplay => false;

  @override
  bool get shuffleMode => false;

  @override
  RepeatMode get repeatMode => RepeatMode.off;

  @override
  Duration get duration => const Duration(minutes: 3);

  @override
  double get rate => 1.0;

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  bool isFavorite(String id) => false;

  // Only the getters above are read by the screen; the buttons are never
  // tapped in these tests, so noSuchMethod's null fallback is safe.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeDownloadService extends DownloadService {
  final Map<String, DownloadState> states = {};
  final Map<String, double> progresses = {};
  final List<String> started = [];
  final List<String> removed = [];

  @override
  DownloadState getState(String songId) =>
      states[songId] ??
      (StorageService.isDownloaded(songId)
          ? DownloadState.downloaded
          : DownloadState.idle);

  @override
  double getProgress(String songId) => progresses[songId] ?? 0.0;

  @override
  bool isDownloading(String songId) =>
      states[songId] == DownloadState.downloading;

  @override
  Future<void> downloadSong(Song song) async {
    started.add(song.id);
  }

  @override
  Future<void> removeDownload(String songId) async {
    removed.add(songId);
  }
}

Future<void> _initStorage(WidgetTester tester) async {
  late Directory tempDir;
  await tester.runAsync(() async {
    tempDir = await Directory.systemTemp.createTemp('caputune_player_test');
    Hive.init(tempDir.path);
    await StorageService.init();
  });
  addTearDown(() => tempDir.deleteSync(recursive: true));
}

Future<void> _pumpPlayer(
  WidgetTester tester,
  Song song, {
  _FakeDownloadService? downloads,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PlayerService>.value(
          value: _FakePlayerService(song),
        ),
        ChangeNotifierProvider<DownloadService>.value(
          value: downloads ?? _FakeDownloadService(),
        ),
        ChangeNotifierProvider<ThemeService>(create: (_) => ThemeService()),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const PlayerScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    // Optional font, same policy as home_screen_test: load Inter when a
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

  testWidgets('menu keeps existing items and adds Download below Add to playlist',
      (tester) async {
    await _initStorage(tester);
    await _pumpPlayer(tester, _song('dl-1'));
    await _openMenu(tester);

    expect(find.text('Add to playlist'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Radio Autoplay'), findsOneWidget);
    expect(find.text('Add to favorites'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);

    // Download sits directly below "Add to playlist" and above the toggles.
    final addY = tester.getTopLeft(find.text('Add to playlist')).dy;
    final downloadY = tester.getTopLeft(find.text('Download')).dy;
    final radioY = tester.getTopLeft(find.text('Radio Autoplay')).dy;
    expect(downloadY, greaterThan(addY));
    expect(downloadY, lessThan(radioY));
  });

  testWidgets('tapping Download starts the download for the current song',
      (tester) async {
    await _initStorage(tester);
    final downloads = _FakeDownloadService();
    await _pumpPlayer(tester, _song('dl-2'), downloads: downloads);
    await _openMenu(tester);

    await tester.tap(find.text('Download'));
    await tester.pump();

    expect(downloads.started, ['dl-2']);
  });

  testWidgets('downloaded songs show Delete download and remove through the menu',
      (tester) async {
    await _initStorage(tester);
    await tester.runAsync(() => StorageService.addDownload(_song('dl-3')));
    final downloads = _FakeDownloadService();
    await _pumpPlayer(tester, _song('dl-3'), downloads: downloads);
    await _openMenu(tester);

    expect(find.text('Download'), findsNothing);
    expect(find.text('Delete download'), findsOneWidget);

    await tester.tap(find.text('Delete download'));
    await tester.pump();

    expect(downloads.removed, ['dl-3']);
  });

  testWidgets('a running download shows a disabled progress entry that ignores taps',
      (tester) async {
    await _initStorage(tester);
    final downloads = _FakeDownloadService()
      ..states['dl-4'] = DownloadState.downloading
      ..progresses['dl-4'] = 0.42;
    await _pumpPlayer(tester, _song('dl-4'), downloads: downloads);
    await _openMenu(tester);

    final entry = find.text('Downloading… 42%');
    expect(entry, findsOneWidget);

    // Disabled: tapping must not restart or duplicate the run.
    await tester.tap(entry, warnIfMissed: false);
    await tester.pump();
    expect(downloads.started, isEmpty);
  });

  testWidgets('imported local files keep the original menu without Download',
      (tester) async {
    await _initStorage(tester);
    await _pumpPlayer(tester, _song('local-1', localPath: '/music/a.mp3'));
    await _openMenu(tester);

    expect(find.text('Download'), findsNothing);
    expect(find.text('Delete download'), findsNothing);
    expect(find.text('Add to playlist'), findsOneWidget);
    expect(find.text('Radio Autoplay'), findsOneWidget);
    expect(find.text('Add to favorites'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
  });
}
