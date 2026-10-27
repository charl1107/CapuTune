import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'player_service.dart';

/// Bridges [PlayerService] playback state with Android's system MediaSession
/// and notification shade using [audio_service].
///
/// Notification buttons:
/// - Previous / Play-Pause / Next are ALWAYS advertised.
///   On Android 13+ System UI renders the media card's buttons from the
///   PlaybackState action bits, and audio_service only sets
///   ACTION_SKIP_TO_PREVIOUS / ACTION_SKIP_TO_NEXT when these controls are
///   present. Substituting rewind/fastForward at queue edges (which have no
///   meaning here) made the buttons disappear entirely on some devices.
///   PlayerService.playPrevious()/playNext() already no-op safely at the
///   queue boundaries, and playNext() still honors repeat / radio autoplay /
///   recommendations, so the buttons always drive the real player.
/// - Play/Pause is state-checked: the notification's Play never pauses and
///   Pause never resumes, even if the session state briefly diverges.
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

    // Previous / Play-Pause / Next, always advertised (see class doc).
    final controls = [
      MediaControl.skipToPrevious,
      if (isPlaying) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
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
  Future<void> play() async {
    // State-checked so a stale session can never turn "Play" into a pause.
    if (!_playerService.isPlaying) await _playerService.togglePlay();
  }

  @override
  Future<void> pause() async {
    if (_playerService.isPlaying) await _playerService.togglePlay();
  }

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
