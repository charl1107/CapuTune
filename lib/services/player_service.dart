import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';
import 'stream_resolver.dart';
import 'storage_service.dart';
import 'cipher_service.dart';
import 'recommendation_service.dart';
import '../utils/snackbar.dart';

enum RepeatMode { off, all, one }

/// Resolves similar tracks for smart autoplay. Injectable so tests never hit
/// the network.
typedef SimilarSongsResolver = Future<List<Song>> Function({
  required Song seed,
  required Set<String> excludedIds,
  required int limit,
});

class PlayerService extends ChangeNotifier {
  /// media_kit (libmpv) engine: all network streaming and legacy .mp3 files.
  /// Its own HTTP stack (libcurl) bypasses ExoPlayer, which fails to load
  /// googlevideo streams on the target device.
  ///
  /// The engine is created lazily so unit/widget tests never load libmpv.
  final Player? _injectedPlayer;
  Player? _lazyPlayer;

  /// True while running under `flutter test`, where libmpv must not be loaded.
  final bool _isTestEnv = Platform.environment.containsKey('FLUTTER_TEST');

  /// The real playback engine (injected instance or lazily created one).
  Player get _engine => _injectedPlayer ??
      (_lazyPlayer ??= Player(
        configuration:
            const PlayerConfiguration(logLevel: MPVLogLevel.info)));

  /// True when an engine instance already exists (no construction implied).
  bool get _hasEngine => _injectedPlayer != null || _lazyPlayer != null;

  /// True when the service is allowed to touch the real media engine.
  bool get _engineUsable => _injectedPlayer != null || !_isTestEnv;

  /// just_audio engine: created lazily, used only for .ct encrypted files
  /// (RAM-only decrypt via [EncryptedAudioSource]). Never created on
  /// Windows, which has no just_audio implementation.
  AudioPlayer? _justAudio;
  bool _usesLocalPlayback = false;

  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();

  /// Rolling tail of mpv log lines: the real failure detail (HTTP status,
  /// curl errors) is reported on the log stream, not the error stream.
  final List<String> _mkLogTail = [];

  List<Song> _queue = [];
  int _currentIndex = -1;
  bool _isDarkMode = false;
  bool _autoplay = true;
  bool _radioAutoplay = true;
  bool _continueWithSimilarAfterPlaylist = false;
  bool _isPlaylistSource = false;
  List<Song> _originalQueue = [];

  /// Tracks appended by smart autoplay. Kept separate from [_originalQueue]
  /// so a playlist's own tracks are never lost or silently replaced.
  List<Song> _recommendedQueue = [];

  /// Tracks queued by the user via "add to queue". These are manual choices
  /// and are therefore preserved ahead of any recommendation lookup.
  List<Song> _manualQueue = [];
  bool _isLoadingRecommendations = false;
  Future<void>? _radioQueueFuture;
  String _audioQuality = '320kbps';
  bool _isPlaying = false;
  bool _shuffleMode = false;
  RepeatMode _repeatMode = RepeatMode.off;
  final StreamResolver _resolver;

  /// Resolver used to find similar tracks at the end of a queue. Defaults to
  /// the network-backed [RecommendationService]; tests inject a fake.
  final SimilarSongsResolver? _similarSongsResolver;

  List<Song> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  bool get isDarkMode => _isDarkMode;
  bool get autoplay => _autoplay;
  bool get radioAutoplay => _radioAutoplay;
  bool get continueWithSimilarAfterPlaylist => _continueWithSimilarAfterPlaylist;
  bool get isPlaylistSource => _isPlaylistSource;
  String get audioQuality => _audioQuality;
  bool get isPlaying => _isPlaying;
  bool get shuffleMode => _shuffleMode;
  RepeatMode get repeatMode => _repeatMode;
  Song? get currentSong =>
      _currentIndex >= 0 && _currentIndex < _queue.length
          ? _queue[_currentIndex]
          : null;

  // Only the active engine is read: _local's branch is unreachable until
  // _usesLocalPlayback becomes true, which only happens after creation.
  Duration get position {
    if (_usesLocalPlayback) return _local.position;
    if (!_engineUsable || !_hasEngine) return Duration.zero;
    return _engine.state.position;
  }

