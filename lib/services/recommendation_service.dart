import '../models/song.dart';
import 'discovery_lookup_io.dart' show songFromYtm;
import 'discovery_service.dart';
import 'ytm/ytm_radio_client.dart';
import 'ytm/ytm_search_client.dart';

/// Service providing related and similar tracks for recommendation / autoplay.
class RecommendationService {
  RecommendationService._();

  /// Injectable radio fetch for tests: mirrors [YtmRadioClient]'s transport
  /// signature. Null in production — the real client is used.
  static YtmHttpFetch? radioFetchForTest;

  /// Injectable text-search fallback for tests: replaces the static
  /// [DiscoveryService.search] call. Null in production.
  static Future<List<Song>> Function(String query)? searchFallbackForTest;

  /// Finds suitable similar songs based on [seed].
  ///
  /// Primary source is YouTube Music's own song radio for the seed
  /// (`youtubei/v1/next`, playlistId `RD<videoId>`): the rows are the exact
  /// queue YTM itself plays on "Start radio", so genre coherence comes from
  /// the provider instead of guesswork (the old text queries
  /// `"$artist $title radio"` were popularity-ordered genre soup — a metal
  /// seed could surface Chris Brown). When the radio call yields nothing
  /// (offline, shape drift, invalid seed) the previous text-query pipeline
  /// runs as fallback so autoplay keeps working, just with weaker relevance.
  ///
  /// Excludes any song IDs present in [excludedIds]. [recentlyPlayed] rows
  /// are also excluded by id and by normalized title (radio often returns
  /// the seed's alternate uploads and previously heard versions).
  ///
  /// Guarantees (unchanged):
  /// - Deduplicates against seed song and already-selected songs.
  /// - Drops duplicate song versions (acoustic, lyric video, remixes).
  /// - Balances artist representation so recommendations remain varied.
  /// - Never invents tracks; returns only real provider results.
  /// - Never throws; a total failure degrades to `[]`.
  static Future<List<Song>> findSimilarSongs({
    required Song seed,
    Set<String> excludedIds = const {},
    int limit = 10,
    List<Song> recentlyPlayed = const [],
  }) async {
    final seenIds = Set<String>.from(excludedIds)..add(seed.id);
    final seenNormalizedTitles = <String>{_normalizeTitle(seed.title)};
    for (final s in recentlyPlayed) {
      seenIds.add(s.id);
      seenNormalizedTitles.add(_normalizeTitle(s.title));
    }

    // 1) Song radio — the provider's own related-track queue.
    final radio = await _songRadioCandidates(seed);
    final fromRadio = _assemble(
      radio,
      seed: seed,
      limit: limit,
      seenIds: seenIds,
      seenNormalizedTitles: seenNormalizedTitles,
    );
    if (fromRadio.length >= limit) return fromRadio;

    // 2) Fallback: the legacy text-query pipeline fills whatever the radio
    // could not provide (e.g. radio returned 3 rows of 10).
    final fallbackSearch = searchFallbackForTest ?? DiscoveryService.search;
    final queries = _fallbackQueries(seed);
    for (final q in queries) {
      try {
        final candidates = await fallbackSearch(q);
        final filled = _assemble(
          candidates,
          seed: seed,
          limit: limit,
          seenIds: seenIds,
          seenNormalizedTitles: seenNormalizedTitles,
          cap: limit * 2 - fromRadio.length,
        );
        fromRadio.addAll(filled);
      } catch (_) {
        // Handle network drops or limited catalogs gracefully
      }
      if (fromRadio.length >= limit) break;
    }

    return fromRadio.take(limit).toList();
  }

  /// Song-radio rows for [seed], seed itself removed. `[]` on any failure.
  static Future<List<Song>> _songRadioCandidates(Song seed) async {
    try {
      final client = YtmRadioClient(fetch: radioFetchForTest);
      final rows = await client.getRadio(seed.id);
      if (rows.isEmpty) return [];
      final songs = rows.map(songFromYtm).toList();

      // Drop the seed itself, including alternate uploads of the same song
      // (the radio's first row frequently carries a different videoId).
      final seedTitle = _normalizeTitle(seed.title);
      final seedArtist = _cleanArtist(seed.artist).toLowerCase();
      return songs.where((s) {
        if (s.id == seed.id) return false;
        if (_normalizeTitle(s.title) == seedTitle) return false;
        // Same-artist + same-title rows under another id are the seed too.
        final artist = _cleanArtist(s.artist).toLowerCase();
        if (artist == seedArtist &&
            artist.isNotEmpty &&
            _normalizeTitle(s.title) == seedTitle) {
          return false;
        }
        return true;
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Filters/dedupes [candidates] into recommended [Song]s, respecting
  /// [limit], the seen-sets, and the artist-diversity guard. Returns at most
  /// [cap] rows (defaults to [limit]).
  static List<Song> _assemble(
    List<Song> candidates, {
    required Song seed,
    required int limit,
    required Set<String> seenIds,
    required Set<String> seenNormalizedTitles,
    int? cap,
  }) {
    final out = <Song>[];
    final artistCount = <String, int>{};
    final effectiveCap = cap ?? limit;
    for (final s in candidates) {
      if (out.length >= effectiveCap) break;
      if (seenIds.contains(s.id)) continue;
      final normTitle = _normalizeTitle(s.title);
      if (seenNormalizedTitles.contains(normTitle)) continue;

      // Diversity guard: avoid overloading with the exact same artist
      // if we already have sufficient diversity
      final normArtist = s.artist.trim().toLowerCase();
      final count = artistCount[normArtist] ?? 0;
      if (count >= 3 && out.length >= limit) continue;

      seenIds.add(s.id);
      seenNormalizedTitles.add(normTitle);
      artistCount[normArtist] = count + 1;
      out.add(s.copyWith(isRecommended: true));
    }
    return out;
  }

  /// The legacy text queries, used only when the radio path came up short.
  static List<String> _fallbackQueries(Song seed) {
    final cleanArtist = _cleanArtist(seed.artist);
    final cleanTitle = _cleanTitle(seed.title);
    final queries = <String>[];
    if (cleanArtist.isNotEmpty && cleanTitle.isNotEmpty) {
      queries.add('$cleanArtist $cleanTitle radio');
      queries.add('$cleanArtist mix');
    }
    if (cleanArtist.isNotEmpty) {
      queries.add('$cleanArtist songs');
    }
    if (seed.album != null &&
        seed.album!.trim().isNotEmpty &&
        cleanArtist.isNotEmpty) {
      queries.add('${seed.album} $cleanArtist');
    }
    return queries;
  }

  static String _cleanArtist(String artist) {
    var a = artist.trim();
    // Strip common topic suffixes from YouTube Music (e.g. "Artist - Topic")
    a = a.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '');
    // Strip "VEVO"
    a = a.replaceAll(RegExp(r'VEVO$', caseSensitive: false), '');
    a = a.replaceAll(RegExp(r'\s*Official$', caseSensitive: false), '');
    return a.trim();
  }

  static String _cleanTitle(String title) {
    var t = title.trim();
    // Strip (Official Music Video), [Lyric Video], etc.
    t = t.replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '');
    t = t.replaceAll(RegExp(r'\s*ft\.?\s*.*$', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\s*feat\.?\s*.*$', caseSensitive: false), '');
    return t.trim();
  }

  static String _normalizeTitle(String title) {
    var t = _cleanTitle(title).toLowerCase();
    t = t.replaceAll(RegExp(r'[^a-z0-9]'), '');
    return t.trim();
  }
}
