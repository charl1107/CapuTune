import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../services/storage_service.dart';
import '../services/player_service.dart';
import '../services/download_service.dart';
import '../widgets/song_card.dart';
import '../theme/app_colors.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  List<Song> _downloads = [];

  @override
  void initState() {
    super.initState();
    _loadDownloads();
  }

  void _loadDownloads() {
    setState(() {
      _downloads = StorageService.getDownloads();
    });
  }

  @override
  Widget build(BuildContext context) {
    final playerService = context.watch<PlayerService>();
    final downloadService = context.watch<DownloadService>();
    final activeDownloads = downloadService.activeSongs;
    _downloads = StorageService.getDownloads();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Downloads',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (activeDownloads.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: AppColors.spacingM),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppColors.spacingS,
                    vertical: AppColors.spacingXS,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppColors.radiusFull),
                  ),
                  child: Text(
                    '${activeDownloads.length} active',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (activeDownloads.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(AppColors.spacingM),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                    Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.3),
                  ],
                ),
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppColors.spacingS),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppColors.radiusS),
                    ),
                    child: Icon(
                      Icons.cloud_download_rounded,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: AppColors.spacingM),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Downloading ${activeDownloads.length} song(s)',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Saving to device...',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: activeDownloads.length,
              itemBuilder: (context, index) {
                final song = activeDownloads[index];
                final progress = downloadService.getProgress(song.id);
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppColors.spacingM,
                    vertical: AppColors.spacingS,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CircularProgressIndicator(
                              strokeWidth: 3,
                              value: progress,
                              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            ),
                            Center(
                              child: Text(
                                '${(progress * 100).toInt()}%',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppColors.spacingM),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: AppColors.spacingXS),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(AppColors.radiusFull),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 4,
                                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          Expanded(
            child: _downloads.isEmpty && activeDownloads.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppColors.spacingXL),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.download_done_rounded,
                            size: 64,
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(height: AppColors.spacingL),
                        Text(
                          'No downloads yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppColors.spacingS),
                        Text(
                          'Tap the download icon on any song!',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  )
                : _downloads.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: AppColors.spacingM),
                            Text(
                              'Waiting for downloads to complete...',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(AppColors.spacingM),
                        itemCount: _downloads.length,
                        itemBuilder: (context, index) {
                          final song = _downloads[index];
                          return SongCard(
                            song: song,
                            onTap: () {
                              playerService.playList(
                                _downloads,
                                startIndex: index,
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