  Duration get duration {
    if (_usesLocalPlayback) return _local.duration ?? Duration.zero;
    if (!_engineUsable || !_hasEngine) return Duration.zero;
    return _engine.state.duration;
  }
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration?> get durationStream => _durationController.stream;

  /// Lazy just_audio instance; mirrors its state into the service streams
  /// on first creation.
  AudioPlayer get _local {
    return _justAudio ??= () {
      final p = AudioPlayer();
      p.positionStream.listen(_positionController.add);
      p.durationStream.listen(_durationController.add);
      p.playerStateStream.listen((state) {
        _isPlaying = state.playing;
        if (state.processingState == ProcessingState.completed && _autoplay) {
          playNext();
        }
        notifyListeners();
      });
      return p;
    }();
  }

  PlayerService({
    StreamResolver? resolver,
    Player? player,
    SimilarSongsResolver? similarSongsResolver,
    bool? initialRadioAutoplay,
  })  : _resolver = resolver ?? StreamResolver(),
        _injectedPlayer = player,
        _similarSongsResolver = similarSongsResolver {
    if (initialRadioAutoplay != null) {
      _radioAutoplay = initialRadioAutoplay;
    }
    _loadSettings();
    if (_engineUsable) {
      _initMpvListeners();
    }
  }

  void _initMpvListeners() {
    final engine = _engine;
    engine.stream.position.listen(_positionController.add);
    engine.stream.duration.listen(_durationController.add);
    engine.stream.playing.listen((p) {
      _isPlaying = p;
      notifyListeners();
    });
    engine.stream.completed.listen((c) {
      if (c && _autoplay) {
        playNext();
      }
    });
    engine.stream.error.listen((msg) {
      debugPrint('[mk] error: $msg');
      final brief = msg.length > 60 ? '${msg.substring(0, 60)}…' : msg;
      final errs = _mkLogTail.where((e) => e.startsWith('E|')).toList();
      final chosen = errs.isNotEmpty ? errs : _mkLogTail;
      var tail = chosen.length <= 4
          ? chosen.join(' ~ ')
          : chosen.skip(chosen.length - 4).join(' ~ ');
      if (tail.length > 210) tail = '…${tail.substring(tail.length - 210)}';
      final full = tail.isEmpty
          ? 'Playback error: $brief'
          : 'Playback error: $brief | mpv: $tail';
      showGlobalSnack(full.length > 320 ? '${full.substring(0, 320)}…' : full);
      final s = currentSong;
      if (s != null && s.localPath == null && !_usesLocalPlayback) {
        _tryPlayLocal(s);
      }
    });
    engine.stream.log.listen((l) {
      debugPrint('[mk] ${l.text}');
      final text = l.text.replaceAll(RegExp(r'https?://\S+'), '<url>');
      final lvl = l.level.trim().toLowerCase();
      final isErr = lvl.startsWith('e') || lvl.startsWith('f');
      _mkLogTail.add('${isErr ? 'E|' : '-|'}${l.prefix}: $text');
      if (_mkLogTail.length > 12) _mkLogTail.removeAt(0);
    });
  }

  Future<void> _loadSettings() async {
    _isDarkMode = StorageService.getDarkMode();
    _autoplay = StorageService.getAutoplay();
    _radioAutoplay = StorageService.getRadioAutoplay();
    _continueWithSimilarAfterPlaylist =
        StorageService.getContinueWithSimilarAfterPlaylist();
    _audioQuality = StorageService.getAudioQuality();
    notifyListeners();
  }

