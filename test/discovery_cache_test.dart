import 'dart:io';

// Search-result cache in DiscoveryService.
//
// Pins: repeat searches for the same query cost one network round-trip,
// case/whitespace variants share the cache, empty results (transient
// failures) are never cached, expired entries re-fetch, and the LRU bound
// holds.
import 'package:caputune/services/discovery_lookup_io.dart';
import 'package:caputune/services/discovery_service.dart';
import 'package:caputune/services/ytm/ytm_search_client.dart';
import 'package:flutter_test/flutter_test.dart';

int _fetches = 0;

YtmSearchClient _countingClient() {
  return _CountingClient();
}

class _CountingClient implements YtmSearchClient {
  @override
  Future<List<YtmSongResult>> searchSongs(String query) async {
    _fetches++;
    if (query == 'empty') return const [];
    return [YtmSongResult(id: 'r-$query', title: query, artist: 'A')];
  }

  @override
  Future<List<YtmSearchSuggestion>> searchSuggestions(String input) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
void main() {
  setUp(() {
    _fetches = 0;
    DiscoveryService.searchCacheTtl = const Duration(minutes: 5);
    ytmClientFactoryForTest = _countingClient;
    DiscoveryService.resetForTest();
  });

  tearDown(() {
    ytmClientFactoryForTest = null;
    DiscoveryService.resetForTest();
  });

  test('a repeat query is served from cache without a new request',
      () async {
    final first = await DiscoveryService.search('lofi');
    expect(_fetches, 1);
    final second = await DiscoveryService.search('lofi');
    expect(_fetches, 1, reason: 'the repeat query must not hit the network');
    expect(second.map((s) => s.id), first.map((s) => s.id));
    expect(DiscoveryService.hasCachedSearch('lofi'), isTrue);
  });

  test('case and whitespace variants share one cache entry', () async {
    await DiscoveryService.search('EBA');
    await DiscoveryService.search('eba');
    await DiscoveryService.search('  eba  ');
    expect(_fetches, 1, reason: 'all variants normalize to the same key');
  });

  test('empty results are never cached (transient failures stay transient)',
      () async {
    await DiscoveryService.search('empty');
    expect(_fetches, 1);
    await DiscoveryService.search('empty');
    expect(_fetches, 2,
        reason: 'an empty answer must be re-fetched, not remembered');
  });

  test('expired entries are re-fetched', () async {
    DiscoveryService.searchCacheTtl = Duration.zero;
    await DiscoveryService.search('lofi');
    await DiscoveryService.search('lofi');
    expect(_fetches, 2, reason: 'a zero TTL must always re-fetch');
  });

  test('the cache is LRU-bounded', () async {
    for (var i = 0; i < 40; i++) {
      await DiscoveryService.search('query $i');
    }
    expect(
      DiscoveryService.cachedSearchQueries.length,
      lessThanOrEqualTo(32),
    );
    // The oldest entries were evicted; a re-search re-fetches.
    _fetches = 0;
    await DiscoveryService.search('query 0');
    expect(_fetches, 1);
  });

  test('clearSearchCache forces the next search to re-fetch', () async {
    await DiscoveryService.search('lofi');
    DiscoveryService.clearSearchCache();
    await DiscoveryService.search('lofi');
    expect(_fetches, 2);
  });

  test('a failed request reports failure and is not cached', () async {
    // Use a factory that throws on every call to simulate offline.
    ytmClientFactoryForTest = () => _ThrowingClient();
    final (songs, failed) = await DiscoveryService.searchDetailed('lofi');
    expect(songs, isEmpty);
    expect(failed, isTrue, reason: 'the request did not complete');
    expect(DiscoveryService.hasCachedSearch('lofi'), isFalse,
        reason: 'a failure must not be served for 5 minutes');
  });
}

class _ThrowingClient implements YtmSearchClient {
  @override
  Future<List<YtmSongResult>> searchSongs(String query) async =>
      throw const SocketException('offline');

  @override
  Future<List<YtmSearchSuggestion>> searchSuggestions(String input) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

