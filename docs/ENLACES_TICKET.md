# Enlaces de Ticket (Sprint 5)

Estado: implementado (2026-07-25). **Revisado el 2026-07-27 (ADR-036 rev. 2):
el enlace es DIRIGIDO.** Complementa `docs/ESPACIOS.md` (enlaces de grupo,
ADR-035) y `docs/RELACIONES_ECONOMICAS.md` (P5, intacto).

## Revisión 2: un enlace, una persona

La primera versión hacía **un enlace por ticket**: publicaba la lista de
todos sus participantes MANUAL y quien lo recibía elegía cuál era. Rules solo
comprobaba «ese pid participa en este ticket», así que consentía la elección.
Consecuencia: un enlace generado para Pedro servía para quedarse con la
identidad económica de Ana, y de ahí —vía ADR-037— para pedir la vinculación
de su historial.

Ahora hay **un enlace por persona**. El destinatario (`targetPid`,
`targetManualId`, `targetName`) es parte del documento, es inmutable, y Rules
exige que la identificación coincida con él. Ocultar el selector en la
interfaz no habría bastado: un cliente modificado escribe lo que quiera, así
que la barrera está en `isTicketLinkTarget()`.

Los enlaces del esquema 1 ya emitidos **dejan de identificar a nadie** —el
`targetManualId` ausente no coincide con ningún `manualId`—; el dueño solo
puede revocarlos, no reactivarlos.

## Qué resuelve

Compartir **un ticket concreto** con quien no tiene por qué entrar en el
grupo — típicamente una persona sin cuenta que participa en ese gasto y a
quien el anfitrión anotó como participante MANUAL.

## Por qué NO se reutiliza `spaceLinks`

Alcance y amenazas distintos. Un enlace de grupo incorpora a alguien de forma
permanente a un contexto; uno de ticket concede lectura de UN ticket y
permite identificarse temporalmente como uno de sus MANUAL. Compartir el
mismo mecanismo habría convertido cualquier fuga de un enlace de ticket en
acceso al grupo entero. Se reutiliza lo que sí es igual: token opaco de 128
bits como id del documento, `list` restringido, revocación y caducidad
opcional e inmutable.

## Modelo de datos

```text
ticketLinks/{token}                       token = 128 bits (ShareCode), ID = secreto
  sessionId · accountId · ticketId        alcance exacto
  merchantName                            dato visible antes de identificarse
  targetPid · targetManualId · targetName DESTINATARIO único e inmutable
  spaceId? · createdByUid
  status: active|revoked · expiresAt? · createdAt · updatedAt · schemaVersion: 2

sessions/{sid}/ticketAccess/{ticketId}_{uid}   identificación TEMPORAL
  uid · token · ticketId · pid · manualId? · createdAt · schemaVersion: 1

sessions/{sid}/ticketParticipants/{ticketId}_{pid}   PROYECCIÓN AUTORITATIVA
  ticketId · pid · manualId? · claimedByDevice?     (la escribe recompute)

sessions/{sid}/ticketParticipantProjections/{ticketId}   SEÑAL DE PREPARADA
  ticketId · ready: true · fingerprint · updatedAt · schemaVersion: 1

sessions/{sid}/ticketClaims/{ticketId}_{manualId}   cerrojo anti-colisión
  uid · ticketId · manualId · createdAt · schemaVersion: 1
```

## El enlace NO es un secreto portador que abra el ticket

Poseerlo **no basta para leer**: hay que representar a alguien que participa
en el ticket. O bien se es un participante ya reclamado por ese UID (cuenta o
invitado conocido), o bien se elige un MANUAL válido. No existe lectura
anónima previa.

Que el participante pertenezca de verdad al ticket lo demuestran las Rules
con `exists()` sobre `ticketParticipants`, una proyección **derivada y
autoritativa** que escribe `recompute` (Admin) a partir del reparto real:
participa quien consume algo o quien paga. No se confía en el array `manuals`
del enlace, que lo escribe el cliente y solo sirve para PINTAR la lista.

## Consistencia eventual: se resuelve en el origen, no con un fallback

La proyección la escribe `recompute` tras un trigger, así que existe un
instante en el que un ticket recién creado todavía no la tiene. Un fallback
—«si no hay proyección, cree al enlace»— habría degradado justo lo que se
acababa de blindar. La carrera se resuelve **impidiendo que exista un enlace
que vaya a fallar**:

