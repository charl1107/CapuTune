// Unit tests for the YouTube Music search response parser.
//
// Fixture `ytm_search_songs.json` is a trimmed live response (captured
// during the investigation against music.youtube.com with the songs
// filter) containing six rows with deliberately varied shapes:
//
//   [0] full song    — artist • album • duration, plays column
//   [1] full song    — different album/duration, deluxe-edition album
//   [2] cover song   — different artist, album == title
//   [3] greyed-out   — MUSIC_ITEM_RENDERER_DISPLAY_POLICY_GREY_OUT
//   [4] missing col2 — flexColumns truncated to 2 (no plays line)
//   [5] artist row   — no videoId (result type drift guard)
//
// Network is never touched: the parser consumes decoded JSON only.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:caputune/services/ytm/ytm_search_parser.dart';

void main() {
  late List<YtmSongResult> songs;

  setUpAll(() {
    final file = File('test/fixtures/ytm_search_songs.json');
    final decoded = jsonDecode(file.readAsStringSync());
    songs = parseYtmSongs(decoded);
  });

  group('parseYtmSongs — fixture overall', () {
    test('parses exactly the four playable songs', () {
      expect(songs, hasLength(4));
    });

    test('every parsed song has a usable id, title, and artist', () {
      for (final s in songs) {
        expect(s.id, isNotEmpty, reason: 'videoId required for playback');
        expect(s.title, isNotEmpty);
        expect(s.artist, isNotEmpty);
      }
    });

    test('keeps songs in response order', () {
      expect(songs.map((s) => s.id).toList(),
          ['rj5wZqReXQE', 'Hj0aJ1R2UAw', 'gsnvWnUvrhM', 'rj5wZqReXQE']);
    });
  });

  group('parseYtmSongs — field mapping', () {
    test('maps the first song completely', () {
      final s = songs.first;
      expect(s.id, 'rj5wZqReXQE');
      expect(s.title, 'Wonderwall');
      expect(s.artist, 'Oasis');
      expect(s.album, "(What's The Story) Morning Glory? (Remastered)");
      expect(s.duration, '4:19');
      expect(s.thumbnailUrl, isNotNull);
      expect(s.thumbnailUrl, contains('yt3.googleusercontent.com'));
    });

    test('maps a second song with different metadata', () {
      final s = songs[1];
      expect(s.id, 'Hj0aJ1R2UAw');
      expect(s.title, 'Wonderwall (Unplugged)');
      expect(s.duration, '4:12');
      expect(s.album, contains('30th Anniversary'));
    });

    test('maps the cover song with its own artist', () {
      final s = songs[2];
      expect(s.id, 'gsnvWnUvrhM');
      expect(s.artist, 'Frog Leap Studios');
      expect(s.album, 'Wonderwall (Metal Cover)');
    });
  });

  group('parseYtmSongs — exclusions', () {
    test('skips greyed-out (region-unavailable) rows', () {
      // Two rows share videoId rj5wZqReXQE; only the non-greyed ones parse.
      expect(songs.where((s) => s.id == 'rj5wZqReXQE'), hasLength(2));
    });

    test('skips rows without a playable videoId (artist/album/playlist rows)',
        () {
      expect(songs.map((s) => s.id), isNot(contains(isNull)));
      // The artist row's would-be title was the artist name, never mapped.
      expect(songs.map((s) => s.title), isNot(contains('Oasis')));
    });
  });

  group('parseYtmSongs — defensive shapes', () {
    test('row with missing flex column 2 still parses fully', () {
      // Row [4] (truncated flexColumns) is structurally identical to row [0]
      // otherwise, so both survive with the same mapped fields.
      final truncated = songs.where((s) => s.id == 'rj5wZqReXQE').toList();
      expect(truncated, hasLength(2));
      for (final s in truncated) {
        expect(s.artist, 'Oasis');
        expect(s.duration, '4:19');
        expect(s.album, isNotNull);
      }
    });

    test('returns empty for each malformed top-level shape', () {
      expect(parseYtmSongs(null), isEmpty);
      expect(parseYtmSongs('nope'), isEmpty);
      expect(parseYtmSongs(42), isEmpty);
      expect(parseYtmSongs(<String, dynamic>{}), isEmpty);
      expect(
          parseYtmSongs(<String, dynamic>{'contents': 'not-a-map'}), isEmpty);
      expect(
          parseYtmSongs(<String, dynamic>{
            'contents': <String, dynamic>{'tabbedSearchResultsRenderer': null},
          }),
          isEmpty);
      // Right path, wrong node types at every level.
      expect(
          parseYtmSongs(<String, dynamic>{
            'contents': <String, dynamic>{
              'tabbedSearchResultsRenderer': <String, dynamic>{
                'tabs': 'not-a-list',
              },
            },
          }),
          isEmpty);
    });

    test('returns empty when shelves exist but contain junk rows', () {
      final junk = {
        'contents': {
          'tabbedSearchResultsRenderer': {
            'tabs': [
              {
                'tabRenderer': {
                  'content': {
                    'sectionListRenderer': {
                      'contents': [
                        {'musicShelfRenderer': 'not-a-map'},
                        {
                          'musicShelfRenderer': {
                            'contents': [
                              'bare-string-row',
                              {'no-renderer-key': true},
                              {'musicResponsiveListItemRenderer': 'not-a-map'},
                              {
                                'musicResponsiveListItemRenderer':
                                    <String, dynamic>{},
                              },
                            ],
                          },
                        },
                      ],
                    },
                  },
                },
              },
            ],
          },
        },
      };
      expect(parseYtmSongs(junk), isEmpty);
    });

    test('extracts title when flexColumns is missing entirely', () {
      // A row with no flexColumns but a valid play overlay cannot yield a
      // title, so it must be dropped rather than mapped with empty text.
      final row = {
        'contents': {
          'tabbedSearchResultsRenderer': {
            'tabs': [
              {
                'tabRenderer': {
                  'content': {
                    'sectionListRenderer': {
                      'contents': [
                        {
                          'musicShelfRenderer': {
                            'contents': [
                              {
                                'musicResponsiveListItemRenderer': {
                                  'overlay': {
                                    'musicItemThumbnailOverlayRenderer': {
                                      'content': {
                                        'musicPlayButtonRenderer': {
                                          'playNavigationEndpoint': {
                                            'watchEndpoint': {
                                              'videoId': 'abc123'
                                            },
                                          },
                                        },
                                      },
                                    },
                                  },
                                },
                              },
                            ],
                          },
                        },
                      ],
                    },
                  },
                },
              },
            ],
          },
        },
      };
      expect(parseYtmSongs(row), isEmpty);
    });
  });

  group('parseYtmSongs — type-specifier skip', () {
    test('leading unlinked "Song" label is never parsed as an artist', () {
      // Mirrors the default-response shape ("Song • Artist") where the
      // first run has no navigationEndpoint and the second is a separator.
      final row = {
        'contents': {
          'tabbedSearchResultsRenderer': {
            'tabs': [
              {
                'tabRenderer': {
                  'content': {
                    'sectionListRenderer': {
                      'contents': [
                        {
                          'musicShelfRenderer': {
                            'contents': [
                              {
                                'musicResponsiveListItemRenderer': {
                                  'flexColumns': [
                                    {
                                      'musicResponsiveListItemFlexColumnRenderer':
                                          {
                                        'text': {
                                          'runs': [
                                            {'text': 'Wonderwall'},
                                          ],
                                        },
                                      },
                                    },
                                    {
                                      'musicResponsiveListItemFlexColumnRenderer':
                                          {
                                        'text': {
                                          'runs': [
                                            {'text': 'Song'},
                                            {'text': ' \u2022 '},
                                            {
                                              'text': 'Oasis',
                                              'navigationEndpoint': {
                                                'browseEndpoint': {
                                                  'browseId':
                                                      'UCmMUZbaYdNH0bEd1PAlAqsA',
                                                },
                                              },
                                            },
                                            {'text': ' \u2022 '},
                                            {'text': '4:19'},
                                          ],
                                        },
                                      },
                                    },
                                  ],
                                  'overlay': {
                                    'musicItemThumbnailOverlayRenderer': {
                                      'content': {
                                        'musicPlayButtonRenderer': {
                                          'playNavigationEndpoint': {
                                            'watchEndpoint': {
                                              'videoId': 'spec123'
                                            },
                                          },
                                        },
                                      },
                                    },
                                  },
                                },
                              },
                            ],
                          },
                        },
                      ],
                    },
                  },
                },
              },
            ],
          },
        },
      };
      final parsed = parseYtmSongs(row);
      expect(parsed, hasLength(1));
      expect(parsed.single.artist, 'Oasis');
      expect(parsed.single.duration, '4:19');
    });
  });
}
