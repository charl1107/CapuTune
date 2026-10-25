// Unit tests for playlist URL validation and source detection.
//
// These cover the accept/reject boundary of the import flow without hitting
// the network: scheme, host, credentials and required parameters.

import 'package:flutter_test/flutter_test.dart';
import 'package:caputune/services/playlist_url.dart';

void main() {
  group('PlaylistUrl.detectSource', () {
    test('accepts a standard YouTube playlist URL', () {
      expect(
        PlaylistUrl.detectSource(
            'https://www.youtube.com/playlist?list=PLabcdef123456'),
        PlaylistUrl.youtube,
      );
    });

    test('accepts a watch URL that carries a list parameter', () {
      expect(
        PlaylistUrl.detectSource(
            'https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLabcdef123456'),
        PlaylistUrl.youtube,
      );
    });

    test('accepts music.youtube.com and m.youtube.com hosts', () {
      expect(
        PlaylistUrl.detectSource('https://music.youtube.com/playlist?list=PLx'),
        PlaylistUrl.youtube,
      );
      expect(
        PlaylistUrl.detectSource('https://m.youtube.com/playlist?list=PLx'),
        PlaylistUrl.youtube,
      );
    });

    test('rejects a watch URL with no list parameter', () {
      expect(
        PlaylistUrl.detectSource('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        isNull,
      );
    });

    test('rejects an empty list parameter', () {
      expect(
        PlaylistUrl.detectSource('https://www.youtube.com/playlist?list='),
        isNull,
      );
    });

    test('rejects unsupported hosts', () {
      expect(
        PlaylistUrl.detectSource('https://open.spotify.com/playlist/abc'),
        isNull,
      );
      expect(
        PlaylistUrl.detectSource('https://example.com/playlist?list=PLx'),
        isNull,
      );
    });

    test('rejects non-http schemes', () {
      expect(PlaylistUrl.detectSource('file:///etc/passwd'), isNull);
      expect(PlaylistUrl.detectSource('javascript:alert(1)'), isNull);
      expect(PlaylistUrl.detectSource('data:text/plain,hello'), isNull);
      expect(
        PlaylistUrl.detectSource('content://media/external/audio/1'),
        isNull,
      );
    });

    test('rejects URLs with embedded credentials', () {
      expect(
        PlaylistUrl.detectSource(
            'https://user:pass@www.youtube.com/playlist?list=PLx'),
        isNull,
      );
    });

    test('rejects malformed input', () {
      expect(PlaylistUrl.detectSource('not a url'), isNull);
      expect(PlaylistUrl.detectSource(''), isNull);
      expect(PlaylistUrl.detectSource('youtube.com/playlist?list=PLx'), isNull);
    });

    test('tolerates surrounding whitespace', () {
      expect(
        PlaylistUrl.detectSource(
            '  https://www.youtube.com/playlist?list=PLx  '),
        PlaylistUrl.youtube,
      );
    });
  });

  group('PlaylistUrl.youtubePlaylistId', () {
    test('extracts the playlist id', () {
      expect(
        PlaylistUrl.youtubePlaylistId(
            'https://www.youtube.com/watch?v=abc&list=PL123'),
        'PL123',
      );
    });

    test('returns null when absent', () {
      expect(
        PlaylistUrl.youtubePlaylistId('https://www.youtube.com/watch?v=abc'),
        isNull,
      );
    });
  });

  test('isValid mirrors detectSource', () {
    expect(
      PlaylistUrl.isValid('https://www.youtube.com/playlist?list=PLx'),
      isTrue,
    );
    expect(PlaylistUrl.isValid('https://example.com'), isFalse);
  });
}
