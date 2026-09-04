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
segunda persona decide la invitación.

**Consecuencia que conviene tener presente (BUG-2):** como el identificador se
deriva de AMBOS UID, hay que conocer el de la otra persona **antes** de crear
la relación. Eso es lo que hace que A→B y B→A sean el mismo contexto, pero
también implica que la segunda plaza **solo** puede completarse con una cuenta
localizable:

| Vía | ¿Válida en una relación? | Motivo |
|---|---|---|
| Cuenta existente | **Sí** | La búsqueda por username o nombre devuelve su UID |
| Participante MANUAL | **Sí** (`schemaVersion: 3`) | Segunda plaza sin UID; el id del espacio se genera |
| Enlace de incorporación | **No** | El ID canónico tendría que calcularse sin saber quién aceptará |
| GUEST | Solo si se conoce su UID | Tiene UID propio, pero por diseño no es buscable (ADR-034) |

### Relación con alguien SIN cuenta (`schemaVersion: 3`)

El caso real: quiero compartir gastos con Pablo, que no usa la app, y que eso
sea **una relación de dos personas**, no un grupo. Exigir que el id derivara
de dos UID lo hacía imposible, así que el esquema se desdobla:

```text
spaces/{idGenerado}
  kind: relationship · schemaVersion: 3
  relationshipUids: [uidDelPropietario]      ← una sola cuenta
  relationshipManualId: {manualId}           ← la segunda identidad
  manualParticipants/{manualId}              ← creado en el MISMO batch
```

Sigue habiendo **exactamente dos identidades económicas**: el UID del
propietario y el actor `manual:{manualId}`, que participa en repartos,
balances, pagos y liquidaciones igual que una cuenta (ADR-033). Rules impide
un segundo manual, una tercera cuenta, retirar el manual de la segunda plaza
y convertir la relación en grupo. `relationshipManualId` es además
**inmutable**: reapuntarlo a otro manual cambiaría de persona la deuda ya
registrada sin tocar el histórico.

**Las relaciones entre dos cuentas no cambian**: siguen en `schemaVersion: 2`
con el id canónico `relationship_{uidMenor}~{uidMayor}`, que es lo que impide
duplicados. Ambos esquemas conviven; no hay migración de datos ni de economía.

Cuando Pablo se registre, la **vinculación del Sprint 6** (ADR-037) añade su
UID en `linkedUid` sin tocar el actor histórico ni reescribir nada.

**Un contexto está operativo por sus IDENTIDADES ECONÓMICAS, no por sus
cuentas.** Una relación v3 tiene un solo miembro y aun así está completa: el
manual ocupa la segunda plaza. El detalle cuenta `miembros + manuales`, igual
que ya hacía la hoja de reparto de un ticket.

### El título de una relación se resuelve al leer, no se guarda

Un grupo tiene nombre propio y elegido: «Piso», «Viaje a Madrid». Una
relación **no tiene nombre**. Lo que cada persona espera ver es *la otra*:
Edgar ve «Pedro» y Pedro ve «Edgar», sobre el MISMO documento. Eso no es un
dato que pueda persistirse, así que se resuelve en tiempo de lectura.

La regla, en `features/spaces/domain/space_title.dart` (Dart puro):

1. obtener las dos identidades económicas efectivas;
2. excluir la de quien mira;
3. enseñar el mejor nombre de la otra — `displayName`, si no `@username`
   (con `@` solo cuando existe de verdad), si no «Persona sin nombre».

En una **v2** las identidades son `relationshipUids`; el orden lexicográfico
fija el id canónico pero **no** decide el título. En una **v3** el propietario
ve el nombre del MANUAL, y quien se vincula a ese manual (ADR-037) ES esa
identidad, así que para él la otra parte es el propietario: contarlos por
separado le enseñaría su propio nombre. La vinculación no cambia el histórico
ni el actor `manual:{id}`, solo quién puede leer.

Nunca se muestran `relationshipManualId`, un UID ni `manual:{id}`. Cuando la
relación no se puede resolver —alguien ajeno, una pareja con UID repetido, un
espacio con más o menos identidades de las esperadas— se cae al nombre
persistido y se registra el MOTIVO por consola, sin identificadores.

**Persistencia:** el campo `name` de una relación queda como **dato legado y
relleno**, nunca como fuente de lo que se pinta. No hay migración: los
nombres históricos se conservan tal cual. Rules sigue exigiendo 2..40
caracteres, así que al crear una v2 se guarda el nombre de la otra persona
—sin concatenar— en vez de «Edgar · Pedro», que no era correcto para ninguno
de los dos. Como el título es derivado, el menú «Editar nombre» solo aparece
en grupos; en una v3 se renombra al MANUAL desde su propia ficha.

