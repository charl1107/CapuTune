// Tests for RecommendationService's song-radio pipeline.
//
// The service must prefer YTM's own song radio (genre-coherent, verified
// live: a Metallica seed returns Metallica/Scorpions/GnR/Linkin Park, no
// pop pollution), fall back to the legacy text-query search when the radio
// path yields nothing, and never duplicate the seed or recently played
// tracks. DiscoveryService and the radio transport are mocked, so nothing
// here touches the network.
import 'package:caputune/models/song.dart';
import 'package:caputune/services/recommendation_service.dart';
import 'package:caputune/services/ytm/ytm_search_client.dart';
import 'package:flutter_test/flutter_test.dart';

Song _song(String id, String title, String artist, {String? album}) =>
    Song(id: id, title: title, artist: artist, album: album, thumbnail: null);

/// Stubs the text-query fallback path.
void _fakeFallback(Map<String, List<Song>> responses, {List<String>? log}) {
  RecommendationService.searchFallbackForTest = (query) async {
    log?.add(query);
    return responses[query] ?? const <Song>[];
  };
}

/// Builds a fake radio transport returning [rows] for any seed.
YtmHttpFetch _radioTransport(List<Map<String, dynamic>> rows) {
  return (url, body) async => {
        'contents': {
          'singleColumnMusicWatchNextResultsRenderer': {
            'tabbedRenderer': {
              'watchNextTabbedResultsRenderer': {
                'tabs': [
                  {
                    'tabRenderer': {
                      'content': {
                        'musicQueueRenderer': {
                          'content': {
                            'playlistPanelRenderer': {
                              'contents': [
                                for (final r in rows)
                                  {'playlistPanelVideoRenderer': r},
                              ],
                            },
                          },
                        },
                      },
                    },
                  },
                ],
              },
            },
          },
        },
      };
}

Map<String, dynamic> _radioRow(String id, String title, String artist) => {
      'videoId': id,
      'title': {
        'runs': [
          {'text': title},
        ],
      },
      'longBylineText': {
        'runs': [
          {'text': artist, 'navigationEndpoint': {}},
        ],
      },
    };

