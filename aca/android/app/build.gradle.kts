import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material lives OUTSIDE the repository (see docs/ACA.md). The
// path can be overridden with ACA_KEY_PROPERTIES for CI.
val keyPropsFile = File(
    System.getenv("ACA_KEY_PROPERTIES") ?: "${System.getProperty("user.home")}/.aca/key.properties"
)
val keyProps = Properties().apply {
    if (keyPropsFile.exists()) FileInputStream(keyPropsFile).use { load(it) }
}

android {
    namespace = "com.archeaxon.aca"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.archeaxon.aca"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keyProps.containsKey("storeFile")) {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Never fall back to the debug key: an unsigned/mis-signed admin app is worse than no build.
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            resValue("string", "app_name", "ACA")
        }
        debug {
            // Debug builds are QA builds: separate id so they can sit beside the real app.
            applicationIdSuffix = ".qa"
            resValue("string", "app_name", "ACA QA")
        }
    }
}

flutter {
    source = "../.."
}
