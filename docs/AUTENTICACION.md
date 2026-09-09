# Identidad y autenticación

Estado: P1 implementado (2026-07-16); P2 identidad pública implementada
(2026-07-17); P3 amistades implementado y escritura robustecida contra tokens
de verificación obsoletos (2026-07-19). Este
documento describe el contrato operativo vigente;
`docs/ESPECIFICACION.md` continúa congelada.

## Tipos de identidad

| Identidad | Núcleo económico | `users/{uid}` | Evolución |
|---|---:|---:|---|
| Invitado móvil (Firebase anónimo) | Sí | No | Email o Google, conservando UID |
| Email sin verificar | Solo lectura de sesiones existentes | No | Verificar email |
| Email verificado | Sí | Sí | — |
| Google | Sí | Sí | — |
| Invitado web | Solo mediante `guestAccess` | No | Fuera de P1 |

Una conversión de invitado usa `linkWithCredential`, nunca un nuevo inicio de
sesión: el UID no cambia y las sesiones existentes conservan propietario. Si la
credencial pertenece a otra cuenta se detiene la operación; P1 no fusiona cuentas.

## Flujo de email y sesión

El registro crea o enlaza la credencial, actualiza el nombre visible y envía el
correo oficial de Firebase. El router lleva toda cuenta pendiente a
`/verify-email`, donde puede comprobar, reenviar con enfriamiento o cambiar de
cuenta. La comprobación ejecuta `reload()` y renueva el ID token para que Rules
reciba `email_verified: true` inmediatamente.

La recuperación usa `sendPasswordResetEmail` y confirma de forma no enumerativa:
muestra el mismo resultado exista o no la cuenta. Firebase conserva la sesión
nativa y renueva tokens; la app escucha `userChanges()` para reaccionar a reload,
enlaces de proveedor y cambios de verificación.

## Cambio de usuario

Los repositorios Firestore dependen de `currentUserIdProvider`: al cambiar el UID,
Riverpod cancela listeners y crea repositorios nuevos. Los borradores de revisión y
las claves de proveedores IA también se separan por UID. Una cuenta completa puede
migrar la configuración IA local anterior; un invitado nunca puede apropiársela.

## Seguridad

Firestore y Storage distinguen identidad activa (`anonymous` o `email_verified`) de
mera autenticación. Una cuenta de email pendiente puede leer sus sesiones históricas
por UID, pero no crear, editar, borrar, subir imágenes ni acceder a `users/{uid}`.
Los invitados móviles pueden operar el núcleo económico, pero no tienen perfil
privado ni personas frecuentes. El invitado web continúa limitado por `guestAccess`.

Las Cloud Functions son triggers Admin sin endpoints de cliente. Las escrituras
origen pasan por Rules y los agregados siguen siendo de solo lectura para clientes.

App Check todavía no se fuerza. El rollout seguro es: integrar móvil y web, registrar
Play Integrity/reCAPTCHA, observar métricas y solo después activar enforcement.
Forzarlo antes rompería la web de invitados.

## Firebase y Google

- **`dev.salda.salda_mobile` es el identificador OFICIAL** y su única fuente de
  verdad es `apps/mobile/android/app/build.gradle.kts`. No se cambia porque Android
  lo trataría como otra app y un invitado perdería su identidad local (ADR-034).
  `salda-dev` tiene una app Firebase específica para ese paquete
  (`1:923355592259:android:024e3c6d1eab95bfbac6f6`). Existe además una app
  registrada para `dev.salda.app` (`…:7e525bf8fd1252b9bac6f6`), resto de un
  identificador provisional que nunca llegó a compilar: **no la usa nadie** y no
  debe tomarse como referencia.
- Huellas SHA-1 registradas hoy en `salda-dev` para `dev.salda.salda_mobile`:
  `4be8fe7f…` y `716725783d…`. **El certificado de depuración de una máquina nueva
  NO está entre ellas**: Google Sign-In fallará desde esa máquina hasta registrar su
  SHA-1, y los App Links solo verifican si `assetlinks.json` incluye el SHA-256 del
  certificado con el que se firmó el APK instalado. Obtener el propio:
  `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey
  -storepass android`.
