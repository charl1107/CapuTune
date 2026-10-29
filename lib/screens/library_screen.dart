import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/playlist.dart';
import '../services/discovery_service.dart';
import '../services/local_music_service.dart';
import '../services/library_export_service.dart';
import '../services/playlist_url.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import 'collections_screen.dart';
import 'playlist_detail_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Playlist> _playlists = [];

  @override
  void initState() {
    super.initState();
    StorageService.playlistsRevision.addListener(_loadPlaylists);
    _loadPlaylists();
  }

  @override
  void dispose() {
    StorageService.playlistsRevision.removeListener(_loadPlaylists);
    super.dispose();
  }

  void _loadPlaylists() {
    setState(() {
      _playlists = StorageService.getPlaylists();
    });
  }

  Future<void> _createPlaylist() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Playlist name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final playlist = Playlist(
        id: const Uuid().v4(),
        name: result,
      );
      await StorageService.addPlaylist(playlist);
      _loadPlaylists();
    }
  }

  Future<void> _renamePlaylist(Playlist playlist) async {
    final controller = TextEditingController(text: playlist.name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'New name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (result != null && result.trim().isNotEmpty) {
      await StorageService.renamePlaylist(playlist.id, result.trim());
      _loadPlaylists();
    }
  }

  Future<void> _deletePlaylist(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Playlist'),
        content: const Text('Are you sure you want to delete this playlist?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await StorageService.deletePlaylist(id);
      _loadPlaylists();
    }
  }

  Future<void> _importLocalMusic() async {
    try {
      final songs = await LocalMusicService.pickAudioSongs();
      if (!mounted || songs == null) return;
      if (songs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No supported audio files were selected.')),
        );
        return;
      }

      final addedCount = await StorageService.addLocalSongs(songs);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(addedCount == 0
              ? 'Those files are already in Local Music.'
              : 'Imported $addedCount songs into Local Music.'),
        ),
      );
    } on UnsupportedError {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Local audio import is not supported on web yet.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not import the selected audio files.')),
      );
    }
  }

  Future<void> _exportLibrary() async {
    try {
      final exported = await LibraryExportService.exportAndShare(context);
      if (!mounted || !exported) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Library export is ready to share.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not export the library.')),
      );
    }
  }

  Future<void> _importLibraryFile() async {
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Import CapuTune library',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (!mounted || files.isEmpty) return;

      final bytes = await files.first.readAsBytes();
      final jsonString = utf8.decode(bytes);
      final imported = await StorageService.importLibraryJson(jsonString);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(imported == 0
              ? 'No new playlists to import (all already exist).'
              : 'Imported $imported playlist${imported == 1 ? '' : 's'}.'),
        ),
      );
      _loadPlaylists();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Invalid library file or unsupported format.')),
      );
    }
  }

  Future<void> _exportPlaylist(Playlist playlist) async {
    try {
      final exported =
          await LibraryExportService.exportSinglePlaylist(context, playlist);
      if (!mounted || !exported) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${playlist.name}" exported.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not export the playlist.')),
      );
    }
  }

  Future<void> _importFromYouTube() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import from YouTube'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Paste YouTube playlist URL',
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              PlaylistUrl.supportedSourcesDescription,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (result == null || result.trim().isEmpty) return;

    final url = result.trim();

    // Validate URL format before hitting the network.
    if (!PlaylistUrl.isValid(url)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unsupported URL. ${PlaylistUrl.supportedSourcesDescription}',
          ),
        ),
      );
      return;
    }

    // Show loading indicator
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Fetching playlist...')),
          ],
        ),
      ),
    );

    final songs = await DiscoveryService.importPlaylist(url);
    if (!mounted) return;
    Navigator.pop(context); // dismiss loading dialog

    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No songs found. The playlist may be private, empty, or the URL is invalid.',
          ),
        ),
      );
      return;
    }

    final existingPlaylists = StorageService.getPlaylists();
    final destination = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import playlist'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.playlist_add_check,
                size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              'Found ${songs.length} song${songs.length == 1 ? '' : 's'}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Where should they go?',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'new'),
            child: const Text('Create new'),
          ),
          if (existingPlaylists.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context, 'existing'),
              child: const Text('Add to existing'),
            ),
        ],
      ),
    );

    if (!mounted || destination == null) return;

    if (destination == 'existing') {
      final selectedPlaylistId = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Choose a playlist'),
          content: SizedBox(
            width: double.maxFinite,
            height: 320,
            child: ListView.builder(
              itemCount: existingPlaylists.length,
              itemBuilder: (context, index) {
                final playlist = existingPlaylists[index];
                return ListTile(
                  title: Text(playlist.name),
                  subtitle: Text('${playlist.songs.length} songs'),
                  onTap: () => Navigator.pop(context, playlist.id),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (!mounted || selectedPlaylistId == null) return;

      final playlists = StorageService.getPlaylists();
      final playlistIndex =
          playlists.indexWhere((playlist) => playlist.id == selectedPlaylistId);
      if (playlistIndex == -1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('That playlist is no longer available.')),
        );
        return;
      }

      final playlist = playlists[playlistIndex];
      final songIds = playlist.songs.map((song) => song.id).toSet();
      final newSongs = songs.where((song) => songIds.add(song.id)).toList();
      if (newSongs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('All imported songs are already in that playlist.')),
        );
        return;
      }

      playlists[playlistIndex] =
          playlist.copyWith(songs: [...playlist.songs, ...newSongs]);
      await StorageService.savePlaylists(playlists);
      if (!mounted) return;

      _loadPlaylists();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Added ${newSongs.length} songs to "${playlist.name}".'),
        ),
      );
      return;
    }

    final nameController = TextEditingController(text: 'Imported Playlist');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Playlist Name'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter a name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name == null || name.trim().isEmpty) return;

    final playlist = Playlist(
      id: const Uuid().v4(),
      name: name.trim(),
      songs: songs,
    );
    await StorageService.addPlaylist(playlist);
    if (!mounted) return;
    _loadPlaylists();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Created "${playlist.name}" with ${songs.length} songs.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.album),
            tooltip: 'Albums & artists',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const CollectionsScreen(),
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'import_local':
                  _importLocalMusic();
                case 'import_youtube':
                  _importFromYouTube();
                case 'import_library':
                  _importLibraryFile();
                case 'export_library':
                  _exportLibrary();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'import_local',
                child: ListTile(
                  leading: Icon(Icons.audio_file),
                  title: Text('Import local audio'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'import_youtube',
                child: ListTile(
                  leading: Icon(Icons.link),
                  title: Text('Import from YouTube'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'import_library',
                child: ListTile(
                  leading: Icon(Icons.file_open),
                  title: Text('Import library backup'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'export_library',
                child: ListTile(
                  leading: Icon(Icons.ios_share),
                  title: Text('Export library'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createPlaylist,
        child: const Icon(Icons.add),
      ),
      body: _playlists.isEmpty
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
                      Icons.library_music,
                      size: 64,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: AppColors.spacingL),
                  Text(
                    'No playlists yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppColors.spacingS),
                  Text(
                    'Create one or import from a backup.',
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
              padding: const EdgeInsets.all(16),
              itemCount: _playlists.length,
              itemBuilder: (context, index) {
                final playlist = _playlists[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.queue_music,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    title: Text(playlist.name),
                    subtitle: Text('${playlist.songs.length} songs'),
                    trailing: PopupMenuButton<String>(
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'rename',
                          child: Text('Rename'),
                        ),
                        const PopupMenuItem(
                          value: 'export',
                          child: Text('Export'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                      onSelected: (value) {
                        switch (value) {
                          case 'rename':
                            _renamePlaylist(playlist);
                          case 'export':
                            _exportPlaylist(playlist);
                          case 'delete':
                            _deletePlaylist(playlist.id);
                        }
                      },
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PlaylistDetailScreen(playlist: playlist),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
