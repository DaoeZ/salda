# Vinculación de identidad (Sprint 6)

Estado: núcleo implementado (2026-07-26). ADR-037. Resuelve la decisión que
ADR-033, ADR-034 y ADR-036 dejaron expresamente abierta.

## Qué resuelve

Un participante MANUAL —alguien a quien el anfitrión anotó a mano— puede
convertirse después en **invitado** o en **cuenta registrada** sin perder
absolutamente ningún dato histórico.

## La decisión: ALIAS, no migración

ADR-033 planteó dos caminos y declaró preferente el alias. Se confirma:

| | Migración de referencias | **Alias (elegido)** |
|---|---|---|
| Documentos históricos | Se reescriben todos | **No se toca ninguno** |
| Atomicidad | Imposible entre colecciones | Irrelevante: no hay escritura masiva |
| Reversible | No | Sí (basta ignorar el alias) |
| IDs deterministas ya calculados | Se invalidan | Siguen siendo válidos |

**El actor económico no cambia nunca.** Sigue siendo `manual:{manualId}`,
que es la clave con la que están escritas todas las obligaciones. El
`participantId` (pid) tampoco cambia. Lo único que ocurre al vincular es que
se **añade** una identidad: la persona pasa a ser LECTORA de lo suyo.

```text
spaces/{spaceId}/manualParticipants/{manualId}
  linkedUid: null → uid        ← lo escribe la aprobación
  linkStatus: ausente → processing → active|failed
              failed → processing (callable de reintento seguro)
  linkError · linkBlockedSessions                 ← solo fallo terminal
  linkPropagatedSessions · linkPropagatedAt       ← solo active
  linkClaimId · linkProcessingAt                  ← claim Admin vigente
  linkRetryCount · linkRetryRequestedAt/By        ← trazabilidad Admin

spaces/{spaceId}/manualLinkRequests/{manualId}_{uid}
  manualId · uid · displayName? · status: pending|accepted|rejected
  createdAt · updatedAt · schemaVersion: 1
```

`recompute` carga los alias del espacio (`manualId → linkedUid`) y los pasa a
`accountUidsOf`, que ahora resuelve un actor manual vinculado a su UID **solo
a efectos de audiencia**. Nada más cambia: mismos ids de documento, mismos
actores, mismos importes, mismos balances, mismas liquidaciones.

## Efecto real: propagación con estado explícito (C1)

`recompute` lee los alias del espacio, pero escribir `linkedUid` no disparaba
nada: la app decía «vinculado» y el acceso no existía hasta que alguien
editaba un ticket por otro motivo. **Corregido con reproyección explícita.**

- `propagateOnManualLink` (trigger sobre `manualParticipants`) detecta la
  transición `linkedUid: null → uid` y reproyecta **todas las sesiones
  afectadas**. El criterio es el real —`collectionGroup('participants')
  .where('manualId','==',…)`— y no `session.spaceId`: `linkTicket` vincula el
  TICKET a un espacio sin tocar la sesión, así que filtrar por `spaceId`
  omitía sesiones afectadas (M3).
- La aprobación escribe `manualLinkRequests.status: 'accepted'` y `linkedUid`
  en el mismo batch; durante la ventana previa al trigger, `linkStatus` queda
  ausente.
- El trigger reclama atómicamente esa versión escribiendo `processing`: esa
  escritura no se realimenta y una entrega duplicada pierde la reclamación.
- La Function solo publica `linkStatus: 'active'` después de reproyectar todas
  las sesiones afectadas, o `linkStatus: 'failed'` con un código estable. **La
  UI nunca afirma acceso que no exista.** `linkPropagatedSessions` y
  `linkPropagatedAt` solo acompañan a `active`; `linkBlockedSessions` solo al
  fallo legacy `legacy-sessions-without-context`.

### Reintento seguro de la propagación

