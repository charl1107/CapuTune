import 'package:flutter/material.dart';

/// Global navigator key + helper so non-UI code (e.g. [PlayerService]) can
/// surface failures to the user. Added as playback-failure diagnostics: the
/// silent no-op paths made device-side failures invisible.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void showGlobalSnack(String message) {
  final context = rootNavigatorKey.currentContext;
  if (context == null) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 6),
    ),
  );
}
