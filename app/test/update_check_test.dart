import 'dart:convert';

import 'package:accounic/core/version.dart';
import 'package:accounic/data/update_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Update detection (core/version.dart, data/update_repository.dart).
///
/// The three cases in the brief are the first three tests, because getting any
/// of them wrong is worse than not having the feature: nagging a user who is
/// already current, or staying silent when they are two versions behind.
void main() {
  group('semantic version comparison', () {
    test('equal versions are not an update', () {
      expect(isNewerVersion(current: '1.2.0', latest: '1.2.0'), isFalse);
      // The tag carries a v and the pubspec carries a build number. Same
      // version, and neither difference may read as an upgrade.
      expect(isNewerVersion(current: '1.2.0', latest: 'v1.2.0'), isFalse);
      expect(isNewerVersion(current: '1.2.0+13', latest: 'v1.2.0'), isFalse);
    });

    test('a higher latest version is an update', () {
      expect(isNewerVersion(current: '1.2.0', latest: 'v1.3.0'), isTrue);
      expect(isNewerVersion(current: '1.2.0', latest: '1.2.1'), isTrue);
      expect(isNewerVersion(current: '1.9.9', latest: '2.0.0'), isTrue);
      // Ten is greater than nine — the comparison is numeric, not textual.
      expect(isNewerVersion(current: '1.9.0', latest: '1.10.0'), isTrue);
    });

    test('a lower latest version is not an update', () {
      expect(isNewerVersion(current: '1.3.0', latest: 'v1.2.0'), isFalse);
      expect(isNewerVersion(current: '2.0.0', latest: '1.9.9'), isFalse);
      expect(isNewerVersion(current: '1.10.0', latest: '1.9.0'), isFalse);
    });

    test('a pre-release sorts below the release it leads to', () {
      expect(isNewerVersion(current: '1.3.0-beta.1', latest: '1.3.0'), isTrue);
      expect(isNewerVersion(current: '1.3.0', latest: '1.3.0-beta.1'), isFalse);
      expect(isNewerVersion(current: '1.3.0-beta.1', latest: '1.3.0-beta.2'), isTrue);
    });

    test('unreadable input can never claim to be an upgrade', () {
      expect(isNewerVersion(current: '1.2.0', latest: ''), isFalse);
      expect(isNewerVersion(current: '1.2.0', latest: 'not-a-version'), isFalse);
      expect(isNewerVersion(current: null, latest: '0.0.0'), isFalse);
    });

    test('missing parts read as zero', () {
      expect(AppVersion.parse('1.3').compareTo(AppVersion.parse('1.3.0')), 0);
      expect(AppVersion.parse('v2').compareTo(AppVersion.parse('2.0.0')), 0);
    });
  });

  group('GitHub Releases', () {
    String body({
      String tag = 'v1.3.0',
      bool draft = false,
      bool prerelease = false,
    }) =>
        jsonEncode({
          'tag_name': tag,
          'name': 'Accounic $tag',
          'html_url': 'https://github.com/VED2107/accounic/releases/tag/$tag',
          'body': 'Multi-currency dashboard.',
          'published_at': '2026-08-26T00:00:00Z',
          'draft': draft,
          'prerelease': prerelease,
          'assets': [
            {
              'name': 'accounic-setup.exe',
              'browser_download_url': 'https://example.invalid/accounic-setup.exe',
            },
            {
              'name': 'app-release.apk',
              'browser_download_url': 'https://example.invalid/app-release.apk',
            },
          ],
        });

    UpdateRepository repositoryReturning(http.Response Function() respond) =>
        UpdateRepository(client: MockClient((_) async => respond()));

    test('reads the latest release', () async {
      final release = await repositoryReturning(() => http.Response(body(), 200))
          .latestRelease();

      expect(release, isNotNull);
      // The tag's `v` is stripped: what is shown is a version, not a ref.
      expect(release!.version, '1.3.0');
      expect(release.name, 'Accounic v1.3.0');
      expect(release.notes, 'Multi-currency dashboard.');
      // Whatever the platform, there is always something to open.
      expect(release.openUrl, isNotEmpty);
    });

    test('a draft or a pre-release is not offered', () async {
      expect(
        await repositoryReturning(() => http.Response(body(draft: true), 200))
            .latestRelease(),
        isNull,
      );
      expect(
        await repositoryReturning(() => http.Response(body(prerelease: true), 200))
            .latestRelease(),
        isNull,
      );
    });

    test('a repository with no releases is silent, not an error', () async {
      expect(
        await repositoryReturning(() => http.Response('{"message":"Not Found"}', 404))
            .latestRelease(),
        isNull,
      );
    });

    test('a rate limit is silent, not an error', () async {
      expect(
        await repositoryReturning(() => http.Response('{"message":"rate limited"}', 403))
            .latestRelease(),
        isNull,
      );
    });

    test('a malformed body is silent, not an error', () async {
      expect(
        await repositoryReturning(() => http.Response('<html>nope</html>', 200))
            .latestRelease(),
        isNull,
      );
    });

    test('a network failure is silent, not an error', () async {
      final repository = UpdateRepository(
        client: MockClient((_) async => throw const _Offline()),
      );
      expect(await repository.latestRelease(), isNull);
    });

    test('a tag with no version is ignored', () async {
      expect(
        await repositoryReturning(() => http.Response(body(tag: ''), 200)).latestRelease(),
        isNull,
      );
    });
  });
}

class _Offline implements Exception {
  const _Offline();
}
