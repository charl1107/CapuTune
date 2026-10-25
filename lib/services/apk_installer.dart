import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Hands a *verified* APK to Android's package installer.
///
/// This never installs silently: we start the system installer with
/// `ACTION_VIEW`, so Android always shows its own confirmation dialog and
/// enforces signature verification against the installed app. Tapping the
/// button only opens that dialog.
class ApkInstaller {
  ApkInstaller._();

  static const MethodChannel _channel =
      MethodChannel('com.example.caputune/installer');

  /// True when the in-app install hand-off is usable on this platform.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// The device's supported ABIs, most preferred first (`Build.SUPPORTED_ABIS`).
  ///
  /// Returns an empty list off Android or if the platform cannot report them;
  /// callers then fall back to the universal APK.
  static Future<List<String>> supportedAbis() async {
    if (!isSupported) return const [];
    try {
      final abis = await _channel.invokeListMethod<String>('supportedAbis');
      return abis ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// Whether Android will currently let this app launch the package installer.
  ///
  /// On Android 8+ this is the per-app "install unknown apps" grant; on older
  /// versions there is no such toggle, so this reports true. Checked only at
  /// the moment of installing.
  static Future<bool> canInstallPackages() async {
    if (!isSupported) return false;
    try {
      final allowed = await _channel.invokeMethod<bool>('canInstallPackages');
      return allowed ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system "install unknown apps" screen for this app. Returns false
  /// when the screen could not be opened.
  static Future<bool> openInstallSettings() async {
    if (!isSupported) return false;
    try {
      final opened = await _channel.invokeMethod<bool>('openInstallSettings');
      return opened ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Asks the platform to install the APK at [apkPath].
  ///
  /// Returns `null` when the installer was launched successfully, or a
  /// human-readable error message the caller can show and fall back from. The
  /// platform refuses to launch for an APK that is not a valid upgrade (wrong
  /// package, not newer, or signed with a different key) and says why.
  static Future<String?> install(String apkPath) async {
    if (!isSupported) {
      return 'In-app install is only available on Android';
    }
    try {
      final error = await _channel.invokeMethod<String>(
        'installApk',
        {'path': apkPath},
      );
      return error;
    } on MissingPluginException {
      return 'In-app install is not available in this build';
    } on PlatformException catch (e) {
      return e.message ?? 'The installer could not be opened';
    } catch (_) {
      return 'The installer could not be opened';
    }
  }
}