Todas las superficies leen del mismo sitio (`spaceTitleProvider`): Inicio,
lista de espacios, cabecera del detalle, chat, selector de contexto, menú de
vinculación de un ticket, iniciales del avatar y frases de actividad. Una
invitación es el único caso que no puede resolver contra el espacio —quien la
recibe aún no puede leerlo—, así que usa el `fromUid`: en una relación, quien
invita es por definición la otra persona.

**Añadir personas a mano es una acción de GRUPOS.** En una relación las dos
identidades ya están decididas: en v2 la segunda plaza la reserva la
invitación, y en v3 la ocupa su manual. Por eso el detalle de una relación no
ofrece «añadir» ni «quitar» manuales —solo renombrar el suyo—, y el
repositorio rechaza la petición antes de llegar al servidor. Rules lo deniega
igualmente: es la autoridad, la UI solo evita ofrecer un botón que únicamente
podía terminar en error. Una relación v2 pendiente, que no tiene manuales ni
puede tenerlos, no pinta la sección en absoluto. Y mientras el espacio se
carga tampoco se pinta: sin saber su tipo, la pantalla no enseña acciones que
después retiraría.

Probado extremo a extremo contra el emulador
(`relationshipManual.it.test.ts`): se reparte, los balances salen
+2000/−2000, se genera la liquidación del manual hacia la cuenta, y al
vincular después se conserva el mismo documento, el mismo importe y el actor
`manual:{id}` — lo único que cambia es que Pablo pasa a poder leerlo. Rules impide otro ID, un tercer miembro o
una invitación fuera de la pareja.

### Cuántas personas hacen falta para repartir (BUG-6)

Repartir un gasto exige **dos identidades económicas**, y una identidad es una
persona: una cuenta, un INVITADO o un participante MANUAL. No es lo mismo que
una membresía, que es solo la de quien tiene UID.

El criterio vive en un único sitio, `effectiveEconomicIdentities`
(packages/domain, junto a los actores de ADR-033), y lo consumen el detalle
del espacio, la hoja de reparto y la guarda del controlador de creación.
Colapsa con `resolveActorIdentity` —el mismo primitivo con el que recompute
consolida saldos—, así que un MANUAL vinculado y su cuenta cuentan UNA vez;
descarta identificadores vacíos o con `:`; y no mira las invitaciones, porque
reservar una plaza no incorpora a nadie.

- **Relación**: exactamente dos. Una v2 con la invitación sin aceptar tiene
  una sola identidad incorporada y no opera; una v3 con MANUAL sí.
- **Grupo**: dos o más. **Antes exigía tres**, que es cuántas personas
  justifican crear un grupo en vez de una relación (ADR-030), no cuántas
  hacen falta para partir una cuenta. Esa confusión bloqueaba el caso real
  —compartir gastos con alguien que no tiene la app— y obligaba a pedirle
  que se registrara. Un grupo también encoge: que se vaya el tercero no
  invalida los gastos entre los dos que quedan.

El backend nunca tuvo esa restricción: no hay ninguna comprobación de número
de participantes en Rules ni en Functions, y el ciclo completo de un grupo
con una cuenta y un MANUAL —reparto, balances, liquidación y obligación con
actor `manual:{id}`— está probado contra el emulador en
`groupManual.it.test.ts`, incluido el MANUAL como pagador.

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
  reversible. P5 permite consultar y liquidar una deuda ya originada porque el
  pago es bilateral y no muta el espacio; no se pueden crear tickets nuevos
  mientras el espacio permanezca archivado.
  **Archivar NO saca al espacio de la economía activa**: sus obligaciones siguen
  contando en los balances (no hay una sola referencia a `archived` en
  `economic_repository.dart`, `recompute.ts` ni `economicPayments.ts`).
- **Eliminar** — **NO IMPLEMENTADO todavía**. Hasta el 2026-09-04 la
  documentación decía que «archivar es la única baja» (ADR-028). Esa afirmación
  queda **superada** por el contrato de **A4**, que distingue expresamente
  **Archivado ≠ Eliminado** y es una decisión de producto **cerrada**: eliminar
  será un estado propio, solo del owner, posible incluso con saldos pendientes
  bajo confirmación reforzada, que congela la economía activa, aparece en
  «Eliminados», avisa individualmente a cada miembro, es restaurable durante 7
  días y después queda como historial readonly que no afecta a balances activos.
  Hoy `SpaceStatus` solo tiene `active|archived` y `spaces` **no tiene
  `allow delete`** en Rules. Contrato completo en `docs/BACKLOG_SALDA.md` § A4.
