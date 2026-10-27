import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'screens/home_screen.dart';
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

  // Playback diagnostics: route youtube_explode's internal logs (which client
  // failed and why) into the debug console instead of swallowing them.
  Logger.root.level = Level.ALL;
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
          androidNotificationIcon: 'mipmap/ic_launcher',
          androidShowNotificationBadge: true,
          androidStopForegroundOnPause: false,
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
        ChangeNotifierProvider(create: (_) => DownloadService()),
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
