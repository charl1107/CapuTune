import '../models/song.dart';
import 'discovery_service.dart';

/// Service providing related and similar tracks for recommendation / autoplay.
class RecommendationService {
  RecommendationService._();

  /// Finds suitable similar songs based on [seed] metadata (artist, genre/title keywords).
  /// Excludes any song IDs present in [excludedIds].
  static Future<List<Song>> findSimilarSongs({
    required Song seed,
    Set<String> excludedIds = const {},
    int limit = 10,
  }) async {
    final results = <Song>[];
    final seen = Set<String>.from(excludedIds)..add(seed.id);

    // 1. Primary candidate queries based on seed artist and title keywords
    final queries = <String>[];
    final cleanArtist = _cleanArtist(seed.artist);
    if (cleanArtist.isNotEmpty) {
      queries.add('$cleanArtist songs');
    }
    if (seed.album != null && seed.album!.trim().isNotEmpty) {
      queries.add('${seed.album} $cleanArtist');
    }
    final cleanTitle = _cleanTitle(seed.title);
    if (cleanTitle.isNotEmpty && cleanArtist.isNotEmpty) {
      queries.add('$cleanArtist $cleanTitle mix');
    }

    for (final q in queries) {
      if (results.length >= limit) break;
      final candidates = await DiscoveryService.search(q);
      for (final s in candidates) {
        if (!seen.contains(s.id)) {
          seen.add(s.id);
          results.add(s.copyWith(isRecommended: true));
          if (results.length >= limit) break;
        }
      }
    }

    return results;
  }

  static String _cleanArtist(String artist) {
    var a = artist.trim();
    // Strip common topic suffixes from YouTube Music (e.g. "Artist - Topic")
    a = a.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '');
    // Strip "VEVO"
    a = a.replaceAll(RegExp(r'VEVO$', caseSensitive: false), '');
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
}
