import '../models/song.dart';

typedef ProgressCallback = void Function(double progress);

Future<void> downloadFile(String url, Song song,
    {ProgressCallback? onProgress, dynamic cancelToken}) async {
  throw Exception('Downloads are not supported on web yet');
}

Future<String> saveToDeviceFile(Song song) async {
  throw Exception('Save to device not supported on web');
}

Future<void> deleteFile(String songId) async {
  // Nothing is stored locally on web
}
