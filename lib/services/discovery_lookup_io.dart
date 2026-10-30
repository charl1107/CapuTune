import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/song.dart';
import '../utils/search_ranking.dart';
import 'ytm/ytm_search_client.dart';

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

/// Injectable YTM client factory for tests: overrides every client the
/// lookup constructs. Null in production — real clients are used.
/// (Test-only by convention; not for app code.)
YtmSearchClient Function()? ytmClientFactoryForTest;

/// Searches YouTube Music's song catalog for [query] and returns the
/// results as [Song]s.
///
/// Two relevance layers sit on top of the raw catalog response:
///
/// 1. **Query expansion.** A bare genre word ("metal", "rock", ...) makes
///    the songs filter return popularity picks instead of the artists
///    named after the genre — a raw "metal" search contains no Metallica
///    at all. When YTM's search-suggestions endpoint (same Innertube
///    endpoint family, same credential-free client) turns the genre word
///    into artist-oriented queries ("metal" → "metallica"), those
///    suggestions are searched and merged after the raw rows.
/// 2. **Local ranking.** YTM orders rows by popularity, not textual
///    relevance ("nothing else" ranks a song literally titled "Nothing
///    Else" above Metallica's "Nothing Else Matters"). [rankTracks]
///    re-orders by title/artist match quality, best first.
///
/// The returned [Song.id] is the same YouTube videoId the existing
/// youtube_explode-based resolver already streams, so playback is
/// untouched.
///
/// Any failure (network, parsing, extraction) is swallowed and reported as
/// an empty list so callers never see an exception.
Future<List<Song>> searchRemote(String query) async {
  final raw = await searchRaw(query);
  return rankTracks(raw, query);
}

/// The unranked search pipeline: raw catalog rows for [query], merged with
/// genre-expansion results when [query] is a genre word the raw search
/// cannot match textually.
///
/// Exposed for tests and for callers that need the provider's own order
/// ([searchRemote] applies local ranking on top of this).
/// The client used for catalog and suggestion requests (test-overridable).
YtmSearchClient _ytmClient() => ytmClientFactoryForTest?.call() ?? YtmSearchClient();

Future<List<Song>> searchRaw(String query) async {
  try {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final client = _ytmClient();
    final rawResults = await client.searchSongs(trimmed);
    final results = rawResults.map(songFromYtm).toList();
    final seenIds = rawResults.map((r) => r.id).toSet();

    // Genre-word expansion: the songs filter answers bare genre words with
    // popularity picks (titles often *contain* the word — "Metal Health" —
    // while missing the artists named after the genre entirely), so textual
    // raw-row matches are NOT a reason to skip. Suggestions are always
    // tried for genre words; with none returned, no extra searches happen.
    if (_isGenreWord(trimmed)) {
      for (final song in await _searchViaSuggestions(trimmed)) {
        if (seenIds.add(song.id)) results.add(song);
      }
    }

    return results;
  } catch (_) {
    return [];
  }
}

/// Genre words where the YTM songs filter returns popularity picks instead
/// of the artists named after the genre.
const Set<String> _genreWords = {
  'metal', 'rock', 'pop', 'jazz', 'blues', 'rap', 'techno', 'punk', 'folk',
  'soul',
};

bool _isGenreWord(String query) => _genreWords.contains(query.toLowerCase());

/// Expands [genreQuery] through YTM's search-suggestions endpoint and
/// searches the top suggestions, returning their on-topic songs.
Future<List<Song>> _searchViaSuggestions(String genreQuery) async {
  final client = _ytmClient();
  final suggestions = await client.searchSuggestions(genreQuery);

  // Cap the expansion: two suggestion searches keep the worst-case latency
  // at three total round-trips while still surfacing the main artist(s).
  final extraQueries = suggestions.take(2).map((s) => s.text).toList();

  final expansion = <Song>[];
  for (final q in extraQueries) {
    try {
      var taken = 0;
      for (final r in await client.searchSongs(q)) {
        // The suggestion query itself is the relevance signal (YTM suggests
        // it in a search context, and the songs filter answers with the
        // most relevant songs for it) — rows are trusted and just capped,
        // since e.g. a "rock music" search legitimately returns songs whose
        // titles/artists never contain the word "rock".
        if (taken >= _maxRowsPerSuggestion) break;
        expansion.add(songFromYtm(r));
        taken++;
      }
    } catch (_) {
      // One failed suggestion round must not kill the others.
    }
  }
  return expansion;
}

/// Upper bound on rows merged per suggestion round.
const int _maxRowsPerSuggestion = 5;

/// Maps a [YtmSongResult] onto a [Song].
///
/// Internal to this lookup file: not re-exported by `discovery_service.dart`,
/// so only this module (and its test) can reach it.
Song songFromYtm(YtmSongResult r) {
  return Song(
    id: r.id,
    title: r.title,
    artist: r.artist,
    album: r.album,
    thumbnail: r.thumbnailUrl,
    duration: r.duration,
  );
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
