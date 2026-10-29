import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Extracts candidate stream URLs for [videoId] in preference order;
/// null when the manifest has no playable streams.
typedef AudioExtract = Future<List<String>?> Function(String videoId);

/// Returns true when [url] answers a ranged request (i.e. is playable).
typedef UrlProbe = Future<bool> Function(String url);

/// Resolves [videoId] to a playable stream URL using youtube_explode_dart,
/// verifying each candidate URL before returning it.
///
/// [quality] selects which audio-only stream is preferred (see
/// [pickAudioStream]); null keeps the previous highest-bitrate behaviour.
///
/// YouTube intermittently hands out stream URLs that answer 403 at the CDN,
/// and stubs audio-only URLs more often than muxed ones. Candidates are
/// therefore probed with a small open-ended ranged request in preference
/// order (audio-only first, then muxed), and extraction is retried with
/// backoff while every candidate is dead.
///
/// Returns null when the manifest contains no playable streams, when
/// extraction fails, or when no live URL is obtained within [maxAttempts]
/// (extraction errors propagate to the caller — `StreamResolver.resolve` in
/// `stream_resolver.dart` converts them to null).
Future<String?> defaultLookup(
  String videoId, {
  String? quality,
}) =>
    resolveWithRetry(
      (id) => _extractCandidates(id, quality: quality),
      probeUrl,
      videoId,
    );

Future<List<String>?> _extractCandidates(
  String videoId, {
  String? quality,
}) async {
  final yt = YoutubeExplode();
  try {
    final manifest = await yt.videos.streamsClient.getManifest(videoId);
    final audio = pickAudioStream(manifest, quality);
    final candidates = <String>[
      if (audio != null) audio.url.toString(),
      if (manifest.muxed.isNotEmpty)
        manifest.muxed.withHighestBitrate().url.toString(),
    ];
    return candidates.isEmpty ? null : candidates;
  } finally {
    yt.close();
  }
}

/// Picks the audio-only stream that best matches the user's quality setting.
///
/// '320kbps' keeps the historical behaviour of taking the highest available
/// bitrate (YouTube's audio-only top out around 160 kbps Opus, so 320 is
/// effectively "best there is"). Lower targets pick the closest stream at or
/// below the target — saving bandwidth without undershooting — and fall back
/// to the lowest stream when everything exceeds the target. Unknown or null
/// quality values behave like '320kbps'.
@visibleForTesting
AudioOnlyStreamInfo? pickAudioStream(StreamManifest manifest, String? quality) {
  if (manifest.audioOnly.isEmpty) return null;
  final streams = manifest.audioOnly.toList()
    ..sort((a, b) => a.bitrate.compareTo(b.bitrate));
  final targetKbps = switch (quality) {
    '128kbps' => 128,
    '192kbps' => 192,
    _ => 320,
  };
  if (targetKbps >= 320) {
    return streams.last;
  }
  // Closest stream at or below the target, else the cheapest available.
  for (final stream in streams.reversed) {
    if (stream.bitrate.kiloBitsPerSecond <= targetKbps) return stream;
  }
  return streams.first;
}

/// Extracts and probes up to [maxAttempts] times, returning the first
/// candidate URL that [probe] confirms live.
@visibleForTesting
Future<String?> resolveWithRetry(
  AudioExtract extract,
  UrlProbe probe,
  String videoId, {
  int maxAttempts = 3,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    List<String>? candidates;
    try {
      candidates = await extract(videoId);
    } catch (e) {
      // Extraction failures are reported by StreamResolver.resolve.
      debugPrint('[resolve] attempt $attempt/$maxAttempts '
          'extraction threw ${e.runtimeType}');
      return null;
    }
    if (candidates == null || candidates.isEmpty) {
      debugPrint('[resolve] attempt $attempt/$maxAttempts '
          'manifest has no streams');
      return null;
    }
    for (var i = 0; i < candidates.length; i++) {
      final host = Uri.tryParse(candidates[i])?.host ?? '(unparsable)';
      final live = await probe(candidates[i]);
      if (!live) {
        debugPrint(
            '[resolve] attempt $attempt candidate $i '
            '($host) dead, trying next');
      }
      if (live) {
        debugPrint('[resolve] attempt $attempt candidate $i ($host) live');
        return candidates[i];
      }
    }
    if (attempt < maxAttempts - 1) {
      await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
    }
  }
  return null;
}

/// Cheap liveness check: issues an open-ended ranged request for [url] and
/// stops after the first 64 bytes.
///
/// The range must be open-ended (`bytes=0-`): the CDN answers 206 to small
/// *bounded* ranges even for URLs it would refuse to actually stream, so a
/// bounded probe cannot detect the 403 state.
Future<bool> probeUrl(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  // Host-only logging: credential-adjacent stream args stay out of logs.
  final host = Uri.tryParse(url)?.host ?? '(unparsable url)';
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('range', 'bytes=0-');
    final resp = await req.close().timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200 && resp.statusCode != 206) {
      debugPrint('[probe] $host answered HTTP ${resp.statusCode} — not live');
      return false;
    }
    var bytes = 0;
    await for (final chunk in resp) {
      bytes += chunk.length;
      if (bytes >= 64) {
        break;
      }
    }
    return true;
  } catch (e) {
    // Evidence of the failure stage on the Dart side (SocketException,
    // TimeoutException, …). Host only; never the signed URL.
    debugPrint('[probe] $host unreachable: ${e.runtimeType}');
    return false;
  } finally {
    client.close(force: true);
  }
}
