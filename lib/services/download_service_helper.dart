import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/song.dart';

typedef ProgressCallback = void Function(double progress);

Future<void> downloadFile(String url, Song song,
    {ProgressCallback? onProgress, dynamic cancelToken}) async {
  final dir = await getApplicationDocumentsDirectory();
  final filePath = '${dir.path}/${song.id}.mp3';
  final file = File(filePath);

  final request = await HttpClient().getUrl(Uri.parse(url));
  final response = await request.close();
  final totalBytes = response.contentLength;

  if (totalBytes > 0 && onProgress != null) {
    int receivedBytes = 0;
    final sink = file.openWrite();

    await for (final chunk in response) {
      sink.add(chunk);
      receivedBytes += chunk.length;
      onProgress(receivedBytes / totalBytes);
    }

    await sink.close();
  } else {
    final sink = file.openWrite();
    await response.pipe(sink);
    if (onProgress != null) {
      onProgress(1.0);
    }
  }
}

Future<void> deleteFile(String songId) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$songId.mp3');
    if (await file.exists()) {
      await file.delete();
    }
  } catch (e) {
    // Ignore deletion errors
  }
}

Future<String> saveToDeviceFile(Song song) async {
  try {
    final dir = await getDownloadsDirectory();
    if (dir == null) throw Exception('Downloads directory not found');
    await dir.create(recursive: true);
    final sanitizedTitle = song.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

    if (song.localPath != null) {
      final source = File(song.localPath!);
      if (!await source.exists()) throw Exception('Local audio file not found');
      final name = source.uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      final extension = dot < 0 ? '.audio' : name.substring(dot).toLowerCase();
      var targetPath = '${dir.path}/$sanitizedTitle$extension';
      var suffix = 2;
      while (await File(targetPath).exists()) {
        targetPath = '${dir.path}/$sanitizedTitle ($suffix)$extension';
        suffix++;
      }
      return (await source.copy(targetPath)).path;
    }

    final targetPath = '${dir.path}/$sanitizedTitle.mp3';
    final sourceFile = File('${(await getApplicationDocumentsDirectory()).path}/${song.id}.mp3');
    if (await sourceFile.exists()) {
      await sourceFile.copy(targetPath);
      return targetPath;
    }
    throw Exception('Downloaded file not found');
  } catch (e) {
    throw Exception('Failed to save: $e');
  }
}