`retryManualLinkPropagation` es un callable autenticado que recibe únicamente
`{spaceId, manualId}`. El servidor deriva el propietario y el `linkedUid` del
documento; autoriza al propietario actual o al UID vinculado exacto. No acepta
UIDs de autoridad ni tiempos del cliente.

- `failed` adquiere un nuevo claim y reutiliza la misma propagación.
- `active` es un no-op; un `processing` con lease fresco responde en curso.
- Un lease Admin caducado puede reclamarse de forma segura. Si falta la
  metadata de lease, la respuesta es conservadora y no muta nada: no se
  adivina antigüedad a partir de `updatedAt`.
- Un manual ya vinculado sin `linkStatus` puede adquirir el claim inicial en
  carrera transaccional con el trigger. La escritura de processing del
  callable no vuelve a lanzar el trigger porque el vínculo ya existía.
- Cada claim tiene ID opaco y lease escrito por servidor; el terminal exige el
  mismo claim. Así, un worker antiguo no puede publicar después de una
  recuperación. Hay cooldown breve para acotar reintentos repetidos.

El trigger conserva la ruta de alta inicial; no se crea una colección adicional
de solicitudes de retry ni un campo de retry escribible por el cliente.

**Por qué reproyectar y no resolver al leer.** Resolver el alias en la
consulta obligaría al cliente a buscar además por `debtorUid`/`creditorUid`,
a que Rules autorizasen cada documento con un `get()` por página, y sobre
todo a **consolidar saldos en el cliente**, rompiendo DC-7 (la function es la
calculadora autoritativa). Además la supresión de auto-deudas (C2) tiene que
ocurrir en el motor: resolver C1 al leer y C2 al calcular dejaría el modelo
híbrido que hay que evitar.

### Sesiones sin contexto estable (M3)

Una sesión afectada **sin `spaceId`** no puede resolver alias —`recompute`
los lee del espacio de la sesión—, así que reproyectarla dejaría el vínculo a
medias. En vez de omitirla en silencio, la propagación **se detiene**:
`linkStatus: 'failed'` con `linkError: 'legacy-sessions-without-context'` y
el número de sesiones bloqueadas. **El estado nunca termina en `active`
habiendo dejado economía fuera.** La app lo traduce a un mensaje
comprensible; el detalle completo vive solo en logs.

### La vinculación es ASÍNCRONA

Conviene decirlo sin rodeos:

- `accepted` **no equivale todavía a acceso**. Significa que el anfitrión
  aprobó, no que la reproyección haya terminado.
- El acceso solo es efectivo en **`active`**.
- Una propagación puede **fallar** y se reintenta mediante el callable,
  devolviendo el estado a `processing`; el trigger solo conserva la ruta de
  alta y no duplica el worker del callable.
- El histórico no se reescribe, pero **la materialización de documentos
  derivados sí puede cambiar** (ver más abajo).

## Una persona nunca se debe dinero a sí misma (C2)

Dos actores distintos pueden ser la misma persona: su UID y un
`manual:{id}` vinculado a ese UID. Antes eso generaba una obligación consigo
mismo y una liquidación pidiendo transferirse dinero.

`recompute` compara ahora la **identidad efectiva** (`resolveActorIdentity`,
que ya no es código muerto) y omite la obligación cuando deudor y acreedor
son la misma persona. **No se toca el reparto**: `balances` y
`sessionTotals` son idénticos antes y después; lo único que cambia es qué
obligaciones se publican. Los actores históricos siguen intactos.

Además, la reserva `linkedIdentities/{uid}` impide de raíz que una persona
quede vinculada a dos manuales del mismo espacio.

## Invitados: hay que convertirse en cuenta antes (M1)

Un GUEST **no puede solicitar** la vinculación. Su UID vive en una sesión
anónima ligada al dispositivo: atarle un historial económico lo condenaría a
desaparecer con el móvil, y como vincular es irreversible no habría rescate.
Debe convertir su acceso en cuenta primero — la conversión **conserva el
UID** (ADR-023), así que no pierde nada. Una vez aprobado el vínculo, el
callable autoriza al `linkedUid` exacto sin aceptar UIDs aportados por el
cliente.

