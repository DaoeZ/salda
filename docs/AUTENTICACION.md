# Identidad y autenticación

Estado: P1 implementado (2026-07-16); P2 identidad pública implementada
(2026-07-17); P3 amistades implementado a nivel de código (2026-07-18). Este
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

- El APK existente usa `dev.salda.salda_mobile`; no se cambia porque Android lo
  trataría como otra app y un invitado podría perder su identidad local. `salda-dev`
  tiene una app Firebase específica para ese paquete
  (`1:923355592259:android:024e3c6d1eab95bfbac6f6`).
- El cliente OAuth público de desarrollo es el valor por defecto de
  `GOOGLE_SERVER_CLIENT_ID`; producción debe pasarlo por `--dart-define` al añadir
  flavors.
- Las huellas SHA-1 y SHA-256 debug están registradas para el paquete existente. Las
  firmas release/Play se registrarán antes de publicar.
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
