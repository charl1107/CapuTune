import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/player_service.dart';
import '../services/update_service.dart';
import '../theme/app_colors.dart';
import '../widgets/update_dialog.dart';
import '../widgets/appearance_settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final playerService = context.watch<PlayerService>();
    final updateService = context.watch<UpdateService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Appearance'),
          const AppearanceSettings(),
          const Divider(),
          const _SectionHeader('Playback'),
          SwitchListTile(
            title: const Text('Autoplay'),
            subtitle: const Text('Automatically play next song'),
            value: playerService.autoplay,
            onChanged: (value) => playerService.setAutoplay(value),
          ),
          SwitchListTile(
            title: const Text('Continue with Similar Songs After Playlist'),
            subtitle: const Text(
                'Play recommended tracks after a playlist reaches the end'),
            value: playerService.continueWithSimilarAfterPlaylist,
            onChanged: (value) =>
                playerService.setContinueWithSimilarAfterPlaylist(value),
          ),
          ListTile(
            title: const Text('Audio Quality'),
            subtitle: Text(playerService.audioQuality),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showQualityDialog(context, playerService),
          ),
          const Divider(),
          const _SectionHeader('Updates'),
          _UpdateTile(updateService: updateService),
          const Divider(),
          const _SectionHeader('About'),
          ListTile(
            title: const Text('Version'),
            subtitle: Text(updateService.currentVersion),
          ),
          ListTile(
            title: const Text('CapuTune'),
            subtitle: const Text('A music player built with Flutter'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'CapuTune',
                applicationVersion: updateService.currentVersion,
                applicationIcon: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/images/logo.jpg',
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                ),
                children: [
                  const Text('A beautiful music player built with Flutter.'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _showQualityDialog(BuildContext context, PlayerService playerService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Audio Quality'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['128kbps', '192kbps', '320kbps'].map((quality) {
            return RadioListTile<String>(
              title: Text(quality),
              value: quality,
              // ignore: deprecated_member_use
              groupValue: playerService.audioQuality,
              // ignore: deprecated_member_use
              onChanged: (value) {
                if (value != null) {
                  playerService.setAudioQuality(value);
                  Navigator.pop(context);
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _UpdateTile extends StatelessWidget {
  final UpdateService updateService;
  const _UpdateTile({required this.updateService});

  @override
  Widget build(BuildContext context) {
    switch (updateService.state) {
      case UpdateState.idle:
      case UpdateState.upToDate:
        return ListTile(
          leading: const Icon(Icons.system_update_outlined),
          title: const Text('Check for Updates'),
          subtitle: Text(
            updateService.state == UpdateState.upToDate
                ? 'You\'re using the latest version'
                : 'Tap to check',
          ),
          trailing: updateService.state == UpdateState.upToDate
              ? Icon(Icons.check_circle_outline,
                  color: Theme.of(context).colorScheme.primary, size: 20)
              : null,
          onTap: () => updateService.checkForUpdate(force: true),
        );

      case UpdateState.checking:
        return const ListTile(
          leading: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('Checking for updates...'),
        );

      case UpdateState.updateAvailable:
        return ListTile(
          leading: Icon(Icons.system_update,
              color: Theme.of(context).colorScheme.primary),
          title: Text('Update available: v${updateService.latestVersion}'),
          subtitle: const Text('Tap to view details'),
          trailing: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppColors.spacingS,
              vertical: AppColors.spacingXS,
            ),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppColors.radiusFull),
            ),
            child: Text(
              'NEW',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          onTap: () => showUpdateOffer(context, updateService),
        );

      case UpdateState.error:
        return ListTile(
          leading: Icon(Icons.error_outline,
              color: Theme.of(context).colorScheme.error),
          title: const Text('Update check failed'),
          subtitle: Text(updateService.errorMessage ?? 'Unknown error'),
          onTap: () => updateService.checkForUpdate(force: true),
        );
    }
  }
}
