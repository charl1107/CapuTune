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
              onPressed: () {
                playerService.clearQueue();
              },
            ),
        ],
      ),
      body: queue.isEmpty
          ? const Center(
              child: Text(
                'No songs in queue.\nPlay something to start!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
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
                    playerService.playList(queue, startIndex: index);
                  },
                );
              },
            ),
    );
  }
}