- **Administradores (ADR-038)**: `members/{uid}.role: 'admin'|'member'`, ausente
  = miembro. Apareció con una necesidad real —un cobro dirigido a alguien SIN
  cuenta no lo podía confirmar nadie más que el propietario—, no por simetría
  con otros productos. El propietario sigue siendo ÚNICO y sigue viviendo en
  `ownerUid`: `role` es una delegación, no un segundo dueño, así que la
  transferencia sigue siendo la escritura atómica de UN documento. Solo el
  propietario lo concede o lo retira, nadie nace administrador, y un INVITADO no
  puede serlo (ADR-034: no tiene cuenta con la que administrar). Ser
  administrador **no** da acceso al saldo de una cuenta ajena; el detalle está
  en `docs/RELACIONES_ECONOMICAS.md`.

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

**Puede**: participar en relaciones y grupos, **verlos en su inicio y entrar
en ellos** (Sprint 4: hasta entonces podía ser miembro en datos pero no tenía
pantalla desde la que llegar), aparecer en balances y liquidaciones, ver la
cronología de lo que le afecta, recibir y aceptar invitaciones, entrar por
enlace, ver a los participantes MANUAL con los que reparte, y renombrarse
(sin perder identidad ni historial).

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

### Incorporación: RESUELTA por los enlaces de grupo (Sprint 4)

Antes, el anfitrión solo podía invitar a un invitado si conocía su UID,
porque un invitado no es buscable por diseño. El **enlace de grupo** (abajo)
es el canal que resuelve esa incorporación: el anfitrión reparte un enlace en
vez de buscar a una persona, así que **nadie tiene que volverse buscable**.

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

Fuera de alcance: vinculación con cuentas y reclamación de participantes
manuales (Sprint 6).

## Enlaces de grupo (Sprint 4, ADR-035)

Un **GRUPO** puede tener un enlace de incorporación. Compartirlo es la forma
normal de sumar gente: sustituye a buscar personas una a una y es lo único
que permite alcanzar a un invitado, que por diseño no es buscable.

```text
spaceLinks/{token}
  spaceId · spaceName (denormalizado solo para pintar) · createdByUid
  status: active|revoked · expiresAt? · createdAt · updatedAt
  schemaVersion: 1
spaces/{spaceId}/joinGrants/{uid}
  uid · token · createdAt          // prueba de conocimiento, SOLO ESCRITURA
```

**El identificador del documento ES el secreto**: 128 bits generados con
`ShareCode`, la misma primitiva del enlace de invitados de sesión. Conocer el
token es la autorización (ADR-012); adivinarlo, inviable. De ahí las dos
mitades de la política en Rules: `get` abierto a cualquier sesión que acierte
el token —para que quien recibe el enlace vea a qué grupo entra antes de ser
miembro— y `list` reservado al propietario ACTUAL del grupo, para que un
enlace **nunca sea enumerable**.

**El enlace no contiene identidades.** Solo dice a qué grupo abre y cómo se
llama: compartirlo no revela quién está dentro, no expone UID y no convierte
a nadie en buscable — la condición que ADR-034 exigía comprobar al cerrar
este sprint.

**Canje en un único batch**: el que entra escribe la prueba de conocimiento
(`joinGrants/{uid}` con el token) y su membresía a la vez, y Rules valida la
segunda contra la primera con `existsAfter`, exactamente como ya hacía
aceptar una invitación. La prueba es un documento de **solo escritura**: no
la lee nadie, ni siquiera el propietario. Si el token viviera en la
membresía, cualquier miembro podría leerlo y reenviar el enlace, saltándose
la regla de que **solo el propietario incorpora gente**.

La membresía **revalida el enlace en cada canje**, no solo al escribir la
prueba: revocar cierra la puerta de inmediato aunque alguien hubiera guardado
el token o quedara una prueba antigua.

Quién puede entrar por enlace:

- **Cuenta** (verificada y con perfil): entra y se lee su nombre en vivo.
- **Invitado** (ADR-034): entra igual, congelando su nombre visible en la
  membresía. Es su vía natural de incorporación.
