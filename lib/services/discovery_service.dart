import '../models/song.dart';
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

  /// Searches YouTube for [query] and returns the matches as [Song]s.
  static Future<List<Song>> search(String query) => lookup
      .searchRemote(query)
      .timeout(_requestTimeout, onTimeout: () => []);

  /// Imports the songs of the YouTube playlist at [url], or `[]` when the
  /// url is invalid or the fetch fails.
  static Future<List<Song>> importPlaylist(String url) => lookup
      .importPlaylistRemote(url)
      .timeout(_requestTimeout, onTimeout: () => []);
}
