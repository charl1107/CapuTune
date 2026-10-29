import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../services/collection_service.dart';
import '../services/player_service.dart';
import '../widgets/song_card.dart';
import '../widgets/mini_player.dart';
import '../theme/app_colors.dart';

/// Albums/Artists view: groups every song the library has seen by album or
/// artist, then lists a group's songs for playback.
class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  CollectionSource _source = CollectionSource.albums;

  void _openGroup(String name, List<Song> songs) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _CollectionDetailScreen(name: name, songs: songs),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = CollectionService.buildGroups(_source);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _source == CollectionSource.albums ? 'Albums' : 'Artists',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppColors.spacingM),
            child: SegmentedButton<CollectionSource>(
              segments: const [
                ButtonSegment(
                  value: CollectionSource.albums,
                  icon: Icon(Icons.album),
                  label: Text('Albums'),
                ),
                ButtonSegment(
                  value: CollectionSource.artists,
                  icon: Icon(Icons.person),
                  label: Text('Artists'),
                ),
              ],
              selected: {_source},
              onSelectionChanged: (selection) =>
                  setState(() => _source = selection.first),
            ),
          ),
          Expanded(
            child: groups.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _source == CollectionSource.albums
                              ? Icons.album
                              : Icons.person,
                          size: 64,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: AppColors.spacingL),
                        Text(
                          'No songs yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppColors.spacingS),
                        Text(
                          'Play, favorite, or download songs to build up ${_source == CollectionSource.albums ? 'albums' : 'artists'}.',
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
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppColors.spacingM),
                    itemCount: groups.length,
                    itemBuilder: (context, index) {
                      final name = groups.keys.elementAt(index);
                      final songs = groups[name]!;
                      return Card(
                        margin:
                            const EdgeInsets.only(bottom: AppColors.spacingS),
                        child: ListTile(
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              borderRadius:
                                  BorderRadius.circular(AppColors.radiusM),
                            ),
                            child: Icon(
                              _source == CollectionSource.albums
                                  ? Icons.album
                                  : Icons.person,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          title: Text(name,
                              overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${songs.length} song${songs.length == 1 ? '' : 's'}'),
                          onTap: () => _openGroup(name, songs),
                        ),
                      );
                    },
                  ),
          ),
          if (context.watch<PlayerService>().currentSong != null)
            const MiniPlayer(),
        ],
      ),
    );
  }
}

/// Lists the songs of one album or artist; taps play the whole group.
class _CollectionDetailScreen extends StatelessWidget {
  final String name;
  final List<Song> songs;

  const _CollectionDetailScreen({required this.name, required this.songs});

  @override
  Widget build(BuildContext context) {
    final playerService = context.watch<PlayerService>();
    final currentSong = playerService.currentSong;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (songs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.play_circle_fill),
              onPressed: () =>
                  playerService.playList(songs, isPlaylistSource: true),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(AppColors.spacingM),
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];
                final isPlaying = currentSong?.id == song.id;

                return Container(
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
                    onTap: () => playerService.playList(
                      songs,
                      startIndex: index,
                    ),
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
