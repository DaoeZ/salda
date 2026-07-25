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

## Participantes manuales (ADR-033)

Un contexto puede incluir personas **sin cuenta**: el anfitrión escribe solo
su nombre y participan en gastos y balances exactamente igual que un miembro
registrado. No tienen UID, no instalan nada, no leen ni confirman nada.

```text
spaces/{spaceId}/manualParticipants/{manualId}
  manualId · displayName (1..40) · linkedUid: null (reservado)
  createdByUid · createdAt · updatedAt · schemaVersion: 1
sessions/*/participants/{pid}.manualId?   // identidad del participante
```

**Identidad económica**: toda obligación de P5 se expresa entre dos ACTORES.
Un actor es el UID de una cuenta, o `manual:{manualId}` para quien no la
tiene. Los UID de Firebase son alfanuméricos y nunca contienen `:`, así que
el prefijo no colisiona y **los documentos económicos anteriores siguen
siendo válidos sin migración**: un valor sin prefijo es, por definición, una
cuenta. Un participante es de cuenta **o** manual, nunca ambos, y una cuenta
jamás se degrada a manual.

`memberUids` sigue conteniendo solo UID reales, porque es lo que Rules y las
queries `array-contains` usan para autorizar: una obligación entre cuenta y
manual tiene un único lector, y entre dos manuales no se publica en la
economía global (esa deuda vive en el balance de su sesión, que no necesita
lectores). Los pagos P5 siguen exigiendo dos cuentas; saldar con una persona
sin cuenta se hace por el flujo de liquidación de la sesión, que ya admite
participantes sin dispositivo.

El identificador es opaco y estable, **nunca el nombre**: renombrar no toca
ninguna obligación derivada, y retirar a la persona del contexto no borra su
historial (las entradas conservan su actor).

### Vinculación con una cuenta: DECISIÓN PENDIENTE (Sprint 6)

**La vinculación queda expresamente fuera del alcance de este sprint.** Aquí
solo se documenta la restricción que hay que respetar y lo que queda por
decidir; nada de esto está implementado. **Se abordará en el Sprint 6
(vinculación de identidad)**, que deberá cubrir los dos casos con el mismo
mecanismo: manual↔cuenta y manual↔invitado (ver la sección de invitados).

Restricción firme: el actor `manual:{manualId}` **debe permanecer estable**.
Es la clave con la que están escritas las obligaciones ya derivadas, así que
cualquier solución que lo altere sin más pierde o corrompe el historial
económico.

La futura fase deberá **elegir explícitamente** entre dos alternativas, que
no son equivalentes:

1. **Migración de referencias** — reescribir en cada documento histórico el
   actor manual por el UID. Deja los datos homogéneos, pero es una escritura
   masiva, no atómica sobre colecciones distintas, difícil de revertir y que
   invalida los ids deterministas ya calculados a partir del actor.
2. **Resolución mediante alias** — conservar intacto el actor histórico y
   mantener una tabla de equivalencia `manual:{manualId} → uid` que se
   aplique al leer y al consolidar. Los documentos no se tocan, la operación
   es reversible y el historial queda demostrable.

**Opción preferente: la resolución mediante alias**, salvo que aparezca
evidencia técnica que justifique lo contrario (por ejemplo, un coste de
lectura o una complejidad de consulta inasumibles al resolver el alias en
cada consolidación).

`linkedUid` **por sí solo NO resuelve la vinculación**: es únicamente un
marcador de intención en la identidad manual. No reescribe obligaciones, no
las consolida al leer y no impide duplicidades; sin la decisión anterior y
su mecanismo, un `linkedUid` relleno no cambiaría ni un balance.

**Duplicidad a evitar** (mismo humano contando dos veces en un contexto,
como actor manual y como UID —sea de una cuenta o de un INVITADO, que
también tiene UID propio—): la fase de vinculación deberá garantizar que un
contexto no pueda tener simultáneamente ambas identidades de la misma
persona activas. El mecanismo tendrá que cubrir al menos:

- vinculación e incorporación como miembro resueltas de forma **atómica**,
  de modo que no exista un instante con las dos identidades participables;
- una vez vinculada, la identidad manual deja de ser **seleccionable** en
  repartos nuevos: quien participa es la cuenta;
- validación en Rules de que un participante de sesión declare exactamente
  una identidad (`manualId` **o** cuenta, nunca ambas — invariante que este
  sprint ya aplica);
