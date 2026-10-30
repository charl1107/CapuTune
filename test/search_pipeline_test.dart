// Tests for the full remote-search pipeline (discovery_lookup_io).
//
// The YTM client is injected, so no test touches the network. These pin:
// - local relevance ranking on top of the provider's popularity order,
// - genre-word expansion through search suggestions ("metal" → "metallica"),
// - the empty-list failure contract for empty queries and client errors.
import 'package:caputune/services/discovery_lookup_io.dart';
import 'package:caputune/services/ytm/ytm_search_client.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubClient implements YtmSearchClient {
  final Map<String, List<YtmSongResult>> songsByQuery;
  final Map<String, List<YtmSearchSuggestion>> suggestionsByQuery;
  int songCalls = 0;
  _StubClient(this.songsByQuery, {this.suggestionsByQuery = const {}});

  @override
  Future<List<YtmSongResult>> searchSongs(String query) async {
    songCalls++;
    return songsByQuery[query] ?? const <YtmSongResult>[];
  }

  @override
  Future<List<YtmSearchSuggestion>> searchSuggestions(String input) async {
    return suggestionsByQuery[input] ?? const <YtmSearchSuggestion>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

YtmSongResult _r(String id, String title, String artist) =>
    YtmSongResult(id: id, title: title, artist: artist);

void main() {
  setUp(() {
    ytmClientFactoryForTest = null;
  });

  tearDown(() {
    ytmClientFactoryForTest = null;
  });

  group('searchRemote ranking', () {
    test('full-title query outranks popularity rows', () async {
      // Live failure: YTM ranked Cody Carnes' "Nothing Else" above
      // Metallica's "Nothing Else Matters" for the full-title query.
      ytmClientFactoryForTest = () => _StubClient({
            'nothing else matters': [
              _r('a', 'Nothing Else', 'Cody Carnes'),
              _r('b', 'Nothing Else Matters', 'Metallica'),
            ],
          });

      final results = await searchRemote('nothing else matters');
      expect(results.first.id, 'b');
    });

    test('exact title beats contains beats no-match', () async {
      ytmClientFactoryForTest = () => _StubClient({
            'enter sandman': [
              _r('x', 'Something Else', 'Other'), // none
              _r('y', 'The Enter Sandman Song', 'Other'), // contains
              _r('z', 'Enter Sandman', 'Metallica'), // exact
            ],
          });

      final results = await searchRemote('enter sandman');
      expect(results.map((s) => s.id), ['z', 'y', 'x']);
    });

    test('normalization: case and punctuation do not block exact rank',
        () async {
      ytmClientFactoryForTest = () => _StubClient({
            // The stub keys on the raw (unnormalized) query string.
            "DONT  STOP me-now!": [
              _r('a', "Don't Stop Me Now", 'Queen'),
              _r('b', 'Unrelated', 'Other'),
            ],
          });

      final results = await searchRemote("DONT  STOP me-now!");
      expect(results.first.id, 'a');
    });

    test('provider order is kept among equal tiers', () async {
      ytmClientFactoryForTest = () => _StubClient({
            'zzz': [
              _r('first', 'ZZZ One', 'A'),
              _r('second', 'ZZZ Two', 'B'),
            ],
          });

      final results = await searchRemote('zzz');
      // Both are exact matches; provider order decides.
      expect(results.map((s) => s.id), ['first', 'second']);
    });
  });

  group('genre expansion', () {
    test('bare genre word with no textual hits triggers suggestions',
        () async {
      final client = _StubClient(
        {
          // Raw "metal": genre picks with zero Metallica (live-verified).
          'metal': [
            _r('g1', 'Heavy Metal Thunder', 'Saxon-adjacent channel'),
            _r('g2', 'Metal Health', 'Quiet Riot'),
          ],
          // Suggestion search results: on-topic artists.
          'metallica': [
            _r('m1', 'Enter Sandman', 'Metallica'),
            _r('m2', 'Master of Puppets', 'Metallica'),
          ],
        },
        suggestionsByQuery: {
          'metal': [
            const YtmSearchSuggestion(text: 'metallica'),
            const YtmSearchSuggestion(text: 'metallica songs'),
          ],
        },
      );
      ytmClientFactoryForTest = () => client;

      final results = await searchRaw('metal');

      // Raw rows first, then expansion, deduped.
      expect(results.map((s) => s.id), ['g1', 'g2', 'm1', 'm2']);
    });

    test('expansion drops off-topic suggestion rows', () async {
      final client = _StubClient(
        {
          'metal': [_r('g1', 'Unrelated Genre Pick', 'No Match Band')],
          // The suggestion search returns rows; they are capped per round.
          'metallica': [
            _r('m1', 'Enter Sandman', 'Metallica'),
            _r('bad', 'Summer Breeze', 'Seals & Crofts'),
          ],
        },
        suggestionsByQuery: {
          'metal': [const YtmSearchSuggestion(text: 'metallica')],
        },
      );
      ytmClientFactoryForTest = () => client;

      final results = await searchRaw('metal');
      expect(results.map((s) => s.id), ['g1', 'm1', 'bad']);
    });

    test('expansion is capped per suggestion round', () async {
      final client = _StubClient(
        {
          'metal': [_r('g1', 'Genre Pick', 'Band')],
          'metallica': [
            for (var i = 0; i < 10; i++) _r('m$i', 'Song $i', 'Metallica'),
          ],
        },
        suggestionsByQuery: {
          'metal': [const YtmSearchSuggestion(text: 'metallica')],
        },
      );
      ytmClientFactoryForTest = () => client;

      final results = await searchRaw('metal');
      expect(results, hasLength(1 + 5)); // 1 raw + 5 capped expansion rows
    });

    test('raw hits still expand for genre words', () async {
      // "Rock" appears in a raw title, but a bare genre word should still
      // surface the artists named after the genre (live: raw "metal" rows
      // contain the word yet zero Metallica).
      final client = _StubClient(
        {
          'rock': [_r('r1', 'Rock', 'Someone')],
          'rock music': [_r('r2', 'Bohemian Rhapsody', 'Queen')],
        },
        suggestionsByQuery: {
          'rock': [const YtmSearchSuggestion(text: 'rock music')],
        },
      );
      ytmClientFactoryForTest = () => client;

      final results = await searchRaw('rock');
      expect(results.map((s) => s.id), ['r1', 'r2']);
      expect(client.songCalls, 2);
    });

    test('non-genre words never expand', () async {
      final client = _StubClient({
        'metallica': [_r('m1', 'Enter Sandman', 'Metallica')],
      });
      ytmClientFactoryForTest = () => client;

      await searchRaw('metallica');
      expect(client.songCalls, 1);
    });
  });

  group('failure contract', () {
    test('empty query returns [] without any request', () async {
      final client = _StubClient(const {});
      ytmClientFactoryForTest = () => client;

      expect(await searchRemote('   '), isEmpty);
      expect(client.songCalls, 0);
    });

    test('client exception degrades to []', () async {
      ytmClientFactoryForTest = () => _ThrowingStub();

      expect(await searchRemote('metallica'), isEmpty);
    });

    test('suggestion failure leaves the raw results in place', () async {
      ytmClientFactoryForTest = () => _StubClient(
            {
              'metal': [_r('g1', 'Genre Pick', 'Band')],
            },
            suggestionsByQuery: {
              'metal': const [], // no suggestions → no expansion searches
            },
          );

      final results = await searchRaw('metal');
      expect(results.map((s) => s.id), ['g1']);
    });
  });
}

class _ThrowingStub implements YtmSearchClient {
  _ThrowingStub();

  @override
  Future<List<YtmSongResult>> searchSongs(String query) async {
    throw Exception('network down');
  }

  @override
  Future<List<YtmSearchSuggestion>> searchSuggestions(String input) async {
    throw Exception('network down');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
