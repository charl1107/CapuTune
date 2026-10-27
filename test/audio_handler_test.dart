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
  Future<String?> resolve(String id) async => 'http://test.audio.url';

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
}