- consolidación de las dos vertientes en el balance bilateral **al leer**
  (con la opción de alias), para que el saldo no se presente partido;
- decisión sobre qué ocurre si la cuenta vinculada ya tenía obligaciones
  propias en ese mismo contexto (fusión de saldos frente a coexistencia
  histórica).

## Invitados (GUEST, ADR-034)

Tercer tipo de participante, entre la cuenta y el manual: **usa la app** pero
**no crea cuenta**.

```text
guestIdentities/{uid}
  uid · displayName (1..40) · createdAt · updatedAt · schemaVersion: 1
spaces/{spaceId}/members/{uid}
  kind: account|guest · displayName?   // snapshot SOLO para invitados
spaces/{spaceId}.guestsCanCreateExpenses: bool   // política del anfitrión
```

**Persistencia**: su identidad es **Firebase Anonymous Auth**. El SDK guarda
esa sesión en el dispositivo, así que **se mantiene entre reinicios y cierres
de la app**: el UID no cambia y su historial económico tampoco.
`guestIdentities/{uid}` solo añade el nombre visible que él elige.

**NO es un perfil público**: **no tiene username** y **no puede aparecer en
búsquedas** (Rules deniega `list` sobre `guestIdentities`). Solo se lee
conociendo el UID (el anfitrión al invitarlo, o los miembros del contexto
para pintar su nombre). Por eso su nombre viaja también como snapshot en la
membresía: no hay perfil del que leerlo en vivo.

**El nombre visible es SOLO un atributo de presentación.** No es identidad
ni clave relacional: cambiarlo **no afecta a la identidad económica** —el UID
sigue siendo el mismo— ni a obligaciones, balances, pagos o historial ya
existentes. Los snapshots congelados en membresías anteriores conservan el
nombre de entonces, exactamente como ocurre con cualquier otro rótulo
histórico.

**Puede**: participar en relaciones y grupos, aparecer en balances y
liquidaciones, ver la cronología de lo que le afecta, recibir y aceptar
invitaciones, y renombrarse (sin perder identidad ni historial).

**No puede**: crear relaciones o grupos, invitar, administrar miembros,
transferir, archivar, tener perfil público ni amistades. Rules lo separa con
dos predicados: `canParticipate()` (cuenta **o** invitado) para participar, y
`canUseSocial()` (solo cuenta) para todo lo que crea o gobierna el contexto.

**Gastos bajo permiso del anfitrión**: un invitado solo origina gasto en un
contexto con `guestsCanCreateExpenses: true`, que únicamente fija su
propietario. Ausente equivale a `false` (valor conservador). Un miembro con
cuenta nunca depende de esa bandera.

**Identidad económica**: un invitado **participa económicamente igual que una
cuenta porque dispone de UID propio**. Para ADR-033 es un actor de cuenta
(`uid` sin prefijo, sin `manual:`), así que entra en obligaciones, neteo
bilateral y liquidaciones de P5 sin ningún cambio ni caso especial.

### Incorporación: FUERA del alcance de este sprint

La incorporación cómoda de invitados **mediante enlaces queda expresamente
fuera del alcance de este sprint**. Hoy el anfitrión solo puede invitar a un
invitado si conoce su UID, porque un invitado no es buscable por diseño.

**El flujo de invitación actual NO es el definitivo**: es el mínimo que
permite validar el modelo, no una decisión de producto cerrada. **El Sprint 4
(Enlaces) resolverá la incorporación**, y al hacerlo deberá decidir el canal
por el que el anfitrión alcanza a un invitado sin exponer identidades ni
convertir al invitado en buscable.

### Consolidación con participantes MANUAL: Sprint 6

Hoy nada impide que una misma persona esté en un contexto **a la vez** como
participante MANUAL (creado por el anfitrión) y como INVITADO (con su propio
UID): serían dos actores económicos distintos y su saldo aparecería partido.
**Esa consolidación se resolverá en el Sprint 6 (vinculación de identidad)**,
junto con la vinculación manual↔cuenta descrita arriba; los dos casos
comparten exactamente el mismo problema y deben resolverse con el mismo
mecanismo. Este sprint no introduce ninguna decisión al respecto y **no
prejuzga** la elección entre migración de referencias y resolución mediante
alias.

Fuera de alcance de este sprint: enlaces, deep links, vinculación con cuentas
y reclamación de participantes manuales.

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