- **Manual** (ADR-033): no aplica — no tiene dispositivo. Los sigue creando
  el propietario dentro del grupo, sin cambios.

Límites deliberados:

- **Solo grupos.** Una relación reserva una pareja canónica e inmutable de
  UID y Rules le impide un tercer miembro: un enlace no tendría a quién
  admitir.
- **Solo espacios activos**: uno archivado no admite ni crear ni canjear.
- **Crear, rotar y revocar es exclusivo del propietario.** Rotar revoca el
  anterior y emite un token nuevo; el viejo queda demostrablemente muerto en
  vez de reciclarse.
- **Expulsar no basta si el enlace sigue vivo**: quien conserve el enlace
  puede volver a entrar, igual que en cualquier grupo de mensajería. Para
  cerrar de verdad hay que rotar o revocar.
- **Enlaces de TICKET y vinculación de identidad siguen fuera** (Sprint 5 y
  Sprint 6).

### Caducidad (opcional)

Un enlace es un secreto portador, así que puede acotársele la vida:
`expiresAt` limita el daño si acaba donde no debe. **Ausente = sin
caducidad**, el valor por defecto y el comportamiento original (el
propietario siempre puede revocar). La app ofrece sin caducidad, 1, 7 o 30
días al crearlo.

- **No puede nacer caducado**: enmascararía un reloj mal puesto en cliente.
- **Es inmutable**: alargarla resucitaría un enlace que ya circula. Para
  cambiarla se rota, que emite un token nuevo y mata el anterior.
- **Caducado ≠ revocado**, pero cierran igual: `spaceLinkOpensGroup` mira
  ambas cosas en CADA canje, no solo al crear la prueba.

### Flujo de entrada

**A quien ya tiene identidad no se le pregunta quién es.** El enlace entra
solo y aterriza en el grupo: sin pantalla intermedia ni botón de confirmar.
El selector de identidad se reserva a los participantes MANUAL de los enlaces
de TICKET (Sprint 5), donde sí hace falta elegir a qué participante sin
cuenta corresponde uno.

| Quién abre el enlace | Qué pasa |
|---|---|
| **Cuenta** verificada | Entra automáticamente y aterriza en el grupo |
| **Invitado** con nombre elegido | Igual: su identidad persiste en el dispositivo (sesión anónima), no se le pregunta nada |
| **Invitado sin nombre** | Solo se le pide el nombre visible —lo único que la app no puede saber por él— y de ahí entra |
| **Sin sesión** | Tres salidas: continuar como invitado, entrar con su cuenta, o crear una |
| **Cuenta sin verificar** | Se le pide verificar; el enlace queda recordado y al volver entra |

El enlace pendiente vive en `pendingGroupLinkProvider` y lo consume el
router: identificarse **nunca pierde el enlace**, que era justo donde el flujo
se rompía (al autenticarse, el router mandaba a `/home`). Por lo mismo, la
pantalla del enlace se queda en pie para cualquier sesión, incluida una
pendiente de verificar el correo.

Volver a pulsar un enlace del que ya se es miembro **no da error**: lleva al
grupo, igual que la primera vez.

**Rutas**: `/g/{token}` es la CANÓNICA —idéntica al camino de la URL
compartida, para que el deep link resuelva sin traducciones— y `/join`
permite pegar el enlace a mano. Aceptar la URL completa pegada desde WhatsApp
es el caso normal, así que el token se normaliza a partir de ella.

**Android**: `AndroidManifest.xml` declara un intent-filter con `autoVerify`
para `https://{salda-dev|salda-prod}.web.app/g/`.

**Digital Asset Links**: `apps/guest_web/public/.well-known/assetlinks.json`
se despliega con el Hosting y declara el paquete `dev.salda.salda_mobile`
junto al SHA-256 del certificado. Dos ajustes de `firebase.json` lo hacen
posible y conviene no deshacerlos:

- `ignore` ya NO incluye `**/.*`: ese patrón excluía del despliegue cualquier
  ruta con punto, y `.well-known` es exactamente eso — el archivo se subía
  «correctamente» sin llegar nunca al servidor.
- `appAssociation: "NONE"` desactiva la generación automática de Hosting,
  para que el archivo servido sea el del repositorio y no uno inventado.

El archivo se sirve como fichero estático, así que gana a la reescritura
`**` → `index.html` sin necesidad de excepción alguna.

