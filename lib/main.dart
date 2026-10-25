import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'screens/home_screen.dart';
import 'services/player_service.dart';
import 'services/download_service.dart';
import 'services/storage_service.dart';
import 'services/update_service.dart';
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

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PlayerService()),
        ChangeNotifierProvider(create: (_) => DownloadService()),
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
    return Consumer<PlayerService>(
      builder: (context, playerService, child) {
        return MaterialApp(
          title: 'CapuTune',
          debugShowCheckedModeBanner: false,
          navigatorKey: rootNavigatorKey,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode:
              playerService.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: const HomeScreen(),
        );
      },
    );
  }
}
