import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Android release build must be able to reach the network.
///
/// Accounic talks to Supabase over HTTPS for everything, so `INTERNET` is not
/// optional. It has to be declared in the **main** manifest: Flutter's stock
/// `src/debug/` and `src/profile/` manifests declare it as well, but only so the
/// tooling can hot-reload, and neither is merged into a release build.
///
/// Leaving it out of the main manifest is close to undetectable in development.
/// Every debug build works, `flutter analyze` is clean, every test passes, and
/// the release APK cannot make a single request. It shipped that way once, and
/// because Supabase's fetch failure extends `AuthException`, the symptom was a
/// sign-in screen insisting the password was wrong.
void main() {
  test('the main AndroidManifest declares the INTERNET permission', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml');
    expect(manifest.existsSync(), isTrue,
        reason: 'the main manifest is missing entirely');

    expect(
      manifest.readAsStringSync(),
      contains('android.permission.INTERNET'),
      reason: 'without this the release APK cannot reach Supabase at all, '
          'while every debug build keeps working',
    );
  });
}
