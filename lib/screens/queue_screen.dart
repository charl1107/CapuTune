import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/player_service.dart';
import '../widgets/song_card.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final playerService = context.watch<PlayerService>();
    final queue = playerService.queue;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Queue'),
        actions: [
          if (queue.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear queue',
              onPressed: () {
                playerService.clearQueue();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Radio Autoplay control header with distinct enabled/disabled states
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: playerService.radioAutoplay
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                        : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.sensors,
                    size: 20,
                    color: playerService.radioAutoplay
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Radio Autoplay',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: playerService.radioAutoplay
                                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                                  : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              playerService.radioAutoplay ? 'ON' : 'OFF',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: playerService.radioAutoplay
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        playerService.radioAutoplay
                            ? 'Plays similar songs when queue ends'
                            : 'Autoplay similar songs disabled',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: playerService.radioAutoplay,
                  onChanged: (value) => playerService.setRadioAutoplay(value),
                ),
              ],
            ),
          ),
          Expanded(
            child: queue.isEmpty
                ? Center(
                    child: Text(
                      'No songs in queue.\nPlay something to start!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: queue.length,
                    onReorderItem: playerService.reorderQueue,
                    itemBuilder: (context, index) {
                      final song = queue[index];
                      return SongCard(
                        key: ValueKey(song.id),
                        song: song,
                        onTap: () {
                          playerService.playList(
                            queue,
                            startIndex: index,
                            isPlaylistSource: playerService.isPlaylistSource,
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
