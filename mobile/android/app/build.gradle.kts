import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

val releaseStoreFile = (keystoreProperties["storeFile"] as String?)
    ?.let { rootProject.file(it) }
val hasReleaseSigningConfig =
    releaseStoreFile?.exists() == true &&
        keystoreProperties["storePassword"] != null &&
        keystoreProperties["keyAlias"] != null &&
        keystoreProperties["keyPassword"] != null
val isReleaseTask = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}

android {
    namespace = "com.archeaxon.axonpos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (uses java.time APIs on
        // API levels below 26 via desugaring).
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Axon POS - Professional Retail Management
        applicationId = "com.archeaxon.axonpos"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // We distribute a single universal APK directly (no Play Store, no
    // per-ABI updater logic) and build with `flutter build apk --release
    // --target-platform android-arm64` (see the CI workflow) — that flag
    // restricts FLUTTER'S OWN engine/AOT binaries to arm64-v8a, but several
    // plugin AARs (ML Kit barcode/OCR, sqlite3) ship their own multi-arch
    // native libraries that still get packaged regardless of that flag.
    // Excluding the other architectures' .so files here at packaging time
    // (rather than via `splits.abi`, which Gradle rejects as conflicting
    // with the abiFilters Flutter's own flag already injects) is what
    // actually drops them. Virtually every Android phone in the field
    // (2019+) is arm64-v8a, so this has no real compatibility cost.
    // Scoped to release builds only: debug builds (flutter run) still need
    // x86_64 libs to run on the x86_64 emulators most dev machines use.
    if (isReleaseTask) {
        packaging {
            jniLibs {
                excludes += setOf(
                    "lib/armeabi-v7a/**",
                    "lib/x86/**",
                    "lib/x86_64/**",
                )
            }
        }
    }

    signingConfigs {
        if (hasReleaseSigningConfig) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = keystoreProperties["storePassword"].toString()
                keyAlias = keystoreProperties["keyAlias"].toString()
                keyPassword = keystoreProperties["keyPassword"].toString()
            }
        }
    }

    buildTypes {
        release {
            if (!hasReleaseSigningConfig && isReleaseTask) {
                throw GradleException(
                    "Release signing config is required. Refusing to create a debug-signed release APK."
                )
            }
            signingConfig = if (hasReleaseSigningConfig) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Disable R8 to avoid duplicate class errors from sqlcipher/sqlite3 conflict
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
