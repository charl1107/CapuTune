import 'dart:async';
import 'dart:io';

import 'cipher_service.dart';

/// Serves decrypted audio from an app-private encrypted `.ct` file over a
/// loopback-only HTTP endpoint, so media_kit (libmpv) can play it.
///
/// Why this exists: the offline `.ct` path originally used just_audio, which
/// is ExoPlayer on Android. The app had already migrated every *other* playback
/// path (streaming + imported files) to media_kit precisely because ExoPlayer
/// fails to load sources on the target device. The `.ct` path was the one
/// holdout and so failed the same way: `setAudioSource` threw, `_tryPlayLocal`
/// returned false, and playback fell through to network streaming (which is
/// impossible offline) — producing "Stream extraction failed".
///
/// Playing through media_kit means the audio now rides the same proven libmpv
/// + libcurl stack as streaming. Decryption stays strictly in RAM: bytes are
/// XOR-decrypted as they are streamed to the socket, so no plaintext audio is
/// ever written to disk and the `.ct` file remains the only thing at rest.
///
/// The server binds only to 127.0.0.1 (never a public interface), supports
/// HTTP Range requests so libmpv can seek, and sniffs the container from the
/// decrypted magic bytes so libmpv gets an accurate Content-Type.
class LocalDecryptServer {
  HttpServer? _server;
  final Map<String, File> _files = {};
  Future<void>? _starting;

  /// True once the loopback server is accepting connections.
  bool get isRunning => _server != null;

  /// Registers [file] (an encrypted `.ct`) under [id] and returns the loopback
  /// URL libmpv should open. Starts the server on first use. Re-registering the
  /// same [id] replaces the previous file, so replaying a song is safe.
  Future<Uri> register(String id, File file) async {
    if (_starting != null) {
      await _starting;
    } else {
      _starting = _start();
      await _starting;
    }
    _files[id] = file;
    final port = _server!.port;
    return Uri.parse('http://${InternetAddress.loopbackIPv4.address}:$port/$id');
  }

  Future<void> _start() async {
    // Ephemeral port on the loopback interface only; never externally visible.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(
      (request) {
        unawaited(_handle(request));
      },
      onError: (_) {
        // A single malformed connection must not take the whole server down.
      },
      cancelOnError: true,
    );
    _server = server;
  }

  Future<void> _handle(HttpRequest request) async {
    final id = request.uri.pathSegments.isNotEmpty
        ? request.uri.pathSegments.first
        : '';
    final file = _files[id];
    final response = request.response;

    if (file == null || !await file.exists()) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    final total = await file.length(); // XOR preserves length
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    var start = 0;
    var end = total - 1; // inclusive
    var partial = false;

    if (rangeHeader != null) {
      final match = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rangeHeader);
      if (match != null) {
        final startStr = match.group(1);
        final endStr = match.group(2);
        if (startStr != null && startStr.isNotEmpty) {
          start = int.parse(startStr);
        }
        if (endStr != null && endStr.isNotEmpty) {
          end = int.parse(endStr);
        }
        if (start >= total) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
          await response.close();
          return;
        }
        if (end >= total) end = total - 1;
        partial = true;
      }
    }

    final contentLength = end - start + 1;
    response.statusCode =
        partial ? HttpStatus.partialContent : HttpStatus.ok;
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(HttpHeaders.contentTypeHeader, await _sniffType(file));
    if (partial) {
      response.headers.set(HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$total');
    }
    response.contentLength = contentLength;

    if (request.method == 'HEAD') {
      await response.close();
      return;
    }

    // Decrypt in RAM chunk-by-chunk at the correct absolute offset so any seek
    // position yields the exact original bytes (the keystream is offset-indexed).
    var offset = start;
    await for (final chunk in file.openRead(start, end + 1)) {
      response.add(CipherService.transformChunk(chunk, offset));
      offset += chunk.length;
    }
    await response.close();
  }

  /// Detects the container from the decrypted magic bytes so libmpv receives an
  /// accurate Content-Type. Falls back to a generic audio type; libmpv sniffs
  /// content regardless, so this is a hint rather than a hard requirement.
  Future<String> _sniffType(File file) async {
    try {
      final header = await file.openRead(0, 12).first;
      final plain = CipherService.transformChunk(header, 0);
      if (plain.length >= 8 &&
          plain[4] == 0x66 && // 'f'
          plain[5] == 0x74 && // 't'
          plain[6] == 0x79 && // 'y'
          plain[7] == 0x70) {
        // 'ftyp' box → MP4 family (m4a).
        return 'audio/mp4';
      }
      if (plain.length >= 4 &&
          plain[0] == 0x1A && // EBML magic → webm/opus
          plain[1] == 0x45 &&
          plain[2] == 0xDF &&
          plain[3] == 0xA3) {
        return 'audio/webm';
      }
      // ID3 tag or MPEG frame sync → mp3.
      return 'audio/mpeg';
    } catch (_) {
      return 'application/octet-stream';
    }
  }

  Future<void> dispose() async {
    final server = _server;
    _server = null;
    _starting = null;
    _files.clear();
    if (server != null) {
      await server.close(force: true);
    }
  }
}
