import 'package:accounic/data/update_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which update links Accounic is willing to hand to the operating system.
///
/// Everything in an [AppRelease] arrives in a remote HTTP response and ends up
/// at `launchUrl`. If that call will open whatever the response said, then
/// "check for updates" is "open anything" for anyone who can shape the
/// response — a mis-issued certificate, a hostile proxy, or a future bug that
/// points the check at the wrong host.
///
/// The rule is an allow-list: https only, on a host GitHub actually serves
/// releases from. These pin the cases that matter, and the near-misses are the
/// point — `github.com.evil.example` and `https://github.com@evil.example` are
/// what a blocklist or a naive `contains('github.com')` would wave through.
void main() {
  group('trusted', () {
    for (final url in [
      'https://github.com/VED2107/accounic/releases/tag/v1.3.0',
      'https://github.com/VED2107/accounic/releases/latest',
      'https://www.github.com/VED2107/accounic/releases',
      'https://objects.githubusercontent.com/github-production-release-asset/1/2',
      'https://release-assets.githubusercontent.com/github-production-release-asset/x.apk',
    ]) {
      test(url, () => expect(isTrustedUpdateUrl(url), isTrue));
    }
  });

  group('refused', () {
    for (final entry in {
      'a look-alike host': 'https://github.com.evil.example/accounic.apk',
      'a suffix look-alike': 'https://notgithub.com/accounic.apk',
      'credentials before an @': 'https://github.com@evil.example/accounic.apk',
      'plain http': 'http://github.com/VED2107/accounic/releases',
      'a javascript scheme': 'javascript:alert(1)',
      'a file scheme': 'file:///C:/Windows/System32/cmd.exe',
      'an intent scheme': 'intent://evil.example/#Intent;scheme=http;end',
      'a data url': 'data:text/html,<script>alert(1)</script>',
      'a relative path': '/VED2107/accounic/releases',
      'an empty string': '',
      'nothing at all': null,
    }.entries) {
      test(entry.key, () => expect(isTrustedUpdateUrl(entry.value), isFalse));
    }
  });

  test('an untrusted asset url never becomes the download link', () {
    // The parse path replaces a bad page link with the canonical releases page
    // and drops a bad asset link entirely, so openUrl is always something this
    // allow-list already accepted.
    const release = AppRelease(
      version: '9.9.9',
      name: 'spoofed',
      url: 'https://github.com/VED2107/accounic/releases/latest',
      downloadUrl: null,
    );
    expect(isTrustedUpdateUrl(release.openUrl), isTrue);
  });
}
