// Phase 1 download-reliability coverage: bounded retry decisions, Dio
// timeout classification, startup .ct.tmp sweep, and the real download
// pipeline (atomic .ct write, cancellation, stall abort) driven against an
// on-loopback HTTP server — no external network needed.
//
// Hive + a fake PathProvider give the real StorageService/Documents gate the
// same runtime the app uses.
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:caputune/models/song.dart';
import 'package:caputune/services/cipher_service.dart';
import 'package:caputune/services/download_service.dart';
import 'package:caputune/services/download_service_mobile.dart'
    show cleanupStaleTmp;
import 'package:caputune/services/storage_service.dart';
import 'package:caputune/services/stream_resolver.dart';

Song _song(String id) => Song(
      id: id,
      title: 'T$id',
      artist: 'A',
      album: 'Alb',
    );

/// Local HTTP server with scripted behaviour per test.
class _TestServer {
  final HttpServer server;

  Uri get url => Uri.parse('http://127.0.0.1:${server.port}/');

  _TestServer._(this.server);

  static Future<_TestServer> serve(
    Future<void> Function(HttpRequest request) handler,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      // dart:io buffers small response writes until the message ends;
      // streaming responses need per-chunk delivery.
      request.response.bufferOutput = false;
      // Tests deliberately abandon responses (stalls/cancels); the resulting
      // socket errors after client cancellation are expected, not fatal.
      handler(request).catchError((Object _) {});
    });
    return _TestServer._(server);
  }

  Future<void> close() => server.close(force: true);
}

class _FakeResolver extends StreamResolver {
  final Uri url;

  _FakeResolver(this.url);

  @override
  Future<String?> resolve(String videoId, {String? quality}) async =>
      url.toString();
}

class _FakePathProvider extends PathProviderPlatform {
  final Directory root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;
}

Future<Directory> _documents() {
  final instance = PathProviderPlatform.instance;
  if (instance is! _FakePathProvider) {
    throw StateError('no test path provider installed');
  }
  return Future.value(instance.root);
}