- `recompute` escribe la señal `ticketParticipantProjections/{ticketId}` en el
  **mismo batch** que las entradas y sus borrados. Firestore lo hace atómico:
  es imposible marcar como lista una proyección a medias.
- Las Rules **exigen la señal para crear un `ticketLink`**. Sin proyección
  completa no hay enlace.
- La app espera la señal **escuchando el documento**, no durmiendo: se
  resuelve en cuanto recompute escribe. El plazo solo acota la espera para
  poder dar un error recuperable (`TicketLinkNotReady`) si la Function no
  termina; nunca se usa como garantía.
- La señal también distingue **«el ticket se está procesando»** de **«esta
  persona no participa»**, que era la ambigüedad que empujaba al fallback.

La `fingerprint` es la lista ordenada de pids participantes: cambia en cuanto
entra o sale alguien, así que delata una proyección antigua.

## Limpieza de proyecciones obsoletas

`recompute` no solo crea: **borra** toda entrada que haya dejado de
representar participación real (`if (!desired.has(doc.id)) batch.delete(...)`),
y borra la señal de un ticket que ya no tiene participación —por ejemplo
porque se eliminó—. Probado en las ocho situaciones que importan: dejar de
consumir, dejar de pagar, línea eliminada, reparto modificado, participante
retirado, ticket eliminado, idempotencia, y que **una entrada antigua deja de
conceder acceso** (esto último en Rules, que es donde se nota).

**La identificación se liga al UID, no al dispositivo.** Un UID es una
identidad: para una cuenta vale en todos sus dispositivos, y eso es lo
correcto. La clave del documento es `{ticketId}_{uid}`, así que **abrir un
segundo ticket no invalida el acceso al primero**.

**Por qué `manuals` va denormalizado**: quien todavía no se ha identificado
no puede leer los participantes de la sesión — y para leerlos necesitaría el
acceso que está intentando obtener. Denormalizarlos es la única forma de
pintar «¿Quién eres?», y a la vez la más estrecha: la lista contiene
exactamente los manuales de ese ticket, nunca cuentas, invitados ni miembros
del grupo, así que **no revela cuánta gente hay**. Contrapartida: si un
manual se renombra después, el rótulo del enlace queda antiguo — es
cosmético, porque Rules revalida `pid → manualId → active` al identificarse.

## Identificación temporal ≠ vinculación

| | Identificación temporal (Sprint 5) | Vinculación definitiva (Sprint 6) |
|---|---|---|
| Dónde vive | `sessions/{sid}/ticketAccess/{ticketId}_{uid}` | Sin decidir (alias vs migración) |
| Actor económico | **Sigue siendo `manual:{manualId}`** | Cambiaría a UID |
| `linkedUid` | **Nunca se escribe** | Es su marcador |
| Balances | **No se mueve un céntimo** | Habría que consolidar |
| Alcance | UN ticket | Todo el historial |
| Deshacer | Borrar un documento | Requiere plan de reversión |

- **Cuánto dura**: hasta que se revoque el enlace, caduque, o el dispositivo
  la suelte. No expira por sí sola.
- **Quién la lee**: solo el propio dispositivo. Ni siquiera el dueño de la
  sesión — no hay auditoría de quién dice ser quién, a propósito.
- **Quién la borra**: el propio dispositivo (botón «No soy yo»). El cerrojo
  además lo puede liberar el dueño de la sesión, para deshacer un error.
- **Reabrir el mismo enlace**: idempotente, entra directo sin repetir pasos.
- **Al cerrar sesión**: el UID anónimo persiste en el dispositivo, así que la
  identificación sigue sirviendo. Con una cuenta, cerrar sesión cambia el UID
  y la prueba deja de aplicar (queda huérfana e inocua).
- **Al convertirse en cuenta**: la conversión conserva el UID (ADR-023), así
  que la identificación sobrevive. Sigue sin ser vinculación.
- **Cuando llegue el Sprint 6**: un MANUAL con `linkedUid` deja de ser
  elegible (Rules ya lo comprueba, aunque hoy nunca excluya a nadie porque
  `linkedUid` es siempre null). Sustituir estas pruebas no toca el historial
  económico, porque nunca formaron parte de él.

