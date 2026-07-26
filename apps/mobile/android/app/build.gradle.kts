import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android y Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ── Firma de DESARROLLO COMPARTIDA (BUG-1) ───────────────────────────────
//
// El problema: cada máquina genera su propio `~/.android/debug.keystore`, así
// que el APK sale con un SHA-1 distinto en cada entorno. Google Sign-In
// autoriza por (package + SHA-1), de modo que solo funcionaba donde esa
// huella estuviera registrada en Firebase; en el resto fallaba con
// DEVELOPER_ERROR. Lo mismo rompe los App Links, que se verifican contra el
// SHA-256 publicado en assetlinks.json.
//
// La solución: TODOS los entornos autorizados firman desarrollo con el MISMO
// certificado. Ni la keystore ni las contraseñas entran en Git: se leen de un
// archivo local ignorado o de variables de entorno (CI/cloud).
fun devSigningValue(propertyKey: String, envKey: String): String? {
    val fromFile = rootProject.file("dev-keystore.properties")
        .takeIf { it.exists() }
        ?.let { file ->
            Properties().apply { file.inputStream().use { load(it) } }
                .getProperty(propertyKey)
        }
    return (fromFile ?: System.getenv(envKey))?.takeIf { it.isNotBlank() }
}

val devStorePath = devSigningValue("storeFile", "SALDA_DEV_KEYSTORE")
val devStorePassword =
    devSigningValue("storePassword", "SALDA_DEV_KEYSTORE_PASSWORD")
val devKeyAlias = devSigningValue("keyAlias", "SALDA_DEV_KEY_ALIAS")
val devKeyPassword = devSigningValue("keyPassword", "SALDA_DEV_KEY_PASSWORD")
val devKeystoreFile = devStorePath?.let { file(it) }
val hasDevKeystore = devKeystoreFile?.exists() == true &&
    devStorePassword != null && devKeyAlias != null && devKeyPassword != null

// Clave de RELEASE (Play), independiente de la anterior. `key.properties` y
// los almacenes (*.jks, *.keystore) están gitignorados: aquí nunca hay
// secretos, solo la ruta por la que se leerían.
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
        // Firma de desarrollo COMPARTIDA entre todos los entornos.
        if (hasDevKeystore) {
            create("dev") {
                storeFile = devKeystoreFile
                storePassword = devStorePassword
                keyAlias = devKeyAlias
                keyPassword = devKeyPassword
            }
        }
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
        debug {
            // NUNCA cae en `~/.android/debug.keystore` sin avisar: si falta la
            // firma compartida, el guardián de abajo detiene el ensamblado.
            if (hasDevKeystore) signingConfig = signingConfigs.getByName("dev")
        }
        release {
            // ESTADO ACTUAL: sin clave propia, `release` se firma con la de
            // DEPURACIÓN. Es deliberado —permite `flutter run --release` y
            // APK de prueba— pero produce un artefacto NO publicable: Play lo
            // rechaza y, si se colara, quedaría atado a un certificado que
            // cualquiera puede reproducir. El guardián de abajo impide que
            // eso llegue a un artefacto de publicación.
            signingConfig = when {
                hasReleaseKeystore -> signingConfigs.getByName("release")
                // Sin clave de Play, una release de PRUEBA se firma con el
                // certificado compartido de desarrollo: así también funcionan
                // Google Sign-In y los App Links al probar en release.
                hasDevKeystore -> signingConfigs.getByName("dev")
                else -> signingConfigs.getByName("debug")
            }
        }
    }
}

// BUG-1: sin firma compartida no se ENSAMBLA ni se INSTALA nada. Se
// comprueba sobre el grafo de tareas, no en la configuración, para que
// `flutter test`, `dart analyze`, `signingReport` y cualquier tarea que no
// produzca un artefacto sigan funcionando en un entorno recién clonado.
gradle.taskGraph.whenReady {
    val producingArtifact = allTasks.any { task ->
        listOf("assemble", "bundle", "install", "package").any {
            task.name.startsWith(it)
        }
    }
    if (producingArtifact && !hasDevKeystore &&
        !project.hasProperty("allowLocalDebugKeystore")) {
        val motivo = when {
            devStorePath == null ->
                "no hay configuracion: falta dev-keystore.properties o las variables SALDA_DEV_*"
            devKeystoreFile?.exists() != true ->
                "la keystore indicada no existe en: " + devStorePath
            else -> "faltan storePassword, keyAlias o keyPassword"
        }
        throw GradleException(
            "Firma de desarrollo COMPARTIDA no configurada (" + motivo + ").\n" +
                "Sin ella el APK saldria con el certificado local de esta " +
                "maquina y Google Sign-In fallaria con DEVELOPER_ERROR, " +
                "ademas de romper los App Links.\n" +
                "Configuralo siguiendo docs/ENTORNOS.md (seccion 'Firma de " +
                "desarrollo compartida'), o repite con " +
                "-PallowLocalDebugKeystore=true si de verdad solo quieres un " +
                "APK local sin Google Sign-In."
        )
    }
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
