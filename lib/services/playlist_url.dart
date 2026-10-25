/// Validation and source detection for playlist import URLs.
///
/// Kept free of Flutter and network dependencies so it can be unit tested in
/// isolation and reused by both the import flow and future import sources.
class PlaylistUrl {
  PlaylistUrl._();

  /// A playlist source we know how to fetch.
  static const String youtube = 'youtube';

  /// Validates a user-entered playlist [url].
  ///
  /// Returns the detected source identifier (currently only [youtube]) when
  /// the URL is well-formed, uses http/https, points at a supported host, and
  /// carries the parameters the fetcher needs. Returns null otherwise, so
  /// callers can present a single, honest error message without leaking
  /// parsing internals.
  static String? detectSource(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return null;

    // Only http/https — reject file:, javascript:, data:, content: etc.
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;

    // Reject credentials in the URL (user:pass@host) — not needed and a
    // common way to smuggle unexpected authority into a fetch.
    if (uri.userInfo.isNotEmpty) return null;

    final host = uri.host.toLowerCase();
    if (_isYoutubeHost(host)) {
      // YouTube playlist URLs carry the playlist id in `list`. A bare video
      // URL (watch?v=...) is not a playlist and cannot be imported here.
      final list = uri.queryParameters['list'];
      if (list != null && list.trim().isNotEmpty) return youtube;
      return null;
    }

    return null;
  }

  /// Extracts the YouTube playlist id from [url], or null when absent.
  static String? youtubePlaylistId(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return null;
    final list = uri.queryParameters['list'];
    if (list == null || list.trim().isEmpty) return null;
    return list;
  }

  /// True when [url] is a fetchable, supported playlist URL.
  static bool isValid(String url) => detectSource(url) != null;

  static bool _isYoutubeHost(String host) {
    return host == 'youtube.com' ||
        host == 'www.youtube.com' ||
        host == 'm.youtube.com' ||
        host == 'music.youtube.com' ||
        host == 'youtu.be' ||
        host == 'www.youtu.be';
  }

  /// Human-readable description of what we support, surfaced in the import
  /// dialog so users understand the limitation before pasting.
  static const String supportedSourcesDescription =
      'Supported: public YouTube playlists (youtube.com/playlist?list=...)';
}
