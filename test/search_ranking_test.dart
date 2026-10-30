// Unit tests for the local search relevance ranker.
//
// The ranker exists because YTM orders search rows by popularity, not
// textual relevance: "nothing else" ranks a song literally titled
// "Nothing Else" above Metallica's "Nothing Else Matters", and a raw
// "metal" search contains no Metallica at all. These tests pin the tier
// contract and the reordering behavior with plain data (no mocks needed —
// the ranker is pure Dart).
import 'package:caputune/services/ytm/ytm_search_parser.dart';
import 'package:caputune/utils/search_ranking.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal rankable row.
class _Track implements RankableTrack {
  @override
  final String title;
  @override
  final String artist;
  @override
  final String? album;
  const _Track(this.title, this.artist, [this.album]);
}

void main() {
  group('normalizeForMatch', () {
    test('lowercases, trims, collapses whitespace and punctuation', () {
      expect(
        normalizeForMatch('  Nothing   Else-Matters! '),
        'nothing else matters',
      );
      expect(normalizeForMatch("Don't Stop Me Now"), 'dont stop me now');
      expect(normalizeForMatch('AC/DC'), 'ac dc');
    });

    test('handles unicode punctuation', () {
      // Typographic apostrophe and em dash.
      expect(normalizeForMatch('Don\u2019t Stop — Now'), 'dont stop now');
    });

    test('empty and whitespace-only input collapses to empty', () {
      expect(normalizeForMatch(''), '');
      expect(normalizeForMatch('   \t '), '');
    });
  });

  group('wordsForMatch', () {
    test('drops single-letter noise words', () {
      expect(wordsForMatch('A Hard Day'), ['hard', 'day']);
      expect(wordsForMatch('I'), isEmpty);
    });
  });

  group('classifyMatch tiers', () {
    const q = 'nothing else';
    const qw = ['nothing', 'else'];

    test('exact title', () {
      final t = classifyMatch(
        const _Track('Nothing Else', 'Someone'),
        q,
        qw,
      );
      expect(t, MatchTier.exactTitle);
    });

    test('title prefix', () {
      final t = classifyMatch(
        const _Track('Nothing Else Matters', 'Metallica'),
        q,
        qw,
      );
      expect(t, MatchTier.titlePrefix);
    });

    test('title word-contains (both words present, not a prefix)', () {
      final t = classifyMatch(
        const _Track('The Nothing Else Song', 'Someone'),
        q,
        qw,
      );
      expect(t, MatchTier.titleWordContains);
    });

    test('multi-word query must not match only one word', () {
      // "Nothing But Trouble" contains "nothing" but not "else" — must not
      // reach any title tier.
      final t = classifyMatch(
        const _Track('Nothing But Trouble', 'Someone'),
        q,
        qw,
      );
      expect(t, isNot(MatchTier.titlePrefix));
      expect(t, isNot(MatchTier.titleWordContains));
    });

    test('artist-name query: both tiers rank above no-match', () {
      // Spec tier order: title-contains ranks above exact-artist.
      final exact = classifyMatch(
        const _Track('Unrelated', 'Metallica'),
        'metallica',
        ['metallica'],
      );
      final titleHit = classifyMatch(
        const _Track('Metallicalove', 'Someone'),
        'metallica',
        ['metallica'],
      );
      expect(exact, MatchTier.exactArtist);
      expect(titleHit, MatchTier.titleContains);
      expect(titleHit.index, lessThan(exact.index));
    });

    test('artist word-contains for channel-style names', () {
      final t = classifyMatch(
        const _Track('Unrelated', 'Metallica - Topic'),
        'metallica',
        ['metallica'],
      );
      expect(t, MatchTier.artistWordContains);
    });

    test('album-only match lands in metadata tier', () {
      final t = classifyMatch(
        const _Track('Unrelated Title', 'Unrelated Artist', 'Metallica'),
        'metallica',
        ['metallica'],
      );
      expect(t, MatchTier.metadata);
    });

    test('no match', () {
      final t = classifyMatch(
        const _Track('Forever', 'Chris Brown'),
        'metallica',
        ['metallica'],
      );
      expect(t, MatchTier.none);
    });

    test('empty query never matches', () {
      final t = classifyMatch(
        const _Track('Enter Sandman', 'Metallica'),
        '',
        [],
      );
      expect(t, MatchTier.none);
    });
  });

  group('rankTracks', () {
    test('full-title query ranks the real song above a partial match', () {
      // The live failure: for "nothing else matters", YTM's popularity order
      // put Cody Carnes' "Nothing Else" first. The ranker must put the
      // exact-title match on top.
      final ranked = rankTracks([
        const _Track('Nothing Else', 'Cody Carnes'),
        const _Track('Nothing Else Matters', 'Metallica'),
      ], 'nothing else matters');
      expect(ranked.first.title, 'Nothing Else Matters');
    });

    test('partial query: exact match wins its tier by contract', () {
      // For "nothing else" the shorter song is an exact title match and the
      // Metallica track is a prefix match — the agreed tier order (exact >
      // prefix) applies. As the user keeps typing, the full query flips the
      // result (tested above).
      final ranked = rankTracks([
        const _Track('Nothing Else Matters', 'Metallica'),
        const _Track('Nothing Else', 'Cody Carnes'),
      ], 'nothing else');
      expect(ranked.first.title, 'Nothing Else');
    });

    test('full tier ordering: exact > prefix > word-contains > none', () {
      final ranked = rankTracks([
        const _Track('Something Else', 'Other'), // none
        const _Track('The Enter Sandman Song', 'Other'), // word-contains
        const _Track('Enter Sandman (Live)', 'Other'), // prefix
        const _Track('Enter Sandman', 'Metallica'), // exact
      ], 'enter sandman');
      expect(ranked.map((t) => t.title).toList(), [
        'Enter Sandman',
        'Enter Sandman (Live)',
        'The Enter Sandman Song',
        'Something Else',
      ]);
    });

    test('artist-name query ranks the artist above a title hit', () {
      final ranked = rankTracks([
        const _Track('Metal Health', 'Quiet Riot'), // titleContains
        const _Track('Unrelated', 'Metallica'), // exactArtist
      ], 'metallica');
      expect(ranked.first.artist, 'Metallica');
    });

    test('stable sort keeps provider order among equal tiers', () {
      final ranked = rankTracks([
        const _Track('Unrelated A', 'Zed'),
        const _Track('Unrelated B', 'Abc'),
      ], 'metallica');
      // Neither matches: original order preserved.
      expect(ranked.map((t) => t.title), ['Unrelated A', 'Unrelated B']);
    });

    test('case and punctuation differences still rank as exact', () {
      final ranked = rankTracks([
        const _Track('ENTER SANDMAN (Live)', 'Metallica'),
        const _Track('Something Else', 'Other'),
      ], 'enter  sandman!');
      expect(ranked.first.title, 'ENTER SANDMAN (Live)');
    });

    test('empty query returns the original order', () {
      final ranked = rankTracks([
        const _Track('B', 'X'),
        const _Track('A', 'Y'),
      ], '');
      expect(ranked.map((t) => t.title), ['B', 'A']);
    });

    test('works with the parser result type', () {
      // YtmSongResult implements RankableTrack — verify the contract holds
      // so searchRemote can rank raw parser rows directly.
      const rows = [
        YtmSongResult(id: 'a', title: 'Nothing Else', artist: 'Cody Carnes'),
        YtmSongResult(id: 'b', title: 'Nothing Else Matters', artist: 'Metallica'),
      ];
      final ranked = rankTracks(rows, 'nothing else matters');
      expect(ranked.first.id, 'b');
    });
  });
}