### La línea roja del diseño

Reclamar el MANUAL por `claimedByDevice` habría sido más corto y
**catastrófico**: `recompute.ts` da PRECEDENCIA a esa vía sobre `manualId`,
así que el actor económico habría migrado de `manual:{id}` a un UID por la
puerta de atrás — exactamente la vinculación definitiva que el Sprint 6 debe
decidir con un ADR propio. De ahí que la prueba viva en documentos que
`recompute` no lee jamás.

## Autorización

Poseer el enlace permite **solo**:

1. leer el propio enlace (comercio y nombres de los MANUAL);
2. crear la propia identificación para ese ticket, **representando a alguien
   que participa en él**;
3. leer ESE ticket y sus líneas.

No permite: leer la sesión (con sus balances), **los participantes** (sus
nombres no son suyos; Rules sí los consulta internamente con `get()` para
validar), otros tickets de la misma sesión, liquidaciones, el espacio ni sus
miembros; ni escribir líneas, participantes o balances. Todo ello con prueba
negativa en Rules.

**Revalidación continua**: `hasTicketAccessTo` vuelve a leer el enlace en cada
lectura, así que revocarlo o dejarlo caducar corta el acceso al instante
aunque la prueba siga escrita en el dispositivo.

## Colisión entre dispositivos

El cerrojo `ticketClaims/{ticketId}_{manualId}` tiene ID determinista y solo
admite `create` si no existe. Firestore garantiza la exclusión sin
transacción extra: **el primero que llega gana**; el segundo recibe
`permission-denied` y la app lo presenta como «ese nombre lo acaba de coger
otro dispositivo», retirándolo de la lista y dejando elegir otro. Reabrir el
enlace en el mismo dispositivo sí actualiza (mismo `uid`).

## Flujo

1. Se resuelve el enlace: solo se ve el comercio.
2. Sin identidad → invitado, entrar o crear cuenta. El token se recuerda en
   `pendingTicketLinkProvider`, así que identificarse **no pierde el enlace**
   (incluido el paso de verificar el correo).
3. Invitado sin nombre → solo se le pide el nombre.
4. Con identidad → se busca el `pid` de este UID en la proyección
   autoritativa. Si ya participa, entra directo, sin preguntar nada.
5. Si no participa y hay MANUAL elegibles → «¿Quién eres?».
6. Si no participa y no hay MANUAL elegible → **no se concede lectura**: no
   hay a quién representar.

Rutas: `/t/{token}` (enlace) y `/ticket/{token}` (vista de solo lectura).

**Con un único MANUAL elegible se confirma igual**, no se autoselecciona: un
enlace reenviado por error convertiría la autoselección en una suplantación
silenciosa, y confirmar cuesta un toque.

## Ticket borrado, archivado o movido

La vista degrada con un mensaje, nunca con una pantalla rota. Un enlace no
puede reapuntarse a otro ticket (Rules lo impide), así que «movido» solo
puede significar borrado y recreado: el enlace deja de resolver y el dueño
crea uno nuevo.

## P5 no cambia

`recompute` gana UNA salida derivada y aditiva —la proyección
`ticketParticipants`— y **ningún cambio económico**: los mismos 120 tests de
Functions siguen verdes sin tocar un vector. No se altera `economicLedger`,
ni los actores, ni los balances, ni las liquidaciones. Se añaden
pruebas que lo demuestran: identificarse no escribe `claimedByDevice` ni
`linkedUid`, no crea `economicEntries` ni `economicPayments`, y no toca
balances (`ticket_links_test.dart`, grupo «el modelo económico NO se toca»;
y en Rules, «el flujo de acceso NO puede tocar balances ni participantes»).

## Pruebas

- `rules.test.mjs`, bloque «enlaces de ticket»: 17 casos, casi todos
  negativos (enumeración, suplantación de cuenta/invitado, pid≠manualId,
  identificación para otro UID, prueba de otro ticket, revocado, caducado,
  acceso al resto de la sesión y del grupo, colisión, MANUAL vinculado).
- `ticket_links_test.dart`: 12 casos del contrato del repositorio.

## Fuera de alcance

Vinculación definitiva (Sprint 6), edición de líneas desde el enlace, pago
desde el enlace, y la página de aterrizaje de Hosting para `/t/{token}`.
