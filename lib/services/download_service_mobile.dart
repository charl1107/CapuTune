import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';
import 'cipher_service.dart';

typedef ProgressCallback = void Function(double progress);

/// Bounded network constants for downloads. Keep them modest: a download
/// that can't make progress should fail fast so the retry ladder (one
/// fresh-URL retry in DownloadService) can take over with a new node.
const Duration _downloadConnectTimeout = Duration(seconds: 15);
const Duration _downloadSendTimeout = Duration(seconds: 15);

/// Covers the wait for response HEADERS: dio applies receiveTimeout to
/// `request.close()` (aborting the connection on timeout). Without it, an
/// origin that accepts TCP but never sends headers would leave `dio.get`
/// waiting indefinitely — the chunk-idle guard below cannot help because it
/// only starts once dio.get has returned (i.e. after the headers).
const Duration _downloadReceiveTimeout = Duration(seconds: 45);

/// No data for this long mid-transfer = connection stalled (the same
/// sustained-connection failure class seen in streaming). Dio's
/// receiveTimeout does not apply to streamed responses, so this explicit
/// chunk-idle timeout is what detects a dead transfer.
const Duration _downloadChunkIdleTimeout = Duration(seconds: 45);

/// Downloads audio from [url] and stores it encrypted (.ct) inside the app's
/// private sandbox directory. When the app is uninstalled, the OS automatically
/// wipes this directory completely.
///
/// No storage permission is required: the app's private documents directory
/// is always writable without runtime permissions.
Future<void> downloadFile(String url, Song song,
    {ProgressCallback? onProgress,
    CancelToken? cancelToken,
    Duration? chunkIdleTimeout,
    Duration? receiveTimeout}) async {
  final dir = await getApplicationDocumentsDirectory();
  final encryptedPath = '${dir.path}/${song.id}.ct';
  final tempFile = File('$encryptedPath.tmp');
  final sink = tempFile.openWrite();

  final dio = Dio(
    BaseOptions(
      connectTimeout: _downloadConnectTimeout,
      sendTimeout: _downloadSendTimeout,
      receiveTimeout: receiveTimeout ?? _downloadReceiveTimeout,
    ),
  );

  try {
    // Header-wait guard: dio's receiveTimeout polices the wait for response
    // headers (it aborts the connection on timeout), so an origin that
    // accepts TCP but stalls before its first header is cut off too. The
    // chunk-idle guard below takes over once the body starts.
    final response = await dio.get<ResponseBody>(
      url,
      options: Options(responseType: ResponseType.stream),
      cancelToken: cancelToken,
    );

    final total = response.data?.contentLength ?? -1;
    var received = 0;

    // Mid-transfer stall guard: a silent connection aborts the download
    // instead of hanging forever.
    await for (final chunk
        in response.data!.stream.timeout(chunkIdleTimeout ?? _downloadChunkIdleTimeout)) {
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

/// Startup housekeeping: deletes stale `*.ct.tmp` staging files left behind
/// when the app was killed mid-download.
///
/// Safety rails:
/// - Only files literally named `<id>.ct.tmp` qualify — completed `.ct`
///   files, legacy `.mp3` files and the `local_music/` directory are never
///   considered (directories are skipped entirely).
/// - Files whose id belongs to an active download ([activeIds]) are untouched.
/// - Files younger than [maxAge] are presumed current and left alone.
/// - Any FS error is swallowed: housekeeping must never fail startup or
///   touch data it cannot inspect.
///
/// Returns the number of files removed (0 on any failure).
Future<int> cleanupStaleTmp({
  Directory? directory,
  Set<String> activeIds = const <String>{},
  Duration maxAge = const Duration(hours: 24),
}) async {
  try {
    final dir = directory ?? await getApplicationDocumentsDirectory();
    var removed = 0;
    for (final entry in dir.listSync(followLinks: false)) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      const suffix = '.ct.tmp';
      if (!name.endsWith(suffix) || name.length <= suffix.length) continue;
      final songId = name.substring(0, name.length - suffix.length);
      if (activeIds.contains(songId)) continue;
      try {
        final modified = await entry.lastModified();
        if (DateTime.now().difference(modified) < maxAge) continue;
        await entry.delete();
        removed++;
      } catch (_) {
        // Cannot stat or delete this entry — leave it; best effort only.
      }
    }
    return removed;
  } catch (_) {
    return 0;
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