**Certificado**: hoy `buildTypes.release` sigue firmando con
`signingConfigs.debug` (el TODO de la plantilla de Flutter), así que debug,
desarrollo y release comparten certificado y basta un fingerprint. **Cuando
exista una clave de release propia habrá que añadir su SHA-256** —y el de
Play App Signing si se publica en Play— o los App Links dejarán de
verificarse en esas variantes.

**Pendiente de Hosting**: servir `/g/{token}` como página de aterrizaje para
quien NO tenga la app instalada (hoy responde el SPA de invitados con
`OpenInAppView`, que solo dice «ábrelo en la app»).

**⚠️ Tensión abierta con el contrato de A5 (2026-09-04, auditoría).** El
mecanismo descrito arriba —un token opaco por GRUPO, reutilizable, revocable y
no enumerable— **ya cumple** la parte de A5 que pide «un único enlace del
contexto, no uno por persona», y resuelve la identidad por UID cuando quien lo
abre tiene cuenta. Faltan dos cosas que este ADR **no** cubre y que A5 sí exige:

1. **La mitad web.** «Sin app / sin cuenta → web» está al 0% mientras `/g/` siga
   siendo una invitación a instalar la app.
2. **Identidades MANUAL.** A5 quiere que la web ofrezca elegir «Soy Tete» entre
   las identidades guest/manual disponibles. ADR-035 lo excluye expresamente
   («Manual: no aplica — no tiene dispositivo») y ADR-036 **rev. 2** retiró ese
   mismo selector de los enlaces de ticket **por una vulnerabilidad real**: un
   enlace emitido para una persona servía para quedarse con la identidad
   económica de otra y, vía ADR-037, pedir la vinculación de su historial.

Ninguno de los dos ADR queda superado. A5 necesita un ADR propio que explique
cómo ofrece el selector sin reabrir la suplantación. Ver
`docs/BACKLOG_SALDA.md` § A5.

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
- Salir: acto propio, nunca el owner (antes transfiere o archiva).
- Expulsar (A11d, solo GRUPOS): el propietario a miembros y administradores;
  un administrador solo a miembros normales; nunca al owner ni a uno mismo.
  Es un batch de tres escrituras y las tres se validan cruzadas: sin
  evidencia del ciclo y bloqueo vigente el borrado se deniega.
- Vincular ticket: dueño de la sesión + miembro del espacio.
- Anónimos y no verificados: sin acceso a nada de lo anterior.

## Expulsión y reentrada (A11d, ADR-039)

Tres documentos, tres responsabilidades que **no** se pueden fusionar:

| Documento | Qué responde | Vida |
|---|---|---|
| `spaces/{id}/removals/{uid}_{joinedAtMillis}` | «esta expulsión ocurrió» | append-only, inmutable |
| `spaces/{id}/entryBlocks/{uid}` | «¿está bloqueado AHORA el enlace?» | nace al expulsar, muere al readmitir |
| `sessions/{sid}/ticketEntitlements/{tid}_{uid}` | «participó económicamente en este ticket» | monotónica, la escribe `recompute` |

La primera está indexada por CICLO de membresía porque P6 la consulta cuando
le llega el evento del borrado, y ese evento puede llegar tarde, reintentado
o cuando la persona ya va por otro ciclo: si el documento fuese mutable,
encontraría el ciclo equivocado y registraría una expulsión real como
abandono voluntario. El razonamiento completo está en ADR-039.

**Reentrada.** Una expulsión cierra el enlace general para esa persona.
Vuelve solo con una invitación posterior al bloqueo —`spaceInvites.createdAt`
está anclado a `request.time` y reenviar lo renueva—, y aceptarla crea la
membresía y levanta el bloqueo en el mismo commit. Vuelve como miembro NUEVO:
`joinedAt` fresco (que es lo que gobierna la privacidad del chat) y sin
`role`, así que un antiguo administrador no recupera nada. Si después sale
por su pie, el enlace vuelve a servirle; si lo vuelven a expulsar, se bloquea
otra vez y nace una evidencia nueva sin tocar la anterior.

**Qué conserva el expulsado.** Sus deudas, sus pagos y sus liquidaciones
—nada de eso dependía nunca de la membresía— y los tickets en los que
participó económicamente: el ticket, sus líneas y su foto. Nada más: ni la
sesión (`shareCode`), ni otros tickets, ni el listado, ni miembros, ni chat,
ni administración. El derecho lleva la cuenta —para alcanzar el ticket con un
GET, sin listar— y los nombres de ESE reparto, porque un `pid` sin nombre no
explica ninguna deuda y el censo de la sesión sería mucho más de lo
necesario. Storage aplica exactamente la misma frontera.

