# P5 — Relaciones económicas y balances consolidados

> ADR-030 no cambia este cálculo: los tickets nuevos nacen dentro de una
> relación o grupo y llevan `spaceId`; las entradas históricas sin contexto
> siguen participando en el balance y nunca se reasocian automáticamente.

Estado: implementado. Este documento define el contrato económico global de Salda.
No redefine el reparto de tickets ni introduce una segunda fuente de verdad.

## Fuente de verdad

La verdad económica sigue siendo inmutable y explicable:

1. tickets, pagadores, líneas y asignaciones determinan lo adelantado y consumido;
2. `SplitEngine` (Dart) y su espejo TypeScript calculan cada consumo en céntimos;
3. los settlements históricos y `economicPayments` representan transferencias humanas;
4. solo un pago `confirmed` reduce una deuda;
5. `economicEntries` es una proyección reconstruible, nunca un saldo editable.

`recompute` genera una entrada por ticket y pareja registrada:

```text
economicEntries/{sessionId_accountId_ticketId_pair}
  memberUids: [uidMenor, uidMayor]
  debtorUid, creditorUid, amount, currency
  sessionId, accountId, ticketId, ticketName, ticketDate?, spaceId?
  schemaVersion: 1
```

La identidad relacional siempre es el UID. Los nombres, usernames y snapshots visuales
pueden cambiar sin alterar una obligación. Un participante sin cuenta registrada no se
convierte en UID por similitud de nombre. El owner se resuelve mediante `ownerUid`; otro
participante solo se publica globalmente cuando su reclamación corresponde a un UID con
perfil registrado. Los invitados anónimos permanecen en el balance de la sesión, pero no
se inventa para ellos una relación social permanente.

## Cálculo y redondeo

P5 consume el resultado final de `SplitEngine`, por lo que hereda el contrato P2.2:
unidades físicas primero, residual por unidad al pagador y resto mayor determinista.
Todos los importes son enteros en céntimos (`Money` en Dart, `Cents` en TypeScript).
No existe un segundo redondeo al consolidar: P5 suma enteros ya cuadrados.

Por ticket, cada consumidor registrado distinto del pagador genera una obligación
`consumidor -> pagador`. Varios movimientos del mismo ticket y UID se agregan antes de
materializarse. La suma económica nunca modifica el ticket original.

## Neteo bilateral

`EconomicLedger` agrupa por `(uidA, uidB, currency)` con los UID ordenados. Conserva:

- deuda original A→B;
- deuda original B→A;
- pagos confirmados en cada dirección;
- pagos pendientes en cada dirección.

El saldo firmado es:

```text
A→B original - B→A original - A→B confirmado + B→A confirmado
```

El signo determina deudor y acreedor. El detalle conserva ambos movimientos brutos y
permite llegar a cada ticket. El resultado no depende del orden de lectura. No se netean
monedas distintas y no se reasignan acreedores mediante simplificación multilateral.

## Liquidaciones

Los pagos P5 viven en `economicPayments/{id}` y solo se crean/resuelven mediante
Functions callable:

```text
memberUids, pairId, payerUid, receiverUid
amount, currency, status: pending|confirmed|cancelled
source: user|legacySettlement
createdByUid, idempotencyKey, allocations{economicEntryId: cents}
sessionIds[], stateHistory[], timestamps, schemaVersion: 1
```

Flujo:

1. el deudor marca un pago total o parcial;
2. `createEconomicPayment` verifica cuenta completa, perfiles, pareja, moneda y saldo;
3. la Function reserva el importe pendiente y lo asigna FIFO por id estable a entradas
   de ticket, dentro de una transacción;
4. únicamente el receptor económico puede confirmar o rechazar;
5. únicamente el pagador puede cancelar mientras sigue pendiente;
6. solo la confirmación reduce el saldo.

La clave de idempotencia forma parte del id canónico. Una repetición devuelve el mismo
pago. Los pagos pendientes también reservan saldo, por lo que dos pulsaciones o dos
dispositivos no pueden sobrepagar. Se bloquean auto-pagos, cero, negativos, moneda
inválida, terceros, campos mutables y pagos superiores al saldo disponible.

Las asignaciones congeladas permiten explicar un pago por ticket y calcular la porción
de cada espacio. Cuando se confirma, un trigger recalcula las sesiones afectadas y
congela esa transferencia en su balance histórico; así el flujo P5 y el detalle legacy
no pueden cobrar dos veces la misma deuda.

