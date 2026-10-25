import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../services/storage_service.dart';
import 'download_service_helper.dart'
    if (dart.library.html) 'download_service_web.dart'
    if (dart.library.io) 'download_service_mobile.dart';
import 'stream_resolver.dart';

enum DownloadState { idle, downloading, downloaded }

class DownloadService extends ChangeNotifier {
  final Map<String, DownloadState> _states = {};
  final Map<String, double> _progress = {};
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, Song> _activeSongs = {};
  final StreamResolver _resolver = StreamResolver();
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

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

    _states[song.id] = DownloadState.downloading;
    _progress[song.id] = 0.0;
    _errorMessage = null;
    _activeSongs[song.id] = song;
    notifyListeners();

    final cancelToken = CancelToken();
    _cancelTokens[song.id] = cancelToken;

    try {
      // Resolve a direct audio URL on-device; web downloads are unsupported
      String audioUrl;
      if (kIsWeb) {
        _errorMessage = 'Downloads are not supported on web yet';
        _states[song.id] = DownloadState.idle;
        _progress[song.id] = 0.0;
        return;
      } else {
        final url = await _resolver.resolve(song.id);
        if (url == null) {
          _errorMessage = 'Failed to get audio URL';
          _states[song.id] = DownloadState.idle;
          _progress[song.id] = 0.0;
          return;
        }
        audioUrl = url;
      }

      await downloadFile(audioUrl, song, onProgress: (p) {
        _progress[song.id] = p;
        notifyListeners();
      }, cancelToken: cancelToken);

      _states[song.id] = DownloadState.downloaded;
      _progress[song.id] = 1.0;
      await StorageService.addDownload(song);
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
