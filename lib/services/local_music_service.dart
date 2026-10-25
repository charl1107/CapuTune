import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/song.dart';
import 'local_music_storage_stub.dart'
    if (dart.library.io) 'local_music_storage_io.dart' as storage;

class LocalMusicService {
  static const Set<String> _audioExtensions = {
    'aac',
    'aif',
    'aiff',
    'alac',
    'flac',
    'm4a',
    'm4b',
    'mp3',
    'ogg',
    'opus',
    'wav',
    'wma',
  };

  static Future<List<Song>?> pickAudioSongs() async {
    if (kIsWeb) {
      throw UnsupportedError('Local audio import is not supported on web yet.');
    }

    // Android registers `pickFiles` as multi-select; an empty list cancel
    // (the old API returned null).
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Choose audio files',
      type: FileType.custom,
      allowedExtensions: _audioExtensions.toList(),
    );
    if (files.isEmpty) return null;

    final songs = <Song>[];
    for (final file in files) {
      final path = file.path;
      final extension = _extensionOf(file.name);
      if (path == null || !_audioExtensions.contains(extension)) continue;

      final dot = file.name.lastIndexOf('.');
      final title = (dot > 0 ? file.name.substring(0, dot) : file.name).trim();
      final id = 'local-${const Uuid().v4()}';
      try {
        final storedPath = await storage.storePickedAudio(path, file.name, id);
        if (storedPath == null) continue;
        songs.add(
          Song(
            id: id,
            title: title.isEmpty ? 'Unknown title' : title,
            artist: 'Local audio',
            localPath: storedPath,
            localSourcePath: path,
          ),
        );
      } catch (_) {
        // Skip unreadable files while still importing the remaining selections.
      }
    }
    return songs;
  }

  static String _extensionOf(String filename) {
    final dot = filename.lastIndexOf('.');
    return dot < 0 ? '' : filename.substring(dot + 1).toLowerCase();
  }
}
