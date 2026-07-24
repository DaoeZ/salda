plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.salda.salda_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Conservado para no convertir una actualización en una app distinta:
        // cambiarlo perdería el almacenamiento local de invitados existentes.
        applicationId = "dev.salda.salda_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Clave de depuración COMPARTIDA y versionada. Sin ella cada máquina
        // y cada runner de CI generan su propio ~/.android/debug.keystore con
        // una huella distinta, y Google Sign-In rechaza el APK porque esa
        // huella no está registrada como cliente OAuth de Android: el
        // selector de cuentas se abre, pero el token nunca se emite.
        // NO es un secreto (contraseña "android", como la clave de depuración
        // por defecto de Android) y NUNCA debe firmar una release.
        getByName("debug") {
            storeFile = file("salda-debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
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
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