  Future<void> play(Song song) async {
    final index = _queue.indexWhere((s) => s.id == song.id);
    if (index == -1) {
      // A song outside the current queue starts a fresh individual source:
      // the previous playlist/queue is dropped rather than silently mixed in.
      _queue = [song];
      _originalQueue = [song];
      _recommendedQueue = [];
      _manualQueue = [];
      _currentIndex = 0;
      _isPlaylistSource = false;
      if (_autoplay && _radioAutoplay) {
        _radioQueueFuture = prepareRadioQueue(seed: song);
      }
    } else {
      _currentIndex = index;
    }

    if (song.localPath != null) {
      if (kIsWeb) {
        showGlobalSnack('Local audio playback is not supported on web yet');
        return;
      }
      final played = await _tryPlayLocal(song);
      if (played) return;

      if (_engineUsable) {
        await _engine.stop();
      }
      await _justAudio?.stop();
      _usesLocalPlayback = false;
      _isPlaying = false;
      showGlobalSnack('Local audio file not found. It may have been moved or deleted.');
      notifyListeners();
      return;
    }

    // Try an app-managed offline copy before resolving a YouTube stream.
    if (!kIsWeb) {
      final played = await _tryPlayLocal(song);
      if (played) return;
    }

    // Stream on-device
    try {
      final audioUrl = await _resolver.resolve(song.id);
      if (audioUrl == null) {
        debugPrint('[play] resolve returned null for ${song.id}');
        showGlobalSnack(
            'Stream extraction failed - YouTube gave no audio for this song');
        return;
      }
      debugPrint('[play] resolve OK for ${song.id}, loading into media_kit');
      _mkLogTail.clear();
      _usesLocalPlayback = false;
      if (_engineUsable) {
        await _engine.open(Media(audioUrl), play: true);
      }
      StorageService.addRecentPlay(song);
      StorageService.incrementPlayCount(song.id);
      notifyListeners();
    } catch (e) {
      debugPrint('[play] playback error for ${song.id}: $e');
      showGlobalSnack('Playback error: $e');
      if (!kIsWeb) {
        await _tryPlayLocal(song);
      }
    }
  }

  Future<void> playList(
    List<Song> songs, {
    int startIndex = 0,
    bool isPlaylistSource = false,
  }) async {
    if (songs.isEmpty) {
      await clearQueue();
      return;
    }

    _isPlaylistSource = isPlaylistSource;
    _originalQueue = List.from(songs);
    _recommendedQueue = [];

    if (_shuffleMode && isPlaylistSource) {
      // Shuffle ON for a playlist: the selected track anchors the head and
      // only the *remaining* playlist tracks are shuffled. No recommendations
      // are injected while shuffle is on.
      final chosenSong = (startIndex >= 0 && startIndex < songs.length)
          ? songs[startIndex]
          : songs.first;
      final remaining = List<Song>.from(songs)
        ..removeWhere((s) => s.id == chosenSong.id);
      remaining.shuffle();
      _queue = [chosenSong, ...remaining];
      _currentIndex = 0;
    } else {
      _queue = List.from(songs);
      _currentIndex = startIndex.clamp(0, songs.length - 1);
    }

    await play(_queue[_currentIndex]);
  }

  bool addToQueue(Song song) {
    if (_queue.any((queuedSong) => queuedSong.id == song.id)) return false;
    _manualQueue.add(song);

    // Place manual queue additions ahead of unplayed recommendations
    final firstRecIndex = _queue.indexWhere(
      (s) => s.isRecommended && _queue.indexOf(s) > _currentIndex,
    );
    if (firstRecIndex != -1) {
      _queue.insert(firstRecIndex, song);
    } else {
      _queue.add(song);
    }
    notifyListeners();
    return true;
  }

