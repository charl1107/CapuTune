import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:caputune/models/song.dart';
import 'package:caputune/services/player_service.dart';
import 'package:caputune/services/storage_service.dart';
import 'package:caputune/services/stream_resolver.dart';

class _FakeStreamResolver implements StreamResolver {
  @override
  Future<String?> resolve(String id) async => 'http://test.audio.url';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> _initTestStorage() async {
  final tempDir = await Directory.systemTemp.createTemp('caputune_autoplay_test');
  Hive.init(tempDir.path);
  await StorageService.init();
}

Song _song(String id, {String title = 'Song', String artist = 'Artist'}) {
  return Song(
    id: id,
    title: '$title $id',
    artist: '$artist $id',
    duration: '3:30',
  );
}

/// Builds a PlayerService whose similar-song lookup is fully controlled, so
/// the tests never touch the network.
///
/// Settings are persisted in Hive, so the helper resets the two switches
/// that the tests toggle to keep cases independent of each other.
PlayerService _player({SimilarSongsResolver? resolver}) {
  final player = PlayerService(
    resolver: _FakeStreamResolver(),
    similarSongsResolver: resolver ??
        (({required seed, required excludedIds, required limit}) async =>
            const <Song>[]),
  );
  player.setAutoplay(true);
  player.setContinueWithSimilarAfterPlaylist(false);
  return player;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _initTestStorage();
  });

  tearDownAll(() async {
    await Hive.close();
  });

  group('PlayerService Smart Similar-Song Autoplay & Playlist Rules', () {
    test('Playing an individual song sets isPlaylistSource to false', () async {
      final player = _player();
      final s = _song('s1');

      await player.play(s);
      expect(player.isPlaylistSource, isFalse);
      expect(player.queue, hasLength(1));
      expect(player.currentSong?.id, 's1');
    });

    test('Playlist playback marks isPlaylistSource to true', () async {
      final player = _player();
      final songs = [_song('p1'), _song('p2'), _song('p3')];

      await player.playList(songs, isPlaylistSource: true);
      expect(player.isPlaylistSource, isTrue);
      expect(player.queue, hasLength(3));
      expect(player.currentSong?.id, 'p1');
    });

    test('Playlist with shuffle OFF plays in original order', () async {
      final player = _player();
      final songs = [_song('p1'), _song('p2'), _song('p3')];

      await player.playList(songs, isPlaylistSource: true);
      expect(player.currentSong?.id, 'p1');

      await player.playNext();
      expect(player.currentSong?.id, 'p2');

      await player.playNext();
      expect(player.currentSong?.id, 'p3');
    });

    test('Playlist with shuffle ON preserves only playlist tracks with current at head', () async {
      final player = _player();
      final songs = [_song('p1'), _song('p2'), _song('p3'), _song('p4')];

      // Enable shuffle first
      player.toggleShuffle();
      expect(player.shuffleMode, isTrue);

      await player.playList(songs, startIndex: 1, isPlaylistSource: true);
      // Head is p2 (startIndex)
      expect(player.currentSong?.id, 'p2');
      // Queue contains exactly the 4 playlist songs and nothing else
      expect(player.queue.map((s) => s.id).toSet(),
          equals({'p1', 'p2', 'p3', 'p4'}));
      expect(player.queue, hasLength(4));
    });

    test('Playlist stops at the end when continueWithSimilarAfterPlaylist is false', () async {
      final player = _player();
      player.setContinueWithSimilarAfterPlaylist(false);
      final songs = [_song('p1'), _song('p2')];

      await player.playList(songs, isPlaylistSource: true);
      expect(player.currentSong?.id, 'p1');

      await player.playNext();
      expect(player.currentSong?.id, 'p2');

      // Reached the end of playlist: should stop and not append random songs
      await player.playNext();
      expect(player.currentIndex, -1);
      expect(player.queue, hasLength(2));
    });

    test('Playlist never fetches recommendations by default', () async {
      var called = false;
      final player = _player(resolver: ({
        required seed,
        required excludedIds,
        required limit,
      }) async {
        called = true;
        return [_song('r1')];
      });
      player.setContinueWithSimilarAfterPlaylist(false);

      await player.playList([_song('p1')], isPlaylistSource: true);
      await player.playNext();

      expect(called, isFalse);
      expect(player.queue, hasLength(1));
    });

    test('Playlist appends similar songs only when opted in', () async {
      final player = _player(resolver: ({
        required seed,
        required excludedIds,
        required limit,
      }) async {
        return [_song('r1').copyWith(isRecommended: true)];
      });
      player.setContinueWithSimilarAfterPlaylist(true);

      await player.playList([_song('p1')], isPlaylistSource: true);
      await player.playNext();

      expect(player.currentSong?.id, 'r1');
      expect(player.currentSong?.isRecommended, isTrue);
      // The playlist track is preserved, the recommendation is appended after.
      expect(player.queue.map((s) => s.id), ['p1', 'r1']);
    });

    test('Individual song continues with similar songs at queue end', () async {
      final player = _player(resolver: ({
        required seed,
        required excludedIds,
        required limit,
      }) async {
        return [
          _song('r1').copyWith(isRecommended: true),
          _song('r2').copyWith(isRecommended: true),
        ];
      });

      await player.play(_song('s1'));
      await player.playNext();

      expect(player.currentSong?.id, 'r1');
      expect(player.currentSong?.isRecommended, isTrue);
      expect(player.queue.map((s) => s.id), ['s1', 'r1', 'r2']);
    });

    test('Recommendations exclude already queued tracks', () async {
      Set<String>? seenExcluded;
      final player = _player(resolver: ({
        required seed,
        required excludedIds,
        required limit,
      }) async {
        seenExcluded = excludedIds;
        return [];
      });

      await player.playList([_song('p1'), _song('p2')], isPlaylistSource: true);
      player.setContinueWithSimilarAfterPlaylist(true);
      await player.playNext();
      await player.playNext();

      expect(seenExcluded, containsAll(['p1', 'p2']));
    });

    test('Falls back to stopping when no recommendations are available', () async {
      final player = _player(resolver: ({
        required seed,
        required excludedIds,
        required limit,
      }) async {
        return [];
      });

      await player.play(_song('s1'));
      await player.playNext();

      expect(player.currentIndex, -1);
      expect(player.queue, hasLength(1));
    });

    test('Recommendation failures degrade to the existing stop behavior', () async {
      final player = _player(resolver: ({
        required seed,
        required excludedIds,
        required limit,
      }) async {
        throw StateError('network down');
      });

      await player.play(_song('s1'));
      await player.playNext();

      expect(player.currentIndex, -1);
      expect(player.queue, hasLength(1));
    });

    test('Shuffle ON never injects recommendations for a playlist', () async {
      var called = false;
      final player = _player(resolver: ({
        required seed,
        required excludedIds,
        required limit,
      }) async {
        called = true;
        return [_song('r1')];
      });
      player.setContinueWithSimilarAfterPlaylist(true);
      player.toggleShuffle();

      await player.playList([_song('p1')], isPlaylistSource: true);
      await player.playNext();

      expect(called, isFalse);
      expect(player.queue, hasLength(1));
    });

    test('Autoplay disabled stops instead of fetching recommendations', () async {
      var called = false;
      final player = _player(resolver: ({
        required seed,
        required excludedIds,
        required limit,
      }) async {
        called = true;
        return [_song('r1')];
      });
      player.setAutoplay(false);

      await player.play(_song('s1'));
      await player.playNext();

      expect(called, isFalse);
      expect(player.currentIndex, -1);
    });

    test('Repeat One repeats the current song and does not advance', () async {
      final player = _player();
      final songs = [_song('p1'), _song('p2')];

      await player.playList(songs, isPlaylistSource: true);
      player.cycleRepeat(); // all
      player.cycleRepeat(); // one
      expect(player.repeatMode, RepeatMode.one);

      await player.playNext();
      expect(player.currentSong?.id, 'p1');
    });

    test('Repeat All wraps to index 0 on playlist end', () async {
      final player = _player();
      final songs = [_song('p1'), _song('p2')];

      await player.playList(songs, isPlaylistSource: true);
      player.cycleRepeat(); // all
      expect(player.repeatMode, RepeatMode.all);

      await player.playNext(); // plays p2
      expect(player.currentSong?.id, 'p2');

      await player.playNext(); // wraps to p1
      expect(player.currentSong?.id, 'p1');
    });

    test('Repeat All does not fetch recommendations at the end', () async {
      var called = false;
      final player = _player(resolver: ({
        required seed,
        required excludedIds,
        required limit,
      }) async {
        called = true;
        return [_song('r1')];
      });
      player.setContinueWithSimilarAfterPlaylist(true);
      player.cycleRepeat(); // all

      await player.playList([_song('p1')], isPlaylistSource: true);
      await player.playNext();

      expect(called, isFalse);
      expect(player.currentSong?.id, 'p1');
    });

    test('Manual queue operations (addToQueue, reorderQueue, clearQueue) work as expected', () async {
      final player = _player();
      final s1 = _song('s1');
      final s2 = _song('s2');

      await player.play(s1);
      final added = player.addToQueue(s2);
      expect(added, isTrue);
      expect(player.queue, hasLength(2));

      // Reorder
      player.reorderQueue(1, 0);
      expect(player.queue.first.id, 's2');

      // Clear
      await player.clearQueue();
      expect(player.queue, isEmpty);
      expect(player.currentIndex, -1);
    });

    test('Manually queued tracks survive the playlist and play before recommendations', () async {
      final player = _player(resolver: ({
        required seed,
        required excludedIds,
        required limit,
      }) async {
        return [_song('r1').copyWith(isRecommended: true)];
      });
      player.setContinueWithSimilarAfterPlaylist(true);

      await player.playList([_song('p1')], isPlaylistSource: true);
      player.addToQueue(_song('m1'));

      await player.playNext();
      expect(player.currentSong?.id, 'm1');

      await player.playNext();
      expect(player.currentSong?.id, 'r1');
      expect(player.currentSong?.isRecommended, isTrue);
    });

    test('Un-shuffle restores the original playlist order', () async {
      final player = _player();
      final songs = [_song('p1'), _song('p2'), _song('p3')];

      await player.playList(songs, isPlaylistSource: true);
      player.toggleShuffle(); // on
      expect(player.currentSong?.id, 'p1');

      player.toggleShuffle(); // off
      expect(player.queue.map((s) => s.id), ['p1', 'p2', 'p3']);
      expect(player.currentSong?.id, 'p1');
    });

    test('Playing a song outside the queue starts a fresh individual source', () async {
      final player = _player();

      await player.playList([_song('p1'), _song('p2')], isPlaylistSource: true);
      await player.play(_song('other'));

      expect(player.isPlaylistSource, isFalse);
      expect(player.queue.map((s) => s.id), ['other']);
      expect(player.currentSong?.id, 'other');
    });

    test('Empty playlist clears the queue without crashing', () async {
      final player = _player();

      await player.playList(const [], isPlaylistSource: true);
      expect(player.queue, isEmpty);
      expect(player.currentIndex, -1);
    });
  });
}