Los settlements existentes `marked` y `confirmed` se proyectan como pagos legacy. Una
sugerencia `pending` generada por el motor no es prueba de pago y no se duplica en P5.

## Vistas y tiempo real

Flutter consulta con `array-contains` únicamente recursos cuyo `memberUids` incluye al
usuario y calcula localmente, mediante el motor puro:

- resumen global por moneda: debes, te deben y neto;
- relaciones bilaterales abiertas;
- detalle con tickets, espacios y pagos;
- confirmaciones pendientes;
- porción del balance dentro de cada espacio.

Las cifras se actualizan por streams. Archivar un espacio conserva consulta e historial.
Un pago bilateral global puede liquidar deuda originada allí porque no crea ni modifica
tickets del espacio. Expulsar a un miembro, abandonar el espacio o eliminar una amistad
no elimina obligaciones ni pagos históricos.

## Privacidad y permisos

Firestore Rules aplican mínimo privilegio:

- solo una cuenta no anónima, verificada y con perfil completo usa P5;
- una entrada o pago solo puede leerla un UID presente en `memberUids`;
- un tercero y el owner de un espacio sin participación económica no pueden leerla;
- ningún cliente crea, modifica o elimina `economicEntries` o `economicPayments`;
- las Functions derivan el actor de Auth, nunca de un UID declarado por el cliente;
- el propietario del espacio no recibe privilegios económicos especiales.

La explicación abre el ticket original bajo sus reglas existentes. P5 no amplía el
permiso de lectura del ticket: si una persona pierde acceso conserva su propia relación
económica y sus metadatos mínimos derivados, pero no obtiene acceso nuevo al contenido
privado completo de terceros.

## Concurrencia, reparación y compatibilidad

Las entradas tienen ids deterministas y `recompute` compara la proyección antes de
escribir. Las Functions usan transacciones y operaciones idempotentes. Reintentos,
confirmaciones duplicadas y carreras confirmar/cancelar convergen en un solo estado.
Una edición concurrente del ticket vuelve a ejecutar `recompute`; la proyección siempre
puede reconstruirse desde el ticket y los eventos de pago.

Compatibilidad:

- tickets históricos y tickets sin `spaceId` siguen funcionando;
- el algoritmo histórico de reparto no se reinterpreta; se consume su resultado actual
  versionado, incluidos los modelos P2.1/P2.2;
- settlements existentes se leen sin migración destructiva;
- amistades, usernames y pertenencia actual a espacios no son claves económicas;
- miembros históricos siguen apareciendo mientras existan movimientos;
- `schemaVersion` permite evolucionar ambas proyecciones y reconstruirlas.
- Al abrir Economía por primera vez, `rebuildMyEconomicRelations` materializa de
  forma perezosa las sesiones históricas del usuario y deja una marca de versión
  en `users/{uid}`. La operación es autoritativa, idempotente y está limitada a
  200 sesiones por tipo de acceso para mantener el techo de coste; superar ese
  límite exige una reconstrucción administrativa explícita.

## Permisos y liquidación por obligación (ADR-038)

Estado: implementado. Corrige tres incoherencias reales observadas en dispositivo
y no introduce una segunda arquitectura: reutiliza `economicEntries`,
`economicPayments` y su campo `allocations`.

### Quién confirma un cobro

**El receptor del dinero, y nadie más.** Ser propietario o administrador de un
espacio NO da acceso al saldo de una cuenta ajena; si lo diera, el balance de una
persona registrada dependería de la buena fe de otra.

La única excepción es la que el producto necesita para cerrar: un participante
MANUAL (ADR-033) no tiene cuenta ni dispositivo, así que un cobro dirigido a él
no podría confirmarse jamás. Entonces —y solo entonces— lo confirma el
propietario o un administrador del espacio que custodia esa identidad.

El predicado vive en un único sitio, `economicActingRole`
(`packages/domain/lib/src/identity/economic_authority.dart` y su espejo TS), y lo
consumen la interfaz, las Functions y —en su forma de lectura— las Rules:

| Acreedor | Quién puede confirmar |
|---|---|
| Cuenta | **Solo** esa cuenta |
| `manual:{id}` sin vincular | Propietario o administrador del espacio |
| `manual:{id}` **vinculado** (ADR-037) | **Solo** la cuenta vinculada |

La representación es temporal por construcción: vincular termina con ella sin
revocar nada, porque nunca fue un permiso concedido sino la ausencia de alguien
capaz de ejercerlo.