void main() {
  setUp(() {
    RecommendationService.radioFetchForTest = null;
    // Inert fallback by default: radio tests assert radio rows only, and no
    // test here may touch the real network.
    RecommendationService.searchFallbackForTest = (_) async => const [];
  });

  tearDown(() {
    RecommendationService.radioFetchForTest = null;
    RecommendationService.searchFallbackForTest = null;
  });

  group('radio path', () {
    test('prefers song-radio rows for the seed', () async {
      RecommendationService.radioFetchForTest = _radioTransport([
        _radioRow('r1', 'Rock You Like a Hurricane', 'Scorpions'),
        _radioRow('r2', 'Welcome to the Jungle', 'Guns N\u2019 Roses'),
        _radioRow('r3', 'Numb', 'Linkin Park'),
      ]);

      final recs = await RecommendationService.findSimilarSongs(
        seed: _song('seed', 'Enter Sandman', 'Metallica'),
        limit: 10,
      );

      expect(recs.map((s) => s.id), ['r1', 'r2', 'r3']);
      expect(recs.every((s) => s.isRecommended), isTrue);
      // No text-query fallback calls needed.
    });

    test('excludes the seed, including alternate uploads', () async {
      // Live behavior: the radio's first row is often the seed song under a
      // different videoId.
      RecommendationService.radioFetchForTest = _radioTransport([
        _radioRow('alt', 'Enter Sandman', 'Metallica'),
        _radioRow('same-id', 'Enter Sandman', 'Metallica'),
        _radioRow('r1', 'Other Song', 'Someone'),
      ]);

      final recs = await RecommendationService.findSimilarSongs(
        seed: _song('seed', 'Enter Sandman', 'Metallica'),
        limit: 10,
      );

      expect(recs.map((s) => s.id), ['r1']);
    });

    test('dedupes duplicate versions within the radio rows', () async {
      RecommendationService.radioFetchForTest = _radioTransport([
        _radioRow('r1', 'Numb', 'Linkin Park'),
        _radioRow('r1x', 'Numb (Official Video)', 'Linkin Park'),
        _radioRow('r2', 'In The End', 'Linkin Park'),
      ]);

      final recs = await RecommendationService.findSimilarSongs(
        seed: _song('seed', 'Faint', 'Linkin Park'),
        limit: 10,
      );

      expect(recs.map((s) => s.id), ['r1', 'r2']);
    });

    test('honors excludedIds', () async {
      RecommendationService.radioFetchForTest = _radioTransport([
        _radioRow('r1', 'One', 'Metallica'),
        _radioRow('r2', 'Fade to Black', 'Metallica'),
      ]);

      final recs = await RecommendationService.findSimilarSongs(
        seed: _song('seed', 'Enter Sandman', 'Metallica'),
        excludedIds: {'r1'},
        limit: 10,
      );

      expect(recs.map((s) => s.id), ['r2']);
    });

    test('excludes recently played by id and normalized title', () async {
      RecommendationService.radioFetchForTest = _radioTransport([
        _radioRow('r1', 'Rock You Like a Hurricane', 'Scorpions'),
        // Same song as recent 'rp2' but different id + punctuation.
        _radioRow('r2', 'Wind of Change (Remastered)', 'Scorpions'),
        _radioRow('r3', 'Still Loving You', 'Scorpions'),
      ]);

      final recs = await RecommendationService.findSimilarSongs(
        seed: _song('seed', 'Enter Sandman', 'Metallica'),
        recentlyPlayed: [
          _song('r1', 'Rock You Like a Hurricane', 'Scorpions'),
          _song('rp2', 'Wind of Change', 'Scorpions'),
        ],
        limit: 10,
      );

      expect(recs.map((s) => s.id), ['r3']);
    });

    test('respects the limit', () async {
      RecommendationService.radioFetchForTest = _radioTransport([
        for (var i = 0; i < 20; i++)
          _radioRow('r$i', 'Song $i', 'Artist $i'),
      ]);

      final recs = await RecommendationService.findSimilarSongs(
        seed: _song('seed', 'Enter Sandman', 'Metallica'),
        limit: 5,
      );

      expect(recs, hasLength(5));
    });

    test('radio rows keep the provider order (no shuffle)', () async {
      // The old pipeline shuffled away YTM's relevance ordering; the radio
      // path must preserve it.
      RecommendationService.radioFetchForTest = _radioTransport([
        _radioRow('a', 'AAA', 'Artist A'),
        _radioRow('b', 'BBB', 'Artist B'),
        _radioRow('c', 'CCC', 'Artist C'),
      ]);

      final recs = await RecommendationService.findSimilarSongs(
        seed: _song('seed', 'Enter Sandman', 'Metallica'),
        limit: 10,
      );

      expect(recs.map((s) => s.id), ['a', 'b', 'c']);
    });
  });

  group('fallback path', () {
    test('radio shortfall is filled by the text-query fallback', () async {
      RecommendationService.radioFetchForTest = _radioTransport([
        _radioRow('r1', 'One', 'Metallica'),
      ]);
      final queries = <String>[];
      _fakeFallback({
        'Metallica Enter Sandman radio': [
          _song('f1', 'Two', 'Metallica'),
          _song('r1', 'One', 'Metallica'), // dupe of radio row
        ],
        'Metallica mix': [_song('f2', 'Three', 'Metallica')],
      }, log: queries);

      final recs = await RecommendationService.findSimilarSongs(
        seed: _song('seed', 'Enter Sandman', 'Metallica'),
        limit: 3,
      );

      expect(recs.map((s) => s.id), ['r1', 'f1', 'f2']);
      expect(queries, isNotEmpty);
    });

    test('radio failure falls back to text queries without throwing',
        () async {
      RecommendationService.radioFetchForTest =
          (url, body) async => throw Exception('network down');
      _fakeFallback({
        'Metallica Enter Sandman radio': [_song('f1', 'One', 'Metallica')],
      });

      final recs = await RecommendationService.findSimilarSongs(
        seed: _song('seed', 'Enter Sandman', 'Metallica'),
        limit: 10,
      );

      expect(recs.map((s) => s.id), ['f1']);
    });

    test('both paths failing yields the empty contract', () async {
      RecommendationService.radioFetchForTest = _radioTransport([]);
      _fakeFallback(const {});

      final recs = await RecommendationService.findSimilarSongs(
        seed: _song('seed', 'Enter Sandman', 'Metallica'),
        limit: 10,
      );
      expect(recs, isEmpty);
    });

    test('fallback exception does not abort the remaining queries',
        () async {
      RecommendationService.radioFetchForTest = _radioTransport([]);
      var first = true;
      RecommendationService.searchFallbackForTest = (query) async {
        if (first) {
          first = false;
          throw Exception('transient');
        }
        return [_song('f1', 'One', 'Metallica')];
      };

      final recs = await RecommendationService.findSimilarSongs(
        seed: _song('seed', 'Enter Sandman', 'Metallica'),
        limit: 10,
      );

      expect(recs.map((s) => s.id), ['f1']);
    });
  });

  group('recently played combined with queue exclusion', () {
    test('radio seed-dedupe plus recent plays leave only fresh songs',
        () async {
      RecommendationService.radioFetchForTest = _radioTransport([
        _radioRow('r1', 'Song One', 'A'),
        _radioRow('r2', 'Song Two', 'B'),
        _radioRow('r3', 'Song Three', 'C'),
        _radioRow('r4', 'Song Four', 'D'),
      ]);

      final recs = await RecommendationService.findSimilarSongs(
        seed: _song('seed', 'Enter Sandman', 'Metallica'),
        excludedIds: {'r2'},
        recentlyPlayed: [_song('r3', 'Song Three', 'C')],
        limit: 10,
      );

      expect(recs.map((s) => s.id), ['r1', 'r4']);
    });
  });
}
