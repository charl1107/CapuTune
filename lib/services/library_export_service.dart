import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/song.dart';
import '../models/playlist.dart';
import 'storage_service.dart';

class LibraryExportService {
  static Future<bool> exportAndShare(BuildContext context) async {
    final now = DateTime.now().toUtc();
    final filename =
        'caputune_library_${now.toIso8601String().replaceAll(':', '-')}.json';
    final playlists = StorageService.getPlaylists();
    final export = {
      'format': 'caputune-library',
      'version': 1,
      'exportedAt': now.toIso8601String(),
      'playlists': playlists
          .map((playlist) => {
                'id': playlist.id,
                'name': playlist.name,
                'description': playlist.description,
                'createdAt': playlist.createdAt.toIso8601String(),
                'tracks': playlist.songs.map(_trackData).toList(),
              })
          .toList(),
    };
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(export)),
    );

    return _shareOrSave(context, filename, bytes);
  }

  /// Exports a single playlist in the same caputune-library format so it
  /// can be re-imported with the library import flow.
  static Future<bool> exportSinglePlaylist(
      BuildContext context, Playlist playlist) async {
    final now = DateTime.now().toUtc();
    final safeName = playlist.name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    final filename =
        'caputune_${safeName}_${now.toIso8601String().replaceAll(':', '-')}.json';
    final export = {
      'format': 'caputune-library',
      'version': 1,
      'exportedAt': now.toIso8601String(),
      'playlists': [
        {
          'id': playlist.id,
          'name': playlist.name,
          'description': playlist.description,
          'createdAt': playlist.createdAt.toIso8601String(),
          'tracks': playlist.songs.map(_trackData).toList(),
        }
      ],
    };
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(export)),
    );

    return _shareOrSave(context, filename, bytes);
  }

  /// M3U8 export for a single playlist — portable format compatible with
  /// most media players. Only contains metadata references, not audio files.
  static Future<bool> exportAsM3u8(
      BuildContext context, Playlist playlist) async {
    final safeName = playlist.name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    final filename = '$safeName.m3u8';
    final buffer = StringBuffer('#EXTM3U\n');
    buffer.writeln('#PLAYLIST:${playlist.name}');
    for (final song in playlist.songs) {
      final durationSecs = _parseDurationSeconds(song.duration);
      buffer.writeln('#EXTINF:$durationSecs,${song.artist} - ${song.title}');
      // Use YouTube URL as the reference since local paths are device-specific
      buffer.writeln('https://www.youtube.com/watch?v=${song.id}');
    }
    final bytes = Uint8List.fromList(utf8.encode(buffer.toString()));

    return _shareOrSave(context, filename, bytes, mimeType: 'audio/x-mpegurl');
  }

  static Future<bool> _shareOrSave(
    BuildContext context,
    String filename,
    Uint8List bytes, {
    String mimeType = 'application/json',
  }) async {
    // Resolve the share origin before any await so `context` is not used
    // across an async gap.
    final renderObject = context.findRenderObject();
    final sharePositionOrigin = renderObject is RenderBox
        ? renderObject.localToGlobal(Offset.zero) & renderObject.size
        : null;

    // Prefer the platform's own save dialog: on Android that is
    // ACTION_CREATE_DOCUMENT, on desktop a native file dialog, and on web a
    // download. A null result means the user cancelled, so it is reported as
    // "not exported" rather than silently falling through to sharing.
    try {
      final savedUri = await FilePicker.saveFile(
        dialogTitle: 'Save CapuTune export',
        fileName: filename,
        mimeType: mimeType,
        bytes: bytes,
      );
      return savedUri != null;
    } on UnimplementedError {
      // Some platforms (e.g. iOS) do not implement saveFile; fall back to the
      // share sheet below, which can also write into Files.
    } catch (_) {
      // Any other failure also falls back to the share sheet.
    }

    await SharePlus.instance.share(
      ShareParams(
        subject: 'CapuTune library',
        text: 'CapuTune playlist and track information',
        files: [
          XFile.fromData(
            bytes,
            mimeType: mimeType,
            name: filename,
          ),
        ],
        fileNameOverrides: [filename],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
    return true;
  }

  static int _parseDurationSeconds(String? duration) {
    if (duration == null) return -1;
    final parts = duration.split(':');
    if (parts.length == 2) {
      return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
    }
    if (parts.length == 3) {
      return (int.tryParse(parts[0]) ?? 0) * 3600 +
          (int.tryParse(parts[1]) ?? 0) * 60 +
          (int.tryParse(parts[2]) ?? 0);
    }
    return -1;
  }

  static Map<String, dynamic> _trackData(Song song) => {
        'id': song.id,
        'title': song.title,
        'artist': song.artist,
        'album': song.album,
        'duration': song.duration,
        'thumbnail': song.thumbnail,
        if (song.localPath != null) 'fileName': _fileName(song.localPath!),
      };

  static String _fileName(String path) =>
      path.replaceAll('\\', '/').split('/').last;
}
