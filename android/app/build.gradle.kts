// Must be a real import: inside the Gradle Kotlin DSL `java` resolves to the
// Java plugin extension, so a fully-qualified `java.util.Properties` won't compile.
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

// Release signing credentials. android/key.properties is gitignored and points
// at a keystore stored OUTSIDE this repo. If it is missing (fresh clone, CI, or
// another developer's machine) the release build falls back to debug signing and
// says so loudly, rather than failing with an opaque Gradle error.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
val releaseStorePath: String? = keystoreProperties.getProperty("storeFile")
val hasReleaseSigning = releaseStorePath != null && file(releaseStorePath).exists()

android {
    namespace = "com.shantinathagroagency.shantinath_agro"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStorePath!!)
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.shantinathagroagency.shantinath_agro"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // println, not logger.warn — Gradle warn-level output is swallowed by
            // `flutter build`, which is how a silent fallback to debug signing
            // slipped through once already. Always say which key was used.
            signingConfig = if (hasReleaseSigning) {
                println("[signing] RELEASE build signed with upload key: $releaseStorePath")
                signingConfigs.getByName("release")
            } else {
                println(
                    "\n*** WARNING: no usable release keystore (android/key.properties " +
                    "missing, or storeFile does not resolve) — signing the RELEASE build " +
                    "with DEBUG keys. This APK cannot be published, and anyone who installs " +
                    "it cannot upgrade to a properly signed build. ***\n" +
                    "    storeFile read as: $releaseStorePath\n" +
                    "    NOTE: backslashes are escape characters in .properties files — " +
                    "use forward slashes.\n"
                )
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
