// Unit tests for StreamResolver.
//
// The resolver delegates to an injectable AudioUrlLookup so these tests use a
// fake lookup instead of hitting YouTube.

import 'package:flutter_test/flutter_test.dart';
import 'package:http_parser/http_parser.dart';
import 'package:caputune/services/stream_resolver.dart';
import 'package:caputune/services/stream_resolver_lookup_io.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  group('StreamResolver', () {
    test('returns the URL produced by the lookup', () async {
      final resolver = StreamResolver(
        lookup: (String videoId, {String? quality}) async =>
            'https://example.com/audio.mp4?iq=1',
      );

      final result = await resolver.resolve('dQw4w9WgXcQ');

      expect(result, 'https://example.com/audio.mp4?iq=1');
    });

    test('returns null when the lookup throws', () async {
      final resolver = StreamResolver(
        lookup: (String videoId, {String? quality}) async =>
            throw Exception('network down'),
      );

      final result = await resolver.resolve('dQw4w9WgXcQ');

      expect(result, isNull);
    });

    test('returns null when the lookup returns null', () async {
      final resolver = StreamResolver(
        lookup: (String videoId, {String? quality}) async => null,
      );

      final result = await resolver.resolve('dQw4w9WgXcQ');

      expect(result, isNull);
    });

    test('forwards the quality setting to the lookup', () async {
      String? receivedQuality;
      final resolver = StreamResolver(
        lookup: (String videoId, {String? quality}) async {
          receivedQuality = quality;
          return 'https://example.com/audio.mp4?iq=1';
        },
      );

      await resolver.resolve('dQw4w9WgXcQ', quality: '128kbps');

      expect(receivedQuality, '128kbps');
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

  group('pickAudioStream (quality selection)', () {
    // Helper mirroring YouTube's real audio-only ladder: fixed Opus bitrates
    // from which the resolver must choose.
    AudioOnlyStreamInfo stream(int kbps, int tag) => AudioOnlyStreamInfo(
          VideoId('dQw4w9WgXcQ'),
          tag,
          Uri.parse('https://example.com/$tag'),
          StreamContainer.webM,
          const FileSize(0),
          Bitrate(kbps * 1000),
          'opus',
          '${kbps}k',
          const [],
          MediaType('audio', 'webm'),
          null,
        );

    StreamManifest manifestWith(List<AudioOnlyStreamInfo> streams) =>
        StreamManifest(streams);

    test("returns the highest stream for '320kbps'", () {
      final manifest = manifestWith([stream(70, 249), stream(160, 251)]);

      final picked = pickAudioStream(manifest, '320kbps');

      expect(picked!.tag, 251);
    });

    test('returns the highest stream for null quality', () {
      final manifest = manifestWith([stream(70, 249), stream(160, 251)]);

      final picked = pickAudioStream(manifest, null);

      expect(picked!.tag, 251);
    });

    test("returns the highest stream at or below '128kbps'", () {
      final manifest = manifestWith(
        [stream(50, 248), stream(96, 250), stream(160, 251)],
      );

      final picked = pickAudioStream(manifest, '128kbps');

      expect(picked!.tag, 250);
    });

    test("returns the highest stream at or below '192kbps'", () {
      final manifest = manifestWith(
        [stream(70, 249), stream(128, 250), stream(160, 251)],
      );

      final picked = pickAudioStream(manifest, '192kbps');

      expect(picked!.tag, 251);
    });

    test('falls back to the lowest stream when all exceed the target', () {
      final manifest = manifestWith([stream(160, 251), stream(256, 999)]);

      final picked = pickAudioStream(manifest, '128kbps');

      expect(picked!.tag, 251);
    });

    test('returns null when the manifest has no audio-only streams', () {
      final picked = pickAudioStream(manifestWith(const []), '128kbps');

      expect(picked, isNull);
    });
  });
}
