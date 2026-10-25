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
Future<String?> defaultLookup(String videoId) => resolveWithRetry(
      _extractCandidates,
      probeUrl,
      videoId,
    );

Future<List<String>?> _extractCandidates(String videoId) async {
  final yt = YoutubeExplode();
  try {
    final manifest = await yt.videos.streamsClient.getManifest(videoId);
    final candidates = <String>[
      if (manifest.audioOnly.isNotEmpty)
        manifest.audioOnly.withHighestBitrate().url.toString(),
      if (manifest.muxed.isNotEmpty)
        manifest.muxed.withHighestBitrate().url.toString(),
    ];
    return candidates.isEmpty ? null : candidates;
  } finally {
    yt.close();
  }
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
    } catch (_) {
      // Extraction failures are reported by StreamResolver.resolve.
      return null;
    }
    if (candidates == null || candidates.isEmpty) {
      return null;
    }
    for (final url in candidates) {
      if (await probe(url)) {
        return url;
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
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('range', 'bytes=0-');
    final resp = await req.close().timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200 && resp.statusCode != 206) {
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
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}
