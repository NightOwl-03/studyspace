plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {

    ndkVersion = "28.2.13676358"
    // This is required in newer Android Gradle Plugin versions
    namespace = "com.example.studyspace"

    // In Kotlin DSL (.kts), use '=' for assignments
    compileSdk = 36

    defaultConfig {
        // TODO: Specify your own unique Application ID
        applicationId = "com.example.studyspace"

        // Use 21 to satisfy mobile_scanner requirements
        minSdk = flutter.minSdkVersion

        // Use 34 to match the compileSdk
        targetSdk = 36

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        getByName("release") {
            // TODO: Add your own signing config for the release build.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
}

flutter {
    source = "../.."
}