  /// Prepares a diverse radio queue based on [seed] without interrupting playback.
  Future<void> prepareRadioQueue({Song? seed}) async {
    final seedSong = seed ?? currentSong;
    if (seedSong == null ||
        !_autoplay ||
        !_radioAutoplay ||
        _isLoadingRecommendations) {
      return;
    }
    _isLoadingRecommendations = true;
    try {
      final excluded = <String>{
        ..._queue.map((s) => s.id),
        ..._manualQueue.map((s) => s.id),
      };
      final recs = await _findSimilarSongs(
        seed: seedSong,
        excludedIds: excluded,
        limit: 10,
      );
      if (!_radioAutoplay || currentSong?.id != seedSong.id || _isPlaylistSource) {
        return;
      }
      if (recs.isNotEmpty) {
        final toAdd = List<Song>.from(recs);
        if (_shuffleMode) {
          toAdd.shuffle();
        }
        _recommendedQueue.addAll(toAdd);
        _queue.addAll(toAdd);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[radio] prepare error: $e');
    } finally {
      _isLoadingRecommendations = false;
    }
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _queue.length ||
        newIndex < 0 ||
        newIndex >= _queue.length ||
        oldIndex == newIndex) {
      return;
    }

    final song = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, song);
    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }
    notifyListeners();
  }

  Future<void> clearQueue() async {
    if (_engineUsable) {
      await _engine.stop();
      await _justAudio?.stop();
    }
    _usesLocalPlayback = false;
    _isPlaying = false;
    _queue.clear();
    _originalQueue.clear();
    _recommendedQueue.clear();
    _manualQueue.clear();
    _currentIndex = -1;
    _isPlaylistSource = false;
    notifyListeners();
  }

  Future<void> playNext() async {
    if (_queue.isEmpty) return;

    if (_repeatMode == RepeatMode.one) {
      // Repeat One restarts the current track; it never advances the queue
      // and never triggers a recommendation lookup.
      await seek(Duration.zero);
      if (_usesLocalPlayback) {
        await _local.play();
      } else if (_engineUsable && _hasEngine) {
        await _engine.play();
      }
      return;
    }

    if (_radioQueueFuture != null) {
      try {
        await _radioQueueFuture;
      } catch (_) {}
      _radioQueueFuture = null;
    }

    final nextIndex = _currentIndex + 1;
    if (nextIndex >= _queue.length) {
      if (_repeatMode == RepeatMode.all) {
        // Repeat All wraps within the existing queue; recommendations are
        // never fetched in this mode.
        _currentIndex = 0;
        await play(_queue[_currentIndex]);
        return;
      }

      // End of the queue.
      //
      // Individual song: continue with similar songs when radio autoplay is enabled.
      // Playlist: only when the user opted in via
      // "Continue with Similar Songs After Playlist" and shuffle is off.
      final canAutoplaySimilar = _autoplay &&
          _radioAutoplay &&
          (!_isPlaylistSource || (_continueWithSimilarAfterPlaylist && !_shuffleMode));

      if (canAutoplaySimilar && !_isLoadingRecommendations && currentSong != null) {
        _isLoadingRecommendations = true;
        try {
          final seed = _originalQueue.isNotEmpty ? _originalQueue.first : currentSong!;
          final excluded = <String>{
            ..._queue.map((s) => s.id),
            ..._manualQueue.map((s) => s.id),
          };
          final recommendations = await _findSimilarSongs(
            seed: seed,
            excludedIds: excluded,
            limit: 5,
          );
          if (recommendations.isNotEmpty && _radioAutoplay) {
            // Recommendations are appended as a clearly separated tail; the
            // original playlist/queue order is left untouched.
            final toAdd = List<Song>.from(recommendations);
            if (_shuffleMode) {
              toAdd.shuffle();
            }
            _recommendedQueue.addAll(toAdd);
            _queue.addAll(toAdd);
            _currentIndex = nextIndex;
            notifyListeners();
            await play(_queue[_currentIndex]);
            return;
          }
        } catch (e) {
          debugPrint('[autoplay] recommendation fetch error: $e');
        } finally {
          _isLoadingRecommendations = false;
        }
      }

      // No recommendations available (or not allowed): fall back to the
      // existing queue behavior and stop.
      await stop();
      return;
    }

    _currentIndex = nextIndex;
    await play(_queue[_currentIndex]);
  }

  /// Looks up similar tracks for [seed]. Uses the injected resolver when
  /// present, otherwise the network-backed recommendation service.
  Future<List<Song>> _findSimilarSongs({
    required Song seed,
    required Set<String> excludedIds,
    required int limit,
  }) {
    final resolver = _similarSongsResolver;
    if (resolver != null) {
      return resolver(seed: seed, excludedIds: excludedIds, limit: limit);
    }
    return RecommendationService.findSimilarSongs(
      seed: seed,
      excludedIds: excludedIds,
      limit: limit,
    );
  }

  Future<void> playPrevious() async {
    if (_currentIndex > 0) {
      _currentIndex--;
      await play(_queue[_currentIndex]);
    }
  }

  Future<void> togglePlay() async {
    if (_usesLocalPlayback) {
      if (_local.playing) {
        await _local.pause();
      } else {
        await _local.play();
      }
      return;
    }
    if (!_engineUsable || !_hasEngine) return;
    if (_engine.state.playing) {
      await _engine.pause();
    } else {
      await _engine.play();
    }
  }

  Future<void> seek(Duration position) async {
    if (!_engineUsable) return;
    if (_usesLocalPlayback) {
      await _local.seek(position);
    } else if (_hasEngine) {
      await _engine.seek(position);
    }
  }

  Future<void> stop() async {
    if (_engineUsable) {
      await _engine.stop();
      await _justAudio?.stop();
    }
    _currentIndex = -1;
    notifyListeners();
  }

  void toggleDarkMode() {
    _isDarkMode = !_isDarkMode;
    StorageService.setDarkMode(_isDarkMode);
    notifyListeners();
  }

  void setAutoplay(bool value) {
    _autoplay = value;
    StorageService.setAutoplay(_autoplay);
    notifyListeners();
  }

  void setRadioAutoplay(bool value) {
    _radioAutoplay = value;
    StorageService.setRadioAutoplay(value);

    if (!_radioAutoplay) {
      // Disabling radio autoplay must not stop, restart, or interrupt the currently playing song.
      // Do not remove manually queued songs when the setting changes.
      // If radio autoplay is disabled, finish the existing applicable queue normally and stop when there are no more tracks.
      if (_currentIndex >= 0 && _currentIndex < _queue.length) {
        final current = _queue[_currentIndex];
        final history = _queue.sublist(0, _currentIndex);
        final upcoming = _queue.sublist(_currentIndex + 1);
        final filteredUpcoming =
            upcoming.where((s) => !s.isRecommended).toList();
        _queue = [
          ...history,
          current,
          ...filteredUpcoming,
        ];
        _recommendedQueue.clear();
      } else {
        _queue.removeWhere((s) => s.isRecommended);
        _recommendedQueue.clear();
      }
    } else {
      // Enabling radio autoplay for a standalone song:
      // If playing a standalone song and no upcoming recommendations exist, prepare the queue.
      if (!_isPlaylistSource &&
          currentSong != null &&
          _recommendedQueue.isEmpty) {
        _radioQueueFuture = prepareRadioQueue(
          seed: _originalQueue.isNotEmpty ? _originalQueue.first : currentSong!,
        );
      }
    }
    notifyListeners();
  }

  void setContinueWithSimilarAfterPlaylist(bool value) {
    _continueWithSimilarAfterPlaylist = value;
    StorageService.setContinueWithSimilarAfterPlaylist(value);
    notifyListeners();
  }

  void setAudioQuality(String quality) {
    _audioQuality = quality;
    StorageService.setAudioQuality(quality);
    notifyListeners();
  }

  void toggleShuffle() {
    _shuffleMode = !_shuffleMode;
    if (_queue.isEmpty || _currentIndex < 0 || _currentIndex >= _queue.length) {
      notifyListeners();
      return;
    }

    final current = _queue[_currentIndex];
    final history = _queue.sublist(0, _currentIndex);

    if (_shuffleMode) {
      // Shuffle ON:
      // Keep current song at _currentIndex, preserve already-played history before it.
      // Randomize only the remaining eligible upcoming tracks.
      if (_originalQueue.length > 1) {
        final playedIds = {
          ...history.map((s) => s.id),
          current.id,
        };
        final remainingOriginal = _originalQueue
            .where((s) => !playedIds.contains(s.id))
            .toList();
        remainingOriginal.shuffle();

        final upcomingManual = _manualQueue
            .where((s) => !playedIds.contains(s.id))
            .toList();
        final upcomingRecommended = _recommendedQueue
            .where((s) => !playedIds.contains(s.id))
            .toList();

        _queue = [
          ...history,
          current,
          ...remainingOriginal,
          ...upcomingManual,
          ...upcomingRecommended,
        ];
      } else {
        // Standalone song: reorder only upcoming tracks without inventing anything
        final upcoming = _queue.sublist(_currentIndex + 1);
        if (upcoming.isNotEmpty) {
          final shuffled = List<Song>.from(upcoming)..shuffle();
          _queue = [
            ...history,
            current,
            ...shuffled,
          ];
        }
      }
    } else {
      // Shuffle OFF: restore original order of unplayed tracks
      if (_originalQueue.length > 1) {
        final playedIds = {
          ...history.map((s) => s.id),
          current.id,
        };
        final remainingOriginal = _originalQueue
            .where((s) => !playedIds.contains(s.id))
            .toList();

        final upcomingManual = _manualQueue
            .where((s) => !playedIds.contains(s.id))
            .toList();
        final upcomingRecommended = _recommendedQueue
            .where((s) => !playedIds.contains(s.id))
            .toList();

        _queue = [
          ...history,
          current,
          ...remainingOriginal,
          ...upcomingManual,
          ...upcomingRecommended,
        ];
      } else {
        // Standalone song: restore manual and recommended in original order
        final playedIds = {
          ...history.map((s) => s.id),
          current.id,
        };
        final upcomingManual = _manualQueue
            .where((s) => !playedIds.contains(s.id))
            .toList();
        final upcomingRecommended = _recommendedQueue
            .where((s) => !playedIds.contains(s.id))
            .toList();

        _queue = [
          ...history,
          current,
          ...upcomingManual,
          ...upcomingRecommended,
        ];
      }
    }

    _currentIndex = history.length;
    notifyListeners();
  }

  void cycleRepeat() {
    switch (_repeatMode) {
      case RepeatMode.off:
        _repeatMode = RepeatMode.all;
        break;
      case RepeatMode.all:
        _repeatMode = RepeatMode.one;
        break;
      case RepeatMode.one:
        _repeatMode = RepeatMode.off;
        break;
    }
    notifyListeners();
  }

  bool isFavorite(String songId) => StorageService.isFavorite(songId);

  void toggleFavorite(Song song) {
    if (isFavorite(song.id)) {
      StorageService.removeFavorite(song.id);
    } else {
      StorageService.addFavorite(song);
    }
    notifyListeners();
  }

  /// Attempts to play local encrypted (.ct) or legacy file
  Future<bool> _tryPlayLocal(Song song) async {
    if (kIsWeb) return false;
    try {
      if (song.localPath != null) {
        final importedFile = File(song.localPath!);
        if (!await importedFile.exists()) return false;

        _mkLogTail.clear();
        _usesLocalPlayback = false;
        if (_engineUsable) {
          await _engine.open(Media(importedFile.path), play: true);
        }
        StorageService.addRecentPlay(song);
        StorageService.incrementPlayCount(song.id);
        notifyListeners();
        return true;
      }

      final dir = await getApplicationDocumentsDirectory();
      final encryptedFile = File('${dir.path}/${song.id}.ct');
      if (await encryptedFile.exists()) {
        final length = await encryptedFile.length();
        _usesLocalPlayback = true;
        await _local.setAudioSource(EncryptedAudioSource(encryptedFile, length));
        await _local.play();
        StorageService.addRecentPlay(song);
        StorageService.incrementPlayCount(song.id);
        notifyListeners();
        return true;
      }

      final legacyFile = File('${dir.path}/${song.id}.mp3');
      if (await legacyFile.exists()) {
        _usesLocalPlayback = false;
        if (_engineUsable) {
          await _engine.open(Media(legacyFile.path), play: true);
        }
        StorageService.addRecentPlay(song);
        StorageService.incrementPlayCount(song.id);
        notifyListeners();
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('[_tryPlayLocal] failed for ${song.id}: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _positionController.close();
    _durationController.close();
    // Only dispose an engine that was actually created; never construct one
    // just to tear it down.
    _injectedPlayer?.dispose();
    _lazyPlayer?.dispose();
    _justAudio?.dispose();
    super.dispose();
  }
}

// In-memory streaming audio source that decrypts .ct files on-the-fly.
// Decryption happens strictly in RAM; no unencrypted file is ever written to disk.
// ignore: experimental_member_use
class EncryptedAudioSource extends StreamAudioSource {
  final File file;
  final int fileSize;

  EncryptedAudioSource(this.file, this.fileSize);

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= fileSize;
    final stream = _decryptStream(file.openRead(start, end), start);
    // ignore: experimental_member_use
    return StreamAudioResponse(
      sourceLength: fileSize,
      contentLength: end - start,
      offset: start,
      stream: stream,
      contentType: 'audio/mpeg',
    );
  }

  Stream<List<int>> _decryptStream(Stream<List<int>> source, int startOffset) async* {
    var offset = startOffset;
    await for (final chunk in source) {
      yield CipherService.transformChunk(chunk, offset);
      offset += chunk.length;
    }
  }
}
