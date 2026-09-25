import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials live only in android/key.properties (gitignored,
// never committed — see android/.gitignore). Falls back to null (→ debug
// signing) when the file is absent, so a fresh checkout without the real
// keystore still builds a debug-signed APK for local development instead of
// failing outright.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Firebase Cloud Messaging (push notifications) needs google-services.json
// (downloaded from the Firebase console for this app's package name,
// com.mypreparation.app) placed at android/app/google-services.json — NOT
// committed to git (it is not secret the way a private key is, but it's
// project-specific and environment-provided, same treatment as
// key.properties above). Applying the google-services plugin
// unconditionally would fail the ENTIRE build for anyone without that file
// yet (a fresh checkout, CI before the file is provisioned, etc.) — so,
// mirroring the key.properties pattern above exactly, it's applied only
// when the file is actually present. Until then, Firebase.initializeApp()
// fails at runtime and PushNotificationService catches that gracefully
// (push simply stays disabled) — the rest of the app is unaffected either
// way.
val googleServicesFile = rootProject.file("app/google-services.json")
if (googleServicesFile.exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.mypreparation.app"
    // flutter.compileSdkVersion (34) is behind what flutter_plugin_android_lifecycle's
    // AAR metadata requires transitively via file_picker; pinned to 36 per Gradle's
    // own recommended action so the debug build can compile.
    compileSdk = 36
    ndkVersion = "30.0.16248370"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.mypreparation.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // No android/key.properties present (e.g. a fresh checkout
                // without the real release keystore) — fall back to debug
                // signing rather than failing the build.
                signingConfigs.getByName("debug")
            }
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
