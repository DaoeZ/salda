# Amistades (P3)

Estado: implementado a nivel de código (2026-07-18). Este documento define el
contrato social vigente. No amplía el alcance a grupos permanentes, chat,
actividad ni notificaciones.

## Cuenta habilitada

Una cuenta puede usar amistades solo cuando cumple las tres condiciones:

1. Firebase Auth no es anónimo.
2. El correo está verificado, o el proveedor ya entrega una cuenta verificada
   (por ejemplo Google): `AppUser.isFullAccount`.
3. Existe su perfil público `profiles/{uid}`.

Los invitados conservan todos los flujos económicos existentes, pero no pueden
leer ni escribir relaciones sociales. Firestore Rules aplica esta política sin
confiar en la interfaz.

## Fuente de verdad

Cada pareja tiene un único documento:

```text
friendships/{canonicalFriendshipId(uidA, uidB)}
  memberUids: [uidMenor, uidMayor]
  requesterUid: uid
  receiverUid: uid
  status: pending | friends
  createdAt: server timestamp
  updatedAt: server timestamp
  acceptedAt: server timestamp   # solo friends
  schemaVersion: 1
```

La relación depende exclusivamente de UID. Username, nombre visible y avatar se
leen en tiempo real desde `profiles/{uid}`; cambiar cualquiera de ellos no altera
la amistad.

El ID canónico se obtiene ordenando los UID, serializando cada uno con longitud
(`longitud:uid`) y codificando el UTF-8 en hexadecimal. Es determinista,
independiente del orden y sin colisiones por separadores. No es un secreto.
Cliente y Rules recalculan el mismo ID, por lo que no puede existir un segundo
documento válido para la misma pareja.

## Operaciones y concurrencia

Todas las mutaciones móviles usan transacciones:

- enviar sin relación crea `pending`;
- repetir el mismo envío no cambia nada;
- si existe la solicitud inversa, el receptor la acepta y converge en `friends`;
- solo el receptor acepta o rechaza;
- solo el emisor cancela;
- cualquiera de los miembros elimina una amistad;
- repetir una resolución ya aplicada es seguro e idempotente;
- tras eliminar o rechazar, cualquiera puede iniciar una solicitud nueva.

Aceptar modifica el mismo documento canónico. No hay solicitud y amistad
duplicadas ni vistas denormalizadas que puedan quedar desincronizadas.

## Consultas y tiempo real

El usuario escucha una única query con
`where('memberUids', arrayContains: currentUid)`. La app clasifica localmente los
documentos como amigos, recibidas o enviadas. Solo se requieren índices
automáticos; no hay índice compuesto nuevo.

La búsqueda reutiliza los perfiles públicos de P2. El perfil público muestra una
única acción válida según el estado: añadir, cancelar, aceptar/rechazar o eliminar
amistad. La UI espera la confirmación del servidor y muestra carga o error; no
inventa un estado optimista.

## Seguridad

Firestore Rules protege:

- cuenta completa y perfil propio obligatorios;
- perfil de destino existente;
- creación exclusiva por `requesterUid` autenticado;
- dos miembros distintos, ordenados y con ID canónico;
- campos, estado, versión y timestamps exactos;
- lectura solo por participantes mediante query compatible;
- aceptación exclusiva del receptor y transición `pending -> friends`;
- identidad y campos estructurales inmutables;
- cancelación/rechazo según rol y eliminación de amistad por cualquiera de sus
  miembros;
- denegación a anónimos, no verificados, terceros y documentos malformados.

Las reglas no pueden consultar el token Auth de otra persona. La existencia de su
perfil público es la prueba persistida de que el destino completó P2; solo una
cuenta completa puede crear ese perfil.

## Separación del dominio económico

Eliminar una amistad borra únicamente `friendships/{id}`. No modifica perfiles,
sesiones, participantes, tickets, balances, pagos, liquidaciones ni historial. Una
relación económica puede existir sin amistad y viceversa.

## Fuera de P3

- No se crean grupos o espacios permanentes.
- No se añaden amigos automáticamente a tickets.
- No hay chat ni feed social.
- No se implementan notificaciones: la infraestructura actual está ligada a
  eventos económicos y ampliarla requeriría un contrato propio de tokens,
  preferencias y privacidad.
- La futura eliminación definitiva de una cuenta deberá limpiar sus amistades
  canónicas mediante un proceso autoritativo, sin tocar el historial económico.

## Pruebas

La cobertura se reparte entre:

- `friendship_repository_test.dart`: identidad canónica, idempotencia,
  concurrencia, solicitudes cruzadas, roles, tiempo real y cambios de username;
- `friends_screen_test.dart`: vacíos, perfil requerido, acciones contextuales,
  confirmación de borrado y layout con nombres/texto grandes;
- `backend/firestore/test/rules.test.mjs`: permisos positivos y negativos contra
  Emulator Suite.
