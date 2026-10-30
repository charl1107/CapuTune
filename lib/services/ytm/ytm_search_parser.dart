// YouTube Music search response parser.
//
// Adapted from ytmusicapi (https://github.com/sigma67/ytmusicapi),
// MIT License — Copyright (c) sigma67. Specifically: `navigation.py:nav`,
// `parsers/_utils.py` flex-column helpers, and `parsers/songs.py`
// (`parse_song_run` / `parse_song_runs`), reduced to the subset needed to
// read songs out of a songs-filter search response. Only the structural
// parsing was ported; upstream's i18n, auth, and non-song result types
// were deliberately left out.
//
// This file is intentionally pure Dart (no Flutter imports) so it can be
// unit-tested and smoke-tested without a widget environment.
library;

import '../../utils/search_ranking.dart' show RankableTrack;

/// One song-shaped search result, before mapping onto the app's [Song] model.
///
/// Parsed defensively: every field except [id] and [title] may be null when
/// the response omits it.
class YtmSongResult implements RankableTrack {
  final String id;
  @override
  final String title;
  @override
  final String artist;
  @override
  final String? album;
  final String? duration;
  final String? thumbnailUrl;

  const YtmSongResult({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.duration,
    this.thumbnailUrl,
  });
}

/// One parsed search suggestion: the suggested query text and the span
/// that should be highlighted (null = whole suggestion).
class YtmSearchSuggestion {
  final String text;

  /// The substring of [text] YTM marks as the typed part, or null when the
  /// response carries no explicit highlight.
  final String? highlight;

  const YtmSearchSuggestion({required this.text, this.highlight});
}

/// Reads `path` out of a decoded Innertube response, returning null as soon
/// as any segment is missing or has the wrong type.
///
/// Port of ytmusicapi's `navigation.nav` with `none_if_absent` semantics
/// (this parser never navigates into required paths, so the throwing mode
/// is not needed).
dynamic nav(dynamic root, List<Object> path) {
  var node = root;
  for (final key in path) {
    if (node is Map) {
      node = node[key];
    } else if (node is List && key is int) {
      if (key < 0 || key >= node.length) return null;
      node = node[key];
    } else {
      return null;
    }
  }
  return node;
}

/// The path from a search response root to the list of result sections.
const List<Object> _sectionListPath = [
  'contents',
  'tabbedSearchResultsRenderer',
  'tabs',
  0,
  'tabRenderer',
  'content',
  'sectionListRenderer',
  'contents',
];

/// Extracts every song from a decoded YouTube Music search response.
///
/// Expects the response the songs filter produces (a `musicShelfRenderer`
/// full of `musicResponsiveListItemRenderer` rows); `itemSectionRenderer`
/// rows are walked too so a filter regression degrades to "fewer songs"
/// instead of "no results". Non-song rows — artists, albums, playlists,
/// podcasts, greyed-out items, anything without a playable videoId — are
/// excluded. Never throws on malformed input; unknown shapes yield `[]`.
List<YtmSongResult> parseYtmSongs(dynamic decoded) {
  final sections = nav(decoded, _sectionListPath);
  if (sections is! List) return [];
  final results = <YtmSongResult>[];
  for (final section in sections) {
    if (section is! Map) continue;
    for (final shelfKey in const [
      'musicShelfRenderer',
      'itemSectionRenderer'
    ]) {
      final shelf = section[shelfKey];
      if (shelf is! Map) continue;
      final rows = shelf['contents'];
      if (rows is! List) continue;
      for (final row in rows) {
        if (row is! Map) continue;
        final item = row['musicResponsiveListItemRenderer'];
        if (item is! Map) continue;
        final song = _parseSongItem(item);
        if (song != null) results.add(song);
      }
    }
  }
  return results;
}

/// Flex-column renderer key wrapping each line of a list item.
const String _flexColumnKey = 'musicResponsiveListItemFlexColumnRenderer';

/// Grey-out policy marking an item as unplayable in the current region.
const String _greyOutPolicy = 'MUSIC_ITEM_RENDERER_DISPLAY_POLICY_GREY_OUT';