**Rol de administrador**: `spaces/{id}/members/{uid}.role: 'admin'|'member'`
(ausente = `member`). El propietario único sigue siendo `ownerUid` —la
transferencia sigue siendo la escritura atómica de UN documento—; `role` es la
única delegación, solo la concede el propietario, nadie nace administrador y un
INVITADO no puede serlo (no tiene cuenta con la que administrar).

**Lectura**: una obligación con parte manual la lee también quien administra su
espacio. La regla es VIVA (se evalúa contra la membresía del momento), así que
retirar a un administrador cierra el acceso al instante y no hay proyección que
reconstruir. Para que la consulta sea demostrable documento a documento,
`recompute` escribe `hasManualParty` —propiedad derivada e inmutable de la
obligación— y el cliente filtra por ella: sin ese filtro la consulta arrastraría
deudas entre dos cuentas y Firestore la deniega entera. Esa denegación **es** la
garantía de que un administrador nunca ve una deuda cuenta↔cuenta ajena.

### Una liquidación por obligación, nunca por el agregado

`settleEconomicEntries` recibe obligaciones concretas y escribe **un
`economicPayment` por cada una**, con `allocations: {entryId: importe}` y
`economicEntryId`. Un saldo agregado —«Test te debe 14,73 €»— es un RESUMEN de
sus deudas (Familycash 6,75 + t familycash 7,98) y jamás se convierte en una
obligación nueva: confirmar las dos a la vez es comodidad de la interfaz y
produce dos liquidaciones, cada una con su ticket.

- **El importe por defecto es el pendiente de esa deuda**: el camino normal no
  pide teclear nada. El **pago parcial** es la excepción, se pide desde el menú
  de esa obligación y pertenece a ella, no al saldo global.
- **Dos techos, ambos obligatorios**: lo que queda vivo en la obligación
  (importe − asignado por pagos no cancelados) y lo que queda vivo en el saldo
  bilateral. El segundo es lo que impide cobrar dos veces una deuda ya saldada
  por una liquidación de sesión, que no deja asignación por ticket.
- **Idempotencia** por id determinista `settle_{entryId}_{idempotencyKey}`.
- Si el actor obra por el lado ACREEDOR, la liquidación nace `confirmed`; si obra
  por el lado deudor, nace `pending` (una declaración).

### «Ya he pagado» es un aviso, no una precondición

El deudor puede declarar que pagó y el receptor recibe ese aviso, pero **no hace
falta para cobrar**: el receptor confirma directamente una deuda pendiente
aunque el deudor no haya abierto Salda nunca (puede haber pagado en mano). Vale
igual en el flujo de sesión: `pending → confirmed` ya lo autorizaba `isReceiver`,
y ahora la app y la web de invitados lo ofrecen.

Por lo mismo, **«Pagos por confirmar» son DECLARACIONES**, no todas las deudas
pendientes: una deuda que nadie ha declarado no aparece ahí, pero se cobra desde
su balance.

### Las mismas acciones en todas las superficies

Economía global, la portada de una relación o de un grupo, «Balance con X» y el
detalle de una relación llegan al MISMO sistema de confirmación; el saldo es el
punto de entrada a las deudas que lo explican. Todas leen del mismo ledger por
streams, así que una confirmación hecha en cualquiera de ellas se refleja en las
demás y en otros clientes conectados.

Un pago legado (proyección de una liquidación de sesión) no lo resuelve la
callable de P5 por diseño: la app escribe en su `settlements/{id}`, que es donde
vive. Antes Economía ofrecía el botón igualmente y la acción moría con un error.

**Terminología única** para la misma operación: «Confirmar recepción» (receptor)
y «Ya he pagado» (pagador), en la app y en la web de invitados.

### Fuera de alcance

Que un administrador edite tickets/gastos creados por otros. Un ticket vive en
`sessions/{sid}` y solo lo edita el dueño de la sesión; los miembros del espacio
ven únicamente su RESUMEN. Cambiarlo toca la frontera espacio↔sesión y la
privacidad de líneas y foto: es un subsistema de autoridad distinto y se decidirá
aparte.

## Límites de P5

No incluye pagos bancarios reales, conversión de divisas, presupuestos, suscripciones,
gastos recurrentes, chat, comentarios, feed general ni simplificación multilateral del
balance global. El `BalanceEngine` histórico puede sugerir liquidaciones internas de
una sesión, pero P5 no presenta esas sugerencias como un cambio opaco de acreedor.
