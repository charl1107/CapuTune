import '../models/song.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'discovery_lookup_stub.dart'
    if (dart.library.io) 'discovery_lookup_io.dart' as lookup;

/// On-device discovery: YouTube search and playlist import.
///
/// The actual work is delegated to a platform-specific lookup chosen via
/// conditional import: the real implementation lives in
/// `discovery_lookup_io.dart` (uses youtube_explode_dart, VM/mobile only),
/// while `discovery_lookup_stub.dart` keeps the web build compiling by
/// returning an empty list. Lookups swallow their own errors and return `[]`,
/// so callers never see an exception from discovery.
class DiscoveryService {
  DiscoveryService._();

  /// Upper bound on a single discovery request.
  ///
  /// The backend that predated this service capped requests at 60s; on
  /// device a stalled connection must not leave a screen spinning forever,
  /// so each lookup is bounded at 30s and a timeout degrades to the same
  /// empty-list failure contract as any other error.
  static const Duration _requestTimeout = Duration(seconds: 30);

  // ── Search-result cache ─────────────────────────────────────────────
  //
  // Repeated searches for the same query (re-typing, returning to the tab,
  // the recommendation fallback) re-hit the network for identical results.
  // A small in-memory LRU keyed by the normalized query serves recent
  // answers instantly and keeps repeated searches from costing a new
  // round-trip (and new thumbnail downloads) every time.
  //
  // Bounds: at most [_maxEntries] entries (a ranked result list is a few
  // hundred bytes), each expiring after [_ttl]. Empty results are never
  // cached — a transient network failure must not stick for five minutes.

  /// How long a cached search result stays fresh. Non-const so tests can
  /// shrink it to pin the expiry behavior; production always uses the
  /// initialized five minutes.
  static Duration searchCacheTtl = const Duration(minutes: 5);

  /// Maximum number of cached queries.
  static const int _maxCacheEntries = 32;

  final Map<String, _SearchCacheEntry> _searchCache = {};

  /// True when [query] has a fresh cached result (same key the search uses).
  static bool hasCachedSearch(String query) =>
      _instance.hasFreshCachedResult(query);

  /// The queries currently cached, oldest first (LRU eviction order).
  static Iterable<String> get cachedSearchQueries =>
      _instance._searchCache.keys;

  /// Drops every cached result (fresh or expired).
  static void clearSearchCache() => _instance._searchCache.clear();

  /// Test-only: resets the singleton's cache and TTL so suites start
  /// clean regardless of execution order.
  @visibleForTesting
  static void resetForTest() {
    _instance._searchCache.clear();
    searchCacheTtl = const Duration(minutes: 5);
  }

  bool hasFreshCachedResult(String query) {
    final entry = _searchCache[_normalizeQuery(query)];
    if (entry == null) return false;
    return DateTime.now().difference(entry.fetchedAt) < searchCacheTtl;
  }

  /// Drops only entries older than [ttl]; called on a timer-free basis
  /// whenever a new result is stored, so the cache cannot grow stale
  /// entries without bound even if it is never read again.
  void _evictExpired() {
    final now = DateTime.now();
    _searchCache.removeWhere(
        (_, entry) => now.difference(entry.fetchedAt) >= searchCacheTtl);
  }

  static String _normalizeQuery(String query) {
    // Trim + lowercase + collapse whitespace so "EBA", " eba " and "eba"
    // share one entry (ranking is case/whitespace-insensitive anyway).
    return query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Searches YouTube for [query] and returns the matches as [Song]s.
  static Future<List<Song>> search(String query) =>
      DiscoveryService._instance._search(query);

  /// Same pipeline as [search], but reports whether the request failed
  /// (offline / blocked endpoint / timeout) instead of just returning an
  /// empty list. The UI uses this to show a retry state instead of a
  /// misleading "no results" message.
  static Future<(List<Song>, bool)> searchDetailed(String query) =>
      DiscoveryService._instance._searchDetailed(query);

  static final DiscoveryService _instance = DiscoveryService._();

  Future<List<Song>> _search(String query) async =>
      (await _searchDetailed(query)).$1;

  Future<(List<Song>, bool)> _searchDetailed(String query) async {
    final key = _normalizeQuery(query);
    if (key.isEmpty) return (<Song>[], false);

    _evictExpired();
    final fresh = _searchCache.remove(key);
    if (fresh != null && _isFresh(fresh)) {
      // Re-insert to mark the entry most-recently-used.
      _searchCache[key] = fresh;
      return (fresh.songs, false);
    }

    final (songs, failed) =
        await lookup.searchRemoteDetailed(query).timeout(_requestTimeout, onTimeout: () => (const <Song>[], true));
    if (songs.isNotEmpty) {
      _searchCache[key] = _SearchCacheEntry(songs, DateTime.now());
      while (_searchCache.length > _maxCacheEntries) {
        _searchCache.remove(_searchCache.keys.first);
      }
    }
    return (songs, failed);
  }

  bool _isFresh(_SearchCacheEntry entry) =>
      DateTime.now().difference(entry.fetchedAt) < searchCacheTtl;

  /// Imports the songs of the YouTube playlist at [url], or `[]` when the
  /// url is invalid or the fetch fails.
  static Future<List<Song>> importPlaylist(String url) => lookup
      .importPlaylistRemote(url)
      .timeout(_requestTimeout, onTimeout: () => []);
}

class _SearchCacheEntry {
  final List<Song> songs;
  final DateTime fetchedAt;
  const _SearchCacheEntry(this.songs, this.fetchedAt);
}
