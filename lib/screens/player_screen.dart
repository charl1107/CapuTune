import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/song.dart';
import '../services/download_service.dart';
import '../services/player_service.dart';
import '../services/theme_service.dart';
import '../theme/app_colors.dart';
import '../utils/snackbar.dart';
import '../widgets/add_to_playlist_dialog.dart';
import 'queue_screen.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _vinylController;

  @override
  void initState() {
    super.initState();
    _vinylController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _vinylController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerService = context.watch<PlayerService>();
    final song = playerService.currentSong;

    if (song == null) {
      return const Scaffold(
        body: Center(child: Text('No song playing')),
      );
    }

    // Control vinyl rotation
    if (playerService.isPlaying) {
      _vinylController.repeat();
    } else {
      _vinylController.stop();
    }

    // Theme restriction: the active design style changes ONLY this
    // background gradient. Every foreground element below is untouched.
    final tokens = context.watch<ThemeService>().colors;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              tokens.background,
              tokens.card.withValues(alpha: 0.5),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // App bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppColors.spacingS),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down, size: 32),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Text(
                        'Now Playing',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.queue_music),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const QueueScreen()),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_vert),
                      onPressed: () => _showOptions(context, song),
                    ),
                  ],
                ),
              ),
              // Album art with vinyl effect
              Expanded(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _vinylController,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _vinylController.value * 2 * 3.14159,
                        child: child,
                      );
                    },
                    child: Container(
                      width: 280,
                      height: 280,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Vinyl grooves
                          ...List.generate(6, (index) {
                            final diameter = 280.0 - (index * 30.0);
                            return Container(
                              width: diameter,
                              height: diameter,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.05 + index * 0.01),
                                  width: 1,
                                ),
                              ),
                            );
                          }),
                          // Album art center
                          ClipOval(
                            child: song.thumbnail != null
                                ? CachedNetworkImage(
                                    imageUrl: song.thumbnail!,
                                    width: 160,
                                    height: 160,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      width: 160,
                                      height: 160,
                                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    ),
                                    errorWidget: (context, url, error) => Container(
                                      width: 160,
                                      height: 160,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Theme.of(context).colorScheme.primary,
                                            Theme.of(context).colorScheme.secondary,
                                          ],
                                        ),
                                      ),
                                      child: const Icon(Icons.music_note, color: Colors.white, size: 60),
                                    ),
                                  )
                                : Container(
                                    width: 160,
                                    height: 160,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Theme.of(context).colorScheme.primary,
                                          Theme.of(context).colorScheme.secondary,
                                        ],
                                      ),
                                    ),
                                    child: const Icon(Icons.music_note, color: Colors.white, size: 60),
                                  ),
                          ),
                          // Center dot
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outline,
                                width: 2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Song info
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppColors.spacingL),
                child: Column(
                  children: [
                    Text(
                      song.title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppColors.spacingS),
                    Text(
                      song.artist,
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppColors.spacingL),
              // Progress bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppColors.spacingL),
                child: StreamBuilder<Duration>(
                  stream: playerService.positionStream,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    final duration = playerService.duration;
                    return Column(
                      children: [
                        SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                            activeTrackColor: Theme.of(context).colorScheme.primary,
                            inactiveTrackColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            thumbColor: Theme.of(context).colorScheme.primary,
                          ),
                          child: Slider(
                            value: position.inSeconds.toDouble(),
                            max: duration.inSeconds.toDouble().clamp(1, double.infinity),
                            onChanged: (value) {
                              playerService.seek(Duration(seconds: value.toInt()));
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppColors.spacingS),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(position),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                _formatDuration(duration),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: AppColors.spacingM),
              // Controls
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppColors.spacingXL),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.shuffle,
                        color: playerService.shuffleMode
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      onPressed: () => playerService.toggleShuffle(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous, size: 36),
                      onPressed: () => playerService.playPrevious(),
                    ),
                    // Play/Pause button
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            playerService.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            key: ValueKey(playerService.isPlaying),
                            color: Theme.of(context).colorScheme.onPrimary,
                            size: 40,
                          ),
                        ),
                        onPressed: () => playerService.togglePlay(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next, size: 36),
                      onPressed: () => playerService.playNext(),
                    ),
                    IconButton(
                      icon: Icon(
                        playerService.repeatMode == RepeatMode.one
                            ? Icons.repeat_one
                            : Icons.repeat,
                        color: playerService.repeatMode != RepeatMode.off
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      onPressed: () => playerService.cycleRepeat(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppColors.spacingXXL),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showOptions(BuildContext context, Song song) async {
    final playerService = context.read<PlayerService>();
    final downloadService = context.read<DownloadService>();
    final isLocalFile = song.localPath != null;

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Add to playlist'),
              onTap: () => Navigator.pop(sheetContext, 'add_to_playlist'),
            ),
            // Imported device music is already local; downloading it again
            // would only re-stream a file that is already on the phone.
            if (!isLocalFile)
              Consumer<DownloadService>(
                builder: (context, downloads, _) {
                  final state = downloads.getState(song.id);
                  if (state == DownloadState.downloading) {
                    final progress = downloads.getProgress(song.id);
                    return ListTile(
                      // Duplicate taps are ignored while a download runs
                      // (DownloadService also guards this).
                      enabled: false,
                      leading: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          value: progress > 0 ? progress : null,
                        ),
                      ),
                      title: Text(
                        progress > 0
                            ? 'Downloading… ${(progress * 100).toStringAsFixed(0)}%'
                            : 'Resolving audio…',
                      ),
                    );
                  }
                  final downloaded = state == DownloadState.downloaded;
                  return ListTile(
                    leading: Icon(
                      downloaded ? Icons.delete_outline : Icons.download,
                      color: downloaded ? Colors.red : null,
                    ),
                    title: Text(downloaded ? 'Delete download' : 'Download'),
                    onTap: () => Navigator.pop(
                      sheetContext,
                      downloaded ? 'delete_download' : 'download',
                    ),
                  );
                },
              ),
            SwitchListTile(
              secondary: Icon(
                Icons.sensors,
                color: playerService.radioAutoplay
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: const Text('Radio Autoplay'),
              subtitle: Text(
                playerService.radioAutoplay
                    ? 'Similar songs play automatically'
                    : 'Off',
              ),
              value: playerService.radioAutoplay,
              onChanged: (val) {
                playerService.setRadioAutoplay(val);
                Navigator.pop(sheetContext);
              },
            ),
            ListTile(
              leading: Icon(
                playerService.isFavorite(song.id)
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: playerService.isFavorite(song.id)
                    ? AppColors.accentPink
                    : null,
              ),
              title: Text(
                playerService.isFavorite(song.id)
                    ? 'Remove from favorites'
                    : 'Add to favorites',
              ),
              onTap: () {
                playerService.toggleFavorite(song);
                Navigator.pop(sheetContext);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(sheetContext, 'share');
              },
            ),
          ],
        ),
      ),
    );

    if (action == 'add_to_playlist' && mounted) {
      await showAddToPlaylistDialog(this.context, song);
      return;
    }
    if (action == null) return;

    switch (action) {
      case 'download':
        showGlobalSnack('Downloading “${song.title}”…');
        await downloadService.downloadSong(song);
        // Terminal feedback: a downloaded song only ever lands here after
        // the audio file is fully written and its metadata persisted.
        if (downloadService.getState(song.id) == DownloadState.downloaded) {
          showGlobalSnack('“${song.title}” downloaded — find it in Downloads');
        } else {
          showGlobalSnack(downloadService.errorMessage ?? 'Download failed');
        }
        break;
      case 'delete_download':
        await downloadService.removeDownload(song.id);
        showGlobalSnack('Download removed');
        break;
      case 'share':
        // song.id is the YouTube video id, so this reconstructs a link that
        // opens the same track in any browser or the YT Music app.
        await SharePlus.instance.share(
          ShareParams(
            subject: song.title,
            text: '${song.title} — ${song.artist}\n'
                'https://music.youtube.com/watch?v=${song.id}',
          ),
        );
        break;
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
