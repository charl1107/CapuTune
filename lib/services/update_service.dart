import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'apk_download.dart';
import 'apk_installer.dart';
import 'storage_service.dart';
import 'update_models.dart';

export 'update_models.dart';

/// Fallback version used only until [UpdateService.loadCurrentVersion] runs, or
/// when the platform version genuinely cannot be read. The real version is read
/// from the installed package at runtime, so CI never edits Dart code to keep a
/// version constant in sync.
const String defaultAppVersion = '0.0.0';

/// Checks for updates via GitHub Releases and, when the release publishes a
/// checksum, downloads and verifies an APK before handing it to Android's
/// installer.
///
/// Every failure degrades to [UpdateState.error] (manual checks) or is silently
/// ignored (automatic startup checks); the app never blocks on the network.
class UpdateService extends ChangeNotifier {
  static const String _repoOwner = 'charl1107';
  static const String _repoName = 'CapuTune';
  static const String _apiUrl =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';
  static const Duration _checkCooldown = Duration(minutes: 15);
  static const Duration _requestTimeout = Duration(seconds: 10);

  UpdateState _state = UpdateState.idle;
  ReleaseInfo? _release;
  String? _errorMessage;
  DateTime? _lastCheckTime;
  bool _checkInProgress = false;
  String _currentVersion = defaultAppVersion;
  bool _versionResolved = false;
  double _downloadProgress = 0;
  CancelToken? _cancelToken;
  List<String>? _supportedAbis;

  UpdateState get state => _state;
  String? get latestVersion => _release?.version;
  String? get releaseNotes => _release?.notes;
  String? get releasePageUrl => _release?.releasePageUrl;
  String? get errorMessage => _errorMessage;
  String get currentVersion => _currentVersion;
  bool get hasResolvedVersion => _versionResolved;
  double get downloadProgress => _downloadProgress;

  /// File name of the APK that would be installed, when one is published.
  String? get latestApkFileName => _release?.apkFileName;

  /// ABI of the selected APK, or null when it is the universal build.
  String? get latestApkAbi => _release?.apkAbi;

  /// True while an in-app download is running and can be cancelled.
  bool get isDownloading => _cancelToken != null;

  /// True when this release can be installed in-app: the platform supports it
  /// and the release publishes both an APK and a checksum to verify it against.
  bool get canInstallInApp =>
      ApkInstaller.isSupported &&
      (_release?.apkDownloadUrl != null) &&
      (_release?.apkFileName != null) &&
      (_release?.checksumUrl != null);