/// Parses one `musicResponsiveListItemRenderer` into a [YtmSongResult],
/// or null when the row is not a playable song.
YtmSongResult? _parseSongItem(Map item) {
  if (item['musicItemRendererDisplayPolicy'] == _greyOutPolicy) return null;

  // The play overlay is the only place a row reliably carries the videoId
  // a tap will actually stream; rows for artists/albums/playlists lack it.
  final videoId = nav(item, [
    'overlay',
    'musicItemThumbnailOverlayRenderer',
    'content',
    'musicPlayButtonRenderer',
    'playNavigationEndpoint',
    'watchEndpoint',
    'videoId',
  ]);
  if (videoId is! String || videoId.isEmpty) return null;

  // Podcast episodes carry a videoId but no music catalog; with the songs
  // filter this never appears, keep it as a shape-drift guard.
  final videoType = nav(item, [
    'overlay',
    'musicItemThumbnailOverlayRenderer',
    'content',
    'musicPlayButtonRenderer',
    'playNavigationEndpoint',
    'watchEndpoint',
    'watchEndpointMusicSupportedConfigs',
    'watchEndpointMusicConfig',
    'musicVideoType',
  ]);
  if (videoType == 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE') return null;

  final columns = item['flexColumns'];
  if (columns is! List || columns.isEmpty) return null;
  final title = _firstRunText(columns[0]);
  if (title == null || title.isEmpty) return null;

  String? artist;
  String? album;
  String? duration;
  if (columns.length > 1) {
    final parsed = _parseSongRuns(_columnRuns(columns[1]));
    final artists = parsed['artists'];
    artist = artists is List && artists.isNotEmpty ? artists.join(', ') : null;
    album = parsed['album'] as String?;
    duration = parsed['duration'] as String?;
  }

  return YtmSongResult(
    id: videoId,
    title: title,
    artist: artist ?? '',
    album: album,
    duration: duration,
    thumbnailUrl: _bestThumbnailUrl(item['thumbnail']),
  );
}

/// Extracts query suggestions from `music/get_search_suggestions`
/// responses. Returns `[]` for any malformed shape; only rows with
/// non-empty suggestion text are kept.
List<YtmSearchSuggestion> parseYtmSearchSuggestions(dynamic decoded) {
  final contents = nav(decoded, ['contents']);
  if (contents is! List) return [];
  final out = <YtmSearchSuggestion>[];
  for (final entry in contents) {
    final renderer = entry is Map ? entry['searchSuggestionRenderer'] : null;
    if (renderer is! Map) continue;
    final suggestion = renderer['suggestion'];
    if (suggestion is! Map) continue;
    final runs = suggestion['runs'];
    String? text;
    String? highlight;
    if (runs is List) {
      final buffer = StringBuffer();
      final highlightBuffer = StringBuffer();
      for (final run in runs) {
        if (run is! Map) continue;
        final t = run['text'];
        if (t is! String) continue;
        buffer.write(t);
        if (run['bold'] == true) highlightBuffer.write(t);
      }
      text = buffer.toString();
      if (highlightBuffer.isNotEmpty) highlight = highlightBuffer.toString();
    } else if (suggestion['text'] is String) {
      text = suggestion['text'] as String;
    }
    if (text == null || text.trim().isEmpty) continue;
    out.add(
      YtmSearchSuggestion(text: text.trim(), highlight: highlight?.trim()),
    );
  }
  return out;
}

/// First run text of flex column [index]; null when absent or empty.
String? _firstRunText(dynamic column) {
  final runs = _columnRuns(column);
  if (runs.isEmpty) return null;
  final text = (runs.first as Map?)?['text'];
  return text is String && text.isNotEmpty ? text : null;
}

/// The text runs of a flex column, or `[]` for any malformed shape.
List<dynamic> _columnRuns(dynamic column) {
  if (column is! Map) return [];
  final renderer = column[_flexColumnKey];
  if (renderer is! Map) return [];
  final text = renderer['text'];
  if (text is! Map) return [];
  final runs = text['runs'];
  return runs is List ? runs : [];
}

/// Dot separator between runs ("Oasis • Album • 4:19").
const String _dotSeparator = ' \u2022 ';

/// Duration patterns accepted as `m:ss` / `h:mm:ss` (upstream's regex).
final RegExp _durationPattern = RegExp(r'^(\d+:)*\d+:\d+$');

/// Classifies one text run: ('artist'|'album'|'duration', text, browseId).
///
/// Runs carrying a `navigationEndpoint` resolve to an album when their
/// browseId is an MPRE release id, otherwise an artist; bare runs are
/// durations when they match `m:ss`, and anything else (views, year, an
/// artist YouTube gave no id for) is conservatively treated as an artist
/// name, mirroring upstream's fallback.
(String, String?, String?) _classifyRun(Map run) {
  final text = run['text'];
  final endpoint = run['navigationEndpoint'];
  if (endpoint is Map) {
    final browseId = nav(endpoint, ['browseEndpoint', 'browseId']);
    final id = browseId is String ? browseId : null;
    if (id != null &&
        (id.startsWith('MPRE') || id.contains('release_detail'))) {
      return ('album', text, id);
    }
    return ('artist', text, id);
  }
  if (text is String && _durationPattern.hasMatch(text)) {
    return ('duration', text, null);
  }
  return ('artist', text is String && text.isNotEmpty ? text : null, null);
}

/// Parses the subtitle runs of a song row into artist names, album title,
/// and duration text.
///
/// Port of ytmusicapi's `parsers/songs.py:parse_song_runs` (without the
/// views/year bookkeeping the Song model does not carry). Uneven runs are
/// always " • " separators; a leading unlinked run like "Song" before the
/// separator is a type specifier and is skipped so it is never mistaken
/// for an artist.
Map<String, Object?> _parseSongRuns(List runs) {
  if (runs.length > 2 &&
      _classifyRun(runs[0] as Map? ?? const {}).$1 == 'artist' &&
      (runs[1] as Map?)?['text'] == _dotSeparator) {
    final third = runs[2] as Map?;
    final kind = third == null ? 'artist' : _classifyRun(third).$1;
    if (kind != 'album') runs = runs.sublist(2);
  }

  final artists = <String>[];
  String? album;
  String? duration;
  for (var i = 0; i < runs.length; i += 2) {
    final run = runs[i];
    if (run is! Map) continue;
    final (kind, name, _) = _classifyRun(run);
    switch (kind) {
      case 'album':
        album = name;
      case 'artist':
        if (name != null) artists.add(name);
      case 'duration':
        duration = name;
    }
  }
  return {'artists': artists, 'album': album, 'duration': duration};
}

/// Picks the largest thumbnail URL from a row's `musicThumbnailRenderer`,
/// or null when absent. Thumbnails are listed smallest-first; the last
/// entry is the highest resolution available.
String? _bestThumbnailUrl(dynamic thumbnail) {
  final thumbnails = nav(
    thumbnail,
    ['musicThumbnailRenderer', 'thumbnail', 'thumbnails'],
  );
  if (thumbnails is! List || thumbnails.isEmpty) return null;
  for (final entry in thumbnails.reversed) {
    final url = entry is Map ? entry['url'] : null;
    if (url is String && url.isNotEmpty) return url;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Song radio (`youtubei/v1/next` with playlistId RD<videoId>)
// ---------------------------------------------------------------------------

/// Navigational path to the radio queue rows.
const List<String> _radioQueuePath = [
  'contents',
  'singleColumnMusicWatchNextResultsRenderer',
  'tabbedRenderer',
  'watchNextTabbedResultsRenderer',
  'tabs',
];

/// Parses a song-radio `next` response into queue rows, seed song included.
///
/// The queue lives in the first (watch-next) tab's `musicQueueRenderer`;
/// the "Related" tab is frequently empty in these responses and is not
/// consulted. Rows arrive as `playlistPanelVideoRenderer` maps, which carry
/// the same run structure the search parser already reads, so artist/album/
/// duration extraction is delegated to [_parseSongRuns]. Returns `[]` for
/// any malformed shape, including the "shell" response an invalid videoId
/// produces (no `musicQueueRenderer.content` at all).
List<YtmSongResult> parseYtmRadioSongs(dynamic decoded) {
  final tabs = nav(decoded, _radioQueuePath);
  if (tabs is! List) return [];
  for (final tab in tabs) {
    final content = nav(tab, [
      'tabRenderer',
      'content',
      'musicQueueRenderer',
      'content',
      'playlistPanelRenderer',
      'contents',
    ]);
    if (content is! List) continue;
    final results = <YtmSongResult>[];
    for (final row in content) {
      final renderer = row is Map ? row['playlistPanelVideoRenderer'] : null;
      if (renderer is! Map) continue;
      final song = _parseRadioRow(renderer);
      if (song != null) results.add(song);
    }
    // The watch-next tab is the first one carrying a queue; once found and
    // parsed, later tabs (Related etc.) are irrelevant.
    return results;
  }
  return [];
}

/// Parses one `playlistPanelVideoRenderer` into a [YtmSongResult], or null
/// when the row lacks an id or title (ads, uninitialized placeholders).
YtmSongResult? _parseRadioRow(Map renderer) {
  final videoId = renderer['videoId'];
  if (videoId is! String || videoId.isEmpty) return null;

  final titleMap = renderer['title'];
  String? title;
  if (titleMap is Map) {
    for (final run in _runsOf(titleMap)) {
      final text = run is Map ? run['text'] : null;
      if (text is String && text.isNotEmpty) {
        title = text;
        break;
      }
    }
  }
  if (title == null || title.isEmpty) return null;

  String? artist;
  String? album;
  String? duration;
  final byline = renderer['longBylineText'];
  if (byline is Map) {
    final parsed = _parseRadioByline(_runsOf(byline));
    final artists = parsed['artists'];
    artist = artists is List && artists.isNotEmpty ? artists.join(', ') : null;
    album = parsed['album'] as String?;
    duration = parsed['duration'] as String?;
  }
  // Radio rows carry the duration in a dedicated `lengthText` field rather
  // than inside the byline.
  if (duration == null) {
    final lengthText = renderer['lengthText'];
    if (lengthText is Map) {
      for (final run in _runsOf(lengthText)) {
        final text = run is Map ? run['text'] : null;
        if (text is String && text.isNotEmpty) {
          duration = text;
          break;
        }
      }
    }
  }

  return YtmSongResult(
    id: videoId,
    title: title,
    artist: artist ?? '',
    album: album,
    duration: duration,
    thumbnailUrl: _bestThumbnailUrl(renderer['thumbnail']),
  );
}

/// The text runs of any `{runs: [...]}` map (title, byline), or `[]`.
List<dynamic> _runsOf(Map textMap) {
  final runs = textMap['runs'];
  return runs is List ? runs : [];
}

/// Parses the `longBylineText` runs of a radio row: "artist • album • 4:19"
/// (often with a bare 4-digit year between album and duration) with artists
/// linked (carrying a navigationEndpoint) and everything else classified
/// like search rows. Unlike search bylines, radio bylines have no leading
/// "Song" type specifier, so the shared search-runs parser would drop the
/// first artist — hence this dedicated walker.
Map<String, Object?> _parseRadioByline(List runs) {
  final artists = <String>[];
  String? album;
  String? duration;
  for (final run in runs) {
    if (run is! Map) continue;
    final (kind, name, _) = _classifyRun(run);
    switch (kind) {
      case 'album':
        album = name;
      case 'artist':
        // Separator runs (" • ") fall through _classifyRun to the artist
        // fallback; a bare separator text is never a name. Bare 4-digit
        // runs are release years, not artist names.
        final text = run['text'];
        if (name != null &&
            text != _dotSeparator &&
            !_yearPattern.hasMatch(name)) {
          artists.add(name);
        }
      case 'duration':
        duration = name;
    }
  }
  return {'artists': artists, 'album': album, 'duration': duration};
}

/// Bare 4-digit release years in radio bylines (" • 1991 • ").
final RegExp _yearPattern = RegExp(r'^\d{4}$');
