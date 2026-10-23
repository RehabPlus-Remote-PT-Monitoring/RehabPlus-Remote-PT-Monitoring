import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

// Release signing secrets, if present (see signingConfigs below).
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "com.rehabplus.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Needed by flutter_local_notifications (daily exercise reminder).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.rehabplus.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 28 // Android 9 (Pie), per thesis 3.3.2
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Upload keystore for release builds. android/key.properties (never
    // committed; android/.gitignore ignores it and *.jks) holds:
    //   storeFile=/absolute/path/to/upload-keystore.jks
    //   storePassword=...   keyAlias=upload   keyPassword=...
    // Create the keystore with:
    //   keytool -genkey -v -keystore ~/keys/upload-keystore.jks -keyalg RSA \
    //     -keysize 2048 -validity 10000 -alias upload
    signingConfigs {
        if (!keystoreProperties.isEmpty) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Signed with the upload key from android/key.properties when it
            // exists (git-ignored, see below). Without it the build falls back
            // to the debug key so `flutter run --release` still works, but
            // such an APK must never be published.
            signingConfig = if (keystoreProperties.isEmpty) {
                logger.warn("android/key.properties not found: release build is signed with the DEBUG key")
                signingConfigs.getByName("debug")
            } else {
                signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
