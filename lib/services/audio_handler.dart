import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'player_service.dart';

/// Bridges [PlayerService] playback state with Android's system MediaSession
/// and notification shade using [audio_service].
///
/// Keeps Android recognizing CapuTune as an active music player with:
/// - CapuTune as media app
/// - Current song title, artist, artwork
/// - Play/Pause, Previous, Next
/// - Seekbar / duration position synchronization
/// - Proper background foreground service lifecycle
class CapuTuneAudioHandler extends BaseAudioHandler with SeekHandler {
  final PlayerService _playerService;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;

  CapuTuneAudioHandler(this._playerService) {
    _playerService.addListener(_onPlayerStateChanged);
    _posSub = _playerService.positionStream.listen(_onPositionChanged);
    _durSub = _playerService.durationStream.listen(_onDurationChanged);
    _onPlayerStateChanged();
  }

  void _onPositionChanged(Duration pos) {
    playbackState.add(playbackState.value.copyWith(
      updatePosition: pos,
    ));
  }

  void _onDurationChanged(Duration? dur) {
    if (dur != null && mediaItem.value != null) {
      mediaItem.add(mediaItem.value!.copyWith(duration: dur));
    }
  }

  void _onPlayerStateChanged() {
    final song = _playerService.currentSong;
    if (song != null) {
      final currentItem = mediaItem.value;
      if (currentItem?.id != song.id) {
        mediaItem.add(MediaItem(
          id: song.id,
          title: song.title,
          artist: song.artist,
          album: song.album ?? 'CapuTune',
          artUri: song.thumbnail != null ? Uri.tryParse(song.thumbnail!) : null,
          duration: _playerService.duration,
        ));
      }
    }

    final isPlaying = _playerService.isPlaying;
    final hasNext = _playerService.currentIndex + 1 < _playerService.queue.length ||
        _playerService.radioAutoplay ||
        _playerService.repeatMode != RepeatMode.off;
    final hasPrev = _playerService.currentIndex > 0;

    final controls = [
      if (hasPrev) MediaControl.skipToPrevious else MediaControl.rewind,
      if (isPlaying) MediaControl.pause else MediaControl.play,
      if (hasNext) MediaControl.skipToNext else MediaControl.fastForward,
    ];

    playbackState.add(playbackState.value.copyWith(
      controls: controls,
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.setShuffleMode,
        MediaAction.setRepeatMode,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: song == null
          ? AudioProcessingState.idle
          : AudioProcessingState.ready,
      playing: isPlaying,
      updatePosition: _playerService.position,
      bufferedPosition: _playerService.position,
      speed: 1.0,
      queueIndex: _playerService.currentIndex >= 0 ? _playerService.currentIndex : null,
      repeatMode: _toAudioServiceRepeatMode(_playerService.repeatMode),
      shuffleMode: _playerService.shuffleMode
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    ));
  }

  static AudioServiceRepeatMode _toAudioServiceRepeatMode(RepeatMode mode) {
    switch (mode) {
      case RepeatMode.off:
        return AudioServiceRepeatMode.none;
      case RepeatMode.one:
        return AudioServiceRepeatMode.one;
      case RepeatMode.all:
        return AudioServiceRepeatMode.all;
    }
  }

  @override
  Future<void> play() => _playerService.togglePlay();

  @override
  Future<void> pause() => _playerService.togglePlay();

  @override
  Future<void> stop() => _playerService.stop();

  @override
  Future<void> seek(Duration position) => _playerService.seek(position);

  @override
  Future<void> skipToNext() => _playerService.playNext();

  @override
  Future<void> skipToPrevious() => _playerService.playPrevious();

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _playerService.cycleRepeat();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _playerService.toggleShuffle();
  }

  Future<void> dispose() async {
    _playerService.removeListener(_onPlayerStateChanged);
    await _posSub?.cancel();
    await _durSub?.cancel();
  }
}
