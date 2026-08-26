/// Semantic version comparison, for deciding whether a GitHub release is newer
/// than the copy of Accounic that is running.
///
/// Hand-rolled rather than pulled in: the whole rule is forty lines, and the
/// alternative is a dependency in the update path — the one path that has to
/// keep working on a build nobody can patch any more.
///
/// What it understands, because that is what the project's tags actually carry:
///
///   * an optional leading `v` — `v1.3.0` and `1.3.0` are the same version
///   * build metadata after `+` — `1.2.0+13` is Flutter's `versionCode`, and
///     semver says metadata is ignored when comparing, so `1.2.0+13` and
///     `1.2.0+9` are equal
///   * pre-releases after `-` — `1.3.0-beta.1` is BEFORE `1.3.0`, which is the
///     rule people get backwards and the reason this is tested
///
/// Missing numeric parts read as zero, so `1.3` equals `1.3.0`. Anything that
/// cannot be parsed at all compares as `0.0.0`, which means a garbled tag can
/// never claim to be an upgrade.
library;

/// One parsed version. Compare with [compareTo]; `a.compareTo(b)` is negative
/// when `a` is older, zero when they are the same version, positive when newer.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.parts, this.preRelease);

  /// major, minor, patch — always three entries.
  final List<int> parts;

  /// The dot-separated identifiers after `-`, empty for a final release.
  final List<String> preRelease;

  static final _numeric = RegExp(r'^\d+$');

  /// Parses a tag or a pubspec version. Never throws: unreadable input becomes
  /// 0.0.0 rather than an exception in the middle of a background check.
  factory AppVersion.parse(String? raw) {
    var text = (raw ?? '').trim();
    if (text.isEmpty) return const AppVersion([0, 0, 0], []);

    // Tags are written `v1.3.0`; pubspec writes `1.3.0`. Same version.
    if (text.startsWith('v') || text.startsWith('V')) text = text.substring(1);

    // Build metadata is not part of the ordering (semver §10).
    final plus = text.indexOf('+');
    if (plus >= 0) text = text.substring(0, plus);

    final dash = text.indexOf('-');
    final preRelease = dash >= 0
        ? text.substring(dash + 1).split('.').where((p) => p.isNotEmpty).toList()
        : const <String>[];
    if (dash >= 0) text = text.substring(0, dash);

    final numbers = text.split('.');
    return AppVersion(
      [
        for (var i = 0; i < 3; i++)
          i < numbers.length ? (int.tryParse(numbers[i].trim()) ?? 0) : 0,
      ],
      preRelease,
    );
  }

  @override
  int compareTo(AppVersion other) {
    for (var i = 0; i < 3; i++) {
      final diff = parts[i].compareTo(other.parts[i]);
      if (diff != 0) return diff;
    }

    // A pre-release is older than the release it leads to: 1.3.0-beta < 1.3.0.
    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;

    for (var i = 0; i < preRelease.length && i < other.preRelease.length; i++) {
      final mine = preRelease[i];
      final theirs = other.preRelease[i];
      if (mine == theirs) continue;

      final mineNumeric = _numeric.hasMatch(mine);
      final theirsNumeric = _numeric.hasMatch(theirs);
      // Numeric identifiers always sort below alphanumeric ones (semver §11).
      if (mineNumeric && theirsNumeric) {
        return int.parse(mine).compareTo(int.parse(theirs));
      }
      if (mineNumeric != theirsNumeric) return mineNumeric ? -1 : 1;
      return mine.compareTo(theirs);
    }
    return preRelease.length.compareTo(other.preRelease.length);
  }

  @override
  String toString() => [
        parts.join('.'),
        if (preRelease.isNotEmpty) '-${preRelease.join('.')}',
      ].join();
}

/// True when [latest] is a strictly newer version than [current].
///
/// The three cases that matter, and all three are pinned by a test:
/// equal versions are not an update, older ones are not an update, and only a
/// higher one is.
bool isNewerVersion({required String? current, required String? latest}) =>
    AppVersion.parse(latest).compareTo(AppVersion.parse(current)) > 0;