- El cliente OAuth público de desarrollo es el valor por defecto de
  `GOOGLE_SERVER_CLIENT_ID`; producción debe pasarlo por `--dart-define` al añadir
  flavors.
- Las firmas release/Play se registrarán antes de publicar.
- **Firma de release: hoy NO existe clave propia.** `buildTypes.release` firma con la
  clave de DEPURACIÓN, lo que sirve para `flutter run --release` y APK de prueba pero
  produce un artefacto no publicable. Gradle lo protege: si no hay
  `android/key.properties`, **el AAB de release falla** (es el formato con el que se
  sube a Play) y el APK avisa por consola pero se genera. Para forzar un AAB de
  prueba: `-PallowDebugSigning=true`.
- **Qué hará falta para Play App Signing**: (1) generar una clave de subida
  (`keytool -genkeypair -v -keystore upload.jks -keyalg RSA -keysize 2048
  -validity 10000 -alias upload`); (2) crear `apps/mobile/android/key.properties`
  con `storeFile/storePassword/keyAlias/keyPassword` — ya gitignorado, junto a
  `*.jks` y `*.keystore`, y **nunca** en el repositorio ni en CI sin secret manager;
  (3) subir el AAB, con lo que Play genera el certificado de **firma de app**, que es
  distinto del de subida; (4) añadir a `assetlinks.json` el SHA-256 de la firma de app
  que muestra Play Console, o los App Links dejarán de verificarse en producción;
  (5) registrar en Firebase el SHA-1 de ambos certificados para Google Sign-In.
- En `salda-dev` están habilitados y verificados Email/Password, Anonymous y Google.
  Producción deberá repetir esta configuración antes de publicar.

## Identidad pública (P2)

Solo una cuenta completa (`isFullAccount`) tiene perfil público en
`profiles/{uid}`: displayName, displayNameLower (búsqueda sin diacríticos),
username, photoPath (preparado, aún sin UI de subida), createdAt/updatedAt y
schemaVersion. `users/{uid}` sigue siendo privado. El username es único e
insensible a mayúsculas por construcción (siempre minúsculas) mediante el claim
`usernames/{username}`; perfil y claim se escriben en el mismo batch y las
reglas los validan juntos con `getAfter()`. La validación, los nombres
reservados y las propuestas naturales de registro (edgar → edgar27 →
edgar_cantera) están en `packages/domain/lib/src/identity/`. El avatar sin foto
se deriva siempre (iniciales + color FNV-1a del uid sobre `avatarPalette`). La
búsqueda de personas (por @username o nombre) son dos queries de prefijo de
campo único, sin índices compuestos. El detalle completo está en ADR-024 de la
Biblia. P3 añade amistades sin introducir campos sociales en el perfil ni usar
el username como clave; los espacios compartidos siguen fuera.

## Amistades (P3)

Solo una cuenta completa con perfil público puede usar amistades. Existe un único
`friendships/{canonicalId}` por pareja de UID, con estados `pending` y `friends`.
El emisor, receptor y los dos miembros se expresan siempre con UID; nombres y
usernames se leen desde `profiles/{uid}` en tiempo real. Solicitudes cruzadas
convergen de forma transaccional en amistad, y todas las resoluciones son
idempotentes. Eliminar una amistad no toca ningún dato económico. Modelo,
concurrencia, matriz de Rules y alcance están detallados en `docs/AMISTADES.md` y
ADR-027 de la Biblia.

## Pruebas

`auth_repository_test.dart`, `auth_screens_test.dart`, `app_smoke_test.dart`,
`friendship_repository_test.dart` y `friends_screen_test.dart` cubren operaciones,
UX y router. La suite de Rules contrasta identidades verificada, pendiente y
anónima, perfiles, relaciones sociales, lectura heredada y agregados manipulados.