Esos nombres se indexan **por `pid`** (el reparto, línea a línea) y **por
ACTOR económico** cuando el participante es MANUAL (`manual:{id}`). El
segundo índice existe porque la deuda de P5 nombra al actor, nunca a un
`pid`, y el nombre de un manual lo custodia el ESPACIO (ADR-033), que un
ex-miembro ya no puede leer: sin él, su propio saldo pasaba a leerse
«Persona sin nombre». Es el mínimo posible —solo los manuales de los tickets
que ya están en SU economía— y no abre `manualParticipants`: ni la colección
ni un documento suelto. Una cuenta no necesita alias: su nombre vive en el
perfil público, que sigue siendo legible. Sin backfill: los derechos ya
escritos adquieren el alias en el siguiente `recompute` de esa sesión —los
nombres se FUNDEN con los guardados, nunca se sustituyen—; hasta entonces
sigue apareciendo el rótulo controlado de siempre.

Índices: dos `fieldOverrides` de collection group (members.uid,
tickets.spaceId); las queries de invitaciones son de igualdad pura (sin
composites).

## Repartir el consumo de otras personas (A10)

**Misma asignación económica, distinta autoridad.** No hay un segundo sistema
de reparto: se escribe en el modelo por unidades de siempre
(`assignment.units.{unitId}.{pid}`), con la misma operación quirúrgica por par
(unidad, persona). Lo único que cambia es quién puede escribirla.

| Actor | Lo suyo | Lo de otra persona | A un MANUAL |
|---|---|---|---|
| Creador del gasto (dueño de la sesión) | sí | sí | sí |
| Propietario / administrador del **grupo** | sí | sí | sí |
| Miembro normal del grupo | sí | no | no |
| Contraparte de una **relación** | sí | no | no |
| Ajeno o expulsado | no | no | no |

Una asignación hecha por quien tiene autoridad es **económicamente válida al
instante**: la persona beneficiaria no tiene que entrar a confirmarla. Solo
aplica en «cada uno lo suyo» —a partes iguales el motor no mira las líneas— y
nunca con la sesión cerrada.

**Repartir no es editar.** La rama de asignación exige que la escritura toque
únicamente `assignment`: por ahí no entra un nombre, una cantidad, un precio
ni una unidad nueva. Corregir el contenido sigue siendo A11c, con su propia
autoridad y su propia firma.

**Procedencia (`assignment.by`).** Quién asignó qué se guarda por PAR:
`assignment.by.{unitId}.{pid} = uid`. Una firma única por línea no valdría —la
siguiente persona que tocase otra unidad borraría la atribución de la
anterior—. Rules exigen que ese uid sea el de quien escribe, así que nadie
puede atribuir a otro lo que hace él; la firma se retira con su asignación, y
al podar unidades (A11c) se va con ellas. Es obligatoria al asignar a un
tercero y opcional al marcarse uno mismo, porque la web de invitados no la
escribe: **si no hay firma, la asignación es una autoselección**. Esa
convención solo se sostiene porque la rama sin firma exige además que el `pid`
tocado esté reclamado por quien escribe (`claimedBy(pid) == uid`): sin firma y
con el `pid` de otra persona no pasa por ninguna puerta.

**Mientras la asignación vive, su procedencia no se reescribe.** Sobre un par
(unidad, persona) que ya estaba asignado, `by` solo puede quedarse igual:
cambiarlo convertiría «me lo asignó Edgar» en «me lo puse yo». Cuando la
asignación se retira, la firma se retira con ella —en la MISMA escritura—, y
quien suelta su consumo tiene que borrar las dos entradas aunque la firma sea
de otra persona. Eso es lo que le permite soltar lo que un administrador le
asignó sin poder tocar nada más: no puede retirar el consumo ajeno, ni dejar
una firma huérfana, ni borrar procedencia ajena dejando la asignación en pie.

**Nadie escribe una asignación sin forma, tampoco el creador.** La autoridad
del dueño de la sesión es anterior a A10 y no se le quita —se asigna a sí
mismo, a terceros y a manuales, comparte, retira y reasigna—, pero desde el
cierre de A10 pasa por el mismo protocolo: bajo el modelo por unidades ya no
tiene una rama que acepte cualquier `assignment`. Antes, un cliente modificado
suyo podía dejar «u0 → Jorge» sin firma: no falsificaba a nadie (el uid lo
pone el servidor) pero borraba la procedencia. La frontera se cierra por las
dos caras —repartir y corregir—, porque colar la asignación junto a un nombre
o un precio habría sido la misma puerta con otro nombre.

