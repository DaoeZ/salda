import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android y Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Clave de release, si existe. `key.properties` y los almacenes (*.jks,
// *.keystore) están gitignorados: aquí nunca hay secretos, solo la ruta por
// la que se leerían. Sin el archivo, el proyecto sigue funcionando igual que
// hasta ahora — firmando con la clave de depuración.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseKeystore) keystorePropertiesFile.inputStream().use { load(it) }
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
        // Solo se declara si hay clave real: crear una config vacía haría
        // fallar builds de desarrollo que hoy funcionan.
        if (hasReleaseKeystore) {
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
            // ESTADO ACTUAL: sin clave propia, `release` se firma con la de
            // DEPURACIÓN. Es deliberado —permite `flutter run --release` y
            // APK de prueba— pero produce un artefacto NO publicable: Play lo
            // rechaza y, si se colara, quedaría atado a un certificado que
            // cualquiera puede reproducir. El guardián de abajo impide que
            // eso llegue a un artefacto de publicación.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// Red de seguridad: el AAB es el formato con el que se sube a Play, así que
// es el único que se bloquea. Los APK de desarrollo (`flutter build apk`,
// `flutter run --release`) siguen funcionando con un aviso visible.
gradle.taskGraph.whenReady {
    if (hasReleaseKeystore) return@whenReady
    val buildingBundle = allTasks.any { it.name.startsWith("bundle") && it.name.contains("Release") }
    val buildingApk = allTasks.any { it.name.startsWith("assemble") && it.name.contains("Release") }
    if (buildingBundle && !project.hasProperty("allowDebugSigning")) {
        throw GradleException(
            "No hay clave de release (apps/mobile/android/key.properties no existe), " +
                "asi que este AAB se firmaria con la clave de DEPURACION y no es publicable. " +
                "Crea la clave y key.properties, o repite con -PallowDebugSigning=true " +
                "si de verdad solo quieres un artefacto de prueba."
        )
    }
    if (buildingApk || buildingBundle) {
        logger.warn(
            "AVISO: compilando release SIN clave propia; se firma con la clave de " +
                "depuracion. Valido para pruebas, NO para publicar."
        )
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
