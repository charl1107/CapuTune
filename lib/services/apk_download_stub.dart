import 'package:dio/dio.dart';

import 'update_models.dart';

/// Web/non-IO fallback: in-app APK download and installation is unavailable.
Future<DownloadResult> downloadVerified({
  required String url,
  required String fileName,
  required String expectedSha256,
  CancelToken? cancelToken,
  void Function(double progress)? onProgress,
}) async {
  return const DownloadResult(
    DownloadStatus.unsupported,
    message: 'In-app updates are only supported on Android',
  );
}
