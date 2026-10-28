import 'dart:io';
import 'dart:typed_data';

import 'package:caputune/services/cipher_service.dart';
import 'package:caputune/services/local_decrypt_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LocalDecryptServer serves decrypted bytes over real HTTP', () async {
    final dir = await Directory.systemTemp.createTemp('ct_server');
    final original = Uint8List.fromList(List.generate(20000, (i) => i % 251));

    // Encrypt exactly like download_service_mobile does (offset-keystream).
    final encFile = File('${dir.path}/song1.ct');
    final sink = encFile.openWrite();
    var off = 0;
    while (off < original.length) {
      final sz = (off + 997 > original.length) ? original.length - off : 997;
      sink.add(CipherService.transformChunk(original.sublist(off, off + sz), off));
      off += sz;
    }
    await sink.close();

    final server = LocalDecryptServer();
    final uri = await server.register('song1', encFile);

    // Loopback-only, ephemeral port.
    expect(uri.host, '127.0.0.1');

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);

    // 1) Full GET decrypts to the original bytes.
    final full = await client.getUrl(uri);
    final fullRes = await full.close();
    expect(fullRes.statusCode, 200);
    final body = <int>[];
    await for (final chunk in fullRes) {
      body.addAll(chunk);
    }
    expect(body, original, reason: 'full GET must decrypt to original audio');

    // 2) Range request (seek) decrypts the exact requested window.
    final ranged = await client.getUrl(uri);
    ranged.headers.set(HttpHeaders.rangeHeader, 'bytes=5000-7999');
    final rangeRes = await ranged.close();
    expect(rangeRes.statusCode, 206);
    expect(rangeRes.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 5000-7999/20000');
    final rangeBody = <int>[];
    await for (final chunk in rangeRes) {
      rangeBody.addAll(chunk);
    }
    expect(rangeBody, original.sublist(5000, 8000),
        reason: 'ranged GET must decrypt the exact window');

    // 3) Open-ended range (what libmpv sends on fresh opens).
    final openEnd = await client.getUrl(uri);
    openEnd.headers.set(HttpHeaders.rangeHeader, 'bytes=15000-');
    final openEndRes = await openEnd.close();
    expect(openEndRes.statusCode, 206);
    final openEndBody = <int>[];
    await for (final chunk in openEndRes) {
      openEndBody.addAll(chunk);
    }
    expect(openEndBody, original.sublist(15000));

    // 4) Unknown id → 404.
    final missing = await client.getUrl(Uri.parse(
        'http://127.0.0.1:${uri.port}/nope'));
    final missingRes = await missing.close();
    expect(missingRes.statusCode, 404);

    // 5) HEAD works without a body.
    final head = await client.headUrl(uri);
    final headRes = await head.close();
    expect(headRes.statusCode, 200);
    final headBody = <int>[];
    await for (final chunk in headRes) {
      headBody.addAll(chunk);
    }
    expect(headBody, isEmpty);

    client.close();
    await server.dispose();
    await dir.delete(recursive: true);
  });
}
