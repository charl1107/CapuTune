import '../models/song.dart';

typedef ProgressCallback = void Function(double progress);

Future<void> downloadFile(String url, Song song,
    {ProgressCallback? onProgress,
    dynamic cancelToken,
    Duration? chunkIdleTimeout,
    // Signature parity with download_service_mobile.dart.
    Duration? receiveTimeout}) async {
  throw Exception('Downloads are not supported on web yet');
}

Future<String> saveToDeviceFile(Song song) async {
  throw Exception('Save to device not supported on web');
}

Future<void> deleteFile(String songId) async {
  // Nothing is stored locally on web
}

/// No-op on web: nothing is ever staged on disk there.
Future<int> cleanupStaleTmp({
  dynamic directory,
  Set<String>? activeIds,
  Duration? maxAge,
}) async => 0;