**La relación también audita su gasto.** A11b abrió la lectura del ticket a
los GRUPOS y dejó fuera a las relaciones, con un resultado absurdo: la otra
mitad de la pareja no podía ver el ticket que comparte ni decir qué consumió
sin entrar por un enlace de invitado. Ahora `auditableByContext` cubre ambos
contextos. Sigue siendo lectura: la corrección administrativa (A11c) y el
reparto de terceros (A10) exigen `managesGroupOf`, que excluye relaciones.

**Líneas históricas.** A10 solo escribe en el modelo por unidades. Convertir
una línea del modelo de pesos NO es lossless —los pesos no dicen qué unidad
concreta se compartía—, así que esa conversión sigue siendo del dueño de la
sesión y explícita. Los tickets creados hoy nacen ya con unidades.

**DEUDA ACEPTADA (confirmada en la auditoría del 2026-09-04).** Quien administra
**no puede** tocar una casilla que su dueño ya se autoseleccionó: la asignación
existe y su procedencia —vacía, por ser autoselección— no se reescribe, así que
firmar deniega, y no firmar también, porque asignar por otra persona exige
firma. Es una limitación de Rules, no del cliente, y la denegación es **limpia**
(no un presupuesto de expresiones agotado). Está fijada por test en
`backend/firestore/test/unit_assignment.test.mjs` («la admin todavía no puede
marcar lo que su dueño autoseleccionó»). El rodeo es pedirle a esa persona que
suelte la unidad. **Esto NO reabre A10**, que queda RESUELTO: el workflow normal
—asignar a cuentas, manuales e invitados, compartir, retirar y reasignar— está
completo. Ver `docs/BACKLOG_SALDA.md` § A10.

## Eliminar un gasto (A2, ADR-040)

**Hard delete.** No hay `deleted: true`, ni papelera, ni restauración: el
ticket deja de existir. Lo que queda es una **evidencia de auditoría**,
`sessions/{sid}/ticketRemovals/{tid}`, con `ticketId`, `accountId`,
`merchantName`, `grandTotal`, `removedBy`, `removedAt` y `schemaVersion`.
Nace en el MISMO commit que el borrado, es inmutable, y **no concede lectura
de nada**: sirve para que P6 pueda decir quién borró qué, no para volver
atrás.

| Quién | Grupo | Relación |
|---|---|---|
| Creador del gasto (= dueño de la sesión) | sí | sí |
| Propietario / administrador del contexto | sí | **no** (no hay administración) |
| Miembro normal, contraparte | no | no |
| Cualquiera, con la sesión `closed` | no | no |

**Qué se lleva por delante** (purga `cleanupOnTicketDelete`, idempotente y con
reintento): las líneas y el «documento fantasma» que deja una subcolección
viva, la cuenta contenedora si queda vacía, `ticketAccess`, `ticketClaims`,
`ticketLinks` y `ticketEntitlements` de ESE ticket, y la foto
`receipts/{sid}/{tid}/` —que ningún cliente puede borrar, porque la regla de
Storage exige un `request.resource` que un delete no tiene—. `recompute`
retira por su cuenta la obligación, la participación y las liquidaciones, y
recalcula los agregados.

**Qué NO se lleva por delante:** los pagos. Un pago confirmado sobrevive y, al
quedarse sin deuda detrás, se convierte en crédito de quien pagó: **el saldo
puede invertirse**, y es correcto porque el dinero se movió. Una declaración
«ya he pagado» pendiente tampoco se cancela y su receptor puede confirmarla
después. Tampoco se tocan la actividad ni las `allocations` del pago, que
siguen nombrando la obligación borrada: son su contexto histórico.

**El derecho histórico de A11d termina aquí.** Es monotónico frente a
correcciones (A11c no puede quitarte el ticket que explica tu deuda), no
frente a la desaparición deliberada del gasto: sin ticket no protege nada, y
retirarlo evita que un derecho viejo abra un id reutilizado en el futuro. Un
ex-miembro que llegue por la actividad ve «Este gasto ya no está disponible»,
no un error de carga.

**La sesión NO se borra** aunque se quede sin gastos: es otro ciclo de vida y
quien borra puede no ser su dueño. Y su vista legacy converge a 0 € mientras
la relación P5 mantiene la inversión: la sesión describe el gasto, P5 describe
lo que dos personas se deben; el saldo autoritativo es el de P5.

## Pruebas

