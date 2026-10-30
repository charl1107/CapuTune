// YouTube Music public search client (Innertube `youtubei/v1/search`).
//
// Request shape mirrors ytmusicapi (https://github.com/sigma67/ytmusicapi),
// MIT License — Copyright (c) sigma67: the WEB_REMIX client context and the
// songs-filter search params. Public search needs no cookies, no API key,
// and no visitor id, so none are sent — this client deliberately never
// touches credentials or user-specific headers.
//
// Pure Dart (no Flutter imports): unit-testable without a widget env.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ytm_search_parser.dart';

/// Re-exported so callers of [YtmSearchClient] (and its tests) can name the
/// result types without importing the parser directly.
export 'ytm_search_parser.dart' show YtmSongResult, YtmSearchSuggestion;

/// Where the request goes.
const String kYtmSearchUrl =
    'https://music.youtube.com/youtubei/v1/search?alt=json';

/// WEB_REMIX client context; `clientVersion` follows ytmusicapi's
/// `1.YYYYMMDD.01.00` date-based scheme.
const String _kClientName = 'WEB_REMIX';

/// Innertube search params selecting the "Songs" filter shelf.
const String kYtmSongsParams = 'EgWKAQIIAWoMEA4QChADEAQQCRAF';

/// Browser-like user agent, matching what ytmusicapi sends. No cookies,
/// credentials, or user-specific headers are ever attached.
const String kYtmUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:88.0) Gecko/20100101 Firefox/88.0';

/// Signature of the injectable transport: POSTs [body] to [url] and returns
/// the decoded JSON response (or null on a non-200/no-content outcome).
typedef YtmHttpFetch = Future<dynamic> Function(
  String url,
  Map<String, dynamic> body,
);

/// A single YouTube Music search round-trip.
///
/// Failures never throw: every error path (bad query, network, HTTP status,
/// timeout, malformed JSON, shape drift) degrades to `[]`, matching the
/// empty-list contract `DiscoveryService` already gives the UI.
class YtmSearchClient {
  YtmSearchClient(
      {YtmHttpFetch? fetch, this.timeout = const Duration(seconds: 30)})
      : _injectedFetch = fetch;

  /// Injectable transport. When set, no socket is ever opened (tests use
  /// this; production leaves it null).
  final YtmHttpFetch? _injectedFetch;

  /// Per-request timeout. A stalled connection degrades to `[]`, mirroring
  /// `DiscoveryService`'s bounded-request contract.
  final Duration timeout;

  /// Where the request goes for query suggestions.
  static const String kYtmSuggestionsUrl =
      'https://music.youtube.com/youtubei/v1/music/get_search_suggestions'
      '?alt=json';

  /// Asks YTM for query completions of [input] ("metal" → "metallica",
  /// "metallica songs", ...). Never throws: every failure degrades to `[]`,
  /// matching the client's other request paths.
  Future<List<YtmSearchSuggestion>> searchSuggestions(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return [];
    try {
      final body = buildSuggestionRequestBody(trimmed);
      final fetch = _injectedFetch;
      final decoded = fetch != null
          ? await fetch(kYtmSuggestionsUrl, body)
          : await _post(kYtmSuggestionsUrl, body);
      return parseYtmSearchSuggestions(decoded);
    } on TimeoutException {
      return [];
    } catch (_) {
      return [];
    }
  }

  /// The POST body the suggestions request sends, exposed for tests.
  Map<String, dynamic> buildSuggestionRequestBody(String input) {
    final now = DateTime.now().toUtc();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    return {
      'context': {
        'client': {
          'clientName': _kClientName,
          'clientVersion': '1.$stamp.01.00',
          'hl': 'en',
          'gl': 'US',
        },
        'user': <String, dynamic>{},
      },
      'input': input,
    };
  }

  /// Searches the YouTube Music catalog (songs filter) for [query].
  ///
  /// Empty or blank queries short-circuit to `[]` without any request.
  Future<List<YtmSongResult>> searchSongs(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    try {
      final body = buildRequestBody(trimmed);
      final fetch = _injectedFetch;
      final decoded =
          fetch != null
              ? await fetch(kYtmSearchUrl, body)
              : await _post(kYtmSearchUrl, body);
      return parseYtmSongs(decoded);
    } on TimeoutException {
      return [];
    } catch (_) {
      return [];
    }
  }

  /// The POST body this client sends, exposed for tests and transparency.
  Map<String, dynamic> buildRequestBody(String query) {
    final now = DateTime.now().toUtc();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    return {
      'context': {
        'client': {
          'clientName': _kClientName,
          'clientVersion': '1.$stamp.01.00',
          'hl': 'en',
          'gl': 'US',
        },
        'user': <String, dynamic>{},
      },
      'query': query,
      'params': kYtmSongsParams,
    };
  }

  /// Default transport over `dart:io` `HttpClient`.
  ///
  /// The client is created per request and force-closed afterwards rather
  /// than kept alive: searches are user-paced (one per keystroke at most),
  /// so connection reuse buys nothing worth the leak risk.
  Future<dynamic> _post(String url, Map<String, dynamic> body) async {
    final client = HttpClient();
    try {
      client.autoUncompress = true;
      client.connectionTimeout = timeout;
      final request =
          await client.postUrl(Uri.parse(url)).timeout(
              timeout,
              onTimeout: () => throw TimeoutException('ytm search connect'));
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
