// Unit tests for update metadata parsing and semantic version comparison.
//
// The network call itself is exercised through the parsing/comparison helpers
// so these tests never touch GitHub.

import 'package:flutter_test/flutter_test.dart';
import 'package:caputune/services/update_service.dart';

void main() {
  group('UpdateService.isNewerVersion', () {
    test('detects a higher patch', () {
      expect(UpdateService.isNewerVersion('1.0.6', '1.0.5'), isTrue);
    });

    test('detects a higher minor', () {
      expect(UpdateService.isNewerVersion('1.1.0', '1.0.9'), isTrue);
    });

    test('detects a higher major', () {
      expect(UpdateService.isNewerVersion('2.0.0', '1.9.9'), isTrue);
    });

    test('equal versions are not newer', () {
      expect(UpdateService.isNewerVersion('1.0.5', '1.0.5'), isFalse);
    });

    test('older versions are not newer', () {
      expect(UpdateService.isNewerVersion('1.0.4', '1.0.5'), isFalse);
      expect(UpdateService.isNewerVersion('0.9.0', '1.0.0'), isFalse);
    });

    test('handles differing component counts', () {
      expect(UpdateService.isNewerVersion('1.1', '1.0.5'), isTrue);
      expect(UpdateService.isNewerVersion('1', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('1.0.0.1', '1.0.0'), isTrue);
    });

    test('treats non-numeric parts as zero', () {
      expect(UpdateService.isNewerVersion('1.x.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('1.beta.0', '1.0.0'), isFalse);
    });

    test('compares only the numeric prefix of pre-releases', () {
      expect(UpdateService.isNewerVersion('1.1.0-beta.1', '1.0.5'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.0-beta.1', '1.0.0'), isFalse);
    });
  });

  group('UpdateService.parseRelease', () {
    test('parses a well-formed release with an APK asset', () {
      final release = UpdateService.parseRelease({
        'tag_name': 'v1.2.3',
        'body': 'Bug fixes and improvements.',
        'html_url':
            'https://github.com/charl1107/nekomusic/releases/tag/v1.2.3',
        'assets': [
          {
            'name': 'nekomusic-v1.2.3-android.apk',
            'browser_download_url':
                'https://github.com/charl1107/nekomusic/releases/download/v1.2.3/app.apk',
          }
        ],
      });

      expect(release, isNotNull);
      expect(release!.version, '1.2.3');
      expect(release.notes, 'Bug fixes and improvements.');
      expect(release.apkDownloadUrl, isNotNull);
      expect(release.apkFileName, 'nekomusic-v1.2.3-android.apk');
      expect(release.releasePageUrl, contains('releases/tag/v1.2.3'));
      // No checksum asset in this payload.
      expect(release.checksumUrl, isNull);
    });

    test('picks up a .sha256 checksum asset and the APK file name', () {
      final release = UpdateService.parseRelease({
        'tag_name': 'v1.2.3',
        'body': '',
        'assets': [
          {
            'name': 'nekomusic-v1.2.3-android.apk',
            'browser_download_url':
                'https://github.com/c/n/releases/download/v1.2.3/app.apk',
          },
          {
            'name': 'nekomusic-v1.2.3-android.apk.sha256',
            'browser_download_url':
                'https://github.com/c/n/releases/download/v1.2.3/app.apk.sha256',
          },
        ],
      });
      expect(release!.checksumUrl, contains('.sha256'));
      expect(release.apkFileName, 'nekomusic-v1.2.3-android.apk');
    });

    test('picks up a checksums.txt asset', () {
      final release = UpdateService.parseRelease({
        'tag_name': 'v1.2.3',
        'body': '',
        'assets': [
          {
            'name': 'checksums.txt',
            'browser_download_url': 'https://example.com/checksums.txt',
          }
        ],
      });
      expect(release!.checksumUrl, 'https://example.com/checksums.txt');
    });

    test('strips a leading v from the tag', () {
      final release =
          UpdateService.parseRelease({'tag_name': 'v2.0.0', 'body': ''});
      expect(release!.version, '2.0.0');
    });

    test('accepts a tag without the v prefix', () {
      final release =
          UpdateService.parseRelease({'tag_name': '2.0.0', 'body': ''});
      expect(release!.version, '2.0.0');
    });

    test('returns null when the tag is missing', () {
      expect(UpdateService.parseRelease({'body': 'notes'}), isNull);
    });

    test('returns null when the tag is empty', () {
      expect(UpdateService.parseRelease({'tag_name': '   '}), isNull);
    });

    test('returns null when the tag is not a string', () {
      expect(UpdateService.parseRelease({'tag_name': 123}), isNull);
    });

    test('handles a release with no assets', () {
      final release = UpdateService.parseRelease({
        'tag_name': 'v1.0.0',
        'body': 'Initial',
        'html_url': 'https://github.com/x/y/releases/tag/v1.0.0',
      });
      expect(release!.apkDownloadUrl, isNull);
    });

    test('skips non-APK and non-https assets', () {
      final release = UpdateService.parseRelease({
        'tag_name': 'v1.0.0',
        'body': '',
        'assets': [
          {
            'name': 'checksums.txt',
            'browser_download_url': 'https://example.com/checksums.txt',
          },
          {
            'name': 'app.apk',
            'browser_download_url': 'http://insecure.example.com/app.apk',
          },
        ],
      });
      expect(release!.apkDownloadUrl, isNull);
    });

    test('ignores malformed asset entries without throwing', () {
      final release = UpdateService.parseRelease({
        'tag_name': 'v1.0.0',
        'body': '',
        'assets': ['not-a-map', 42, null],
      });
      expect(release, isNotNull);
      expect(release!.apkDownloadUrl, isNull);
    });

    test('treats a non-string body as empty notes', () {
      final release =
          UpdateService.parseRelease({'tag_name': 'v1.0.0', 'body': 7});
      expect(release!.notes, '');
    });

    test('rejects a non-https release page URL', () {
      final release = UpdateService.parseRelease({
        'tag_name': 'v1.0.0',
        'body': '',
        'html_url': 'javascript:alert(1)',
      });
      expect(release!.releasePageUrl, isNull);
    });
  });

  group('UpdateService.parseChecksum', () {
    const apkHash =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    const otherHash =
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

    test('reads a sha256sum line for the named file', () {
      const content = '$apkHash  app-release.apk\n$otherHash  other.bin\n';
      expect(
        UpdateService.parseChecksum(content, 'app-release.apk'),
        apkHash,
      );
    });

    test('accepts the binary-mode "*" marker', () {
      expect(
        UpdateService.parseChecksum('$apkHash *app.apk\n', 'app.apk'),
        apkHash,
      );
    });

    test('accepts a single-space separator', () {
      expect(
        UpdateService.parseChecksum('$apkHash app.apk\n', 'app.apk'),
        apkHash,
      );
    });

    test('matches on the base name even with a path prefix', () {
      expect(
        UpdateService.parseChecksum('$apkHash  ./dist/app.apk\n', 'app.apk'),
        apkHash,
      );
    });

    test('is case-insensitive on the file name and normalizes the hash', () {
      expect(
        UpdateService.parseChecksum(
          '${apkHash.toUpperCase()}  App.APK\n',
          'app.apk',
        ),
        apkHash,
      );
    });

    test('ignores comments and blank lines', () {
      const content = '# generated by sha256sum\n\n$apkHash  app.apk\n';
      expect(UpdateService.parseChecksum(content, 'app.apk'), apkHash);
    });

    test('returns null when the file is not listed and there is no bare hash',
        () {
      expect(
        UpdateService.parseChecksum('$otherHash  other.bin\n', 'app.apk'),
        isNull,
      );
    });

    test('falls back to a lone bare hash', () {
      expect(UpdateService.parseChecksum(apkHash, 'anything.apk'), apkHash);
    });

    test('ignores digests that are not 64 hex characters', () {
      expect(
          UpdateService.parseChecksum('deadbeef  app.apk', 'app.apk'), isNull);
    });

    test('handles CRLF line endings', () {
      expect(
        UpdateService.parseChecksum('$apkHash  app.apk\r\n', 'app.apk'),
        apkHash,
      );
    });
  });

  group('UpdateService download guards', () {
    test('reports unsupported when no release has been fetched', () async {
      final result = await UpdateService().downloadVerifiedUpdate();
      expect(result.status, DownloadStatus.unsupported);
      expect(result.filePath, isNull);
    });

    test('cannot install in-app before a release is fetched', () {
      expect(UpdateService().canInstallInApp, isFalse);
    });

    test('currentVersion defaults to the fallback before resolution', () {
      final service = UpdateService();
      expect(service.currentVersion, defaultAppVersion);
      expect(service.hasResolvedVersion, isFalse);
    });

    test('is not downloading before a download starts', () {
      expect(UpdateService().isDownloading, isFalse);
    });

    test('cancelling with no download in flight is a no-op', () {
      expect(() => UpdateService().cancelDownload(), returnsNormally);
    });
  });

  group('UpdateService APK variant selection', () {
    ApkAsset apk(String name) =>
        ApkAsset(name: name, url: 'https://example.com/$name');

    test('prefers the APK matching the most preferred device ABI', () {
      final chosen = UpdateService.selectApkAsset(
        [
          apk('nekomusic-1.2.3-armeabi-v7a.apk'),
          apk('nekomusic-1.2.3-arm64-v8a.apk'),
          apk('nekomusic-1.2.3-universal.apk'),
        ],
        ['arm64-v8a', 'armeabi-v7a'],
      );
      expect(chosen!.name, 'nekomusic-1.2.3-arm64-v8a.apk');
      expect(chosen.abi, 'arm64-v8a');
    });

    test('falls back to the next supported ABI when the first is unpublished',
        () {
      final chosen = UpdateService.selectApkAsset(
        [
          apk('app-armeabi-v7a.apk'),
          apk('app-x86_64.apk'),
        ],
        ['arm64-v8a', 'armeabi-v7a'],
      );
      expect(chosen!.name, 'app-armeabi-v7a.apk');
    });

    test('uses the universal APK when the device ABI is not published', () {
      final chosen = UpdateService.selectApkAsset(
        [
          apk('app-x86.apk'),
          apk('app-universal.apk'),
        ],
        ['arm64-v8a'],
      );
      expect(chosen!.name, 'app-universal.apk');
      expect(chosen.abi, isNull);
    });

    test('with no ABI information, picks the universal APK', () {
      final chosen = UpdateService.selectApkAsset(
        [
          apk('app-arm64-v8a.apk'),
          apk('app-universal.apk'),
        ],
        const [],
      );
      expect(chosen!.name, 'app-universal.apk');
      expect(chosen.abi, isNull);
    });

    test('does not confuse x86 with x86_64', () {
      expect(
        UpdateService.selectApkAsset([apk('app-x86_64.apk')], ['x86']),
        isNull,
      );
      final chosen =
          UpdateService.selectApkAsset([apk('app-x86.apk')], ['x86']);
      expect(chosen!.abi, 'x86');
    });

    test('returns null rather than an incompatible build', () {
      expect(
        UpdateService.selectApkAsset([apk('app-arm64-v8a.apk')], ['x86']),
        isNull,
      );
    });

    test('handles an empty asset list', () {
      expect(UpdateService.selectApkAsset(const [], const []), isNull);
    });
  });

  group('UpdateService.parseRelease with APK variants', () {
    Map<String, dynamic> variantPayload() => {
          'tag_name': 'v1.2.3',
          'body': '',
          'html_url': 'https://github.com/c/n/releases/tag/v1.2.3',
          'assets': [
            {
              'name': 'nekomusic-1.2.3-arm64-v8a.apk',
              'browser_download_url': 'https://x/arm64.apk',
            },
            {
              'name': 'nekomusic-1.2.3-armeabi-v7a.apk',
              'browser_download_url': 'https://x/v7a.apk',
            },
            {
              'name': 'nekomusic-1.2.3-universal.apk',
              'browser_download_url': 'https://x/universal.apk',
            },
            {
              'name': 'nekomusic-1.2.3-armeabi-v7a.apk.sha256',
              'browser_download_url': 'https://x/v7a.apk.sha256',
            },
            {
              'name': 'nekomusic-1.2.3-arm64-v8a.apk.sha256',
              'browser_download_url': 'https://x/arm64.apk.sha256',
            },
          ],
        };

    test('selects the device ABI asset and its matching checksum', () {
      final release = UpdateService.parseRelease(
        variantPayload(),
        supportedAbis: ['armeabi-v7a', 'arm64-v8a'],
      );
      expect(release!.apkFileName, 'nekomusic-1.2.3-armeabi-v7a.apk');
      expect(release.apkDownloadUrl, 'https://x/v7a.apk');
      expect(release.apkAbi, 'armeabi-v7a');
      expect(release.checksumUrl, 'https://x/v7a.apk.sha256');
    });

    test('prefers the primary ABI over a later one', () {
      final release = UpdateService.parseRelease(
        variantPayload(),
        supportedAbis: ['arm64-v8a', 'armeabi-v7a'],
      );
      expect(release!.apkAbi, 'arm64-v8a');
      expect(release.checksumUrl, 'https://x/arm64.apk.sha256');
    });

    test('defaults to the universal APK without ABI information', () {
      final release = UpdateService.parseRelease(variantPayload());
      expect(release!.apkFileName, 'nekomusic-1.2.3-universal.apk');
      expect(release.apkAbi, isNull);
    });

    test('the checksum must never be mistaken for the APK', () {
      final release = UpdateService.parseRelease(variantPayload());
      expect(release!.apkDownloadUrl, isNot(contains('.sha256')));
    });
  });
}
