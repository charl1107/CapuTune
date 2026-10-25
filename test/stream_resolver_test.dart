// Unit tests for StreamResolver.
//
// The resolver delegates to an injectable AudioUrlLookup so these tests use a
// fake lookup instead of hitting YouTube.

import 'package:flutter_test/flutter_test.dart';
import 'package:caputune/services/stream_resolver.dart';
import 'package:caputune/services/stream_resolver_lookup_io.dart';

void main() {
  group('StreamResolver', () {
    test('returns the URL produced by the lookup', () async {
      final resolver = StreamResolver(
        lookup: (String videoId) async => 'https://example.com/audio.mp4?iq=1',
      );

      final result = await resolver.resolve('dQw4w9WgXcQ');

      expect(result, 'https://example.com/audio.mp4?iq=1');
    });

    test('returns null when the lookup throws', () async {
      final resolver = StreamResolver(
        lookup: (String videoId) async => throw Exception('network down'),
      );

      final result = await resolver.resolve('dQw4w9WgXcQ');

      expect(result, isNull);
    });

    test('returns null when the lookup returns null', () async {
      final resolver = StreamResolver(
        lookup: (String videoId) async => null,
      );

      final result = await resolver.resolve('dQw4w9WgXcQ');

      expect(result, isNull);
    });
  });

  group('resolveWithRetry', () {
    // YouTube intermittently returns stream URLs that answer 403 at the CDN,
    // and stubs audio-only URLs more often than muxed ones. The lookup must
    // verify candidate URLs in preference order and re-extract when all are
    // dead.
    test('returns the first candidate when the first probe succeeds',
        () async {
      var extractions = 0;

      final result = await resolveWithRetry(
        (String videoId) async {
          extractions++;
          return ['https://example.com/audio-1', 'https://example.com/mux-1'];
        },
        (String url) async => true,
        'dQw4w9WgXcQ',
      );

      expect(result, 'https://example.com/audio-1');
      expect(extractions, 1);
    });

    test('falls through to the muxed candidate when audio is dead', () async {
      final result = await resolveWithRetry(
        (String videoId) async => [
          'https://example.com/audio-dead',
          'https://example.com/muxed-live',
        ],
        (String url) async => !url.endsWith('dead'),
        'dQw4w9WgXcQ',
      );

      expect(result, 'https://example.com/muxed-live');
    });

    test('re-extracts when every candidate is dead', () async {
      var extractions = 0;

      final result = await resolveWithRetry(
        (String videoId) async {
          extractions++;
          return [
            'https://example.com/audio-$extractions',
            'https://example.com/muxed-$extractions',
          ];
        },
        (String url) async => false,
        'dQw4w9WgXcQ',
        maxAttempts: 3,
      );

      expect(result, isNull);
      expect(extractions, 3);
    });

    test('does not probe when extraction yields no streams', () async {
      var probes = 0;

      final result = await resolveWithRetry(
        (String videoId) async => null,
        (String url) async {
          probes++;
          return true;
        },
        'dQw4w9WgXcQ',
      );

      expect(result, isNull);
      expect(probes, 0);
    });

    test('stops retrying when extraction itself throws', () async {
      var attempts = 0;

      final result = await resolveWithRetry(
        (String videoId) async {
          attempts++;
          throw Exception('network down');
        },
        (String url) async => true,
        'dQw4w9WgXcQ',
      );

      expect(result, isNull);
      expect(attempts, 1);
    });
  });
}
