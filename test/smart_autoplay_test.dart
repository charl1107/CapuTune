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

  group('Radio Autoplay Toggle & Non-Disruptive Shuffle Invariants', () {
    test('1. Toggling Shuffle during standalone playback does not interrupt the song', () async {
      final player = _player();
      final song = _song('s1');

      await player.play(song);
      expect(player.currentSong?.id, 's1');
      expect(player.currentIndex, 0);

      // Toggle Shuffle ON
      player.toggleShuffle();
      expect(player.shuffleMode, isTrue);
      expect(player.currentSong?.id, 's1');
      expect(player.currentIndex, 0);
      expect(player.queue.map((s) => s.id), ['s1']);

      // Toggle Shuffle OFF
      player.toggleShuffle();
      expect(player.shuffleMode, isFalse);
      expect(player.currentSong?.id, 's1');
      expect(player.currentIndex, 0);
      expect(player.queue.map((s) => s.id), ['s1']);
    });

    test('2. Toggling Shuffle in a playlist does not interrupt the song', () async {
      final player = _player();
      final songs = [_song('p1'), _song('p2'), _song('p3'), _song('p4')];

      await player.playList(songs, isPlaylistSource: true);
      await player.playNext(); // Now on p2
      expect(player.currentSong?.id, 'p2');
      expect(player.currentIndex, 1);

      // Toggle Shuffle ON
      player.toggleShuffle();
      expect(player.shuffleMode, isTrue);
      // Current song remains p2 at currentIndex 1
      expect(player.currentSong?.id, 'p2');
      expect(player.currentIndex, 1);
      // Already-played history (p1) is preserved before current song
      expect(player.queue[0].id, 'p1');
    });

    test('3. The next playlist track follows the new shuffled order', () async {
      final player = _player();
      final songs = [_song('p1'), _song('p2'), _song('p3'), _song('p4')];

      await player.playList(songs, isPlaylistSource: true);
      await player.playNext(); // Now on p2
      expect(player.currentSong?.id, 'p2');

      player.toggleShuffle();
      expect(player.shuffleMode, isTrue);

      // Remaining unplayed tracks are p3 and p4 in shuffled positions
      final nextTrackId = player.queue[2].id;
      expect({'p3', 'p4'}, contains(nextTrackId));

      await player.playNext();
      expect(player.currentSong?.id, nextTrackId);
    });

    test('4. Shuffle does not inject external recommendations into a playlist', () async {
      var resolverCalled = false;
      final player = _player(resolver: ({
        required seed,
        required excludedIds,
        required limit,
      }) async {
        resolverCalled = true;
        return [_song('rec1')];
      });

      final songs = [_song('p1'), _song('p2')];
      await player.playList(songs, isPlaylistSource: true);
      player.toggleShuffle();

      await player.playNext(); // plays p2 or p1
      await player.playNext(); // reaches end

      expect(resolverCalled, isFalse);
      expect(player.currentIndex, -1);
      expect(player.queue.map((s) => s.id).toSet(), equals({'p1', 'p2'}));
    });

    test('5. Radio Autoplay can be enabled and disabled independently', () {
      final player = _player();
      expect(player.radioAutoplay, isTrue);
      expect(player.shuffleMode, isFalse);

      // Toggling shuffle does not affect radio autoplay
      player.toggleShuffle();
      expect(player.shuffleMode, isTrue);
      expect(player.radioAutoplay, isTrue);

      // Toggling radio autoplay does not affect shuffle
      player.setRadioAutoplay(false);
      expect(player.radioAutoplay, isFalse);
      expect(player.shuffleMode, isTrue);

      // Disable shuffle
      player.toggleShuffle();
      expect(player.shuffleMode, isFalse);
      expect(player.radioAutoplay, isFalse);

      // Enable radio autoplay
      player.setRadioAutoplay(true);
      expect(player.radioAutoplay, isTrue);
      expect(player.shuffleMode, isFalse);
    });

    test('6. Disabling Radio Autoplay does not interrupt playback or erase the manual queue', () async {
      final player = _player();
      final s1 = _song('s1');
      await player.play(s1);

      // Add a manual queue item
      final m1 = _song('m1');
      player.addToQueue(m1);

      // Inject recommendations
      player.prepareRadioQueue();
      // Suppose recommendations are in queue
      final rec = _song('r1').copyWith(isRecommended: true);
      player.addToQueue(rec);

      expect(player.queue.any((s) => s.id == 'm1'), isTrue);
      expect(player.queue.any((s) => s.id == 'r1'), isTrue);
      expect(player.currentSong?.id, 's1');

      // Disable Radio Autoplay
      player.setRadioAutoplay(false);

      // Current song is uninterrupted
      expect(player.currentSong?.id, 's1');
      expect(player.currentIndex, 0);

      // Manual queue item is preserved!
      expect(player.queue.any((s) => s.id == 'm1'), isTrue);

      // Recommended items are cleared!
      expect(player.queue.any((s) => s.id == 'r1'), isFalse);

      // Play next advances to manual queue item m1
      await player.playNext();
      expect(player.currentSong?.id, 'm1');

      // Next at end stops without fetching recommendations
      await player.playNext();
      expect(player.currentIndex, -1);
    });

    test('7. No queue means Shuffle cannot invent tracks', () async {
      final player = _player();
      player.setRadioAutoplay(false);
      await player.play(_song('single'));

      expect(player.queue, hasLength(1));
      expect(player.currentSong?.id, 'single');

      // Enable shuffle with no upcoming queue
      player.toggleShuffle();
      expect(player.shuffleMode, isTrue);
      expect(player.queue, hasLength(1));
      expect(player.currentSong?.id, 'single');
    });

    test('8. Repeat modes and manual queue operations still work', () async {
      final player = _player();
      await player.playList([_song('a'), _song('b')], isPlaylistSource: true);

      // Manual queue
      player.addToQueue(_song('c'));
      expect(player.queue.map((s) => s.id), ['a', 'b', 'c']);

      // Repeat One
      player.cycleRepeat(); // all
      player.cycleRepeat(); // one
      expect(player.repeatMode, RepeatMode.one);

      await player.playNext();
      expect(player.currentSong?.id, 'a'); // Repeat One seeks zero without advance

      // Repeat All
      player.cycleRepeat(); // off
      player.cycleRepeat(); // all
      expect(player.repeatMode, RepeatMode.all);

      await player.playNext(); // b
      expect(player.currentSong?.id, 'b');

      await player.playNext(); // c
      expect(player.currentSong?.id, 'c');

      await player.playNext(); // wraps to a
      expect(player.currentSong?.id, 'a');
    });
  });
}
