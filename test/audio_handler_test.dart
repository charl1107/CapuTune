import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:caputune/models/song.dart';
import 'package:caputune/services/audio_handler.dart';
import 'package:caputune/services/player_service.dart';
import 'package:caputune/services/storage_service.dart';
import 'package:caputune/services/stream_resolver.dart';

class _FakeStreamResolver implements StreamResolver {
  @override
  Future<String?> resolve(String id, {String? quality}) async =>
      'http://test.audio.url';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Song _song(String id, {String title = 'Title', String artist = 'Artist', String? thumb}) {
  return Song(
    id: id,
    title: '$title $id',
    artist: '$artist $id',
    duration: '3:30',
    thumbnail: thumb,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('caputune_audio_handler_test');
    Hive.init(tempDir.path);
    await StorageService.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('CapuTuneAudioHandler synchronizes mediaItem when song starts', () async {
    final player = PlayerService(
      resolver: _FakeStreamResolver(),
      similarSongsResolver: ({required seed, required excludedIds, required limit}) async => [],
    );

    final handler = CapuTuneAudioHandler(player);
    addTearDown(handler.dispose);

    // Initial state is idle with no media item
    expect(handler.mediaItem.value, isNull);
    expect(handler.playbackState.value.processingState, AudioProcessingState.idle);

    // Start playback of a song
    final s1 = _song('song_1', title: 'Bohemian Rhapsody', artist: 'Queen', thumb: 'https://example.com/art.jpg');
    await player.play(s1);

    // Handler should immediately reflect song title, artist, artUri, album
    expect(handler.mediaItem.value, isNotNull);
    expect(handler.mediaItem.value!.id, 'song_1');
    expect(handler.mediaItem.value!.title, 'Bohemian Rhapsody song_1');
    expect(handler.mediaItem.value!.artist, 'Queen song_1');
    expect(handler.mediaItem.value!.artUri, Uri.parse('https://example.com/art.jpg'));
    expect(handler.playbackState.value.processingState, AudioProcessingState.ready);
  });

  test('CapuTuneAudioHandler reports the configured playback rate', () async {
    final player = PlayerService(
      resolver: _FakeStreamResolver(),
      similarSongsResolver: ({required seed, required excludedIds, required limit}) async => [],
    );

    final handler = CapuTuneAudioHandler(player);
    addTearDown(handler.dispose);

    await player.play(_song('rate_song'));

    expect(handler.playbackState.value.speed, 1.0);

    // The session must advertise the real rate, not a hardcoded 1.0, so the
    // system media card shows the truth for 1.5x playback etc. setRate
    // notifies listeners, which triggers the handler's broadcast.
    await player.setRate(1.5);

    expect(handler.playbackState.value.speed, 1.5);
  });

  test('CapuTuneAudioHandler exposes system actions and transport controls', () async {
    final player = PlayerService(
      resolver: _FakeStreamResolver(),
      similarSongsResolver: ({required seed, required excludedIds, required limit}) async => [],
    );

    final handler = CapuTuneAudioHandler(player);
    addTearDown(handler.dispose);

    final s1 = _song('s1');
    final s2 = _song('s2');
    await player.playList([s1, s2], isPlaylistSource: true);

    expect(handler.mediaItem.value?.id, 's1');
    expect(handler.playbackState.value.controls, isNotEmpty);
    expect(handler.playbackState.value.systemActions, contains(MediaAction.seek));
    expect(handler.playbackState.value.systemActions, contains(MediaAction.setShuffleMode));
    expect(handler.playbackState.value.systemActions, contains(MediaAction.setRepeatMode));

    // Media action callback routing: skipToNext
    await handler.skipToNext();
    expect(player.currentSong?.id, 's2');
    expect(handler.mediaItem.value?.id, 's2');

    // Media action callback routing: skipToPrevious
    await handler.skipToPrevious();
    expect(player.currentSong?.id, 's1');
    expect(handler.mediaItem.value?.id, 's1');

    // Shuffle & repeat mode controls
    expect(player.shuffleMode, isFalse);
    await handler.setShuffleMode(AudioServiceShuffleMode.all);
    expect(player.shuffleMode, isTrue);

    expect(player.repeatMode, RepeatMode.off);
    await handler.setRepeatMode(AudioServiceRepeatMode.all);
    expect(player.repeatMode, RepeatMode.all);
  });

  test('Previous and Next are always advertised, even at queue boundaries',
      () async {
    final player = PlayerService(
      resolver: _FakeStreamResolver(),
      similarSongsResolver: ({required seed, required excludedIds, required limit}) async => [],
    );

    final handler = CapuTuneAudioHandler(player);
    addTearDown(handler.dispose);

    final s1 = _song('s1');
    final s2 = _song('s2');
    await player.playList([s1, s2], isPlaylistSource: true);

    List<MediaAction> controlActions() =>
        handler.playbackState.value.controls.map((c) => c.action).toList();

    // Single-track queue: Previous/Next must still be advertised so Android
    // 13+ renders the buttons (PlayerService no-ops safely at the edges).
    await player.play(_song('only'));
    expect(controlActions(), contains(MediaAction.skipToNext));
    expect(controlActions(), contains(MediaAction.skipToPrevious));

    // First track of a multi-track queue.
    await player.playList([s1, s2], isPlaylistSource: true);
    expect(controlActions(), contains(MediaAction.skipToPrevious));
    expect(controlActions(), contains(MediaAction.skipToNext));

    // Last track, past the queue end boundary.
    await player.playNext();
    expect(player.currentSong?.id, 's2');
    expect(controlActions(), contains(MediaAction.skipToPrevious));
    expect(controlActions(), contains(MediaAction.skipToNext));

    // Skipping Next at the end must not crash and must not lose the session.
    await player.playNext();
    expect(controlActions(), contains(MediaAction.skipToNext));
  });

  test('Play and Pause from the session reflect real playback state', () async {
    final player = PlayerService(
      resolver: _FakeStreamResolver(),
      similarSongsResolver: ({required seed, required excludedIds, required limit}) async => [],
    );

    final handler = CapuTuneAudioHandler(player);
    addTearDown(handler.dispose);

    await player.play(_song('s1'));

    // Pause control shown while playing; Play shown while paused.
    List<MediaAction> controlActions() =>
        handler.playbackState.value.controls.map((c) => c.action).toList();
    final pauseShown = controlActions().contains(MediaAction.pause);
    final playShown = controlActions().contains(MediaAction.play);
    expect(pauseShown != playShown, isTrue,
        reason: 'exactly one of Play/Pause must be advertised');

    // The state-checked play/pause handlers never invert the intent, and the
    // session state mirrors the real player at all times.
    await handler.pause();
    await handler.play();
    await handler.play(); // already playing -> no-op
    expect(handler.playbackState.value.playing, player.isPlaying);
  });

  test('sleep timer persists across songs and reports its end time', () async {
    final player = PlayerService(
      resolver: _FakeStreamResolver(),
      similarSongsResolver: ({required seed, required excludedIds, required limit}) async => [],
    );

    expect(player.sleepTimerEndsAt, isNull);

    player.setSleepTimer(const Duration(minutes: 30));
    final endsAt = player.sleepTimerEndsAt;
    expect(endsAt, isNotNull);
    // Allow a small scheduling skew between setting and reading the clock.
    expect(
      endsAt!.difference(DateTime.now()).inMinutes,
      inInclusiveRange(29, 30),
    );

    // The timer must survive queue navigation — it belongs to the session,
    // not to one song.
    await player.play(_song('sleep_song'));
    expect(player.sleepTimerEndsAt, endsAt);

    player.cancelSleepTimer();
    expect(player.sleepTimerEndsAt, isNull);

    // Cancel is idempotent.
    player.cancelSleepTimer();
    expect(player.sleepTimerEndsAt, isNull);
  });

  test('replacing a sleep timer restarts it rather than stacking', () async {
    final player = PlayerService(
      resolver: _FakeStreamResolver(),
      similarSongsResolver: ({required seed, required excludedIds, required limit}) async => [],
    );

    player.setSleepTimer(const Duration(minutes: 60));
    final firstEnd = player.sleepTimerEndsAt;

    player.setSleepTimer(const Duration(minutes: 15));
    final secondEnd = player.sleepTimerEndsAt;

    expect(secondEnd!.isBefore(firstEnd!), isTrue);
  });

  group('isNetworkStreamError', () {
    test('recognizes the googlevideo CDN timeout burst', () {
      const message = 'ffmpeg: tcp: ffurl_read returned 0xffffff92 ~ '
          'lavf: Failed to create file cache. ~ '
          'ffmpeg: tcp: Connection to tcp://rr2---sn2-2aqu-hoalr.googlevideo.com:443 failed: Connection time out';
      expect(PlayerService.isNetworkStreamError(message), isTrue);
    });

    test('recognizes other reachability failures', () {
      expect(
        PlayerService.isNetworkStreamError('tcp: connection refused'),
        isTrue,
      );
      expect(
        PlayerService.isNetworkStreamError('network is unreachable'),
        isTrue,
      );
      expect(
        PlayerService.isNetworkStreamError('ffmpeg: could not resolve host'),
        isTrue,
      );
    });

    test('does not claim decoding or local-file errors', () {
      expect(
        PlayerService.isNetworkStreamError('Unknown format tag in demuxer'),
        isFalse,
      );
      expect(
        PlayerService.isNetworkStreamError('ao/wasapi: invalid parameter'),
        isFalse,
      );
      expect(
        PlayerService.isNetworkStreamError('Requested format not supported'),
        isFalse,
      );
    });
  });

  group('streamRetryDelay', () {
    test('doubles exponentially across attempts, no jitter', () {
      // Base is 1500 ms; jitter 0 scales strictly down by 0.7.
      expect(
        PlayerService.streamRetryDelay(1, 0.0),
        const Duration(milliseconds: 1050),
      );
      expect(
        PlayerService.streamRetryDelay(2, 0.0),
        const Duration(milliseconds: 2100),
      );
      expect(
        PlayerService.streamRetryDelay(3, 0.0),
        const Duration(milliseconds: 4200),
      );
    });

    test('jitter 1 scales up by 1.3, bounds hold mid-range', () {
      expect(
        PlayerService.streamRetryDelay(1, 1.0),
        const Duration(milliseconds: 1500 * 13 ~/ 10),
      );
      // 0.5 is the exact midpoint: factor 1.0 — pure exponential.
      expect(
        PlayerService.streamRetryDelay(2, 0.5),
        const Duration(milliseconds: 3000),
      );
    });

    test('delays grow monotonically regardless of jitter extremes', () {
      // Even fastest attempt 2 (jitter 0) beats slowest attempt 1 (jitter 1):
      // 3000*0.7 = 2100 > 1500*1.3 = 1950.
      expect(
        PlayerService.streamRetryDelay(2, 0.0).inMilliseconds,
        greaterThan(PlayerService.streamRetryDelay(1, 1.0).inMilliseconds),
      );
    });
  });
}