## Seguridad: aprobación del anfitrión

Vincular es apropiarse de un historial económico, así que hacen falta **dos
partes**:

1. **La persona pide** — el callable `requestManualLink` crea
   `manualLinkRequests/{manualId}_{uid}` para sí misma y deriva el UID desde
   la sesión autenticada: nadie pide en nombre de otro. Vale para una cuenta
   no anónima, con el correo verificado y perfil público; un invitado debe
   convertirse antes sin cambiar de UID.
2. **El anfitrión decide** — solo él pasa la solicitud a `accepted` o
   `rejected`, y **aceptar escribe el `linkedUid` en el MISMO batch**,
   validado con `getAfter`. Sin ese emparejamiento no existe forma de
   escribir un vínculo.

Invariantes que Rules impone:

- un manual **no puede nacer vinculado**;
- **vincular es irreversible**: ni se revincula, ni se desvincula, **ni se
  borra el manual vinculado** — el borrado era una puerta trasera que
  eliminaba el alias y dejaba la solicitud aceptada apuntando a la nada;
- **solo pueden solicitarlo** quienes tienen relación real con el manual:
  miembros del espacio, o quien posea un `ticketAccess` vigente cuyo manual y
  pid coincidan según la proyección autoritativa. Conocer el `manualId` no
  basta: el enlace de ticket lo publica a cualquiera que lo reciba;
- el **nombre declarado** por quien solicita está acotado (1..40) y congelado
  tras crear: es la prueba de qué se le enseñó al anfitrión al decidir;
- no se solicita sobre un manual ya vinculado;
- las solicitudes **no son enumerables** salvo por el anfitrión;
- las solicitudes **no se borran**: son el rastro de que hubo aprobación.
- `linkedUid` se puede consultar por `get` únicamente en el manual propio del
  UID vinculado; esa persona no puede listar la colección. Los miembros y el
  anfitrión conservan la lectura social de sus manuales.
- `linkStatus`, `linkError`, `linkBlockedSessions`, `linkPropagatedSessions`,
  `linkPropagatedAt`, `linkProcessingAt`, `linkClaimId`, `linkRetryCount`,
  `linkRetryRequestedAt` y `linkRetryRequestedBy` son metadatos de Admin: el
  cliente no puede escribirlos, aunque un renombrado siga permitido cuando ya
  existen.

## Migración

**No hay migración.** Es la propiedad que hizo elegir el alias: los
documentos existentes siguen siendo válidos tal cual. Un `linkedUid` nulo
—el estado de todo lo escrito hasta hoy— se comporta exactamente como antes.

## Qué se conserva

Gastos, balances, pagos, actividad e historial: intactos. Comparando el
agregado antes y después de vincular se conservan **actores, importes,
deudor, acreedor, pid y `settlementSync`**.

**Matiz importante, antes lo afirmé de más**: no es cierto que el conjunto de
documentos sea siempre idéntico. Entre dos manuales sin lectores, la
obligación no se publicaba (`readers.length === 0`); al vincular a uno,
**aparece** un `economicEntry` que antes no existía. Y con C2, cuando deudor
y acreedor resultan ser la misma persona, un documento **desaparece**. Lo que
se garantiza es que ningún importe, actor ni reparto cambia — no que la
materialización proyectada sea la misma.

## Pruebas

- `recompute.test.ts` (4): el actor no cambia · la persona pasa a ser lectora
  · balances e importes no se mueven · entre dos manuales, vincular a uno ya
  publica la deuda.
- `rules.test.mjs`, bloque «vinculación de identidad» (11): casi todas
  negativas — suplantación sin aprobación, pedir en nombre de otro,
  autoaprobarse, escribir el vínculo sin solicitud, revincular, desvincular,
  solicitar sobre uno ya vinculado, enumerar, borrar el rastro.

