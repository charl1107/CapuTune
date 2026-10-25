import 'package:flutter/foundation.dart';

/// Parsed, validated view of a GitHub release.
///
/// Only the fields the updater actually needs are kept; anything unexpected in
/// the payload is dropped rather than trusted.
@immutable
class ReleaseInfo {
  /// Version without a leading `v` (e.g. `1.2.3`).
  final String version;

  /// Release notes (GitHub release body). May be empty.
  final String notes;

  /// HTTPS URL of the release APK asset, when one is published.
  final String? apkDownloadUrl;

  /// File name of the APK asset, used to match it against the checksum file.
  final String? apkFileName;

  /// The device ABI this release's APK was selected for, or null when the
  /// universal (ABI-agnostic) APK was chosen.
  final String? apkAbi;

  /// HTTPS URL of the release's published checksum file, when present.
  ///
  /// An APK is only installed in-app after its SHA-256 has been checked
  /// against this file, so updates without it fall back to the release page.
  final String? checksumUrl;

  /// HTTPS URL of the human-readable release page.
  final String? releasePageUrl;

  const ReleaseInfo({
    required this.version,
    required this.notes,
    this.apkDownloadUrl,
    this.apkFileName,
    this.apkAbi,
    this.checksumUrl,
    this.releasePageUrl,
  });
}

/// A single `.apk` asset published on a release.
///
/// [abi] is the architecture the file name advertises (e.g. `arm64-v8a`), or
/// null when the name carries no ABI marker, which is treated as a universal
/// (ABI-agnostic) APK.
@immutable
class ApkAsset {
  final String name;
  final String url;
  final String? abi;

  const ApkAsset({required this.name, required this.url, this.abi});
}

/// High-level state of the update check.
enum UpdateState { idle, checking, updateAvailable, upToDate, error }

/// Outcome of downloading and verifying a release APK.
enum DownloadStatus {
  /// Downloaded and the SHA-256 matched.
  success,

  /// The release does not publish a checksum, so the file was not installed.
  checksumUnavailable,

  /// The downloaded bytes did not match the published SHA-256.
  checksumMismatch,

  /// The network transfer or filesystem write failed.
  downloadFailed,

  /// The user cancelled the download.
  cancelled,

  /// In-app downloads are not supported on this platform.
  unsupported,
}

@immutable
class DownloadResult {
  final DownloadStatus status;

  /// Verified APK path, present only for [DownloadStatus.success].
  final String? filePath;

  /// Human-readable detail for failures, safe to show to the user.
  final String? message;

  const DownloadResult(this.status, {this.filePath, this.message});
}
