import '../models/song.dart';
import 'discovery_service.dart';

/// Service providing related and similar tracks for recommendation / autoplay.
class RecommendationService {
  RecommendationService._();

  /// Finds suitable similar songs based on [seed] metadata (artist, genre/title keywords).
  /// Excludes any song IDs present in [excludedIds].
  ///
  /// Guarantees:
  /// - Deduplicates against seed song and already-selected songs.
  /// - Drops duplicate song versions (acoustic, lyric video, remixes).
  /// - Balances artist representation so recommendations remain varied.
  /// - Shuffles candidate pool to avoid repetitive fixed-order lists.
  /// - Never invents tracks; returns only real discovery results.
  static Future<List<Song>> findSimilarSongs({
    required Song seed,
    Set<String> excludedIds = const {},
    int limit = 10,
  }) async {
    final seenIds = Set<String>.from(excludedIds)..add(seed.id);
    final seenNormalizedTitles = <String>{_normalizeTitle(seed.title)};

    final cleanArtist = _cleanArtist(seed.artist);
    final cleanTitle = _cleanTitle(seed.title);

    // Formulate diverse relevance queries:
    // 1. Radio / mix based on song title & artist
    // 2. Mix based on artist
    // 3. Album / collection search if available
    // 4. Related artist & catalog tracks
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

    final candidatePool = <Song>[];
    final artistCount = <String, int>{};

    for (final q in queries) {
      try {
        final candidates = await DiscoveryService.search(q);
        for (final s in candidates) {
          if (seenIds.contains(s.id)) continue;
          final normTitle = _normalizeTitle(s.title);
          if (seenNormalizedTitles.contains(normTitle)) continue;

          // Diversity guard: avoid overloading with the exact same artist
          // if we already have sufficient diversity
          final normArtist = s.artist.trim().toLowerCase();
          final count = artistCount[normArtist] ?? 0;
          if (count >= 3 && candidatePool.length >= limit) continue;

          seenIds.add(s.id);
          seenNormalizedTitles.add(normTitle);
          artistCount[normArtist] = count + 1;
          candidatePool.add(s.copyWith(isRecommended: true));

          if (candidatePool.length >= limit * 2) break;
        }
      } catch (_) {
        // Handle network drops or limited catalogs gracefully
      }
      if (candidatePool.length >= limit * 2) break;
    }

    if (candidatePool.isEmpty) return [];

    // Shuffle recommendation order without losing relevance
    candidatePool.shuffle();

    return candidatePool.take(limit).toList();
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
