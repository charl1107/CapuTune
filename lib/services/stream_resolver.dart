import 'stream_resolver_lookup_stub.dart'
    if (dart.library.io) 'stream_resolver_lookup_io.dart' as lookup_io;

/// Signature for the platform-specific audio URL lookup.
typedef AudioUrlLookup = Future<String?> Function(String videoId);

/// Resolves a YouTube video ID to a playable audio stream URL.
///
/// The actual extraction is delegated to a platform-specific lookup chosen via
/// conditional import: the real implementation lives in
/// `stream_resolver_lookup_io.dart` (uses youtube_explode_dart, VM/mobile
/// only), while `stream_resolver_lookup_stub.dart` keeps the web build
/// compiling by returning null. Any lookup failure is swallowed and reported
/// as null so callers never see an exception from resolution.
class StreamResolver {
  StreamResolver({AudioUrlLookup? lookup})
      : _lookup = lookup ?? lookup_io.defaultLookup;

  final AudioUrlLookup _lookup;

  /// Returns the audio stream URL for [videoId], or null when extraction
  /// fails, is unsupported on this platform, or no audio stream exists.
  Future<String?> resolve(String videoId) async {
    try {
      return await _lookup(videoId);
    } catch (e) {
      // ignore: avoid_print
      print('[resolve] extraction failed for $videoId: $e');
      return null;
    }
  }
}
