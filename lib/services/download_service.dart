import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../services/storage_service.dart';
import 'download_service_helper.dart'
    if (dart.library.html) 'download_service_web.dart'
    if (dart.library.io) 'download_service_mobile.dart';
import 'stream_resolver.dart';
import 'network_exception_stub.dart'
    if (dart.library.io) 'network_exception_vm.dart';

enum DownloadState { idle, downloading, downloaded }

class DownloadService extends ChangeNotifier {
  DownloadService({StreamResolver? resolver})
      : _resolver = resolver ?? StreamResolver();

  final Map<String, DownloadState> _states = {};
  final Map<String, double> _progress = {};
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, Song> _activeSongs = {};
  final StreamResolver _resolver;
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Deletes stale `*.ct.tmp` download-staging files. Called once at
  /// startup; active downloads (this instance's [_activeSongs]) are the
  /// safe-guard against touching files currently being written.
  Future<int> cleanupStaleTempFiles() =>
      cleanupStaleTmp(activeIds: _activeSongs.keys.toSet());

  // --- Bounded network retry ---------------------------------------------
  //
  // Downloads historically had no network handling: a dead connection hung
  // forever. They now fail fast into a strictly bounded retry that must
  // re-resolve a fresh stream URL per attempt (never reuse a failed
  // attempt's URL).

  /// Total resolve+download attempts: one attempt plus one fresh retry.
  @visibleForTesting
  static const int maxDownloadAttempts = 2;

  /// Flat-with-mild-growth delay between download attempts. Deliberately
  /// small: downloads are user-invoked and blocking for that song.
  @visibleForTesting
  static const Duration downloadRetryBaseDelay = Duration(milliseconds: 700);

