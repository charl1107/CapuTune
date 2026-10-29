// Playlist detail screen: drag-to-reorder and the destructive sort menu.
//
// The reorder/sort transformations live on the Playlist model so they can be
// unit-tested without widget pumps; Hive writes started from widget
// callbacks never resolve in a widget test's fake-async zone (which would
// hang Hive.close() in teardown), so the widget layer gets a smoke test that
// only verifies the sheet options, and the persist step is covered by
// storage_service_test.
import 'dart:io';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'package:caputune/models/playlist.dart';
import 'package:caputune/models/song.dart';
import 'package:caputune/screens/playlist_detail_screen.dart';
import 'package:caputune/services/download_service.dart';
import 'package:caputune/services/player_service.dart';
import 'package:caputune/services/storage_service.dart';
import 'package:caputune/services/theme_service.dart';
import 'package:caputune/theme/app_theme.dart' show AppTheme;

Song _song(String id, {required String title, String artist = 'Artist'}) =>
    Song(id: id, title: title, artist: artist);

Playlist _playlistWith(List<Song> songs) =>
    Playlist(id: 'pl_test', name: 'Test Playlist', songs: songs);

/// ThemeService reads its style from Hive, so the widget tests need a real
/// (temp-dir) store. Writes are only ever started via runAsync.
Future<void> _initStorage(WidgetTester tester) async {
  late Directory tempDir;
  await tester.runAsync(() async {
    tempDir = await Directory.systemTemp.createTemp('caputune_playlist_test');
    Hive.init(tempDir.path);
    await StorageService.init();
  });
  addTearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });
}

void main() {
  group('Playlist.reordered', () {
    test('moves a song up', () {
      final playlist = _playlistWith([
        _song('a', title: 'Alpha'),
        _song('b', title: 'Beta'),
        _song('c', title: 'Gamma'),
      ]);

      final ids = playlist.reordered(1, 0).songs.map((s) => s.id).toList();

      expect(ids, ['b', 'a', 'c']);
    });

    test('moves a song down without skipping (list semantics)', () {
      final playlist = _playlistWith([
        _song('a', title: 'Alpha'),
        _song('b', title: 'Beta'),
        _song('c', title: 'Gamma'),
        _song('d', title: 'Delta'),
      ]);

      // Moving index 0 to index 1 swaps the first two in place; callers no
      // longer need the ReorderableListView newIndex correction.
      final ids = playlist.reordered(0, 1).songs.map((s) => s.id).toList();

      expect(ids, ['b', 'a', 'c', 'd']);
    });

    test('moving to the end appends the song last', () {
      final playlist = _playlistWith([
        _song('a', title: 'Alpha'),
        _song('b', title: 'Beta'),
      ]);

      final ids = playlist.reordered(0, 1).songs.map((s) => s.id).toList();

      expect(ids, ['b', 'a']);
    });

    test('returns an equivalent playlist when indices match', () {
      final playlist = _playlistWith([_song('a', title: 'Alpha')]);

      final moved = playlist.reordered(0, 0);

      expect(moved.songs.map((s) => s.id), ['a']);
      expect(moved.id, playlist.id);
    });
  });

  group('Playlist.sorted', () {
    test('sorts by title case-insensitively', () {
      final playlist = _playlistWith([
        _song('c', title: 'charlie'),
        _song('a', title: 'Alpha'),
        _song('b', title: 'bravo'),
      ]);

      final titles = playlist.sorted(PlaylistSort.title)
          .songs
          .map((s) => s.title)
          .toList();

      expect(titles, ['Alpha', 'bravo', 'charlie']);
    });

    test('sorts by artist case-insensitively', () {
      final playlist = _playlistWith([
        _song('a', title: 'One', artist: 'zeta'),
        _song('b', title: 'Two', artist: 'Alpha'),
        _song('c', title: 'Three', artist: 'midway'),
      ]);

      final artists = playlist.sorted(PlaylistSort.artist)
          .songs
          .map((s) => s.artist)
          .toList();

      expect(artists, ['Alpha', 'midway', 'zeta']);
    });

    test('handles an empty playlist', () {
      final sorted = _playlistWith(const []).sorted(PlaylistSort.title);

      expect(sorted.songs, isEmpty);
    });
  });

  group('PlaylistDetailScreen sheet', () {
    testWidgets('sort menu offers custom, title and artist options',
        (tester) async {
      await _initStorage(tester);
      final playlist = _playlistWith([_song('a', title: 'Alpha')]);

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
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: PlaylistDetailScreen(playlist: playlist),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.sort));
      await tester.pumpAndSettle();

      expect(find.text('Sort playlist'), findsOneWidget);
      expect(find.text('Custom order'), findsOneWidget);
      expect(find.text('Title (A–Z)'), findsOneWidget);
      expect(find.text('Artist (A–Z)'), findsOneWidget);
    });
  });
}

class _FakePlayerService implements PlayerService {
  @override
  Song? get currentSong => null;

  @override
  bool isFavorite(String songId) => false;

  // SongCard's favorite button reads only the members above; the buttons are
  // never tapped in these tests, so noSuchMethod's null fallback is safe.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// SongCard watches DownloadService for its download badge.
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
