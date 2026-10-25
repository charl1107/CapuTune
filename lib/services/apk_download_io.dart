import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import 'update_models.dart';

/// Downloads [url] into the app's private cache and verifies it against
/// [expectedSha256].
///
/// The bytes are streamed to a `.part` file so a large APK is never held in
/// memory. On any failure the partial file is removed; on a checksum mismatch
/// the file is deleted and never renamed into place. Writing into the app's
/// cache directory needs no storage permission.
Future<DownloadResult> downloadVerified({
  required String url,
  required String fileName,
  required String expectedSha256,
  CancelToken? cancelToken,
  void Function(double progress)? onProgress,
}) async {
  if (!url.startsWith('https://')) {
    return const DownloadResult(
      DownloadStatus.downloadFailed,
      message: 'Refusing to download over a non-HTTPS connection',
    );
  }

  final cacheDir = await getTemporaryDirectory();
  final updatesDir = Directory('${cacheDir.path}/updates');
  await updatesDir.create(recursive: true);

  final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final target = File('${updatesDir.path}/$safeName');
  final partial = File('${target.path}.part');
  if (await partial.exists()) await partial.delete();

  final dio = Dio();
  IOSink? sink;
  try {
    final response = await dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: true,
        headers: {'Accept': 'application/octet-stream'},
        receiveTimeout: const Duration(minutes: 5),
      ),
      cancelToken: cancelToken,
    );
    final body = response.data;
    if (body == null) {
      return const DownloadResult(
        DownloadStatus.downloadFailed,
        message: 'The update server returned an empty response',
      );
    }

    final total = body.contentLength;
    sink = partial.openWrite();
    var received = 0;
    await for (final chunk in body.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0 && onProgress != null) {
        final value = received / total;
        onProgress(value > 1.0 ? 1.0 : value);
      }
    }
    await sink.flush();
    await sink.close();
    sink = null;

    final actual = await _sha256OfFile(partial);
    if (actual.toLowerCase() != expectedSha256.toLowerCase()) {
      await partial.delete();
      return const DownloadResult(
        DownloadStatus.checksumMismatch,
        message: 'The downloaded file failed its integrity check',
      );
    }

    if (await target.exists()) await target.delete();
    await partial.rename(target.path);
    return DownloadResult(DownloadStatus.success, filePath: target.path);
  } on DioException catch (e) {
    if (CancelToken.isCancel(e)) {
      return const DownloadResult(
        DownloadStatus.cancelled,
        message: 'Update cancelled',
      );
    }
    final timedOut = e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout;
    return DownloadResult(
      DownloadStatus.downloadFailed,
      message: timedOut
          ? 'The update download timed out'
          : 'The update could not be downloaded',
    );
  } catch (_) {
    return const DownloadResult(
      DownloadStatus.downloadFailed,
      message: 'The update could not be downloaded',
    );
  } finally {
    try {
      await sink?.close();
    } catch (_) {}
    if (await partial.exists()) {
      try {
        await partial.delete();
      } catch (_) {}
    }
  }
}

/// Streams [file] through SHA-256 so even a large APK is hashed without being
/// loaded into memory.
Future<String> _sha256OfFile(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}