void main() {
  // NOTE: no TestWidgetsFlutterBinding.ensureInitialized() here on purpose —
  // with the Flutter binding active, HttpClient traffic is hardened to 400
  // and the loopback download servers below could never be reached.
  late Directory artifacts;

  setUpAll(() async {
    artifacts = await Directory.systemTemp.createTemp('caputune_dl_test');
    Hive.init(artifacts.path);
  });

  setUp(() async {
    // Fresh boxes for every test so state never leaks between cases.
    await Hive.deleteFromDisk();
    await StorageService.init();
    // Documents root unique per test so file assertions never overlap.
    final documents = Directory(
      '${artifacts.path}/docs_${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(documents);
  });

  tearDownAll(() async {
    await Hive.close();
    if (artifacts.existsSync()) {
      artifacts.deleteSync(recursive: true);
    }
  });

  group('isTransientDownloadError', () {
    RequestOptions opts() => RequestOptions(path: '/x');

    test('transport timeouts and connection loss are transient', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
      ]) {
        expect(
          DownloadService.isTransientDownloadError(
            DioException(requestOptions: opts(), type: type),
          ),
          isTrue,
          reason: '$type should be transient',
        );
      }
      expect(
        DownloadService.isTransientDownloadError(TimeoutException('')),
        isTrue,
      );
      expect(
        DownloadService.isTransientDownloadError(
          DioException(
            requestOptions: opts(),
            type: DioExceptionType.unknown,
            error: const SocketException('dead'),
          ),
        ),
        isTrue,
      );
    });

    test('cancellation, TLS errors and HTTP responses are not', () {
      for (final type in [
        DioExceptionType.badCertificate,
        DioExceptionType.badResponse,
        DioExceptionType.cancel,
      ]) {
        expect(
          DownloadService.isTransientDownloadError(
            DioException(requestOptions: opts(), type: type),
          ),
          isFalse,
          reason: '$type must never retry',
        );
      }
      expect(DownloadService.isTransientDownloadError(Exception('x')), isFalse);
      expect(DownloadService.isTransientDownloadError(null), isFalse);
    });
  });

  group('shouldRetryDownloadAttempt — strictly bounded', () {
    test('first transient attempt may retry', () {
      expect(
        DownloadService.shouldRetryDownloadAttempt(
          attempt: 1,
          error: DioException(
            requestOptions: RequestOptions(path: '/'),
            type: DioExceptionType.connectionTimeout,
          ),
          cancelled: false,
        ),
        isTrue,
      );
    });

    test('attempt == max is the hard ceiling — never retries beyond it', () {
      expect(
        DownloadService.shouldRetryDownloadAttempt(
          attempt: DownloadService.maxDownloadAttempts,
          error: TimeoutException(''),
          cancelled: false,
        ),
        isFalse,
      );
    });

    test('a cancelled download never retries, regardless of error', () {
      expect(
        DownloadService.shouldRetryDownloadAttempt(
          attempt: 1,
          error: TimeoutException(''),
          cancelled: true,
        ),
        isFalse,
      );
    });

    test('a deterministic outcome (HTTP error) never retries', () {
      expect(
        DownloadService.shouldRetryDownloadAttempt(
          attempt: 1,
          error: DioException(
            requestOptions: RequestOptions(path: '/'),
            type: DioExceptionType.badResponse,
          ),
          cancelled: false,
        ),
        isFalse,
      );
    });
  });

  group('cleanupStaleTmp', () {
    test('removes only stale .ct.tmp staging files', () async {
      final dir =
          await Directory.systemTemp.createTemp('caputune_cleanup_tmp');
      addTearDown(() => dir.deleteSync(recursive: true));

      final old = DateTime.now().subtract(const Duration(days: 3));

      // In scope: stale staging file.
      final stale = File('${dir.path}/songA.ct.tmp')
        ..writeAsBytesSync(const [1, 2]);
      stale.setLastModifiedSync(old);

      // In scope by name, but still fresh (a live session's file).
      final fresh = File('${dir.path}/songB.ct.tmp')
        ..writeAsBytesSync(const [3]);

      // In scope by name, but its id belongs to an active download.
      final active = File('${dir.path}/activeC.ct.tmp')
        ..writeAsBytesSync(const [4]);
      active.setLastModifiedSync(old);

      // Never in scope: completed cache, legacy copy, unrelated suffix.
      File('${dir.path}/songA.ct').writeAsBytesSync(const [5]);
      File('${dir.path}/songA.mp3').writeAsBytesSync(const [6]);
      File('${dir.path}/fresh.tmp').writeAsBytesSync(const [7]);

      // Never in scope: imported local music lives in a subdirectory.
      final localMusic =
          Directory('${dir.path}/local_music/lm1')..createSync(recursive: true);
      final imported = File('${localMusic.path}/x.mp3')
        ..writeAsBytesSync(const [8]);

      final removed = await cleanupStaleTmp(
        directory: dir,
        activeIds: {'activeC'},
        maxAge: const Duration(days: 2),
      );

      expect(removed, 1);
      expect(stale.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
      expect(active.existsSync(), isTrue);
      expect(File('${dir.path}/songA.ct').existsSync(), isTrue);
      expect(File('${dir.path}/songA.mp3').existsSync(), isTrue);
      expect(File('${dir.path}/fresh.tmp').existsSync(), isTrue);
      expect(imported.existsSync(), isTrue);
    });

    test('survives a missing directory without throwing', () async {
      final removed = await cleanupStaleTmp(
        directory: Directory(
            '${Directory.systemTemp.path}/caputune-nope-does-not-exist'),
      );
      expect(removed, 0);
    });
  });

  group('DownloadService against a loopback server', () {
    setUp(() {
      // Keep the mid-transfer stall test snappy: abort a silent transfer
      // after 300ms instead of the production 45s.
      DownloadService.chunkIdleTimeoutOverride =
          const Duration(milliseconds: 300);
    });

    tearDown(() {
      DownloadService.chunkIdleTimeoutOverride = null;
    });

    test(
        'completed download writes the atomic .ct (renamed, no .tmp) whose '
        'decryption matches the payload, and registers in storage',
        () async {
      final payload = List.generate(1000, (i) => (i * 7) & 0xFF);
      final server = await _TestServer.serve((request) async {
        request.response.statusCode = 200;
        request.response.headers
            .set(HttpHeaders.contentLengthHeader, '${payload.length}');
        request.response.add(payload);
        await request.response.close();
      });

      final service = DownloadService(resolver: _FakeResolver(server.url));
      final song = _song('atomic1');
      await service.downloadSong(song);

      expect(service.getState(song.id), DownloadState.downloaded);
      final docs = await _documents();
      final ct = File('${docs.path}/${song.id}.ct');
      expect(ct.existsSync(), isTrue, reason: 'final atomic .ct must exist');
      expect(File('${ct.path}.tmp').existsSync(), isFalse,
          reason: 'staging file must have been renamed away');

      final decrypted = CipherService.transformChunk(ct.readAsBytesSync(), 0);
      expect(decrypted, payload);

      expect(StorageService.isDownloaded(song.id), isTrue);
      await server.close();
    });

    test(
        'cancellation mid-transfer ends idle with no .ct and no staging '
        'residue', () async {
      // Stream slowly forever; the client cancels while data is flowing.
      final server = await _TestServer.serve((request) async {
        request.response.statusCode = 200;
        request.response.headers
            .set(HttpHeaders.contentLengthHeader, '1000000');
        await request.response.addStream(
          Stream.periodic(
            const Duration(milliseconds: 25),
            (_) => List.filled(20, 0xAA),
          ),
        );
      });

      final service = DownloadService(resolver: _FakeResolver(server.url));
      final song = _song('cancel1');
      final started = service.downloadSong(song);

      // Wait until data is flowing, then cancel exactly like the UI does.
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (service.getProgress(song.id) <= 0) {
        if (DateTime.now().isAfter(deadline)) {
          fail('download never started delivering data');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await service.cancelDownload(song.id);
      // Let the in-flight attempt fully unwind before asserting file state:
      // cancelDownload only signals and flips UI state; downloadSong's catch
      // is what cleans the staging file.
      await started;

      expect(service.getState(song.id), DownloadState.idle);
      expect(service.errorMessage, 'Download cancelled');
      final docs = await _documents();
      expect(File('${docs.path}/${song.id}.ct').existsSync(), isFalse);
      expect(File('${docs.path}/${song.id}.ct.tmp').existsSync(), isFalse,
          reason: 'failed staging file must be cleaned up');

      await server.close();
    });

    test('a stalled transfer aborts inside the chunk-idle timeout', () async {
      // Sends headers + two chunks, then goes silent forever.
      final server = await _TestServer.serve((request) async {
        request.response.statusCode = 200;
        request.response.headers.set(HttpHeaders.contentLengthHeader, '1000');
        request.response.add(List.filled(100, 0x11));
        request.response.add(List.filled(100, 0x22));
        await request.response.flush();
        // Nothing more is ever written; no close() → client must abort.
        await Completer<void>().future;
      });

      final service = DownloadService(resolver: _FakeResolver(server.url));
      final song = _song('stall1');
      await service.downloadSong(song);

      expect(service.getState(song.id), DownloadState.idle);
      // Failure report, not a successful partial.
      expect(service.errorMessage, isNotNull);
      expect(service.errorMessage, isNot('Download cancelled'));
      final docs = await _documents();
      expect(File('${docs.path}/${song.id}.ct').existsSync(), isFalse);
      expect(File('${docs.path}/${song.id}.ct.tmp').existsSync(), isFalse);

      await server.close();
    });
  });
}
