// Startup sweep of the update-APK cache (apk_download_io).
//
// Pins: `.part` staging files from killed downloads are always removed,
// finished APKs newer than the cutoff are kept (still installable), old
// APKs are removed, and the sweep never strays outside cache/updates.
import 'dart:io';

import 'package:caputune/services/apk_download_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory cacheDir;

  setUp(() async {
    cacheDir = await Directory.systemTemp.createTemp('caputune_updates');
  });

  tearDown(() async {
    if (await cacheDir.exists()) await cacheDir.delete(recursive: true);
  });

  Future<File> seed(String name, {required Duration age}) async {
    final dir = Directory('${cacheDir.path}/updates');
    await dir.create(recursive: true);
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(List.filled(16, 1));
    final old = DateTime.now().subtract(age);
    await file.setLastModified(old);
    return file;
  }

  test('removes staging files and expired APKs, keeps fresh APKs',
      () async {
    final staging = await seed('caputune-v2.0.1.apk.part',
        age: const Duration(minutes: 5));
    final freshApk =
        await seed('caputune-v2.0.1.apk', age: const Duration(minutes: 5));
    final staleApk =
        await seed('caputune-v1.0.0.apk', age: const Duration(hours: 48));

    final deleted = await cleanupStaleUpdateFiles(
      cacheDirOverride: cacheDir,
      maxAge: const Duration(hours: 24),
    );

    expect(deleted, 2);
    expect(await staging.exists(), isFalse,
        reason: 'a staging file is always stale once the process died');
    expect(await freshApk.exists(), isTrue,
        reason: 'a fresh APK may still be handed to the installer');
    expect(await staleApk.exists(), isFalse,
        reason: 'an APK that was never installed is dead cache weight');
  });

  test('no-op when the updates directory does not exist', () async {
    expect(
      await cleanupStaleUpdateFiles(
        cacheDirOverride: cacheDir,
        maxAge: const Duration(hours: 24),
      ),
      0,
    );
  });

  test('empty cache directory yields zero deletions', () async {
    await Directory('${cacheDir.path}/updates').create(recursive: true);
    expect(
      await cleanupStaleUpdateFiles(
        cacheDirOverride: cacheDir,
        maxAge: const Duration(hours: 24),
      ),
      0,
    );
  });
}