- `backend/firestore/test/rules.test.mjs` (bloque spaces): 19 casos
  positivos/negativos contra el emulador.
- `rules.test.mjs` (bloque «enlaces de grupo»): 20 casos — gobierno del
  enlace, no enumerabilidad, canje por cuenta e invitado, token inventado /
  revocado / caducado / de otro grupo, alta de terceros, prueba de solo
  escritura, revocación con prueba antigua, caducidad inmutable, y regresión
  de las otras dos vías de alta.
- `space_links_test.dart`: 18 casos del contrato del repositorio (ciclo de
  vida, caducidad, rotación, idempotencia del doble toque, URL pegada,
  invitado que llega a sus grupos).
- `join_space_screen_test.dart`: 5 casos del flujo de entrada — cuenta e
  invitado entran SIN que se les pregunte quién son, las tres salidas de
  quien no tiene identidad, el enlace recordado, y el enlace caducado que no
  filtra el nombre del grupo.
- `join_route_test.dart`: la URL compartida y la ruta canónica no pueden
  divergir.
- `spaces_repository_test.dart`: ciclo de vida, idempotencia de
  invitaciones, transferencia, salida/expulsión, vínculo de tickets y
  compatibilidad con tickets sin espacio.
- `spaces_screen_test.dart`: vacío, activos/archivados, aceptar invitación.
- `group_member_removal.test.mjs` (A11d): 29 casos — matriz de autoridad,
  atomicidad de las tres escrituras, inmutabilidad de la evidencia, veto
  preventivo, bloqueo del enlace, invitación anterior vs posterior, que el
  expulsado no puede renovarse él la invitación, y dos ciclos completos de
  entrada y salida (incluido que un `removal` histórico SIN bloqueo vigente
  no cierra el enlace).
- `group_ticket_history.test.mjs` (A11d): 17 casos — qué conserva y qué
  pierde un ex-miembro (tampoco un `manualParticipants` suelto), y que el
  miembro activo no pierde nada de A11b.
- `economic_names_test.dart` (A11d): el saldo de un ex-miembro frente a una
  persona MANUAL se nombra por el derecho histórico, y sin derecho no se
  inventa ningún nombre.
- `unit_assignment.test.mjs` (A10): 49 casos — matriz de autoridad en grupo y
  relación, destinatarios válidos, compartir/retirar/reasignar, firma
  infalsificable que sobrevive a tocar otra unidad, y que repartir no cuela
  contenido. Incluye al creador del gasto: reparte y retira, pero no sin
  procedencia ni junto al dato fuente de la línea. Y a la invitada del enlace:
  suelta lo que le asignó un administrador —con su firma— sin poder soltar el
  consumo ajeno ni apropiarse de una procedencia viva. Cada denegación se
  comprueba además LIMPIA: no por agotar el presupuesto de expresiones de
  Rules.
- `unit_assignment_test.dart` (A10): 14 casos — a quién se le ofrece el
  reparto, qué se escribe, y que la escritura no pisa lo que ya había.
- `assignedConsumption.it.test.ts` (A10): la economía de una asignación hecha
  por otra persona es idéntica a la de una autoselección, incluida una
  persona sin cuenta y una unidad compartida.
- `ticket_deletion.test.mjs` (A2): 20 casos — matriz de autoridad (incluida
  la relación sin administración y la sesión cerrada), atomicidad de las dos
  escrituras, y una evidencia que no se puede falsear, retocar ni borrar.
- `ticketDeletion.it.test.ts` (A2): los vectores económicos A–E contra el
  motor real, la convergencia del recompute, la purga acotada al ticket (con
  su foto) y su idempotencia.
- `activity.test.ts` (A2): el borrado lo firma quien borró, no el dueño de la
  sesión, y conserva la hora del hecho y el id determinista.
- `ticket_deletion_test.dart` (A2): a quién se le ofrece la acción, el aviso
  reforzado según pagos confirmados o declaraciones pendientes, el commit
  atómico que sale, el fallo que no finge éxito, y el «ya no está disponible»
  de quien perdió el acceso.
- `storage_receipt_access.test.mjs` (A11d): la foto sigue la misma frontera.
- `ticketEntitlements.it.test.ts` (A11d): el derecho se persiste, sobrevive a
  una corrección A11c y se crea aunque el recompute resulte «sin cambios».
- `space_member_removal_test.dart` (A11d): batch atómico, readmisión, Mis
  contextos, autoridad ofrecida y pérdida de acceso con la pantalla abierta.
