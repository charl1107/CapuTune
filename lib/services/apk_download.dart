import 'apk_download_stub.dart' if (dart.library.io) 'apk_download_io.dart'
    as impl;
import 'package:dio/dio.dart';
import 'update_models.dart';

/// Downloads a release APK to app-private storage and verifies its SHA-256
/// digest before returning the path.
///
/// The real implementation lives behind a conditional import so the app still
/// compiles for web, where in-app installation is unsupported.
class ApkDownload {
  ApkDownload._();

  static Future<DownloadResult> downloadVerified({
    required String url,
    required String fileName,
    required String expectedSha256,
    CancelToken? cancelToken,
    void Function(double progress)? onProgress,
  }) {
    return impl.downloadVerified(
      url: url,
      fileName: fileName,
      expectedSha256: expectedSha256,
      cancelToken: cancelToken,
      onProgress: onProgress,
    );
  }
}
