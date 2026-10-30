// Tests for the song-radio client and parser.
//
// Fixtures mirror the live-verified `youtubei/v1/next` response shape:
// rows at contents → singleColumnMusicWatchNextResultsRenderer →
// tabbedRenderer → watchNextTabbedResultsRenderer → tabs[0].tabRenderer
// .content.musicQueueRenderer.content.playlistPanelRenderer.contents[].
import 'dart:convert';

import 'package:caputune/services/ytm/ytm_radio_client.dart';
import 'package:caputune/services/ytm/ytm_search_parser.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _radioResponse(List<Map<String, dynamic>> rows) {
  return {
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
              // The "Related" tab: present but empty in real responses.
              {
                'tabRenderer': {
                  'content': {'musicMultiRowListRenderer': {}},
                },
              },
            ],
          },
        },
      },
    },
  };
}

Map<String, dynamic> _row(
  String id, {
  required String title,
  required String artist,
  String? album,
  String? duration,
  bool withVideoId = true,
}) {
  final runs = [
    {'text': artist},
    {'text': ' \u2022 '},
    if (album != null) ...[
      {
        'text': album,
        'navigationEndpoint': {
          'browseEndpoint': {'browseId': 'MPREb_testalbum'},
        },
      },
      {'text': ' \u2022 '},
    ],
    if (duration != null) {'text': duration},
  ];
  return {
    if (withVideoId) 'videoId': id,
    'title': {
      'runs': [
        {'text': title},
      ],
    },
    'longBylineText': {'runs': runs},
    'thumbnail': {
      'musicThumbnailRenderer': {
        'thumbnail': {
          'thumbnails': [
            {'url': 'https://example.com/t.jpg'},
          ],
        },
      },
    },
  };
}

void main() {
  group('YtmRadioClient', () {
    test('sends the song-radio request shape and parses rows', () async {
      String? capturedUrl;
      Map<String, dynamic>? capturedBody;
      final client = YtmRadioClient(
        fetch: (url, body) async {
          capturedUrl = url;
          capturedBody = body;
          return _radioResponse([
            _row('v1', title: 'Nothing Else Matters', artist: 'Metallica'),
            _row('v2', title: 'Rock You Like a Hurricane', artist: 'Scorpions'),
          ]);
        },
      );

      final rows = await client.getRadio('abc123');
      expect(rows, hasLength(2));
      expect(capturedUrl, kYtmRadioUrl);
      expect(capturedBody!['videoId'], 'abc123');
      expect(capturedBody!['playlistId'], 'RDabc123');
      expect(capturedBody!['contentCheckOk'], true);
      final context = capturedBody!['context']['client'] as Map;
      expect(context['clientName'], 'WEB_REMIX');
    });

    test('empty videoId short-circuits without a request', () async {
      var calls = 0;
      final client = YtmRadioClient(
        fetch: (url, body) async {
          calls++;
          return _radioResponse([]);
        },
      );
      expect(await client.getRadio('  '), isEmpty);
      expect(calls, 0);
    });

    test('transport failure degrades to [] instead of throwing', () async {
      final client = YtmRadioClient(
        fetch: (url, body) async => throw const FormatException('bad'),
      );
      expect(await client.getRadio('abc'), isEmpty);
    });

    test('request body is valid JSON with the RD playlist prefix', () {
      final client = YtmRadioClient();
      final body = client.buildRadioRequestBody('xyz');
      expect(jsonEncode(body), contains('RDxyz'));
    });
  });

  group('parseYtmRadioSongs', () {
    test('parses title, artist, album, duration from byline runs', () {
      final rows = parseYtmRadioSongs(_radioResponse([
        _row(
          'v1',
          title: 'Enter Sandman',
          artist: 'Metallica',
          album: 'Metallica',
          duration: '5:31',
        ),
      ]));
      expect(rows, hasLength(1));
      expect(rows.first.id, 'v1');
      expect(rows.first.title, 'Enter Sandman');
      expect(rows.first.artist, 'Metallica');
      expect(rows.first.album, 'Metallica');
      expect(rows.first.duration, '5:31');
      expect(rows.first.thumbnailUrl, isNotNull);
    });

    test('multiple artists join with a comma', () {
      final rows = parseYtmRadioSongs(_radioResponse([
        {
          'videoId': 'v9',
          'title': {
            'runs': [
              {'text': 'Song X'},
            ],
          },
          'longBylineText': {
            'runs': [
              {'text': 'A', 'navigationEndpoint': {}},
              {'text': ' • '},
              {'text': 'B', 'navigationEndpoint': {}},
            ],
          },
        },
      ]));
      expect(rows.first.artist, 'A, B');
    });

    test('bare release years are not glued onto the artist', () {
      // Live-verified shape: " • 1991 • " between album and duration.
      final rows = parseYtmRadioSongs(_radioResponse([
        {
          'videoId': 'v1',
          'title': {
            'runs': [
              {'text': 'Enter Sandman'},
            ],
          },
          'longBylineText': {
            'runs': [
              {'text': 'Metallica', 'navigationEndpoint': {}},
              {'text': ' • '},
              {
                'text': 'Metallica',
                'navigationEndpoint': {
                  'browseEndpoint': {'browseId': 'MPREb_album'},
                },
              },
              {'text': ' • '},
              {'text': '1991'},
              {'text': ' • '},
              {'text': '5:31'},
            ],
          },
        },
      ]));
      expect(rows.first.artist, 'Metallica');
      expect(rows.first.album, 'Metallica');
      expect(rows.first.duration, '5:31');
    });

    test('invalid videoId shell (no queue content) degrades to []', () {
      // Live-verified: a bad videoId returns a response with tabs but no
      // musicQueueRenderer content at all.
      final shell = {
        'contents': {
          'singleColumnMusicWatchNextResultsRenderer': {
            'tabbedRenderer': {
              'watchNextTabbedResultsRenderer': {
                'tabs': [
                  {
                    'tabRenderer': {
                      'content': {
                        'backgroundOverlayRenderer': {},
                      },
                    },
                  },
                ],
              },
            },
          },
        },
      };
      expect(parseYtmRadioSongs(shell), isEmpty);
    });

    test('completely malformed response degrades to []', () {
      expect(parseYtmRadioSongs(null), isEmpty);
      expect(parseYtmRadioSongs(<String, dynamic>{}), isEmpty);
      expect(parseYtmRadioSongs({'contents': 42}), isEmpty);
    });

    test('rows without videoId or title are skipped', () {
      final rows = parseYtmRadioSongs(_radioResponse([
        _row('v1', title: 'Ok', artist: 'A'),
        _row('', title: 'No id', artist: 'A', withVideoId: false),
        {
          'title': {
            'runs': [
              {'text': 'No id either'},
            ],
          },
        },
      ]));
      expect(rows, hasLength(1));
      expect(rows.first.id, 'v1');
    });
  });
}
