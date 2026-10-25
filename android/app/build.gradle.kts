import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. When android/key.properties exists (CI and release machines)
// the release build is signed with a stable release key. A stable key is what
// lets an upgrade install over the previous version and keep the user's data;
// an auto-generated debug key changes per machine, which forces an uninstall.
// Local builds without key.properties fall back to the debug key.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val releaseStoreFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }

android {
    namespace = "com.example.caputune"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.caputune"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storePassword = keystoreProperties.getProperty("storePassword")
                storeFile = releaseStoreFile
                // The keystore is PKCS12 (the modern standard). Stated
                // explicitly so signing never depends on the JDK default.
                storeType = keystoreProperties.getProperty("storeType")?.takeIf { it.isNotBlank() }
                    ?: "PKCS12"
            }
        }
    }

    buildTypes {
        release {
            // Stable release key when configured, otherwise the debug key so
            // `flutter run --release` still works locally.
            signingConfig = signingConfigs.getByName(
                if (hasReleaseSigning) "release" else "debug",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Provides FileProvider, used to share a verified update APK with the
    // system installer over a content:// URI.
    implementation("androidx.core:core-ktx:1.13.1")
}

flutter {
    source = "../.."
}
