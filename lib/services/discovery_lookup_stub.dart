import '../models/song.dart';

/// Web implementation of the discovery lookups.
///
/// `youtube_explode_dart` is not web-safe, so the real lookups live in
/// `discovery_lookup_io.dart` and are pulled in via conditional import on
/// `dart.library.io`. On the web this stub is used instead and always
/// reports that nothing was found.
Future<List<Song>> searchRemote(String query) async => [];

/// Web/non-IO variant with the failure signal: the web build never
/// searches, which is reported as a successful-but-empty answer.
Future<(List<Song>, bool)> searchRemoteDetailed(String query) async =>
    (<Song>[], false);

/// Web stub: playlist import is unsupported on the web; always empty.
Future<List<Song>> importPlaylistRemote(String url) async => [];
