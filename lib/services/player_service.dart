import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';
import 'stream_resolver.dart';
import 'storage_service.dart';
import 'local_decrypt_server.dart';
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

  /// Loopback server that streams decrypted audio from `.ct` files to the
  /// media_kit engine. Replaces the old just_audio path, which was ExoPlayer
  /// under the hood and failed to load sources on the target device — the very
  /// reason every other playback path already migrated to media_kit.
  final LocalDecryptServer _decryptServer = LocalDecryptServer();

  /// True while the engine is serving a decrypted `.ct` source, so the
  /// stream-error retry below never re-opens the same local file in a loop.
  bool _isLocalSource = false;

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
  double _rate = 1.0;
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
  double get rate => _rate;
  bool get isPlaying => _isPlaying;
  bool get shuffleMode => _shuffleMode;
  RepeatMode get repeatMode => _repeatMode;
  Song? get currentSong =>
      _currentIndex >= 0 && _currentIndex < _queue.length
          ? _queue[_currentIndex]
          : null;

  Duration get position {
    if (!_engineUsable || !_hasEngine) return Duration.zero;
    return _engine.state.position;
  }

  Duration get duration {
    if (!_engineUsable || !_hasEngine) return Duration.zero;
    return _engine.state.duration;
  }
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration?> get durationStream => _durationController.stream;

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
      final song = currentSong;

      // CDN/network failures on a streamed song are recoverable: re-resolve
      // the song, which fetches a fresh stream URL — typically from a
      // different edge node — instead of leaving a dead track.
      if (song != null &&
          song.localPath == null &&
          !_isLocalSource &&
          isNetworkStreamError(msg)) {
        _scheduleStreamRetry(song);
        return;
      }

      // Everything else keeps the full diagnostics: these are the errors
      // where the mpv log tail is the only real clue.
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
      if (song != null && song.localPath == null && !_isLocalSource) {
        _tryPlayLocal(song);
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
    _rate = StorageService.getSetting<double>(1.0, key: 'playbackRate');
    notifyListeners();
  }

  Future<void> play(Song song) async {
    // A new manual song supersedes any in-flight stream retry of the old one.
    _cancelStreamRetry(resetCounters: true);
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
      _isLocalSource = false;
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
      final audioUrl = await _resolver.resolve(song.id, quality: _audioQuality);
      if (audioUrl == null) {
        debugPrint('[play] resolve returned null for ${song.id}');
        // Distinguish offline from a genuine extraction failure with the
        // same baseline probe the retry give-up uses; never tell an offline
        // user that "YouTube gave no audio".
        unawaited(_explainResolutionFailure(song.id));
        return;
      }
      debugPrint('[play] resolve OK for ${song.id}, loading into media_kit');
      _mkLogTail.clear();
      _isLocalSource = false;
      if (_engineUsable) {
        _lastStreamUrl = audioUrl;
        await _engine.open(Media(audioUrl), play: true);
        await _applyRateToEngine();
        // A clean open means the retry bookkeeping starts fresh.
        _streamRetryCount = 0;
        _streamRetrySongId = null;
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
    }
    _isLocalSource = false;
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
      if (_engineUsable && _hasEngine) {
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
    if (!_engineUsable || !_hasEngine) return;
    if (_engine.state.playing) {
      await _engine.pause();
    } else {
      await _engine.play();
    }
  }

  Future<void> seek(Duration position) async {
    if (!_engineUsable) return;
    if (_hasEngine) {
      await _engine.seek(position);
    }
  }

  /// Applies [rate] (0.5–2.0) to the engine and persists it, so songs opened
  /// later resume at the same speed. In test environments without an engine
  /// the value is still stored so the UI reflects the choice.
  Future<void> setRate(double rate) async {
    final clamped = rate.clamp(0.5, 2.0);
    _rate = clamped;
    StorageService.setSetting(clamped, key: 'playbackRate');
    if (_engineUsable && _hasEngine) {
      await _engine.setRate(clamped);
    }
    notifyListeners();
  }

  /// Re-applies the persisted rate after a new engine source is opened;
  /// media_kit resets the rate to 1.0 on `open`.
  Future<void> _applyRateToEngine() async {
    if (_engineUsable && _hasEngine && _rate != 1.0) {
      await _engine.setRate(_rate);
    }
  }

  // --- Stream self-heal -------------------------------------------------
  //
  // YouTube stream URLs point at one specific CDN edge node, assigned at
  // resolve time. When the phone can no longer reach that node mid-song
  // (node flake, WiFi↔mobile switch), mpv hits connection time-outs instead
  // of audio. A fresh extraction returns a new URL — usually routed to a
  // different node — so the failure is recoverable by resolving again.

  /// Recognizes mpv/ffmpeg errors caused by an unreachable or dead network
  /// stream. These are eligible for the re-resolve retry; anything else
  /// keeps the full diagnostics path.
  static bool isNetworkStreamError(String message) {
    final lowered = message.toLowerCase();
    const markers = [
      // ffmpeg tcp layer: 0xffffff92 is -110 (ETIMEDOUT).
      'connection timed out',
      'timed out',
      'time out',
      '0xffffff92',
      'connection refused',
      'connection reset',
      'no route to host',
      'could not resolve',
      'unreachable',
      // mpv demuxer cache cannot back its stream — the source is dead.
      'failed to create file cache',
    ];
    return markers.any(lowered.contains);
  }

  static const int _maxStreamRetries = 3;
  static const Duration _streamRetryBaseDelay = Duration(milliseconds: 1500);

  /// Backoff for stream-retry attempt [attempt] (1-based): exponential from
  /// [attempt], scaled by [jitter] (0–1) into a ±30%-ish band so simultaneous
  /// failures across devices don't re-strike in lockstep.
  @visibleForTesting
  static Duration streamRetryDelay(int attempt, double jitter) {
    final exponential = _streamRetryBaseDelay.inMilliseconds * (1 << (attempt - 1));
    final scaled = exponential * (0.7 + 0.6 * jitter.clamp(0.0, 1.0));
    return Duration(milliseconds: scaled.round());
  }

  String? _streamRetrySongId;
  int _streamRetryCount = 0;
  Timer? _streamRetryTimer;
  bool _streamRetryPending = false;

  /// The stream URL most recently opened with the engine. In-memory only
  /// (never logged — it is a signed URL); used by the give-up diagnosis to
  /// ask whether this network can still reach that host at all.
  String? _lastStreamUrl;

  static final Random _jitterRandom = Random();

  /// Random jitter (0–1) for the retry backoff, so a fleet of devices that
  /// fail together don't retry in lockstep.
  double _jitter() => _jitterRandom.nextDouble();

  void _cancelStreamRetry({bool resetCounters = false}) {
    _streamRetryTimer?.cancel();
    _streamRetryTimer = null;
    _streamRetryPending = false;
    if (resetCounters) {
      _streamRetryCount = 0;
      _streamRetrySongId = null;
    }
  }

  void _scheduleStreamRetry(Song song) {
    // First failure of this song resets the steady-state counters.
    if (_streamRetrySongId != song.id) {
      _streamRetrySongId = song.id;
      _streamRetryCount = 0;
    }
    // A retry is already ticking down or re-opening the stream.
    if (_streamRetryPending) return;

    if (_streamRetryCount >= _maxStreamRetries) {
      _cancelStreamRetry();
      showGlobalSnack(
        'Playback failed after $_maxStreamRetries retries. '
        'Checking why this network can’t reach YouTube…',
      );
      _tryPlayLocal(song);
      // Diagnosis runs after the fallback so the refind message lands last.
      unawaited(_diagnoseUnreachableNetwork(song.id));
      return;
    }

    _streamRetryCount++;
    _streamRetryPending = true;
    final attempt = _streamRetryCount;
    showGlobalSnack(
      'Lost connection to the song’s server — retrying '
      '($attempt/$_maxStreamRetries)…',
    );
    _streamRetryTimer = Timer(
      streamRetryDelay(attempt, _jitter()),
      () => _retryStream(song),
    );
  }

  /// Re-resolves and reopens [song] at the position the listener left off.
  Future<void> _retryStream(Song song) async {
    _streamRetryTimer = null;
    try {
      if (_streamRetryCount == 0 || currentSong?.id != song.id) {
        return;
      }
      final resumePosition = _engine.state.position;
      final url = await _resolver.resolve(song.id, quality: _audioQuality);
      if (url == null || currentSong?.id != song.id) {
        if (currentSong?.id == song.id) {
          showGlobalSnack(
            'Playback failed: couldn’t reach YouTube to refresh this song. '
            'Checking this network…',
          );
          // No engine open happened, so the fallback is the only option;
          // the diagnosis still tells the user who is unreachable.
          unawaited(_diagnoseUnreachableNetwork(song.id));
        }
        _streamRetryCount = 0;
        _streamRetrySongId = null;
        await _tryPlayLocal(song);
        return;
      }
      _mkLogTail.clear();
      _lastStreamUrl = url;
      await _engine.open(Media(url), play: true);
      if (resumePosition > Duration.zero) {
        await _engine.seek(resumePosition);
      }
      await _applyRateToEngine();
    } catch (e) {
      debugPrint('[play] stream retry failed: $e');
      // The next engine error event re-enters _scheduleStreamRetry, which
      // keeps the attempt counter honest and eventually gives up cleanly.
    } finally {
      _streamRetryPending = false;
    }
  }

  // --- Resolution failure explanation -------------------------------------
  //
  // A null from resolve() has two very different causes: no usable network
  // (nothing to explain about the song) or a genuine extraction problem.
  // The old one-size message claimed "YouTube gave no audio" even when the
  // device was offline — now the baseline probe picks the right story.

  /// User-facing message for a failed stream resolution.
  /// [networkReachable] is the baseline connectivity result. Kept pure so
  /// tests can pin both branches without any networking.
  @visibleForTesting
  static String resolutionFailureMessage({required bool networkReachable}) {
    if (!networkReachable) {
      return 'No usable internet on this network. Streaming is unavailable — '
          'downloaded songs still play.';
    }
    return 'Stream extraction failed - YouTube gave no audio for this song';
  }

  /// Explains a resolve-null result: one baseline connectivity probe, then
  /// the accurate message. Fire-and-forget; never blocks playback UI.
  Future<void> _explainResolutionFailure(String songId) async {
    final networkReachable = await _probeReachable(_connectivityCheckUrl);
    debugPrint(
        '[play] resolve failed for $songId: baseline=$networkReachable');
    showGlobalSnack(
      resolutionFailureMessage(networkReachable: networkReachable),
    );
  }

  // --- Differential network diagnosis -------------------------------------
  //
  // All re-resolve retries exhausted: figure out *who* is unreachable and
  // report it honestly. If the Wi-Fi router or ISP can't reach Google's
  // media servers, that is a network-path problem no app code can fix — the
  // user needs to switch to mobile data or another network, and deserves to
  // be told so in plain language.

  /// Neutral endpoint: completing an HTTP exchange with Google's
  /// connectivity checker proves the network itself works.
  static const String _connectivityCheckUrl =
      'https://www.google.com/generate_204';

  Future<void> _diagnoseUnreachableNetwork(String songId) async {
    final baselineOk = await _probeReachable(_connectivityCheckUrl);
    final streamUrl = _lastStreamUrl;
    final streamOk = streamUrl != null && await _probeReachable(streamUrl);
    debugPrint(
      '[diagnose] song $songId: baseline=$baselineOk streamHost=$streamOk',
    );

    if (!baselineOk) {
      showGlobalSnack(
        'Diagnosis: no usable internet on this network. Playback needs a '
        'working connection — try mobile data.',
      );
      return;
    }
    if (!streamOk) {
      // Internet works, Google's media CDN does not — router firewall,
      // ISP filtering, or DNS pointing at an unreachable edge node.
      showGlobalSnack(
        'Diagnosis: this network reaches the internet, but not YouTube’s '
        'media servers. Your Wi-Fi router or internet provider may be '
        'blocking them — try mobile data or another network.',
      );
      return;
    }
    // Both passed, yet mpv kept failing: small probes succeed while the
    // sustained connection doesn't — the hallmark of throttled or unstable
    // Wi-Fi rather than an outright block.
    showGlobalSnack(
      'Diagnosis: the song’s server answers a quick test, but streaming '
      'still failed. This network may be too unstable for streaming — '
      'try mobile data or another Wi-Fi.',
    );
  }

  /// One-shot reachability check for [url]: true when any HTTP response
  /// arrives within the timeouts — status code irrelevant, since the
  /// question is whether the TCP/TLS/HTTP path works at all. Logs the host
  /// and the Dart-level failure type only; the URL is signed, so it never
  /// goes to a log line.
  static Future<bool> _probeReachable(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    final host = Uri.tryParse(url)?.host ?? '(unparsable url)';
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close().timeout(const Duration(seconds: 10));
      debugPrint('[diagnose] $host answered HTTP ${resp.statusCode}');
      return true;
    } catch (e) {
      debugPrint('[diagnose] $host unreachable: ${e.runtimeType}');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Timer? _sleepTimer;

  /// When the sleep timer fires, or null when none is set.
  DateTime? get sleepTimerEndsAt => _sleepTimerEndsAt;
  DateTime? _sleepTimerEndsAt;

  /// Starts (or replaces) a timer that pauses playback after [duration].
  ///
  /// Pause — not stop — so the queue survives and playback resumes where the
  /// listener left off when they press play in the morning.
  void setSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _sleepTimer = Timer(duration, _onSleepTimerFired);
    _sleepTimerEndsAt = DateTime.now().add(duration);
    notifyListeners();
  }

  /// Cancels any pending sleep timer. No-op when none is running.
  void cancelSleepTimer() {
    if (_sleepTimer == null && _sleepTimerEndsAt == null) return;
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerEndsAt = null;
    notifyListeners();
  }

  void _onSleepTimerFired() {
    _sleepTimer = null;
    _sleepTimerEndsAt = null;
    // Engine-guarded pause: mirrors togglePlay without flipping its state.
    if (_engineUsable && _hasEngine && _engine.state.playing) {
      _engine.pause();
    }
    notifyListeners();
  }

  Future<void> stop() async {
    if (_engineUsable) {
      await _engine.stop();
    }
    _cancelStreamRetry(resetCounters: true);
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
        _isLocalSource = false;
        if (_engineUsable) {
          await _engine.open(Media(importedFile.path), play: true);
          await _applyRateToEngine();
        }
        StorageService.addRecentPlay(song);
        StorageService.incrementPlayCount(song.id);
        notifyListeners();
        return true;
      }

      final dir = await getApplicationDocumentsDirectory();
      final encryptedFile = File('${dir.path}/${song.id}.ct');
      if (await encryptedFile.exists()) {
        // Serve the decrypted audio from a loopback-only HTTP endpoint so the
        // same media_kit engine that plays streams also plays downloads. The
        // old just_audio path was ExoPlayer under the hood, which is exactly
        // what this engine replaced after failing on the target device.
        _mkLogTail.clear();
        final uri = await _decryptServer.register(song.id, encryptedFile);
        _isLocalSource = true;
        if (_engineUsable) {
          await _engine.open(Media(uri.toString()), play: true);
          await _applyRateToEngine();
        }
        StorageService.addRecentPlay(song);
        StorageService.incrementPlayCount(song.id);
        notifyListeners();
        return true;
      }

      final legacyFile = File('${dir.path}/${song.id}.mp3');
      if (await legacyFile.exists()) {
        _isLocalSource = false;
        if (_engineUsable) {
          await _engine.open(Media(legacyFile.path), play: true);
          await _applyRateToEngine();
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
    unawaited(_decryptServer.dispose());
    super.dispose();
  }
}

