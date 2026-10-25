/// Web implementation of the audio URL lookup.
///
/// `youtube_explode_dart` is not web-safe, so the real lookup lives in
/// `stream_resolver_lookup_io.dart` and is pulled in via conditional import on
/// `dart.library.io`. On the web this stub is used instead and always reports
/// that no stream URL is available.
Future<String?> defaultLookup(String videoId) async => null;
