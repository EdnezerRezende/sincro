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
    // AGP 8.10.1 (e não o 8.7.3 anterior) porque o androidx.health.connect:connect-client
    // trazido pelo plugin `health` exige AGP >= 8.9.1 e compileSdk >= 36 — com o AGP antigo o
    // build falha em :app:checkDebugAarMetadata. Compatível com o Gradle 8.12 do wrapper.
    id("com.android.application") version "8.10.1" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.3.10") apply false
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")
