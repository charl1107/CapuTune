import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'screens/home_screen.dart';
import 'services/apk_download.dart';
import 'services/audio_handler.dart';
import 'services/player_service.dart';
import 'services/download_service.dart';
import 'services/storage_service.dart';
import 'services/update_service.dart';
import 'services/theme_service.dart';
import 'theme/app_theme.dart';
import 'utils/snackbar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Hive.initFlutter();
  await StorageService.init();

  // Startup housekeeping: remove download staging files left by killed
  // sessions. Uses the same DownloadService instance that tracks active
  // downloads, so an in-progress write is never touched. No-op on web.
  final downloadService = DownloadService();
  unawaited(downloadService.cleanupStaleTempFiles());

  // Startup housekeeping: sweep the update cache the same way. An update
  // APK that was downloaded but never installed, or a `.part` file left by
  // a killed download, otherwise stays in cache/ forever (tens of MB per
  // abandoned update). Only app-cache files are touched — downloaded songs
  // and playlists live elsewhere and are never deleted by this.
  unawaited(ApkDownload.cleanupStaleUpdateFiles());

  // Playback diagnostics: route youtube_explode's internal logs (which client
  // failed and why) into the debug console instead of swallowing them.
  // Release builds keep only warnings: processing every mpv/youtube_explode
  // record (string formatting, list churn) is constant CPU work a phone
  // pays for in battery, and debug-only detail never helps a release user.
  Logger.root.level = kReleaseMode ? Level.WARNING : Level.ALL;
  Logger.root.onRecord.listen((r) {
    debugPrint('[yt] ${r.loggerName}: ${r.message}'
        '${r.error != null ? ' | error: ${r.error}' : ''}');
  });

  final updateService = UpdateService();

  // Resolve the installed version before anything compares against it. This
  // reads the real version from the APK, so a release bump never needs a Dart
  // edit to stay in sync.
  await updateService.loadCurrentVersion();

  final playerService = PlayerService();

  // Initialize Android / system MediaSession via AudioService if supported
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      await AudioService.init(
        builder: () => CapuTuneAudioHandler(playerService),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.example.caputune.playback',
          androidNotificationChannelName: 'CapuTune Music Playback',
          androidNotificationChannelDescription:
              'Active playback notification for CapuTune music player',
          // Notifications need a flat monochrome drawable; the adaptive
          // launcher icon (mipmap/ic_launcher) renders as a white square here.
          androidNotificationIcon: 'drawable/ic_notification',
          androidShowNotificationBadge: true,
          // While playback is paused the service drops out of the foreground
          // state: the media notification stays, but the process is no
          // longer held at foreground priority by a paused session. Keeping
          // the foreground service alive while idle-paused (the previous
          // behavior) burned battery for nothing — resume re-promotes the
          // service automatically when the user presses play.
          androidStopForegroundOnPause: true,
          // Notification/lock-screen artwork is loaded by the system from
          // artUri; capping the decoded size avoids a 1280px+ bitmap for a
          // ~64dp notification icon.
          artDownscaleWidth: 512,
          artDownscaleHeight: 512,
          notificationColor: Color(0xFF1E1E2E),
        ),
      );
    } catch (e) {
      debugPrint('[audio_service] init error: $e');
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: playerService),
        ChangeNotifierProvider.value(value: downloadService),
        ChangeNotifierProvider(create: (_) => ThemeService()),
        ChangeNotifierProvider.value(value: updateService),
      ],
      child: const CapuTuneApp(),
    ),
  );

  // Non-blocking startup update check — runs after the first frame so the
  // UI is responsive immediately.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    updateService.checkForUpdate();
  });
}

class CapuTuneApp extends StatelessWidget {
  const CapuTuneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        final tokens = themeService.colors;
        return MaterialApp(
          title: 'CapuTune',
          debugShowCheckedModeBanner: false,
          navigatorKey: rootNavigatorKey,
          theme: AppTheme.fromTokens(tokens, dark: false),
          darkTheme: AppTheme.fromTokens(tokens, dark: true),
          themeMode: tokens.isDark ? ThemeMode.dark : ThemeMode.light,
          home: const HomeScreen(),
        );
      },
    );
  }
}
