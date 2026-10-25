// Unit tests for the discovery lookup helpers.
//
// `formatDuration` lives in the io lookup file so it can be tested directly
// on the Dart VM (flutter test runs on the VM, so importing an io file is
// fine here). The remote search/playlist functions are covered by the device
// acceptance test.

import 'package:flutter_test/flutter_test.dart';
import 'package:caputune/services/discovery_lookup_io.dart';

void main() {
  group('formatDuration', () {
    test('returns null for a null duration', () {
      expect(formatDuration(null), isNull);
    });

    test('formats 215 seconds as 3:35', () {
      expect(formatDuration(const Duration(seconds: 215)), '3:35');
    });

    test('formats 59 seconds as 0:59', () {
      expect(formatDuration(const Duration(seconds: 59)), '0:59');
    });

    test('formats 1h2m3s as 1:02:03', () {
      expect(
        formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });
  });

  group('songFromVideo', () {
    test('maps Video fields onto Song', () {
      // The Video constructor takes 13 positional params; the nullable ones
      // are passed null. Types come via discovery_lookup_io.dart's re-export
      // so this test never imports youtube_explode_dart directly.
      final video = Video(
        VideoId('dQw4w9WgXcQ'),
        'Never Gonna Give You Up',
        'Rick Astley',
        ChannelId('UCuAXFkgsw1L7xaCfnd5JJOw'),
        null, // uploadDate
        null, // uploadDateRaw
        null, // publishDate
        'Video description',
        const Duration(seconds: 215),
        const ThumbnailSet('dQw4w9WgXcQ'),
        null, // keywords
        const Engagement(0, null, null),
        false, // isLive
      );

      final song = songFromVideo(video);

      expect(song.id, 'dQw4w9WgXcQ');
      expect(song.title, 'Never Gonna Give You Up');
      expect(song.artist, 'Rick Astley');
      expect(
        song.thumbnail,
        'https://img.youtube.com/vi/dQw4w9WgXcQ/maxresdefault.jpg',
      );
      expect(song.duration, '3:35');
      expect(song.album, isNull);
    });
  });
}
