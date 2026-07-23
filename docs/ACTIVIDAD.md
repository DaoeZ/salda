# Actividad (P6)

Estado: implementado (2026-07-20). Decisión: ADR-031. Contrato de la
cronología de Salda.
Especificación de origen: `docs/P6_ESPECIFICACIONES.md`. No incluye chat,
mensajes libres, comentarios, reacciones, menciones, adjuntos, notificaciones
push completas, correo, rankings ni gamificación (P7+).

## Objetivo

Que un usuario vea qué cambió, quién lo hizo, cuándo ocurrió y pueda llegar
al objeto original que explica el evento.

## Fuente de verdad

La actividad es una PROYECCIÓN de auditoría. Las fuentes de verdad siguen
siendo tickets, espacios, membresías, invitaciones, settlements y pagos P5.
Eliminar un evento jamás modificaría el objeto original, y el feed nunca se
usa para calcular balances, permisos, membresías ni estados.

## Eventos soportados

| Tipo | Hecho | Actor |
|---|---|---|
| space_created / renamed / archived / reactivated | ciclo de vida del espacio | owner |
| space_transferred | transferencia | owner ANTERIOR |
| invite_sent | invitación (o reenvío) | emisor |
| member_joined | aceptar invitación | el propio miembro |
| member_left / member_removed | salida / expulsión | miembro / owner |
| ticket_created / updated / deleted | ticket (edición RELEVANTE: comercio, total, fecha, pagador) | dueño de la sesión |
| ticket_linked / unlinked | vínculo con espacio | dueño de la sesión |
| payment_marked / confirmed | settlements humanos del flujo antiguo (marked/confirmed) | deudor / receptor reales |
| payment_marked / confirmed / cancelled | pagos P5 `source: user` | del `stateHistory` |

Sin eventos: rechazos/cancelaciones de invitación (privados), cambios de
línea/asignación (ruido técnico; una edición atómica del ticket = un evento),
settlements `pending` (sugerencia del motor, no un hecho humano) y pagos
`legacySettlement` (su hecho ya se registra desde el settlement: el mismo
hecho jamás se duplica entre el sistema antiguo y P5).

## Modelo

```text
activityEvents/{id determinista}
  type · actorUid · memberUids[] (audiencia congelada, máx. 30)
  spaceId? · sessionId? · ticketId? · paymentId?
  summary { spaceName? ticketName? sessionName? amount? currency? }
  at (server timestamp) · schemaVersion: 1
```

No se guardan correos, tokens ni datos privados. Los nombres de personas NO
se congelan: se resuelven en vivo por UID (cambiar el username no altera el
historial y el histórico sobrevive a bajas). Solo se congela el rótulo del
objeto (espacio/ticket) para que la fila siga siendo legible si el objeto
desaparece; en ese caso la navegación muestra el estado "no disponible" de
la pantalla destino en lugar de romperse.

## Generación e idempotencia

Solo los triggers Admin generan eventos (`activity.ts`): ningún cliente
escribe actividad ni puede fabricar eventos a nombre de otro (el actor se
deriva de datos autoritativos: ownerUid, uid de la membresía, participantes
con cuenta o `stateHistory` del pago). La expulsión se distingue de la
salida con el marcador `removedBy` que el owner escribe justo antes del
borrado y que Rules valida (solo el owner, nunca sobre sí mismo).

Los IDs son deterministas por hecho (`sp_{id}_created`,
`mb_{spaceId}_{uid}_join_{joinedAt}`, `tk_{sid}_{tid}_upd_{hash(estado)}`,
`st_{sid}_{stid}_{estado}`, `pay_{hash(paymentId)}_{estado}`…) y la
escritura es `create()`-only: reintentos de trigger, escrituras offline
repetidas, dobles pulsaciones y reescrituras de proyecciones por recompute
convergen en el MISMO documento y conservan su hora original. recompute no
puede llenar el feed: solo escribe settlements `pending` (ignorados) y
reescrituras sin transición de estado (ignoradas).

Límite conocido: una edición que devuelve el ticket EXACTAMENTE a un estado
relevante anterior colapsa con el evento previo de ese estado (id por hash
del destino). Es deliberado: preferimos colapsar a duplicar.

## Privacidad

`memberUids` es la audiencia CONGELADA del hecho: participantes del objeto y
miembros del espacio en ese momento. Un miembro nuevo no hereda actividad
anterior (coherente con la política de tickets de P4); un expulsado conserva
los hechos en los que participó; el owner del espacio no recibe visibilidad
económica extra (los pagos solo llevan a sus dos partes). Rules: lectura
solo con cuenta completa (`canUseSocial`) y `uid in memberUids`; escrituras
de cliente prohibidas. Todas las queries incluyen `array-contains` del
propio uid, que es lo que hace la regla demostrable.

## Consultas, índices y escalabilidad

- Global: `memberUids array-contains uid · orderBy at desc · limit 30`.
- Espacio: igual + `spaceId ==`.
- Paginación por fecha con `startAfter` (página viva por stream, historial
  bajo demanda). Nunca se descarga todo para filtrar en cliente.

Índices compuestos: `(memberUids CONTAINS, at DESC)` y
`(spaceId ASC, memberUids CONTAINS, at DESC)`.

Límites documentados: audiencia máx. 30 UIDs por evento (espacios mayores
truncan la audiencia por orden de UID; suficiente para el uso
personal/amigos de Salda y revisable con un modelo fan-out si creciera).

## Compatibilidad histórica

P6 empieza en su despliegue: NO se retro-genera actividad de P1–P5 (no se
fabrican fechas ni actores no demostrables). Tickets y pagos antiguos siguen
accesibles desde sus pantallas aunque no tengan eventos.

## UX

- Cronología global (`/home/activity`, icono en Home): tiempo real en la
  primera página, "Cargar más" para el historial, vacío/carga/error con
  reintento, importes tabulares y elipsis en nombres largos.
- Actividad del espacio: sección en el detalle (últimos 8, en vivo) +
  cronología completa en `/home/spaces/{id}/activity`.
- Cada fila: actor (avatar+nombre en vivo), acción con el rótulo del
  objeto, tiempo relativo e importe si procede; al tocar navega al espacio,
  la sesión o Economía según el objeto.

## Pruebas

- `backend/functions/src/test/activity.test.ts`: builders puros — tipos,
  actores, audiencia congelada, ids deterministas, reintentos, expulsión vs
  salida, ruido técnico ignorado, legacy/pending/recompute sin eventos.
- `backend/firestore/test/rules.test.mjs` (bloque activityEvents): lectura
  por audiencia, anónimos/no verificados fuera, escrituras y suplantación
  denegadas, query demostrable, marcador `removedBy`.
- `apps/mobile/test/activity_test.dart`: repositorio (audiencia, orden,
  paginación sin duplicados, filtro por espacio, resumen congelado), textos
  por tipo, tiempo relativo, pantalla (vacío, filas, importes y nombres
  largos sin overflow).
