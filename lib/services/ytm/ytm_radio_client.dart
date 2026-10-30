// YouTube Music song-radio client (Innertube `youtubei/v1/next`).
//
// Request shape mirrors ytmusicapi's `get_watch_playlist` for the song-radio
// playlistId (`RD<videoId>`): the same WEB_REMIX client context the search
// client sends, and likewise no cookies, no API key, and no visitor id —
// verified live that the minimal context returns the full radio queue.
//
// Pure Dart (no Flutter imports): unit-testable without a widget env.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ytm_search_client.dart' show YtmHttpFetch, kYtmUserAgent;
import 'ytm_search_parser.dart';

/// Re-exported so callers can name result types without importing the parser.
export 'ytm_search_parser.dart' show YtmSongResult;

/// Where the request goes.
const String kYtmRadioUrl =
    'https://music.youtube.com/youtubei/v1/next?alt=json';

/// Builds the song-radio playlistId for [videoId] ("RD" prefix).
String ytmRadioPlaylistId(String videoId) => 'RD$videoId';

/// A single YouTube Music song-radio round-trip.
///
/// Failures never throw: every error path (bad seed, network, HTTP status,
/// timeout, malformed JSON, shape drift, invalid videoId) degrades to `[]`,
/// matching [YtmSearchClient]'s empty-list contract.
class YtmRadioClient {
  YtmRadioClient({
    YtmHttpFetch? fetch,
    this.timeout = const Duration(seconds: 30),
  }) : _injectedFetch = fetch;

  /// Injectable transport (same signature as the search client's), so tests
  /// never open a socket and production shares one transport pattern.
  final YtmHttpFetch? _injectedFetch;

  /// Per-request timeout. A stalled connection degrades to `[]`.
  final Duration timeout;

  /// Fetches the song radio for [videoId] and parses the queue rows.
  ///
  /// The seed song itself frequently appears as the first row (sometimes
  /// under a different videoId — same song, alternate upload); callers
  /// dedupe by id AND normalized title, so the parser returns rows as-is.
  Future<List<YtmSongResult>> getRadio(String videoId) async {
    final trimmed = videoId.trim();
    if (trimmed.isEmpty) return [];
    try {
      final body = buildRadioRequestBody(trimmed);
      final fetch = _injectedFetch;
      final decoded = fetch != null
          ? await fetch(kYtmRadioUrl, body)
          : await _post(kYtmRadioUrl, body);
      return parseYtmRadioSongs(decoded);
    } on TimeoutException {
      return [];
    } catch (_) {
      return [];
    }
  }

  /// The POST body the radio request sends, exposed for tests.
  Map<String, dynamic> buildRadioRequestBody(String videoId) {
    final now = DateTime.now().toUtc();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    return {
      'context': {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': '1.$stamp.01.00',
          'hl': 'en',
          'gl': 'US',
        },
        'user': <String, dynamic>{},
      },
      'videoId': videoId,
      'playlistId': ytmRadioPlaylistId(videoId),
      'contentCheckOk': true,
      'racyCheckOk': true,
      'isObserved': true,
    };
  }

  /// Default transport: same shape as the search client's `_post`.
  Future<dynamic> _post(String url, Map<String, dynamic> body) async {
    final client = HttpClient();
    try {
      client.autoUncompress = true;
      client.connectionTimeout = timeout;
      final request =
          await client.postUrl(Uri.parse(url)).timeout(
              timeout,
              onTimeout: () => throw TimeoutException('ytm radio connect'));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set('origin', 'https://music.youtube.com');
      request.headers.set(HttpHeaders.userAgentHeader, kYtmUserAgent);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip');
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) {
        // Body is drained (not logged): it is server noise, never secrets.
        await response.drain<void>();
        return null;
      }
      final text = await utf8.decodeStream(response).timeout(timeout);
      return jsonDecode(text);
    } finally {
      client.close(force: true);
    }
  }
}
