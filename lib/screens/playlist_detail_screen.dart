import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../services/player_service.dart';
import '../services/storage_service.dart';
import '../widgets/song_card.dart';
import '../widgets/mini_player.dart';
import '../theme/app_colors.dart';

/// The distinct sort states a playlist can be viewed in. `custom` is the
/// user's manual order, maintained by drag-and-drop reordering.
enum _PlaylistView { custom, title, artist }

class PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;
  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  late Playlist _playlist;

  /// Last sort the user applied, shown as the selected row in the sort
  /// sheet. Purely cosmetic: sorting rewrites the song list itself, so after
  /// any drag the order is custom again.
  _PlaylistView _sort = _PlaylistView.custom;

  @override
  void initState() {
    super.initState();
    _playlist = widget.playlist;
  }

  /// Persists the current song order, keeping the playlist's slot among the
  /// other stored playlists and bumping playlistsRevision for listeners.
  Future<void> _persistOrder(List<Song> songs) async {
    final playlists = StorageService.getPlaylists();
    final index = playlists.indexWhere((p) => p.id == _playlist.id);
    if (index == -1) return;
    playlists[index] = playlists[index].copyWith(songs: songs);
    await StorageService.savePlaylists(playlists);
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      _playlist = _playlist.reordered(oldIndex, newIndex);
      _sort = _PlaylistView.custom;
    });
    _persistOrder(_playlist.songs);
  }

  /// Applies [sort] destructively: the chosen order becomes the playlist's
  /// stored custom order, like most music apps. 'Custom' is a no-op since it
  /// can only restore what the last sort/drag already produced.
  void _applySort(_PlaylistView sort) {
    if (sort == _PlaylistView.custom) return;
    setState(() {
      _playlist = _playlist.sorted(
        sort == _PlaylistView.title ? PlaylistSort.title : PlaylistSort.artist,
      );
      _sort = sort;
    });
    _persistOrder(_playlist.songs);
  }

  Future<void> _confirmSort() async {
    final chosen = await showModalBottomSheet<_PlaylistView>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Sort playlist',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ..._PlaylistView.values.map(
              (sort) => ListTile(
                leading: Icon(
                  _sort == sort
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: _sort == sort
                      ? Theme.of(sheetContext).colorScheme.primary
                      : null,
                ),
                title: Text(
                  switch (sort) {
                    _PlaylistView.custom => 'Custom order',
                    _PlaylistView.title => 'Title (A–Z)',
                    _PlaylistView.artist => 'Artist (A–Z)',
                  },
                ),
                onTap: () => Navigator.pop(sheetContext, sort),
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen != null) _applySort(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final playerService = context.watch<PlayerService>();
    final currentSong = playerService.currentSong;
    final songs = _playlist.songs;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _playlist.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_playlist.songs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort',
              onPressed: _confirmSort,
            ),
          if (_playlist.songs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.play_circle_fill),
              onPressed: () {
                playerService.playList(
                  songs,
                  isPlaylistSource: true,
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _playlist.songs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppColors.spacingXL),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.3),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.queue_music,
                            size: 64,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(height: AppColors.spacingL),
                        Text(
                          'No songs in this playlist',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppColors.spacingS),
                        Text(
                          'Add songs from search.',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  )
                // Songs are drag-reorderable; a tap still starts playback at
                // the row's current index.
                : ReorderableListView.builder(
                    padding: const EdgeInsets.all(AppColors.spacingM),
                    buildDefaultDragHandles: true,
                    itemCount: songs.length,
                    onReorderItem: _reorder,
                    itemBuilder: (context, index) {
                      final song = songs[index];
                      final isPlaying = currentSong?.id == song.id;

                      return Container(
                        key: ValueKey('${song.id}-$index'),
                        margin:
                            const EdgeInsets.only(bottom: AppColors.spacingS),
                        decoration: isPlaying
                            ? BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.1),
                                borderRadius:
                                    BorderRadius.circular(AppColors.radiusM),
                              )
                            : null,
                        child: SongCard(
                          song: song,
                          onTap: () {
                            playerService.playList(
                              songs,
                              startIndex: index,
                              isPlaylistSource: true,
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
