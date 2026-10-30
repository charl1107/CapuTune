/// Local relevance ranking for search results.
///
/// The YouTube Music songs-filter returns popularity-ordered rows that do
/// not necessarily reflect textual relevance ("nothing else" ranks a song
/// literally titled "Nothing Else" above "Nothing Else Matters"; "metal"
/// returns genre picks with no Metallica at all). This module re-orders a
/// result list by how well each row's title/artist/album matches the query,
/// so exact and partial title matches surface before tangential results.
///
/// Pure Dart: no Flutter imports, unit-testable without a widget env.
library;

/// A ranked search candidate: anything carrying a title, artist, album.
///
/// Structurally satisfied by both `Song` and `YtmSongResult`; declared as a
/// lightweight interface so the ranker needs no model imports.
abstract interface class RankableTrack {
  String get title;
  String get artist;
  String? get album;
}

/// Ranking tiers, ordered best-first. Exported so tests can pin the
/// ordering contract precisely.
enum MatchTier {
  /// Title equals the query ("enter sandman" == "Enter Sandman").
  exactTitle,

  /// Title starts with the query ("enter s" → "Enter Sandman").
  titlePrefix,

  /// Title contains the query as a word ("nothing else" inside
  /// "Nothing Else Matters").
  titleWordContains,

  /// Title contains the query as a substring ("met" inside "Metallica").
  titleContains,

  /// Artist equals the query ("metallica" == "Metallica").
  exactArtist,

  /// Query is a word inside the artist name ("metallica" inside
  /// "Metallica - Topic").
  artistWordContains,

  /// Album or remaining metadata matches; weakest textual signal.
  metadata,

  /// No textual match at all (popularity-only row).
  none,
}

/// Lowercase, trim, collapse whitespace, drop punctuation.
///
/// "  Nothing   Else-Matters! " → "nothing else matters". Apostrophes are
/// removed only when surrounded by letters ("don't" → "dont"), so a
/// standalone quote never splits words unexpectedly.
String normalizeForMatch(String input) {
  var s = input.trim().toLowerCase();
  // Drop apostrophes between letters ("don't" → "dont"), so a query typed
  // without the apostrophe still matches a title that has it. (Capture-group
  // replace: Dart's RegExp has no lookbehind.)
  s = s.replaceAllMapped(
    RegExp(r'(\p{L})[\u0027\u2019\u02BC](?=\p{L})', unicode: true),
    (m) => m[1]!,
  );
  s = s.replaceAll(RegExp(r"[\p{P}\p{S}]", unicode: true), ' ');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// The significant words of [input] after normalization. A word only counts
/// when it has at least 2 characters — single letters ("a", "i") are noise
/// for matching purposes.
List<String> wordsForMatch(String input) => normalizeForMatch(input)
    .split(' ')
    .where((w) => w.length >= 2)
    .toList();

/// Classifies how well [track] matches the normalized [query].
///
/// [queryWords] is the pre-split word list of the query; pass it when
/// ranking many tracks against the same query to avoid re-splitting.
MatchTier classifyMatch(
  RankableTrack track,
  String normalizedQuery,
  List<String> queryWords,
) {
  if (normalizedQuery.isEmpty) return MatchTier.none;

  final title = normalizeForMatch(track.title);
  final artist = normalizeForMatch(track.artist);
  final album = track.album == null ? '' : normalizeForMatch(track.album!);

  // A multi-word query only counts as a prefix/containment when EVERY word
  // is present, so "nothing else" matches "Nothing Else Matters" but not
  // "Nothing But Trouble".
  if (title == normalizedQuery) return MatchTier.exactTitle;
  if (title.startsWith('$normalizedQuery ')) {
    return MatchTier.titlePrefix;
  }
  if (queryWords.length > 1 && queryWords.every(title.contains)) {
    return MatchTier.titleWordContains;
  }
  if (queryWords.length == 1 && title.contains(normalizedQuery)) {
    return MatchTier.titleContains;
  }

  if (artist == normalizedQuery) return MatchTier.exactArtist;
  // Single-word queries also rank a plain substring hit on the artist
  // ("metalica" typo → "Metallica", or a "Metallica - Topic" channel name).
  if (queryWords.length == 1 && artist.contains(normalizedQuery)) {
    return MatchTier.artistWordContains;
  }
  if (queryWords.every(artist.contains) || queryWords.every(album.contains)) {
    return MatchTier.metadata;
  }

  return MatchTier.none;
}

/// Stable relevance rank for sorting: lower is better.
int tierRank(MatchTier tier) => tier.index;

/// Ranks [tracks] against [query], best matches first.
///
/// Ties keep the provider's original relative order (popularity signal)
/// via [List.sort]'s stability guarantee. Rows with no textual match keep
/// their original order after every matching row.
List<T> rankTracks<T extends RankableTrack>(List<T> tracks, String query) {
  final normalizedQuery = normalizeForMatch(query);
  final queryWords = wordsForMatch(query);
  final ranked = List<T>.of(tracks);
  ranked.sort((a, b) {
    final ra = tierRank(classifyMatch(a, normalizedQuery, queryWords));
    final rb = tierRank(classifyMatch(b, normalizedQuery, queryWords));
    return ra.compareTo(rb);
  });
  return ranked;
}
