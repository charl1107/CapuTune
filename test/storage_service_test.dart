// Persistence and migration-safety tests for StorageService.
//
// These run against a real Hive database in a temp directory, so they verify
// that playlists/settings survive a simulated app restart and that corrupt
// stored data degrades gracefully instead of crashing or wiping user data.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:caputune/models/playlist.dart';
import 'package:caputune/models/song.dart';
import 'package:caputune/services/storage_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('caputune_storage_test');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    // Fresh boxes for every test so state never leaks between cases.
    await Hive.deleteFromDisk();
    await StorageService.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Song song(String id) => Song(id: id, title: 'Title $id', artist: 'Artist');

  group('playlist persistence', () {
    test('saves and reads back playlists with ordering preserved', () async {
      final playlist = Playlist(
        id: 'p1',
        name: 'Chill',
        songs: [song('a'), song('b'), song('c')],
      );
      await StorageService.addPlaylist(playlist);

      final loaded = StorageService.getPlaylists();
      expect(loaded, hasLength(1));
      expect(loaded.first.name, 'Chill');
      expect(loaded.first.songs.map((s) => s.id).toList(), ['a', 'b', 'c']);
    });

    test('survives a simulated restart (close + reopen boxes)', () async {
      await StorageService.addPlaylist(
        Playlist(id: 'p1', name: 'Roadtrip', songs: [song('x'), song('y')]),
      );

      // Simulate an app restart: flush and reopen the database.
      await Hive.close();
      await StorageService.init();

      final loaded = StorageService.getPlaylists();
      expect(loaded, hasLength(1));
      expect(loaded.first.name, 'Roadtrip');
      expect(loaded.first.songs.map((s) => s.id), ['x', 'y']);
    });

    test('bumps the revision notifier on every save', () async {
      final before = StorageService.playlistsRevision.value;
      await StorageService.addPlaylist(Playlist(id: 'p1', name: 'A'));
      expect(StorageService.playlistsRevision.value, greaterThan(before));
    });

    test('renames a playlist without touching its songs', () async {
      await StorageService.addPlaylist(
          Playlist(id: 'p1', name: 'Old', songs: [song('a')]));
      await StorageService.renamePlaylist('p1', 'New');

      final loaded = StorageService.getPlaylists().single;
      expect(loaded.name, 'New');
      expect(loaded.songs.single.id, 'a');
    });

    test('rename of a missing playlist is a no-op', () async {
      await StorageService.renamePlaylist('nope', 'Whatever');
      expect(StorageService.getPlaylists(), isEmpty);
    });

    test('deletes only the targeted playlist', () async {
      await StorageService.addPlaylist(Playlist(id: 'p1', name: 'A'));
      await StorageService.addPlaylist(Playlist(id: 'p2', name: 'B'));
      await StorageService.deletePlaylist('p1');

      final loaded = StorageService.getPlaylists();
      expect(loaded.map((p) => p.id), ['p2']);
    });
  });

  group('local music dedupe', () {
    test('adds new local songs and skips duplicates by source path', () async {
      final first = await StorageService.addLocalSongs([
        Song(
            id: 'l1', title: 'One', artist: 'Local', localSourcePath: '/a.mp3'),
        Song(
            id: 'l2', title: 'Two', artist: 'Local', localSourcePath: '/b.mp3'),
      ]);
      expect(first, 2);

      final second = await StorageService.addLocalSongs([
        Song(
            id: 'l3',
            title: 'One again',
            artist: 'Local',
            localSourcePath: '/a.mp3'),
        Song(
            id: 'l4',
            title: 'Three',
            artist: 'Local',
            localSourcePath: '/c.mp3'),
      ]);
      expect(second, 1);

      final localPlaylist = StorageService.getPlaylists()
          .firstWhere((p) => p.id == StorageService.localMusicPlaylistId);
      expect(localPlaylist.songs.map((s) => s.localSourcePath),
          ['/a.mp3', '/b.mp3', '/c.mp3']);
    });
  });

  group('library import', () {
    String exportEnvelope(List<Map<String, dynamic>> playlists,
            {String format = 'caputune-library'}) =>
        json.encode({
          'format': format,
          'version': 1,
          'exportedAt': DateTime.now().toUtc().toIso8601String(),
          'playlists': playlists,
        });

    test('imports a valid exported library', () async {
      final jsonString = exportEnvelope([
        {
          'id': 'imp-1',
          'name': 'Imported',
          'createdAt': DateTime.now().toIso8601String(),
          'tracks': [
            {'id': 'a', 'title': 'A', 'artist': 'X'},
            {'id': 'b', 'title': 'B', 'artist': 'Y'},
          ],
        }
      ]);

      final count = await StorageService.importLibraryJson(jsonString);
      expect(count, 1);

      final loaded = StorageService.getPlaylists().single;
      expect(loaded.name, 'Imported');
      expect(loaded.songs.map((s) => s.id), ['a', 'b']);
    });

    test('skips playlists whose id already exists (no data loss)', () async {
      await StorageService.addPlaylist(
          Playlist(id: 'imp-1', name: 'Existing', songs: [song('keep')]));

      final jsonString = exportEnvelope([
        {
          'id': 'imp-1',
          'name': 'Overwrite attempt',
          'tracks': [
            {'id': 'evil', 'title': 'Evil', 'artist': 'X'}
          ],
        }
      ]);

      final count = await StorageService.importLibraryJson(jsonString);
      expect(count, 0);

      final loaded = StorageService.getPlaylists().single;
      expect(loaded.name, 'Existing');
      expect(loaded.songs.single.id, 'keep');
    });

    test('rejects a document with the wrong format marker', () async {
      final count = await StorageService.importLibraryJson(json.encode({
        'format': 'spotify-backup',
        'playlists': [
          {'id': 'x', 'name': 'n', 'tracks': []}
        ],
      }));
      expect(count, 0);
    });

    test('imports a pre-rename nekomusic-library export (back-compat)',
        () async {
      final jsonString = exportEnvelope([
        {
          'id': 'legacy-1',
          'name': 'Legacy',
          'createdAt': DateTime.now().toIso8601String(),
          'tracks': [
            {'id': 'l', 'title': 'L', 'artist': 'Y'},
          ],
        }
      ], format: 'nekomusic-library');

      final count = await StorageService.importLibraryJson(jsonString);
      expect(count, 1);
      expect(StorageService.getPlaylists().single.name, 'Legacy');
    });

    test('skips malformed playlist entries', () async {
      final jsonString = exportEnvelope([
        {'name': 'No id', 'tracks': []},
        {'id': '', 'name': 'Empty id', 'tracks': []},
        {'id': 'good', 'name': 'Good', 'tracks': []},
      ]);
      final count = await StorageService.importLibraryJson(jsonString);
      expect(count, 1);
      expect(StorageService.getPlaylists().single.id, 'good');
    });

    test('throws FormatException on invalid JSON', () async {
      expect(
        () => StorageService.importLibraryJson('{not json'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('corrupt data recovery', () {
    test('a corrupt playlists payload does not crash and is preserved',
        () async {
      final box = Hive.box('playlists');
      await box.put('playlists', '{corrupt');

      // Should not throw, and should report no playlists.
      expect(StorageService.getPlaylists(), isEmpty);
      // Original payload is stashed for recovery, not destroyed.
      expect(box.get('playlists.corrupt'), '{corrupt');
    });

    test('corrupt recents/favorites/downloads degrade to empty lists',
        () async {
      await Hive.box('recents').put('recents', '###');
      await Hive.box('favorites').put('favorites', '###');
      await Hive.box('downloads').put('downloads', '###');

      expect(StorageService.getRecentPlays(), isEmpty);
      expect(StorageService.getFavorites(), isEmpty);
      expect(StorageService.getDownloads(), isEmpty);
    });

    test('a JSON payload of the wrong shape yields an empty list', () async {
      await Hive.box('playlists').put('playlists', '{"not":"a list"}');
      expect(StorageService.getPlaylists(), isEmpty);
    });

    test('non-object entries inside the list are skipped', () async {
      await Hive.box('playlists').put(
        'playlists',
        json.encode([
          {'id': 'ok', 'name': 'Ok', 'songs': []},
          'garbage',
          42,
        ]),
      );
      final loaded = StorageService.getPlaylists();
      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'ok');
    });
  });

  group('settings and dismissal', () {
    test('settings round-trip', () async {
      StorageService.setDarkMode(true);
      StorageService.setAutoplay(false);
      StorageService.setAudioQuality('192kbps');

      expect(StorageService.getDarkMode(), isTrue);
      expect(StorageService.getAutoplay(), isFalse);
      expect(StorageService.getAudioQuality(), '192kbps');
    });

    test('dismissed update version round-trips and defaults to null', () async {
      expect(StorageService.getDismissedUpdateVersion(), isNull);
      StorageService.setDismissedUpdateVersion('9.9.9');
      expect(StorageService.getDismissedUpdateVersion(), '9.9.9');
    });
  });

  group('favorites and recents', () {
    test('favorites are deduped by id', () async {
      await StorageService.addFavorite(song('a'));
      await StorageService.addFavorite(song('a'));
      expect(StorageService.getFavorites(), hasLength(1));
      expect(StorageService.isFavorite('a'), isTrue);

      await StorageService.removeFavorite('a');
      expect(StorageService.isFavorite('a'), isFalse);
    });

    test('recents move the played song to the front', () async {
      await StorageService.addRecentPlay(song('a'));
      await StorageService.addRecentPlay(song('b'));
      await StorageService.addRecentPlay(song('a'));

      expect(StorageService.getRecentPlays().map((s) => s.id), ['a', 'b']);
    });
  });
}
