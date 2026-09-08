import java.util.Base64

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/**
 * Is this a DEMO build?
 *
 * Flutter hands `--dart-define` values to Gradle as `dart-defines`: a
 * comma-separated list of base64-encoded `KEY=VALUE` strings. Reading it here is
 * what lets one command — `flutter build apk --dart-define=DEMO_MODE=on` —
 * produce an application the phone treats as a DIFFERENT app, without a product
 * flavour and without changing the production build command by a single
 * character (docs/demo.md).
 *
 * It matters because the alternative is worse than untidy: with one application
 * ID, installing the demo REPLACES the real Accounic on that device, taking the
 * user's session with it.
 */
val isDemoBuild: Boolean = (project.findProperty("dart-defines") as String?)
    ?.split(",")
    ?.map { String(Base64.getDecoder().decode(it)) }
    ?.any { it == "DEMO_MODE=on" }
    ?: false

android {
    namespace = "com.accounic.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.accounic.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // A demo is a different application as far as the device is concerned:
        // its own ID, its own sandbox, its own session, its own icon in the
        // launcher. Install both and neither disturbs the other.
        //
        // The label goes through a resource rather than the manifest, so the two
        // are distinguishable in the launcher and in Settings without a second
        // manifest to keep in step.
        if (isDemoBuild) {
            applicationIdSuffix = ".demo"
            resValue("string", "app_name", "Accounic Demo")
        } else {
            resValue("string", "app_name", "Accounic")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
