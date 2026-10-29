// Albums/Artists grouping: source collection and attribute grouping.
//
// Runs against a real Hive database in a temp directory (same pattern as
// storage_service_test) so collectSongs() reads persisted data as the app
// would; grouping itself is pure.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';import 'package:provider/provider.dart';

import 'package:caputune/models/playlist.dart';
import 'package:caputune/models/song.dart';
import 'package:caputune/screens/collections_screen.dart';
import 'package:caputune/services/download_service.dart';
import 'package:caputune/services/collection_service.dart';
import 'package:caputune/services/player_service.dart';
import 'package:caputune/services/storage_service.dart';
import 'package:caputune/services/theme_service.dart';

Song _song(
  String id, {
  required String title,
  String artist = 'Artist',
  String? album,
}) =>
    Song(id: id, title: title, artist: artist, album: album);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    // Same policy as home_screen_test: never fetch fonts at runtime in tests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  late Directory tempDir;

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('caputune_collections_test');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    await Hive.deleteFromDisk();
    await StorageService.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('groupSongs', () {
    test('groups by album, keys sorted alphabetically', () {
      final groups = CollectionService.groupSongs(
        [
          _song('1', title: 'Track B', album: 'Zeta'),
          _song('2', title: 'Track A', album: 'Alpha'),
          _song('3', title: 'Track C', album: 'Zeta'),
        ],
        CollectionSource.albums,
      );

      expect(groups.keys.toList(), ['Alpha', 'Zeta']);
      expect(groups['Zeta']!.map((s) => s.id), ['1', '3']);
    });

    test('groups by artist', () {
      final groups = CollectionService.groupSongs(
        [
          _song('1', title: 'A', artist: 'Zeta'),
          _song('2', title: 'B', artist: 'Alpha'),
        ],
        CollectionSource.artists,
      );

      expect(groups.keys.toList(), ['Alpha', 'Zeta']);
      expect(groups['Alpha']!.map((s) => s.id), ['2']);
    });

    test('songs without an album fall into Unknown Album', () {
      final groups = CollectionService.groupSongs(
        [_song('1', title: 'A'), _song('2', title: 'B', album: 'Alpha')],
        CollectionSource.albums,
      );

      expect(groups.keys.toList(), ['Alpha', 'Unknown Album']);
      expect(groups['Unknown Album']!.map((s) => s.id), ['1']);
    });

    test('empty input yields no groups', () {
      final groups =
          CollectionService.groupSongs(const [], CollectionSource.albums);

      expect(groups, isEmpty);
    });
  });

  group('collectSongs', () {
    test('collects from favorites, downloads and playlists without duplicates',
        () async {
      final shared = _song('shared', title: 'Shared', album: 'Album');
      final playlistOnly =
          _song('in_playlist', title: 'Playlist song', album: 'Album');

      await StorageService.addFavorite(shared);
      await StorageService.addDownload(shared);
      await StorageService.savePlaylists(
        [
          Playlist(id: 'pl', name: 'P', songs: [playlistOnly]),
        ],
      );

      final songs = CollectionService.collectSongs();

      final ids = songs.map((s) => s.id).toSet();
      expect(ids, containsAll(['shared', 'in_playlist']));
      // The shared song must appear exactly once despite being in two sources.
      expect(songs.where((s) => s.id == 'shared'), hasLength(1));
    });
  });

  group('CollectionsScreen', () {
    testWidgets('shows album groups from stored songs and switches to artists',
        (tester) async {
      await tester.runAsync(() async {
        final tempDir = await Directory.systemTemp
            .createTemp('caputune_collections_widget');
        Hive.init(tempDir.path);
        await StorageService.init();
        addTearDown(() async {
          await Hive.close();
          tempDir.deleteSync(recursive: true);
        });
      });

      await tester.runAsync(
        () => StorageService.addFavorite(
          _song('1', title: 'One', artist: 'Zeta', album: 'Alpha'),
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PlayerService>.value(
              value: _FakePlayerService(),
            ),
            ChangeNotifierProvider<DownloadService>.value(
              value: _FakeDownloadService(),
            ),
            ChangeNotifierProvider<ThemeService>(create: (_) => ThemeService()),
          ],
          child: const MaterialApp(home: CollectionsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // The stored song's album appears as a group card.
      expect(find.text('Alpha'), findsOneWidget);

      // Switching the segmented button to Artists regroups.
      await tester.tap(find.text('Artists'));
      await tester.pumpAndSettle();
      expect(find.text('Zeta'), findsOneWidget);
      expect(find.text('Alpha'), findsNothing);
    });
  });
}

class _FakePlayerService implements PlayerService {
  @override
  Song? get currentSong => null;

  @override
  bool isFavorite(String songId) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Not rendered inside SongCard here, but CollectionsScreen's tree may build
/// one once a group is opened; idle state keeps the badge quiet.
class _FakeDownloadService extends DownloadService {
  @override
  DownloadState getState(String songId) => DownloadState.idle;

  @override
  double getProgress(String songId) => 0.0;

  @override
  bool isDownloading(String songId) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