  /// Reads the installed version from the platform (e.g. `1.0.6` from the APK
  /// manifest). Safe to call repeatedly; failures leave the fallback in place.
  Future<void> loadCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.trim().isNotEmpty) {
        _currentVersion = info.version.trim();
        _versionResolved = true;
        notifyListeners();
      }
    } catch (_) {
      // Keep the fallback version; the check below reports the problem.
    }
  }

  /// Checks for updates. When [force] is false, skips the check if a recent
  /// result is cached or the user already dismissed this version.
  Future<void> checkForUpdate({bool force = false}) async {
    if (_checkInProgress) return;

    if (!_versionResolved) {
      // Without a trustworthy current version, no comparison is meaningful.
      if (force) {
        _fail('Could not determine the installed version');
        notifyListeners();
      }
      return;
    }

    if (!force && _lastCheckTime != null) {
      final elapsed = DateTime.now().difference(_lastCheckTime!);
      if (elapsed < _checkCooldown) return;
    }

    _checkInProgress = true;
    _state = UpdateState.checking;
    _errorMessage = null;
    notifyListeners();

    try {
      final dio = Dio();
      final response = await dio.get(
        _apiUrl,
        options: Options(
          headers: {'Accept': 'application/vnd.github.v3+json'},
          receiveTimeout: _requestTimeout,
          sendTimeout: const Duration(seconds: 5),
        ),
      );
      _lastCheckTime = DateTime.now();

      if (response.statusCode != 200 || response.data == null) {
        _fail('Unexpected response from GitHub (${response.statusCode})');
        return;
      }

      final raw = response.data;
      final Map<String, dynamic> data;
      if (raw is String) {
        final decoded = json.decode(raw);
        if (decoded is! Map<String, dynamic>) {
          _fail('Release metadata was not a JSON object');
          return;
        }
        data = decoded;
      } else if (raw is Map<String, dynamic>) {
        data = raw;
      } else {
        _fail('Release metadata had an unexpected shape');
        return;
      }

      final release = parseRelease(
        data,
        supportedAbis: await _supportedAbisOrEmpty(),
      );
      if (release == null) {
        _fail('Release metadata is missing a version tag');
        return;
      }
      _release = release;

      if (!isNewerVersion(release.version, _currentVersion)) {
        _state = UpdateState.upToDate;
        return;
      }

      // A dismissed version stays dismissed for automatic checks; an explicit
      // manual check (force) always shows the update.
      if (!force &&
          StorageService.getDismissedUpdateVersion() == release.version) {
        _state = UpdateState.upToDate;
        return;
      }

      _state = UpdateState.updateAvailable;
    } on DioException catch (e) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          _fail('Update check timed out');
        case DioExceptionType.connectionError:
          _fail('No internet connection');
        default:
          _fail('Could not reach the update server');
      }
      _lastCheckTime = DateTime.now();
    } on FormatException {
      _fail('Release metadata could not be parsed');
      _lastCheckTime = DateTime.now();
    } catch (_) {
      _fail('Update check failed');
      _lastCheckTime = DateTime.now();
    } finally {
      _checkInProgress = false;
      notifyListeners();
    }
  }

  /// Downloads the release APK and verifies it against the published SHA-256.
  ///
  /// Never installs anything; the caller decides what to do with the returned
  /// file. Returns a [DownloadResult] describing exactly what happened so the
  /// UI can offer an honest fallback (usually the release page). Cancel an
  /// in-flight download with [cancelDownload].
  Future<DownloadResult> downloadVerifiedUpdate({
    void Function(double progress)? onProgress,
  }) async {
    final release = _release;
    if (release == null ||
        release.apkDownloadUrl == null ||
        release.apkFileName == null) {
      return const DownloadResult(
        DownloadStatus.unsupported,
        message: 'This release does not publish an installable package',
      );
    }
    if (!ApkInstaller.isSupported) {
      return const DownloadResult(
        DownloadStatus.unsupported,
        message: 'In-app updates are only supported on Android',
      );
    }
    if (release.checksumUrl == null) {
      return const DownloadResult(
        DownloadStatus.checksumUnavailable,
        message: 'This release does not publish an integrity checksum',
      );
    }

    final token = CancelToken();
    _cancelToken = token;
    try {
      String checksumText;
      try {
        final dio = Dio();
        final res = await dio.get<String>(
          release.checksumUrl!,
          options: Options(
            responseType: ResponseType.plain,
            receiveTimeout: const Duration(seconds: 20),
          ),
          cancelToken: token,
        );
        checksumText = res.data ?? '';
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) {
          return const DownloadResult(
            DownloadStatus.cancelled,
            message: 'Update cancelled',
          );
        }
        return const DownloadResult(
          DownloadStatus.downloadFailed,
          message: 'The integrity checksum could not be downloaded',
        );
      }

      final expected = parseChecksum(checksumText, release.apkFileName!);
      if (expected == null) {
        return const DownloadResult(
          DownloadStatus.checksumUnavailable,
          message: 'The release checksum file did not list this package',
        );
      }

      _downloadProgress = 0;
      notifyListeners();
      final result = await ApkDownload.downloadVerified(
        url: release.apkDownloadUrl!,
        fileName: release.apkFileName!,
        expectedSha256: expected,
        cancelToken: token,
        onProgress: (progress) {
          _downloadProgress = progress;
          onProgress?.call(progress);
        },
      );
      return result;
    } finally {
      if (identical(_cancelToken, token)) _cancelToken = null;
    }
  }

  /// Cancels an in-flight [downloadVerifiedUpdate], if any.
  void cancelDownload() {
    _cancelToken?.cancel('cancelled-by-user');
  }

  /// Whether Android will currently allow this app to launch its installer.
  ///
  /// Only meaningful at the moment of installing; the UI must not call this at
  /// startup or while importing local files.
  Future<bool> canInstallPackages() => ApkInstaller.canInstallPackages();

  /// Sends the user to the system "install unknown apps" screen for this app.
  Future<bool> openInstallSettings() => ApkInstaller.openInstallSettings();

  /// Opens Android's installer for an already-verified APK. Returns null on
  /// success, or a message describing why it could not be opened (including a
  /// signature mismatch or a downgrade, which are rejected before launching).
  Future<String?> installVerified(String apkPath) =>
      ApkInstaller.install(apkPath);

  /// Primary ABI(s) of the device, cached for the session. Empty when the
  /// platform cannot report them, which selects the universal APK.
  Future<List<String>> _supportedAbisOrEmpty() async {
    final cached = _supportedAbis;
    if (cached != null) return cached;
    List<String> abis;
    try {
      abis = await ApkInstaller.supportedAbis();
    } catch (_) {
      abis = const [];
    }
    _supportedAbis = abis;
    return abis;
  }

  /// Dismiss the current update so it is not shown again automatically.
  void dismissUpdate() {
    final version = _release?.version;
    if (version != null) {
      StorageService.setDismissedUpdateVersion(version);
    }
    _state = UpdateState.upToDate;
    notifyListeners();
  }

  void _fail(String message) {
    _state = UpdateState.error;
    _errorMessage = message;
  }

  /// ABI markers recognised in release asset names, in preference order.
  ///
  /// The order matters: `-x86_64` must be tested before `-x86`, since the
  /// former contains the latter. Matches the set Aniyomi publishes (see
  /// `docs/updates.md` for attribution).
  static const List<String> apkBuildTypes = [
    'arm64-v8a',
    'armeabi-v7a',
    'x86_64',
    'x86',
  ];

  /// Parses and validates GitHub's `releases/latest` payload.
  ///
  /// [supportedAbis] is the device's ABI list, most preferred first (Android's
  /// `Build.SUPPORTED_ABIS`). When the release publishes several APK variants,
  /// the one matching the device is chosen; otherwise the universal APK (one
  /// whose name carries no ABI marker) is used. With no ABI information the
  /// universal APK is chosen.
  ///
  /// Returns null when the payload is unusable (missing/invalid tag). All
  /// fields are read defensively: a malformed asset entry is skipped rather
  /// than crashing the check.
  @visibleForTesting
  static ReleaseInfo? parseRelease(
    Map<String, dynamic> data, {
    List<String> supportedAbis = const [],
  }) {
    final tag = data['tag_name'];
    if (tag is! String || tag.trim().isEmpty) return null;
    final trimmed = tag.trim();
    final version = trimmed.startsWith('v') ? trimmed.substring(1) : trimmed;
    if (version.isEmpty) return null;

    final apks = <ApkAsset>[];
    final checksums = <String, String>{};

    final assets = data['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = asset['name'];
        final url = asset['browser_download_url'];
        if (name is! String || url is! String || !url.startsWith('https://')) {
          continue;
        }
        final lower = name.toLowerCase();
        if (lower.endsWith('.apk')) {
          apks.add(ApkAsset(name: name, url: url));
        } else if (_isChecksumAsset(lower)) {
          checksums.putIfAbsent(lower, () => url);
        }
      }
    }

    final apk = selectApkAsset(apks, supportedAbis);

    final notes = data['body'];
    final htmlUrl = data['html_url'];

    return ReleaseInfo(
      version: version,
      notes: notes is String ? notes : '',
      apkDownloadUrl: apk?.url,
      apkFileName: apk?.name,
      apkAbi: apk?.abi,
      checksumUrl: _selectChecksum(checksums, apk?.name),
      releasePageUrl: (htmlUrl is String && htmlUrl.startsWith('https://'))
          ? htmlUrl
          : null,
    );
  }

  /// Chooses the APK variant for a device whose supported ABIs are
  /// [supportedAbis] (most preferred first).
  ///
  /// Mirrors Aniyomi's `ReleaseServiceImpl.getDownloadLink`: an ABI match wins,
  /// otherwise the asset with no ABI marker (the universal build) is used.
  /// Unlike Aniyomi, every supported ABI is tried in order rather than only the
  /// primary one, which is a strict improvement when the first ABI is
  /// unpublished. Returns null when neither an ABI match nor a universal APK
  /// exists, so the caller falls back to the release page rather than
  /// installing an incompatible build.
  @visibleForTesting
  static ApkAsset? selectApkAsset(
    List<ApkAsset> apks,
    List<String> supportedAbis,
  ) {
    final byAbi = <String, ApkAsset>{};
    ApkAsset? universal;
    for (final apk in apks) {
      final abi = _abiForAssetName(apk.name);
      if (abi == null) {
        // Last ABI-less asset wins, matching Aniyomi's `associate` behaviour.
        universal = apk;
      } else {
        byAbi[abi] = ApkAsset(name: apk.name, url: apk.url, abi: abi);
      }
    }
    for (final abi in supportedAbis) {
      final match = byAbi[abi];
      if (match != null) return match;
    }
    return universal;
  }

  static String? _abiForAssetName(String name) {
    final lower = name.toLowerCase();
    for (final abi in apkBuildTypes) {
      if (lower.contains('-$abi')) return abi;
    }
    return null;
  }

  /// Picks the checksum asset most likely to describe [apkName], preferring a
  /// per-APK `<apk>.sha256` over a shared `checksums.txt`.
  static String? _selectChecksum(
      Map<String, String> checksums, String? apkName) {
    if (checksums.isEmpty) return null;
    if (apkName != null) {
      final lower = apkName.toLowerCase();
      for (final entry in checksums.entries) {
        if (entry.key.startsWith(lower)) return entry.value;
      }
    }
    for (final shared in const ['checksums.txt', 'sha256sums.txt']) {
      final url = checksums[shared];
      if (url != null) return url;
    }
    return checksums.values.first;
  }

  static bool _isChecksumAsset(String lowercaseName) {
    return lowercaseName.endsWith('.sha256') ||
        lowercaseName.endsWith('.sha256sum') ||
        lowercaseName == 'checksums.txt' ||
        lowercaseName == 'sha256sums.txt';
  }

  /// Extracts the SHA-256 for [fileName] from a checksum file body.
  ///
  /// Understands `sha256sum` output (`<hex>  <name>`, with an optional `*`
  /// binary marker), a bare hex digest, and comment/blank lines. Returns the
  /// lower-cased hex, or null when no matching, well-formed digest exists.
  @visibleForTesting
  static String? parseChecksum(String content, String fileName) {
    final target = _baseName(fileName).toLowerCase();
    final linePattern = RegExp(r'^([0-9a-fA-F]{64})(?:\s+\*?(.+))?$');
    String? bareHash;
    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final match = linePattern.firstMatch(line);
      if (match == null) continue;
      final hash = match.group(1)!.toLowerCase();
      final name = match.group(2)?.trim();
      if (name == null || name.isEmpty) {
        bareHash ??= hash;
        continue;
      }
      if (_baseName(name).toLowerCase() == target) return hash;
    }
    return bareHash;
  }

  static String _baseName(String path) =>
      path.replaceAll('\\', '/').split('/').last;

  /// Returns true when [latest] is strictly newer than [current].
  ///
  /// Tolerant of differing component counts and non-numeric junk (treated as
  /// 0). Pre-release suffixes (e.g. `1.2.0-beta.1`) compare on their numeric
  /// prefix only, which is the conservative choice for update prompts.
  static bool isNewerVersion(String latest, String current) {
    final l = _numericParts(latest);
    final c = _numericParts(current);
    final len = l.length > c.length ? l.length : c.length;
    for (var i = 0; i < len; i++) {
      final lv = i < l.length ? l[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }

  static List<int> _numericParts(String version) {
    final core = version.split(RegExp(r'[-+]')).first;
    return core.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
  }
}
