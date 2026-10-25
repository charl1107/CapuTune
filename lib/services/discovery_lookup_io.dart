import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/song.dart';

// Re-exported so `discovery_service_test.dart` can construct a `Video` for
// the mapping test without importing `youtube_explode_dart` itself: the
// package may only be imported by this file (web-build safety).
export 'package:youtube_explode_dart/youtube_explode_dart.dart'
    show Video, VideoId, ChannelId, ThumbnailSet, Engagement;

/// Formats [d] as `m:ss`, or `h:mm:ss` when the duration is an hour or
/// longer. Returns null when [d] is null.
///
/// In the `m:ss` form minutes are unpadded and seconds are zero-padded
/// (`215s` -> `3:35`, `59s` -> `0:59`); in the `h:mm:ss` form both minutes
/// and seconds are zero-padded (`1h2m3s` -> `1:02:03`).
String? formatDuration(Duration? d) {
  if (d == null) return null;
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
  }
  return '$minutes:$ss';
}

/// Maps a [Video] to a [Song].
///
/// Internal to this lookup file: not re-exported by `discovery_service.dart`,
/// so only this module (and its test) can reach it.
Song songFromVideo(Video v) {
  return Song(
    id: v.id.value,
    title: v.title,
    artist: v.author,
    thumbnail: v.thumbnails.maxResUrl,
    duration: formatDuration(v.duration),
  );
}

/// Extracts the `list=` query parameter from a YouTube playlist [url].
/// Returns null when the url carries no playlist id.
String? _extractPlaylistId(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  return uri.queryParameters['list'];
}

/// Searches YouTube for [query] and returns the results as [Song]s.
///
/// Any failure (network, parsing, extraction) is swallowed and reported as
/// an empty list so callers never see an exception.
Future<List<Song>> searchRemote(String query) async {
  try {
    final yt = YoutubeExplode();
    try {
      final videos = await yt.search.search(query);
      return videos.map(songFromVideo).toList();
    } finally {
      yt.close();
    }
  } catch (_) {
    return [];
  }
}

/// Imports the videos of the YouTube playlist at [url] as [Song]s.
///
/// The playlist id is read from the `list=` query parameter; a url without
/// one, an invalid url, or any fetch failure yields an empty list.
Future<List<Song>> importPlaylistRemote(String url) async {
  try {
    final id = _extractPlaylistId(url);
    if (id == null || id.isEmpty) return [];
    final yt = YoutubeExplode();
    try {
      final videos = await yt.playlists.getVideos(id).toList();
      return videos.map(songFromVideo).toList();
    } finally {
      yt.close();
    }
  } catch (_) {
    return [];
  }
}
