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
import '../utils/snackbar.dart';

enum RepeatMode { off, all, one }

class PlayerService extends ChangeNotifier {
  /// media_kit (libmpv) engine: all network streaming and legacy .mp3 files.
  /// Its own HTTP stack (libcurl) bypasses ExoPlayer, which fails to load
  /// googlevideo streams on the target device.
  final Player _mk = Player(
      configuration:
          const PlayerConfiguration(logLevel: MPVLogLevel.info));

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
  String _audioQuality = '320kbps';
  bool _isPlaying = false;
  bool _shuffleMode = false;
  RepeatMode _repeatMode = RepeatMode.off;
  final StreamResolver _resolver;

  List<Song> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  bool get isDarkMode => _isDarkMode;
  bool get autoplay => _autoplay;
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
  Duration get position =>
      _usesLocalPlayback ? _local.position : _mk.state.position;
  Duration get duration =>
      (_usesLocalPlayback ? _local.duration : _mk.state.duration) ??
      Duration.zero;
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

  PlayerService({StreamResolver? resolver})
      : _resolver = resolver ?? StreamResolver() {
    _loadSettings();
    _mk.stream.position.listen(_positionController.add);
    _mk.stream.duration.listen(_durationController.add);
    _mk.stream.playing.listen((p) {
      _isPlaying = p;
      notifyListeners();
    });
    _mk.stream.completed.listen((c) {
      if (c && _autoplay) {
        playNext();
      }
    });
    // media_kit reports load failures on this stream rather than throwing
    // from open(); surface them with the same popup contract as thrown errors,
    // appended with mpv's last log lines so the on-device popup carries the
    // real cause (e.g. "HTTP error 403", curl failures).
    _mk.stream.error.listen((msg) {
      debugPrint('[mk] error: $msg');
      // media_kit's message embeds the entire stream URL (hundreds of chars);
      // the real cause is an earlier error-level log line. Abbreviate the
      // message, then prefer error-level lines (URLs already stripped on
      // capture) so the actual cause always fits in the popup.
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
    _mk.stream.log.listen((l) {
      debugPrint('[mk] ${l.text}');
      // Strip URLs: mpv's failure wrapper embeds the full stream URL and
      // would swallow the whole popup window on its own.
      final text = l.text.replaceAll(RegExp(r'https?://\S+'), '<url>');
      // mpv reports level as either a single letter or a full word.
      final lvl = l.level.trim().toLowerCase();
      final isErr = lvl.startsWith('e') || lvl.startsWith('f');
      _mkLogTail.add('${isErr ? 'E|' : '-|'}${l.prefix}: $text');
      if (_mkLogTail.length > 12) _mkLogTail.removeAt(0);
    });
  }

  Future<void> _loadSettings() async {
    _isDarkMode = StorageService.getDarkMode();
    _autoplay = StorageService.getAutoplay();
    _audioQuality = StorageService.getAudioQuality();
    notifyListeners();
  }

  Future<void> play(Song song) async {
    final index = _queue.indexWhere((s) => s.id == song.id);
    if (index == -1) {
      _queue.add(song);
      _currentIndex = _queue.length - 1;
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

      await _mk.stop();
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

    // Stream on-device; web: resolver stub returns null -> web playback disabled until IFrame phase
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
      await _mk.open(Media(audioUrl), play: true);
      StorageService.addRecentPlay(song);
      StorageService.incrementPlayCount(song.id);
      notifyListeners();
    } catch (e) {
      debugPrint('[play] playback error for ${song.id}: $e');
      showGlobalSnack('Playback error: $e');
      // Stream failed - try local file as fallback (mobile only)
      if (!kIsWeb) {
        await _tryPlayLocal(song);
      }
    }
  }

  Future<void> playList(List<Song> songs, {int startIndex = 0}) async {
    _queue = List.from(songs);
    _currentIndex = startIndex;
    if (_queue.isNotEmpty) {
      await play(_queue[_currentIndex]);
    }
  }

  bool addToQueue(Song song) {
    if (_queue.any((queuedSong) => queuedSong.id == song.id)) return false;
    _queue.add(song);
    notifyListeners();
    return true;
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
    await _mk.stop();
    await _justAudio?.stop();
    _usesLocalPlayback = false;
    _isPlaying = false;
    _queue.clear();
    _currentIndex = -1;
    notifyListeners();
  }

  Future<void> playNext() async {
    if (_queue.isEmpty) return;

    if (_repeatMode == RepeatMode.one) {
      await seek(Duration.zero);
      if (_usesLocalPlayback) {
        await _local.play();
      } else {
        await _mk.play();
      }
      return;
    }

    _currentIndex++;
    if (_currentIndex >= _queue.length) {
      if (_repeatMode == RepeatMode.all) {
        _currentIndex = 0;
      } else {
        await stop();
        return;
      }
    }

    await play(_queue[_currentIndex]);
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
    } else {
      if (_mk.state.playing) {
        await _mk.pause();
      } else {
        await _mk.play();
      }
    }
  }

  Future<void> seek(Duration position) async {
    if (_usesLocalPlayback) {
      await _local.seek(position);
    } else {
      await _mk.seek(position);
    }
  }

  Future<void> stop() async {
    await _mk.stop();
    await _justAudio?.stop();
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

  void setAudioQuality(String quality) {
    _audioQuality = quality;
    StorageService.setAudioQuality(quality);
    notifyListeners();
  }

  void toggleShuffle() {
    _shuffleMode = !_shuffleMode;
    if (_shuffleMode) {
      _queue.shuffle();
    }
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
        await _mk.open(Media(importedFile.path), play: true);
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
        await _mk.open(Media(legacyFile.path), play: true);
        StorageService.addRecentPlay(song);
        StorageService.incrementPlayCount(song.id);
        notifyListeners();
        return true;
      }
    } catch (e) {
      // Local playback error, fallback to streaming
    }
    return false;
  }

  /// Check if a song has a local file (downloaded)
  Future<bool> hasLocalFile(String songId) async {
    if (kIsWeb) return false;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final encFile = File('${dir.path}/$songId.ct');
      if (await encFile.exists()) return true;
      final mp3File = File('${dir.path}/$songId.mp3');
      return await mp3File.exists();
    } catch (e) {
      return false;
    }
  }

  /// Get local file path for a downloaded song
  Future<String?> getLocalPath(String songId) async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final encFile = File('${dir.path}/$songId.ct');
      if (await encFile.exists()) return encFile.path;
      final mp3File = File('${dir.path}/$songId.mp3');
      if (await mp3File.exists()) return mp3File.path;
    } catch (e) {
      // Ignore errors
    }
    return null;
  }

  @override
  void dispose() {
    _mk.dispose();
    _justAudio?.dispose();
    _positionController.close();
    _durationController.close();
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
