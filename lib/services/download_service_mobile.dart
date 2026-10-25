import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';
import 'cipher_service.dart';

typedef ProgressCallback = void Function(double progress);

/// Downloads audio from [url] and stores it encrypted (.ct) inside the app's
/// private sandbox directory. When the app is uninstalled, the OS automatically
/// wipes this directory completely.
///
/// No storage permission is required: the app's private documents directory
/// is always writable without runtime permissions.
Future<void> downloadFile(String url, Song song,
    {ProgressCallback? onProgress, CancelToken? cancelToken}) async {
  final dir = await getApplicationDocumentsDirectory();
  final encryptedPath = '${dir.path}/${song.id}.ct';
  final tempFile = File('$encryptedPath.tmp');
  final sink = tempFile.openWrite();

  final dio = Dio();
  final response = await dio.get<ResponseBody>(
    url,
    options: Options(responseType: ResponseType.stream),
    cancelToken: cancelToken,
  );

  final total = response.data?.contentLength ?? -1;
  var received = 0;

  try {
    await for (final chunk in response.data!.stream) {
      if (cancelToken?.isCancelled ?? false) {
        throw DioException(
          requestOptions: RequestOptions(path: url),
          type: DioExceptionType.cancel,
        );
      }
      // Encrypt chunk with offset-based keystream before writing to disk
      final encryptedChunk = CipherService.transformChunk(chunk, received);
      sink.add(encryptedChunk);
      received += chunk.length;
      if (total > 0 && onProgress != null) {
        onProgress(received / total);
      }
    }
    await sink.flush();
    await sink.close();

    final finalFile = File(encryptedPath);
    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    await tempFile.rename(encryptedPath);
  } catch (e) {
    await sink.close();
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    rethrow;
  }
}

/// Deletes the song from the app's private sandbox storage
Future<void> deleteFile(String songId) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final encryptedFile = File('${dir.path}/$songId.ct');
    if (await encryptedFile.exists()) {
      await encryptedFile.delete();
    }
    final legacyFile = File('${dir.path}/$songId.mp3');
    if (await legacyFile.exists()) {
      await legacyFile.delete();
    }
  } catch (e) {
    // Ignore deletion errors
  }
}

/// Optional user export: Decrypts the private in-app file and exports
/// a playable .mp3 to the phone's public Downloads directory.
///
/// On Android 10+ the public Downloads directory is writable without
/// runtime permissions. On older versions the directory may not exist;
/// the fallback path handles that.
Future<String> saveToDeviceFile(Song song) async {
  try {
    Directory? dir = await getDownloadsDirectory();
    if (dir == null && Platform.isAndroid) {
      final fallback = Directory('/storage/emulated/0/Download');
      if (await fallback.exists()) dir = fallback;
    }
    if (dir == null) throw Exception('Downloads directory not found on device');
    await dir.create(recursive: true);

    final sanitizedTitle = song.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    if (song.localPath != null) {
      final sourceFile = File(song.localPath!);
      if (!await sourceFile.exists()) {
        throw Exception('Local audio file not found');
      }
      final sourceName = sourceFile.uri.pathSegments.last;
      final dot = sourceName.lastIndexOf('.');
      final rawExtension =
          dot < 0 ? '' : sourceName.substring(dot).toLowerCase();
      final extension = RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(rawExtension)
          ? rawExtension
          : '.audio';
      var targetPath = '${dir.path}/$sanitizedTitle$extension';
      var suffix = 2;
      while (await File(targetPath).exists()) {
        targetPath = '${dir.path}/$sanitizedTitle ($suffix)$extension';
        suffix++;
      }
      return (await sourceFile.copy(targetPath)).path;
    }

    final targetPath = '${dir.path}/$sanitizedTitle.mp3';
    final appDocDir = await getApplicationDocumentsDirectory();
    final encryptedFile = File('${appDocDir.path}/${song.id}.ct');
    final legacyFile = File('${appDocDir.path}/${song.id}.mp3');

    if (await encryptedFile.exists()) {
      final targetFile = File(targetPath);
      final sink = targetFile.openWrite();
      var offset = 0;
      await for (final chunk in encryptedFile.openRead()) {
        final decryptedChunk = CipherService.transformChunk(chunk, offset);
        sink.add(decryptedChunk);
        offset += chunk.length;
      }
      await sink.flush();
      await sink.close();
      return targetPath;
    } else if (await legacyFile.exists()) {
      await legacyFile.copy(targetPath);
      return targetPath;
    }

    throw Exception('Downloaded song file not found in app storage');
  } catch (e) {
    throw Exception('Failed to save: $e');
  }
}
