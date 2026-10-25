import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';

/// Shows the "update available" dialog and drives the whole update flow:
/// download → SHA-256 verification → hand off to Android's installer, falling
/// back to the GitHub release page whenever any step is unavailable or fails.
Future<void> showUpdateOffer(BuildContext context, UpdateService service) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final notes = service.releaseNotes ?? '';
      final colorScheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: Row(
          children: [
            Icon(Icons.system_update, color: colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Update Available'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _versionChip(
                      dialogContext, 'Current', service.currentVersion),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_forward,
                      size: 16, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  _versionChip(
                      dialogContext, 'Latest', service.latestVersion ?? ''),
                ],
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'What\'s New',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Text(
                      notes,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                service.canInstallInApp
                    ? 'Installing always asks for your confirmation, and Android '
                        'verifies the app signature before it is replaced.'
                    : 'This release is installed from the GitHub release page.',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
              if (service.canInstallInApp &&
                  service.latestApkFileName != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Package: ${service.latestApkFileName}'
                  '${service.latestApkAbi != null ? ' (${service.latestApkAbi})' : ' (universal)'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              service.dismissUpdate();
              Navigator.pop(dialogContext);
            },
            child: const Text('Later'),
          ),
          if (service.canInstallInApp)
            FilledButton.icon(
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Download & install'),
              onPressed: () {
                Navigator.pop(dialogContext);
                _downloadAndInstall(context, service);
              },
            )
          else
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Open release page'),
              onPressed: () {
                Navigator.pop(dialogContext);
                _openReleasePage(service);
              },
            ),
        ],
      );
    },
  );
}

Widget _versionChip(BuildContext context, String label, String version) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      '$label: v$version',
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    ),
  );
}

Future<void> _openReleasePage(UpdateService service) async {
  final url = service.releasePageUrl;
  if (url == null) return;
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    // Nothing actionable if no browser is available.
  }
}

Future<void> _downloadAndInstall(
    BuildContext context, UpdateService service) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final progress = ValueNotifier<double>(0);
  var dialogOpen = true;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Updating'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (_, value, __) =>
                  LinearProgressIndicator(value: value <= 0 ? null : value),
            ),
            const SizedBox(height: 12),
            const Text(
              'Downloading and verifying the update…',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (!dialogOpen) return;
              dialogOpen = false;
              service.cancelDownload();
              navigator.pop();
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );

  final result = await service.downloadVerifiedUpdate(
    onProgress: (value) {
      if (dialogOpen) progress.value = value;
    },
  );

  if (dialogOpen) {
    dialogOpen = false;
    if (navigator.canPop()) navigator.pop();
  }
  progress.dispose();

  switch (result.status) {
    case DownloadStatus.success:
      if (context.mounted) {
        await _installVerifiedApk(
            context, service, result.filePath!, messenger);
      }
    case DownloadStatus.cancelled:
      messenger.showSnackBar(
        const SnackBar(content: Text('Update cancelled.')),
      );
    case DownloadStatus.checksumUnavailable:
    case DownloadStatus.checksumMismatch:
    case DownloadStatus.downloadFailed:
    case DownloadStatus.unsupported:
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${result.message ?? 'The update could not be installed'}. '
            'Opening the release page.',
          ),
        ),
      );
      await _openReleasePage(service);
  }
}

/// Hands a verified APK to the installer, asking for the "install unknown
/// apps" grant first only if Android currently withholds it.
Future<void> _installVerifiedApk(
  BuildContext context,
  UpdateService service,
  String apkPath,
  ScaffoldMessengerState messenger,
) async {
  if (!await service.canInstallPackages()) {
    if (!context.mounted) return;
    final granted = await _requestInstallPermission(context, service);
    if (!granted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Install permission was not granted. Opening the release page instead.',
          ),
        ),
      );
      await _openReleasePage(service);
      return;
    }
  }

  final error = await service.installVerified(apkPath);
  if (error == null) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Confirm the installation in the dialog that appears.'),
      ),
    );
  } else {
    messenger.showSnackBar(
      SnackBar(content: Text('$error. Opening the release page instead.')),
    );
    await _openReleasePage(service);
  }
}

/// Explains why the grant is needed, then opens the system screen for it and
/// waits for the user to return before reporting whether it was granted.
Future<bool> _requestInstallPermission(
    BuildContext context, UpdateService service) async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Allow installing updates'),
      content: const Text(
        'Android needs your permission before it can install this update. '
        'On the next screen, allow this app to install unknown apps, then '
        'come back here.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Open settings'),
        ),
      ],
    ),
  );
  if (proceed != true) return false;

  final opened = await service.openInstallSettings();
  if (!opened) return service.canInstallPackages();
  // The setting is applied in the system UI, so re-check once the user returns.
  await _nextResume();
  return service.canInstallPackages();
}

/// Completes the first time the app returns to the foreground, or after
/// [timeout] so a user who never comes back does not hang the flow.
Future<void> _nextResume({
  Duration timeout = const Duration(minutes: 5),
}) {
  final completer = Completer<void>();
  late final _AppResumeObserver observer;
  void done() {
    WidgetsBinding.instance.removeObserver(observer);
    if (!completer.isCompleted) completer.complete();
  }

  observer = _AppResumeObserver(done);
  WidgetsBinding.instance.addObserver(observer);
  return completer.future.timeout(timeout, onTimeout: () => done());
}

class _AppResumeObserver extends WidgetsBindingObserver {
  final VoidCallback onResume;
  _AppResumeObserver(this.onResume);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}
