import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.sincro.sincro_mobile"
    // O androidx.health.connect:connect-client (dependência do plugin `health`) exige compilar
    // contra a API 36; o padrão do Flutter 3.32 ainda é 35.
    compileSdk = 36
    // url_launcher_android/webview_flutter_android/workmanager_android todos exigem NDK
    // 27.0.12077973 — mais novo que o default do Flutter (flutter.ndkVersion); fixado aqui em vez
    // de deixar o build só avisar e seguir com uma versão incompatível.
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // flutter_local_notifications usa APIs de java.time que exigem desugaring em minSdk < 26... na
        // prática o AGP exige isso habilitado sempre que essa dependência está presente, independente
        // do minSdk configurado.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.sincro.sincro_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // O plugin `health` (Health Connect) declara minSdkVersion 26 na própria biblioteca;
        // manter o padrão do Flutter (21) faz o merge de manifestos do AGP falhar o build.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    // Substitui o antigo bloco `kotlinOptions` dentro de `android {}`, removido no Kotlin 2.3.0
    // em favor da DSL `compilerOptions`.
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_11)
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
