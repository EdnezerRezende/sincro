pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // AGP 8.11.1 porque o Flutter 3.47.1 exige AGP >= 8.11.1 (e o wrapper Gradle 8.14 que isso
    // arrasta). O androidx.health.connect:connect-client trazido pelo plugin `health` já exigia
    // AGP >= 8.9.1 e compileSdk >= 36 — com um AGP mais antigo o build falha em
    // :app:checkDebugAarMetadata.
    id("com.android.application") version "8.11.1" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.3.10") apply false
    // END: FlutterFire Configuration
    // 2.3.0 (e não 2.1.0) porque o firebase-auth 24.1.0 trazido pelo plugin `firebase_auth` foi
    // compilado com metadata Kotlin 2.3.0 — um compilador 2.1.0 não consegue ler esse .kotlin_module
    // e o daemon do Gradle crasha em vez de reportar um erro normal.
    id("org.jetbrains.kotlin.android") version "2.3.0" apply false
}

include(":app")
