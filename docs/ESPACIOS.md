# Relaciones y grupos (evolución de P4)

Estado: eje principal integrado sobre P4 y P5 (2026-07-22). Contrato vigente del
contenedor social de gastos. Los balances explicables por espacio se describen
en `docs/RELACIONES_ECONOMICAS.md`; actividad, chat y notificaciones siguen fuera.

## Concepto

Un espacio agrupa tickets y personas alrededor de un contexto. En producto se
presenta como **relación** cuando reserva exactamente dos UID, o como **grupo**
cuando participan tres o más personas. Ambos reutilizan `spaces`; no existe un
segundo backend social ni económico.

Separación estricta de conceptos:

- **Membresía ≠ amistad.** Se puede compartir espacio sin ser amigos. Eliminar
  una amistad no expulsa de ningún espacio; expulsar de un espacio no elimina
  la amistad. La UI prioriza invitar amigos, pero el modelo no los acopla.
- **Membresía ≠ participación económica.** Los tickets siguen viviendo en
  sesiones con sus participantes por nombre; pertenecer a un espacio no te
  añade a ningún reparto.
- **Membresía ≠ deuda.** El dinero sigue siendo de los motores y `recompute`.
  P5 filtra sus obligaciones derivadas por `spaceId`, pero salir, ser expulsado
  o archivar nunca elimina la relación económica ni su historial.

Todas las claves relacionales son UID. Username, nombre visible y avatar se
leen de `profiles/{uid}` en tiempo real: cambiarlos no altera membresías ni
invitaciones.

## Modelo

```text
spaces/{spaceId}
  name (2..40) · avatarEmoji? (≤8) · ownerUid · status: active|archived
  kind: relationship|group · relationshipUids? · schemaVersion: 2
  createdAt · updatedAt
  members/{uid}: { uid, joinedAt }
spaceInvites/{spaceId}_{toUid}
  spaceId · spaceName (denormalizado solo para pintar) · fromUid · toUid
  status: pending|accepted|rejected|cancelled · createdAt · updatedAt
sessions/*.contextModelVersion: 1 · spaceId · spaceName
tickets/*.contextModelVersion: 1 · spaceId
```

Los documentos P4 `schemaVersion: 1` sin `kind` se leen como grupos. No se
clasifican automáticamente por número de miembros ni por tickets: hacerlo
inventaría una intención social y podría cambiar la presentación histórica.

Una relación usa el ID canónico `relationship_{uidMenor}~{uidMayor}` y conserva
los dos UID ordenados e inmutables en `relationshipUids`, incluso mientras la
segunda persona decide la invitación. Rules impide otro ID, un tercer miembro o
una invitación fuera de la pareja. Un grupo mantiene membresía flexible, pero la
app exige al menos tres miembros antes de permitir gastos nuevos.

Decisiones clave:

- **El rol no se persiste.** El propietario único es `ownerUid` (fuente única
  de verdad); miembro es quien tiene doc de membresía. Transferir la
  propiedad es actualizar UN documento — atómico por definición — y Rules
  exige que el destino sea un miembro activo. Sin este diseño, la
  transferencia necesitaría un batch multi-doc cuyas reglas no pueden
  validarse (get() sobre docs del propio batch falla).
- **Invitaciones con ID determinista** `{spaceId}_{toUid}`: no puede haber
  dos activas para la misma persona; reenviar tras rechazo o cancelación
  reutiliza el documento. Aceptar une al receptor y resuelve la invitación
  en el MISMO batch (validado con getAfter); una cancelada ya no se puede
  aceptar.
- **El owner no puede salir**: antes transfiere o archiva. Salir o expulsar
  borra SOLO la membresía: tickets, asignaciones, pagos, balances e
  historial quedan intactos, incluida la identidad del ex-miembro en
  operaciones anteriores. Si participa en tickets aún activos, esos tickets
  no cambian: su relación con ellos es por sesión (nombres/guestAccess), no
  por membresía.
- **Archivar** oculta el espacio de la lista principal, conserva miembros,
  tickets e historial, bloquea invitaciones/edición/vínculos nuevos y es
  reversible. No existe el borrado de espacios en P4 (nada destructivo).
  P5 permite consultar y liquidar una deuda ya originada porque el pago es
  bilateral y no muta el espacio; no se pueden crear tickets nuevos mientras
  el espacio permanezca archivado.
- **Sin administradores**: solo propietario y miembro. No hay necesidad real
  todavía (lista negra de sobre-ingeniería de la Biblia).

## Tickets y política de privacidad

Todo ticket nuevo pertenece a UN contexto. La sesión y el ticket llevan
`contextModelVersion: 1` y el mismo `spaceId`; Rules impide cambiarlo o
desvincularlo. Sus participantes registrados se crean desde las membresías y
quedan reclamados por UID, lo que mantiene explicables los balances P5.

Los tickets anteriores sin marcador siguen siendo legibles y no se asocian por
heurísticas. Aparecen en «Histórico sin organizar» y pueden vincularse solo por
una acción explícita. Vincular o desvincular un ticket histórico NUNCA cambia participantes,
asignaciones, balances ni pagos, y solo puede hacerlo el dueño de la sesión
del ticket, hacia espacios de los que es miembro (Rules lo valida).

Lectura: los miembros del espacio ven el RESUMEN del ticket (documento del
ticket vía collection group, en tiempo real y sin copias desincronizables).
Las líneas, la foto y el resto de la sesión NO se exponen: el detalle sigue
siendo de quien ya tiene acceso a la sesión por los cauces existentes (dueño
o invitado por enlace). Edición: solo el dueño de la sesión, como siempre.
Los tickets sin `spaceId` funcionan exactamente igual que antes.

Flujos: crear ticket desde el espacio (el flujo normal de escaneo con
vínculo diferido al guardar), vincular/desvincular uno existente desde el
detalle del ticket, y lista en vivo en el detalle del espacio.

## Seguridad (Rules)

- Crear espacio: cuenta completa con perfil (`canUseSocial`), owner = autor,
  batch atómico espacio+membresía (getAfter).
- Leer espacio/miembros: solo miembros. "Mis espacios": collection group de
  membresías restringido a `uid == auth.uid`.
- Editar/archivar/reactivar/transferir: solo el owner ACTUAL (pre-imagen del
  doc, sin get()); createdAt y schemaVersion inmutables; transferencia solo
  a miembro existente y con el espacio activo.
- Invitar: owner de espacio activo, a cuenta con perfil que no es miembro,
  con ID canónico; aceptar/rechazar solo el receptor; cancelar/reenviar solo
  el owner; alta de miembro solo con invitación aceptada en el mismo batch.
- Salir/expulsar: nunca al owner; el propio miembro o el owner.
- Vincular ticket: dueño de la sesión + miembro del espacio.
- Anónimos y no verificados: sin acceso a nada de lo anterior.

Índices: dos `fieldOverrides` de collection group (members.uid,
tickets.spaceId); las queries de invitaciones son de igualdad pura (sin
composites).

## Pruebas

- `backend/firestore/test/rules.test.mjs` (bloque spaces): 19 casos
  positivos/negativos contra el emulador.
- `spaces_repository_test.dart`: ciclo de vida, idempotencia de
  invitaciones, transferencia, salida/expulsión, vínculo de tickets y
  compatibilidad con tickets sin espacio.
- `spaces_screen_test.dart`: vacío, activos/archivados, aceptar invitación.