## Bandeja global del anfitrión (M4)

Un indicador en Inicio con el total de solicitudes pendientes de **todos** sus
grupos, agrupadas por espacio y con acceso directo. Antes había que entrar
grupo por grupo para descubrirlas.

Se apoya en `spaceOwnerUid` denormalizado en la solicitud, pero lo escribe
exclusivamente el callable `requestManualLink`: deriva el propietario actual
del espacio dentro de su transacción. Así, una transferencia de propiedad no
puede dejar una nueva solicitud apuntando al anfitrión anterior. Índice
compuesto `(spaceOwnerUid, status)`.

## Vocabulario, para no confundir capas

| Término | Qué es |
|---|---|
| **Actor histórico** | `manual:{manualId}` o un UID. Es lo escrito en los documentos y **nunca cambia**. |
| **Identidad efectiva** | A quién corresponde ese actor hoy, aplicando alias. Solo se usa para decidir. |
| **Obligación calculada** | Lo que el motor deriva del reparto. |
| **Documento materializado** | El `economicEntry` que llega a escribirse. **Puede aparecer o desaparecer** al vincular. |
| **Audiencia** | `memberUids`: quién puede leerlo. Es lo que amplía la vinculación. |

## Ciclo de vida de la solicitud

```
(nada) --crear--> pending --anfitrión acepta--> accepted   [TERMINAL]
                     |                              `-> linkStatus ausente -> processing -> active | failed
                     |                                                           `-- callable seguro --> processing
                     |--anfitrión rechaza--------> rejected
                     |--el solicitante retira----> rejected
                                                      |
                                                      `--nuevo intento--> pending (attempt+1)
```

- **Una solicitud por `manualId + uid`**, con ID determinista: crear es
  idempotente y reintentar no duplica.
- **`accepted` es terminal de verdad**: no vuelve a `pending` ni a
  `rejected`. Es lo que respalda un vínculo ya escrito.
- **`rejected` no deja a nadie sin salida**: el solicitante puede volver a
  intentarlo subiendo `attempt`. No se reescribe un terminal en silencio —el
  contador es el rastro— y el reintento exige que el manual siga sin vincular
  y que ese UID no tenga ya reserva.
- **Nunca se borra** una solicitud: es la prueba de que hubo decisión.
- **Si el MANUAL se vincula a otro UID** mientras la nuestra está rechazada,
  el reintento queda bloqueado: ya no hay nada que reclamar.
- **Dos anfitriones o dos pestañas a la vez**: Rules evalúa contra el estado
  comprometido, así que la segunda operación ve `linkedUid` no nulo (o la
  reserva ya existente) y falla limpiamente.

## Interfaz

- **Quien lo pide**: en el ticket abierto por enlace, tras identificarse como
  un MANUAL, aparece «Soy yo». La tarjeta muestra después el estado
  (pendiente, rechazada, aprobada/vinculando, activa o fallida). En `failed`
  ofrece **Reintentar**; en `processing` ofrece comprobar de forma segura.
  «Identidad vinculada» solo aparece con
  `manualParticipants.linkStatus == 'active'`.
  La lectura del manual para esta tarjeta es un `get`/watch del documento
  exacto, nunca una lista.
- **El anfitrión**: en el detalle del grupo, sobre las invitaciones, ve
  «Solicitudes de identidad» con quién dice ser quién y dos botones,
  **Aceptar** y **Rechazar**. El texto avisa de lo que implica aceptar: esa
  persona pasará a ver sus gastos y su saldo, y no cambia nada de lo ya
  registrado. Los manuales vinculados muestran su estado real y permiten
  reintentar una propagación fallida o comprobar una que quedó procesando.

Fuera de alcance por decisión del sprint: consolidar en una sola fila los
saldos de alguien que tuviera obligaciones propias *y* heredadas en el mismo
contexto. `resolveActorIdentity` queda escrita para cuando se aborde.
