import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/storage_service.dart';

Future<void> showAddToPlaylistDialog(BuildContext context, Song song) async {
  final availablePlaylists = StorageService.getPlaylists();
  if (availablePlaylists.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Create a playlist before adding songs.')),
    );
    return;
  }

  final selectedPlaylistId = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Add to playlist'),
      content: SizedBox(
        width: double.maxFinite,
        height: 320,
        child: ListView.builder(
          itemCount: availablePlaylists.length,
          itemBuilder: (context, index) {
            final playlist = availablePlaylists[index];
            final alreadyAdded =
                playlist.songs.any((playlistSong) => playlistSong.id == song.id);
            return ListTile(
              leading: Icon(
                alreadyAdded ? Icons.check_circle_outline : Icons.playlist_add,
              ),
              title: Text(playlist.name),
              subtitle: Text(
                alreadyAdded
                    ? 'Already contains this song'
                    : '${playlist.songs.length} songs',
              ),
              enabled: !alreadyAdded,
              onTap: alreadyAdded
                  ? null
                  : () => Navigator.pop(dialogContext, playlist.id),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );

  if (!context.mounted || selectedPlaylistId == null) return;

  final playlists = StorageService.getPlaylists();
  final playlistIndex =
      playlists.indexWhere((playlist) => playlist.id == selectedPlaylistId);
  if (playlistIndex == -1) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('That playlist is no longer available.')),
    );
    return;
  }

  final playlist = playlists[playlistIndex];
  if (playlist.songs.any((playlistSong) => playlistSong.id == song.id)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This song is already in that playlist.')),
    );
    return;
  }

  playlists[playlistIndex] = playlist.copyWith(
    songs: [...playlist.songs, song],
  );
  await StorageService.savePlaylists(playlists);
  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Added "${song.title}" to "${playlist.name}".')),
  );
}
