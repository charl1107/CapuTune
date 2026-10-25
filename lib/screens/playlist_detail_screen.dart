import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/playlist.dart';
import '../services/player_service.dart';
import '../widgets/song_card.dart';
import '../widgets/mini_player.dart';
import '../theme/app_colors.dart';

class PlaylistDetailScreen extends StatelessWidget {
  final Playlist playlist;
  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) {
    final playerService = context.watch<PlayerService>();
    final currentSong = playerService.currentSong;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          playlist.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (playlist.songs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.play_circle_fill),
              onPressed: () {
                playerService.playList(playlist.songs);
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: playlist.songs.isEmpty
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
                            Icons.queue_music,
                            size: 64,
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(height: AppColors.spacingL),
                        Text(
                          'No songs in this playlist',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppColors.spacingS),
                        Text(
                          'Add songs from search.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(AppColors.spacingM),
                    itemCount: playlist.songs.length,
                    itemBuilder: (context, index) {
                      final song = playlist.songs[index];
                      final isPlaying = currentSong?.id == song.id;

                      return Container(
                        margin: const EdgeInsets.only(bottom: AppColors.spacingS),
                        decoration: isPlaying
                            ? BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(AppColors.radiusM),
                              )
                            : null,
                        child: SongCard(
                          song: song,
                          onTap: () {
                            playerService.playList(
                              playlist.songs,
                              startIndex: index,
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
          if (playerService.currentSong != null) const MiniPlayer(),
        ],
      ),
    );
  }
}