  /// True for transient transport errors worth a fresh attempt: connection
  /// establishment failures, connection loss, and receive stalls.
  /// Cancellation, TLS errors, and HTTP responses (including 4xx/5xx from
  /// the CDN) are deterministic outcomes and are NOT retried.
  @visibleForTesting
  static bool isTransientDownloadError(Object? e) {
    if (e == null) return false;
    if (e is TimeoutException || e is NetworkSocketException) return true;
    if (e is DioException) {
      return switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.transformTimeout ||
        DioExceptionType.connectionError => true,
        DioExceptionType.unknown =>
          e.error is NetworkSocketException || e.error is TimeoutException,
        DioExceptionType.cancel ||
        DioExceptionType.badCertificate ||
        DioExceptionType.badResponse => false,
      };
    }
    return e is NetworkSocketException;
  }

  /// Whether attempt number [attempt] (1-based, the attempt that just
  /// failed) may retry after [error]. Bounded by [maxDownloadAttempts];
  /// a cancelled download never retries.
  @visibleForTesting
  static bool shouldRetryDownloadAttempt({
    required int attempt,
    required Object? error,
    required bool cancelled,
  }) =>
      !cancelled &&
      attempt < maxDownloadAttempts &&
      isTransientDownloadError(error);

  /// Test hook: shrinks the download chunk-idle timeout for one run so the
  /// stall test doesn't wait the production 45 s. Null in production.
  @visibleForTesting
  static Duration? chunkIdleTimeoutOverride;

  /// Test hook: shrinks the header-wait receive timeout for one run so the
  /// never-sends-headers test doesn't wait the production 45 s. Null in
  /// production.
  @visibleForTesting
  static Duration? receiveTimeoutOverride;

  DownloadState getState(String songId) =>
      _states[songId] ??
      (StorageService.isDownloaded(songId)
          ? DownloadState.downloaded
          : DownloadState.idle);

  double getProgress(String songId) => _progress[songId] ?? 0.0;

  bool isDownloading(String songId) =>
      _states[songId] == DownloadState.downloading;

  List<Song> get activeSongs => List.unmodifiable(_activeSongs.values);

  Future<void> downloadSong(Song song) async {
    if (getState(song.id) == DownloadState.downloading) return;

    final cancelToken = CancelToken();
    _cancelTokens[song.id] = cancelToken;
    _states[song.id] = DownloadState.downloading;
    _progress[song.id] = 0.0;
    _errorMessage = null;
    _activeSongs[song.id] = song;
    notifyListeners();

    try {
      // One attempt plus at most one bounded retry, each on a freshly
      // resolved URL (re-resolving gets a new CDN edge node, exactly the
      // mechanism that heals streaming retries).
      for (var attempt = 1; attempt <= maxDownloadAttempts; attempt++) {
        if (kIsWeb) {
          _errorMessage = 'Downloads are not supported on web yet';
          _states[song.id] = DownloadState.idle;
          _progress[song.id] = 0.0;
          return;
        }
        final url = await _resolver.resolve(
          song.id,
          quality: StorageService.getAudioQuality(),
        );
        if (url == null) {
          _errorMessage = 'Failed to get audio URL';
          _states[song.id] = DownloadState.idle;
          _progress[song.id] = 0.0;
          return;
        }

        try {
          await downloadFile(
            url,
            song,
            onProgress: (p) {
              _progress[song.id] = p;
              notifyListeners();
            },
            cancelToken: cancelToken,
            chunkIdleTimeout: chunkIdleTimeoutOverride,
            receiveTimeout: receiveTimeoutOverride,
          );

          _states[song.id] = DownloadState.downloaded;
          _progress[song.id] = 1.0;
          await StorageService.addDownload(song);
          return;
        } catch (e) {
          // Cancellation is terminal for this download: report and stop.
          if (e is DioException && e.type == DioExceptionType.cancel) {
            _errorMessage = 'Download cancelled';
            _states[song.id] = DownloadState.idle;
            _progress[song.id] = 0.0;
            return;
          }
          debugPrint('[download] attempt $attempt failed: ${e.runtimeType}');

          // A cancel may land at the same moment as a transport error;
          // cancellation always wins over a retry.
          if (cancelToken.isCancelled) {
            _errorMessage = 'Download cancelled';
            _states[song.id] = DownloadState.idle;
            _progress[song.id] = 0.0;
            return;
          }

          if (!shouldRetryDownloadAttempt(
            attempt: attempt,
            error: e,
            cancelled: cancelToken.isCancelled,
          )) {
            _errorMessage = 'Download failed: ${e.toString()}';
            _states[song.id] = DownloadState.idle;
            _progress[song.id] = 0.0;
            return;
          }

          _errorMessage = 'Download failed: ${e.toString()}. Retrying…';
          await Future<void>.delayed(downloadRetryBaseDelay * attempt);
          // Cancellation during backoff stops before the next network
          // attempt ever starts.
          if (cancelToken.isCancelled) {
            _errorMessage = 'Download cancelled';
            _states[song.id] = DownloadState.idle;
            _progress[song.id] = 0.0;
            return;
          }
          _progress[song.id] = 0.0;
        }
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        _errorMessage = 'Download cancelled';
      } else {
        _errorMessage = 'Download failed: ${e.toString()}';
      }
      _states[song.id] = DownloadState.idle;
      _progress[song.id] = 0.0;
    } catch (e) {
      _states[song.id] = DownloadState.idle;
      _progress[song.id] = 0.0;
      _errorMessage = 'Download failed: ${e.toString()}';
    } finally {
      _cancelTokens.remove(song.id);
      _activeSongs.remove(song.id);
      notifyListeners();
    }
  }

  Future<void> cancelDownload(String songId) async {
    if (_cancelTokens.containsKey(songId)) {
      _cancelTokens[songId]!.cancel('User cancelled');
      _cancelTokens.remove(songId);
    }
    _states[songId] = DownloadState.idle;
    _progress.remove(songId);
    _errorMessage = 'Download cancelled';
    notifyListeners();
  }

  Future<String?> saveToDevice(Song song) async {
    try {
      return await saveToDeviceFile(song);
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> removeDownload(String songId) async {
    await deleteFile(songId);
    await StorageService.removeDownload(songId);
    _states.remove(songId);
    _progress.remove(songId);
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
