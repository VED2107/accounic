import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../core/config.dart';
import '../core/version.dart';

/// Update detection against GitHub Releases (context.md §31 adjacent).
///
/// There is no update server and there will not be one: releases are already
/// published to GitHub, the Releases API is public and unauthenticated for a
/// public repository, and "what is the newest version" is exactly the question
/// it answers. Nothing here knows a version number — the installed one comes
/// from the bundle at runtime, the newest one comes from the API, and the two
/// are compared by the rules in core/version.dart.
///
/// Every failure is silent by design. A phone on a train, a rate limit, a
/// private repository, a machine with no network at all: none of those are the
/// user's problem, and none of them may break a ledger that works offline. The
/// check returns "no update" and the app carries on.
class AppRelease {
  const AppRelease({
    required this.version,
    required this.name,
    required this.url,
    this.notes,
    this.publishedAt,
    this.downloadUrl,
  });

  /// The release tag, `v` stripped: what is shown to the user.
  final String version;

  /// The release's title, falling back to the tag when it has none.
  final String name;

  /// The release page on GitHub — always safe to open.
  final String url;

  /// The release body, as written on GitHub. Markdown, shown as plain text.
  final String? notes;
  final String? publishedAt;

  /// The asset for this platform, when the release carries one: the installer
  /// on Windows, the APK on Android. Null falls back to [url].
  final String? downloadUrl;

  /// What the update button should open.
  String get openUrl => downloadUrl ?? url;
}

class UpdateRepository {
  const UpdateRepository({http.Client? client, this.repo = AppConfig.releaseRepo})
      : _client = client;

  final http.Client? _client;
  final String repo;

  /// The version this binary was built as, from the bundle rather than from a
  /// constant — so a release cannot ship claiming to be the version before it.
  Future<String> installedVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// The newest published release, or null when there is none, when the check
  /// is switched off, or when anything at all goes wrong.
  Future<AppRelease?> latestRelease() async {
    if (!AppConfig.updateCheckEnabled || repo.isEmpty) return null;

    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(
            Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
            headers: const {
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
            },
          )
          .timeout(const Duration(seconds: 8));

      // 404 is the ordinary answer for a repository with no releases yet, or a
      // private one seen without a token. Neither is an error worth surfacing.
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) return null;
      if (json['draft'] == true || json['prerelease'] == true) return null;

      final tag = (json['tag_name'] as String?)?.trim();
      if (tag == null || tag.isEmpty) return null;

      final notes = (json['body'] as String?)?.trim();
      return AppRelease(
        version: AppVersion.parse(tag).toString(),
        name: (json['name'] as String?)?.trim().isNotEmpty == true
            ? (json['name'] as String).trim()
            : tag,
        url: (json['html_url'] as String?) ?? 'https://github.com/$repo/releases/latest',
        notes: (notes == null || notes.isEmpty) ? null : notes,
        publishedAt: json['published_at'] as String?,
        downloadUrl: _assetFor(json['assets']),
      );
    } catch (_) {
      // Network down, DNS gone, rate limited, malformed body — all the same
      // answer. An update check may never be the reason the app misbehaves.
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }

  /// The newest release, but only when it is actually newer than what is
  /// installed. Equal or older returns null, which is what stops a current
  /// install from being nagged.
  Future<AppRelease?> availableUpdate() async {
    final release = await latestRelease();
    if (release == null) return null;

    final current = await installedVersion();
    return isNewerVersion(current: current, latest: release.version) ? release : null;
  }

  /// The asset a user on this platform actually wants: the Windows installer,
  /// the Android APK. Anything else falls back to the release page, which every
  /// platform can open.
  String? _assetFor(Object? assets) {
    if (assets is! List) return null;

    final wanted = defaultTargetPlatform == TargetPlatform.android
        ? const ['.apk']
        : _isWindows
            ? const ['.exe', '.msi', '.msix']
            : const <String>[];
    if (wanted.isEmpty) return null;

    for (final suffix in wanted) {
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = (asset['name'] as String?)?.toLowerCase() ?? '';
        final url = asset['browser_download_url'] as String?;
        if (url != null && name.endsWith(suffix)) return url;
      }
    }
    return null;
  }

  // Guarded so the repository stays importable from a test that never touches
  // dart:io platform state.
  bool get _isWindows {
    try {
      return Platform.isWindows;
    } catch (_) {
      return false;
    }
  }
}
