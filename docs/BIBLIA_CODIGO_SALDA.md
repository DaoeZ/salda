# BIBLIA DE CÓDIGO DE SALDA

> **No confundir con `docs/BIBLIA_SALDA.md`.** Aquél es la referencia
> estratégica y técnica histórica: visión de producto, ADRs, contrato del
> proyecto, checklists, métricas y postmortems. **Este archivo es otra cosa.**

---

## A. Propósito

Memoria **acumulativa y cronológica** de cómo está construido realmente Salda:
qué se decidió en cada sesión de trabajo y por qué, qué errores se cometieron,
qué trampas tiene el código, qué se probó y qué se descartó.

Existe porque el conocimiento de este proyecto se estaba perdiendo entre
sesiones. La prueba: durante meses **A12 siguió figurando como pendiente** en la
cabeza del proyecto aunque ya se había cerrado con reproducción, causa raíz, fix
y fixtures. El estado vivía en conversaciones, no en el repositorio.

Aquí se escribe lo que un agente futuro necesitaría saber y **no puede deducir
leyendo el código**: por qué algo está hecho de una forma incómoda, qué se
intentó antes, qué se rompe si lo tocas.

## B. Cómo usarlo en sesiones futuras

**Orden de lectura obligatorio al empezar:**

1. `CLAUDE.md` — guía operativa y reglas de trabajo.
2. `docs/BACKLOG_SALDA.md` — **contrato y estado canónico de A1–A20 + N1–N3**.
3. **Este archivo** — memoria técnica acumulativa.
4. El código, los tests y Git.

**Reglas de escritura:**

- Una entrada por sesión de cierre, en orden cronológico inverso (la más
  reciente arriba, justo debajo de este apartado).
- Cada entrada lleva fecha, alcance, decisiones, errores cometidos, evidencia
  utilizada y qué debe anticipar la siguiente sesión.
- **No borrar entradas antiguas.** Si algo queda superado, anotarlo dentro de la
  entrada nueva y enlazar.
- Las lecciones transversales suben al apartado C.

## C. Invariantes transversales conocidas

Cosas que se rompen en silencio si se olvidan. Ordenadas por coste de romperlas.

### C1. Nunca inferir el significado de un `A#` por una etiqueta de un plan interno

**Primero leer `docs/BACKLOG_SALDA.md`.**

El plan de A19 y varios mensajes de commit usan `A1`…`A7` como **números de
tarea internos**. No son los IDs del backlog. `A19 (A4)` (participante
desactivado) **no** es A4 (eliminar grupo con papelera); `A19 (A5/A6)` (errores
visibles en la web, tickets en vivo) **no** es A5 (enlace único de grupo) ni A6
(reserva de identidad guest).

Esta lección costó una auditoría entera mal clasificada. Ver la entrada del
2026-09-04.

### C2. Existir en el código no es funcionar

Una Function desplegada, una regla escrita o una pantalla montada **no
demuestran** que el workflow de producto esté completo. Antes de declarar algo
resuelto hay que seguir la cadena entera: botón → repositorio → Firestore →
Rules → trigger → proyección → vuelta a la UI. `notifyOnSettlement` es el
ejemplo permanente: está desplegada, testeada y **no puede disparar nunca**
porque nadie escribe `fcmTokens`.

### C3. El dinero se calcula en dos runtimes y la paridad no se confía a la disciplina

`packages/domain` (Dart puro) y `backend/functions/src/domain` (espejo TS)
ejecutan **los mismos vectores dorados** en CI. Si tocas un motor, tocas ambos.
Nunca editar un JSON de `packages/domain/test/golden/` para «arreglar» un test.

### C4. `allocateProportionally` es la única primitiva de redondeo

Si toda división de dinero pasa por ahí, «Σ partes == total exacto» es un
invariante del sistema, no una esperanza. Dinero siempre en céntimos `int`
envueltos en `Money`. Jamás `double`.

### C5. Techo de expresiones en las Rules del reparto por unidades

La rama de `lines/{lid}` admite **UN** acceso de documento adicional
(`getAfter`) y ni uno más, y `validUnitWrite` se evalúa **una sola vez**, izada a
la rama. Con dos accesos, el camino de A10 sobre un participante MANUAL devuelve
`maximum of 1000 expressions`. Está medido, no supuesto. Lo vigila
`backend/firestore/test/picking.test.mjs`.

### C6. Ampliar una lectura no puede ampliar una escritura por detrás

`auditableByContext` abre a los miembros del contexto participantes, cuentas,
tickets y líneas, pero **deliberadamente NO abre `sessions/{sid}`**: ahí vive el
`shareCode`, que es la credencial de invitado. Leerlo permitiría fabricarse un
`guestAccess` y con él editar.

### C7. Un enlace compartible con selector de identidades es una suplantación

ADR-036 rev. 2 retiró el esquema «un enlace por ticket + elige quién eres»
porque un enlace generado para Pedro servía para quedarse con la identidad
económica de Ana, y de ahí —vía ADR-037— para pedir la vinculación de su
historial. Cualquier diseño futuro que ofrezca «Soy X» desde un enlace tiene que
explicar cómo evita eso. Afecta directamente al contrato de A5.

### C8. La autoridad la aplican las Rules; el cliente solo decide qué ofrecer

Esconder un botón no es seguridad. Y al revés: el cliente no siempre puede saber
el estado real (un miembro no puede leer `sessions/{sid}`), así que muchas
pantallas intentan la escritura y **dicen** si la rechazan. Un fallo no puede
parecer un éxito.

### C9. Congelar, no retirar

Retirar la aportación económica de un ticket reabierto dejaría un pago
`confirmed` sin la obligación que lo justificaba, y el modelo lo leería como un
sobrepago: aparecería una liquidación **inversa** por el importe entero, nueva y
cobrable, provocada solo por estar editando. Por eso existe
`picking.firmContribution`. Es también el motivo de que N3 siga abierto: la
contención existe, la solución del sobrepago **real** no.

### C10. «Cuadrar» solo habla de aritmética

La suma de líneas − descuentos + propina frente al `grandTotal`, con tolerancia
**fija de 2 céntimos** (`receiptBalanceToleranceCents`, fuente única en
`packages/domain`). Un ticket puede cuadrar al céntimo con el comercio mal
leído, la cantidad equivocada o sin un solo producto real. Por eso la revisión
dice «El total cuadra», nunca «el ticket cuadra».

### C11. `picking.open` no es «revisión»

A19 (`picking.open`) significa «he terminado de elegir mi consumo». A8
(revisión) significa «he revisado el ticket y doy por comprobada mi situación».
Son estados distintos y A8 **no existe**. Si `picking.open` se usa como señal de
atención, el rótulo correcto es **«Falta terminar el reparto»**, nunca «Falta tu
revisión».

### C12. Nunca dar por terminada una fase en rojo

`dart analyze --fatal-infos` a cero, más `dart test` en `packages/domain` y
`packages/ocr_parser`, `flutter test` en `apps/mobile`, `npm test` en
`backend/functions`, `npm run build` + vitest en `apps/guest_web`, y los tests de
Rules contra el emulador.

### C13. En un batch, `exists()` y `get()` responden por el PASADO

Leen la pre-imagen. Cualquier condición sobre **cómo queda el mundo tras el
commit** —«el sucesor sigue siendo miembro», «el propietario ya no soy yo»—
necesita `existsAfter`/`getAfter`, y eso vale igual para autorizar que para
prohibir. Con `exists()` se podía nombrar sucesor a alguien y expulsarlo en el
mismo batch: el grupo se quedaba con un `ownerUid` que ya no estaba dentro.
Lo descubrió A3 (2026-09-07) y lo vigila `group_member_removal.test.mjs`.

Corolario de coste: la comprobación de futuro va **después** de la barata, para
que el camino frecuente corte en corto y no gaste un acceso de documento (ver
C5, el presupuesto es finito).

---

# Entradas cronológicas

## A3 — ABANDONAR UN GRUPO Y SUCESIÓN DEL PROPIETARIO — 2026-09-07

**Rama:** `codex/relations-groups-navigation` · **HEAD al empezar:** `d53d213`
**Tipo de sesión:** implementación acotada a A3. Sin deploy. `main` y
`salda-prod` intactos.

### Qué se pidió

Completar el contrato canónico de A3 **sin reimplementar lo que ya
funcionaba**. El encargo lo decía explícitamente: «la auditoría anterior
encontró que la salida de un miembro normal ya existe parcialmente; investiga
primero la implementación real y completa únicamente lo que falte». Esa
instrucción resultó ser el eje de la sesión: la mitad del trabajo fue
demostrar qué **no** había que tocar.

### Estado inicial encontrado

La salida de un **miembro normal** ya funcionaba y era correcta. Se verificó
la cadena entera (C2: existir en el código no es funcionar) antes de dejarla
en paz:

- `leave()` borraba **solo** la membresía y **no** comprobaba saldos — que es
  exactamente lo que el contrato manda: se puede abandonar con deudas vivas;
- no escribía `removals` ni `entryBlocks`; esos son **exclusivos de la
  expulsión** (A11d), y confundirlos habría bloqueado la reentrada de quien se
  va por su pie;
- el derecho histórico no depende de la membresía: lo sostienen los
  `ticketEntitlements`, que `recompute` escribe y **jamás retira**
  (`recompute.ts:204-209`, ADR-039). Son monotónicos frente a correcciones, y
  son la razón de que un ex-miembro pueda seguir auditando y liquidando lo
  suyo sin seguir dentro del grupo;
- «no participa en gastos nuevos» tampoco necesitaba código: al desaparecer de
  `members`, deja de aparecer en la lista que `people_sheet.dart:88` ofrece al
  crear un gasto. La membresía **es** el filtro.

**Conclusión reutilizable:** cuando un contrato parece exigir cuatro
comportamientos y tres ya emergen del modelo de datos, la tarea es
*demostrarlos con tests*, no reimplementarlos. Se añadieron pruebas de
regresión que los fijan; no se cambió una línea de esa ruta.

Lo que faltaba era la **sucesión del propietario, en sus cuatro pasos**:

- `canLeave = !owner && isFullAccount` — al propietario ni se le ofrecía salir;
- `leave()` lanzaba `ownerCannotLeave` en seco y la UI lo mostraba como
  `spaceActionError` genérico;
- `transferOwnership()` existía, pero como acción **manual y separada**;
- no había criterio determinista, ni exclusión de guest/manual, ni bloqueo
  razonado.

### Dos huecos de autoridad que la implementación destapó

Ninguno era A3 «pendiente»; los dos eran **agujeros preexistentes** que
completar A3 obligaba a cerrar, porque son justo los estados corruptos que la
sesión tenía que impedir:

1. **Se podía transferir el grupo a un INVITADO.** La regla solo exigía
   `exists(members/{nuevoOwner})`, y un invitado tiene documento de membresía.
   Un invitado no puede ser ni administrador (ADR-034/038), así que heredar el
   contexto entero era una escalada por la puerta de atrás. Cerrado exigiendo
   `kind == 'account'`.
2. **Se podía nombrar sucesor y expulsarlo en el mismo batch.** `exists()` lee
   la **pre-imagen**, así que el sucesor «existía» aunque ese mismo commit
   borrara su membresía → grupo con un `ownerUid` que ya no está dentro.
   Cerrado pasando a `existsAfter` + `getAfter`.

**Lección transversal (ver C13): en un batch, `exists()`/`get()` responden por
el pasado.** Cualquier condición sobre «cómo queda el mundo» necesita
`existsAfter`/`getAfter`, y eso vale tanto para autorizar como para prohibir.

### Decisión: la sucesión la elige el CLIENTE, la valida el SERVIDOR

`ownershipSuccessor()` es una función **pura** en `space_models.dart`: admins
primero, luego `joinedAt` ascendente, desempate por `uid`. Nunca se depende del
orden en que Firestore devuelva la colección — la query de `watchMembers` sí
ordena por `joinedAt`, pero el lote que lee `leave()` no, y confiar en eso
habría hecho el resultado dependiente de la implementación del SDK. Hay un test
que le pasa la misma lista **invertida** y exige el mismo sucesor.

Los tres criterios, y de dónde sale cada uno:

- **admin antes que miembro** — del contrato de A3 y de **A11a** (el rol solo
  lo concede el propietario, nadie nace con él, un invitado no puede tenerlo).
  ⚠️ **No de ADR-038**: ese ADR es autoridad **económica** y su decisión dice
  justo lo contrario en su terreno —administrar no da acceso al saldo de una
  cuenta ajena—. La primera redacción de esta entrada lo citaba mal y se
  corrigió antes del cierre. Heredar el grupo **no** hereda saldos de nadie.
- **`joinedAt` ascendente** — es el único dato de antigüedad **autoritativo**:
  lo sella el servidor al crear la membresía y Rules lo exige `is timestamp`.
  Una membresía todavía sin sellar (escritura local pendiente) va **al final**:
  no se puede afirmar que sea la más antigua.
- **desempate por `uid`** — para que dos lecturas, dos dispositivos o dos
  reintentos den siempre el mismo sucesor.

**Exclusión de manual/guest, por dos vías independientes.** Los MANUALES no
son miembros (no tienen UID ni dispositivo), así que ni entran en la lista: no
existe «promover una identidad económica a autoridad administrativa». Los
GUESTS sí tienen documento de membresía, así que se excluyen explícitamente en
la función **y** en Rules. Que hicieran falta las dos es el hallazgo 1 de más
abajo.

Rules **no** puede comprobar «es el más antiguo»: eso exigiría recorrer la
colección, que no existe en el lenguaje de reglas. Y no hace falta. Lo que
Rules garantiza son los invariantes que sí duelen —hay propietario, tiene
cuenta, es miembro después del commit, no es uno mismo—; el orden es contrato
de **producto**, fijado por tests. Es exactamente C8: la autoridad la aplican
las Rules, el cliente solo decide qué ofrecer.

**Alternativa descartada:** una Cloud Function `leaveSpace` que resolviera la
sucesión en el servidor. Habría añadido una Function, una latencia y un camino
que no funciona offline, para una garantía que el batch de dos escrituras ya
da. El estado corrupto lo impide la atomicidad, no el runtime.

**Alternativa descartada:** transacción con **reelección silenciosa**. Una
transacción de cliente reintenta sola cuando cambia un documento leído, y era
tentador usarla para «buscar otro candidato si el primero ya no vale». Se
descartó por producto, no por técnica: la interfaz acaba de decir «la propiedad
pasará a **Alba**», y un reintento invisible podría dejársela a **Jorge**. La
persona habría regalado su grupo a alguien que nunca vio en el diálogo. El
batch ya impide el estado corrupto; ante un candidato inválido lo correcto es
**fallar entero y volver a preguntar**, no acertar por su cuenta.

**Alternativa descartada:** obligar al propietario a elegir sucesor a mano.
El contrato lo permite explícitamente («no hace falta obligar al usuario a
escoger si la regla determinista ya lo resuelve») y `transferOwnership()`
manual sigue existiendo para quien quiera decidirlo. Añadir un selector
obligatorio habría convertido una salida en un trámite.

### Trampa que costó una vuelta: el orden de las dos ramas del `delete`

La condición del propietario **debe ir después** de
`resource.data.uid != spaceData(spaceId).ownerUid`, no envolviéndola. Así la
salida de un miembro normal —el caso frecuente— corta en corto y no gasta el
`getAfter`. Poner la comprobación de futuro delante habría añadido un acceso de
documento a todas las salidas.

### Relación con A11d: qué se reutilizó y qué NO se duplicó

A3 **no** inventa una segunda semántica de «miembro retirado». Se apoya en lo
que A11d ya cerró y respeta la frontera entre las dos bajas:

| | Salir (A3) | Expulsar (A11d) |
|---|---|---|
| `removals/{uid}_{joinedAtMillis}` | **no** se escribe | obligatorio |
| `entryBlocks/{uid}` | **no** se escribe | obligatorio |
| Reentrada | por enlace o invitación, sin trámite | solo invitación posterior al bloqueo |
| Evento P6 | `member_left`, actor = uno mismo | `member_removed`, actor = quien expulsa |
| `ticketEntitlements` | intactos | intactos |
| Economía | intacta | intacta |

Los eventos de P6 salen **solos y correctos** sin tocar `activity.ts`:
`buildMemberEvents` distingue expulsión de salida por la *presencia* de la
evidencia, y como A3 no la escribe, la salida del propietario se registra como
`member_left`; el cambio de `ownerUid` genera además `space_transferred` desde
`buildSpaceEvents`, con actor = el owner **anterior**, que es justo quien la
inició. Cero líneas de Functions.

### Un test existente se reescribió a propósito

`spaces_repository_test.dart` afirmaba «el owner no puede salir». Ese es
literalmente el contrato que A3 sustituye: se reescribió, no se silenció.
Regla que conviene recordar: un test en rojo solo se toca cuando el **contrato**
cambió y se puede citar dónde; entonces se reescribe entero para afirmar el
contrato nuevo, nunca se relaja el aserto para que pase.

### Validación (todo en verde)

| Suite | Resultado |
|---|---|
| `dart analyze --fatal-infos` | 0 avisos |
| Rules contra el emulador | **483** ✅ (472 antes; +11 de A3), 0 fail |
| `flutter test` en `apps/mobile` | **671** ✅ / 5 skip (650 antes; +21) |
| `dart test` en `packages/domain` | 130 ✅ |
| `dart test` en `packages/ocr_parser` | 33 ✅ |
| `npm test` en `backend/functions` | 203 ✅ |

Las Rules siguen sin agotar el presupuesto de expresiones: `picking.test.mjs`,
que es el que vigila el techo de C5, pasa dentro de la misma ejecución.
`guest_web` no se ejecutó **a propósito**: A3 no toca una sola línea de la web.

Los 32 tests nuevos se repartieron por capa a conciencia: el ORDEN de sucesión
es contrato de producto y se prueba en Dart (barato, sin emulador); la
AUTORIDAD se prueba contra Rules reales, porque un provider de interfaz que
diga «puedo» no demuestra nada (C8).

### Deuda residual conocida

La transferencia exige el espacio **activo**, así que el propietario de un
grupo **archivado** debe reactivarlo antes de salir. La interfaz no le ofrece
la acción mientras esté archivado, así que **no hay callejón sin salida**, solo
un paso extra; por eso es deuda de UX y **no** deja A3 en PARCIAL. Está fijado
con test para que no se rompa por accidente, y su sitio natural es **A4**, que
es quien va a rediseñar el ciclo de vida completo del espacio (archivado ≠
eliminado): allí habrá que decidir si un grupo archivado admite salida directa
o sigue exigiendo reactivar.

### Qué debe anticipar la siguiente sesión

1. **A4 hereda esto.** «Quién manda aquí» ya tiene respuesta: propietario único
   en `ownerUid`, sucesión determinista, y un grupo nunca sin dueño. Eliminar
   un grupo **no puede** reintroducir un estado sin propietario, y la deuda del
   archivado se decide ahí.
2. **C13 aplica a cualquier operación compuesta futura**, no solo a esta. A4
   va a escribir varios documentos por acción (papelera, avisos individuales,
   reconocimiento): cada condición sobre «cómo queda el mundo» necesita
   `existsAfter`/`getAfter`.
3. Sigue pendiente el **CHECKPOINT en dispositivo real**: llevamos varios
   bloques estructurales (A19, A3) sin ejecutar el cliente completo.
4. La app y la web viajan en la rama; el único componente que A3 necesitaba
   desplegar son las Rules.

## AUDITORÍA A1–A20 + N1–N3 — 2026-09-04

**Rama:** `codex/relations-groups-navigation` · **HEAD al empezar:** `6874639`
**Tipo de sesión:** auditoría de estado real. Sin código funcional, sin deploy.

### Qué se pidió

Reconciliar el backlog de Salda con el estado real del repositorio, clasificando
A1–A20 y N1–N3 en RESUELTO / PARCIAL / PENDIENTE / EN DISCUSIÓN / NO
IMPLEMENTADO A PROPÓSITO / DEUDA ACEPTADA / OBSOLETO. El encargo traía una
advertencia explícita: *«el backlog documental se ha quedado alguna vez por
detrás del código; por ejemplo A12 seguía apareciendo como pendiente aunque ese
asunto ya había sido cerrado. No confíes ciegamente ni en el backlog ni en
estados históricos. Código + tests + Git son la evidencia principal.»*

### Descubrimiento que condicionó todo: el backlog no estaba versionado

`docs/BIBLIA_CODIGO_SALDA.md` no existía. Y el backlog A1–A20/N1–N3 **tampoco
existía en el repositorio**: ni versionado, ni borrado en el historial
(`git log --all --diff-filter=D` solo devolvía el plan exploratorio v3 de A19).
Solo aparecían fragmentos sueltos en ADRs, en `CLAUDE.md` y en mensajes de
commit.

Se reconstruyeron los contratos desde tres fuentes, en este orden de fiabilidad:
ADRs y contratos versionados → cuerpos completos de commits → transcripts
locales de sesiones anteriores (`~/.claude/projects/…/*.jsonl`). En los
transcripts apareció una enumeración del propio usuario que fijó las etiquetas:
`A4 eliminación/restauración de grupos · A15 OCR · A10 asignación manual · A19
realtime · N2 web completa · N3 reconciliación/reembolso · A3 abandonar grupo` y
`A8 reviews · A9 inferencia de dos personas · A5/A6/A7 guest links · A16
offline`, más *«A2 es exclusivamente lifecycle de un ticket»*.

**Esa dependencia de transcripts es exactamente lo que este archivo y
`docs/BACKLOG_SALDA.md` vienen a eliminar.**

### El error más caro de la sesión: inferir A# desde el plan de A19

En la primera pasada se clasificaron **A5 y A6 como RESUELTOS** citando
`describeWriteError` y el paso de `loadTickets` a `onSnapshot`, y **A7 como
«bloqueado por el modelo»** citando la sonda K (dos mutaciones al mismo
documento en un batch se deniegan). Los tres eran **tareas internas del plan de
A19**, no los IDs del backlog. También se auditó **A20 como navegación
(`openTicket`)**, cuando A20 es confirmar cobros desde cualquier superficie de
balance, y la evidencia correcta estaba mal colocada bajo A18.

La colisión se detectó al comparar dos hechos incompatibles: el commit `68fc292`
se llama «A2: eliminar un gasto de verdad» y el commit `0e7a99b` se llama
«A19 (A2/A3): la firma dice quién te lo asignó». Ambos no podían ser A2.

De ahí sale la invariante **C1**, y el aviso destacado que abre
`docs/BACKLOG_SALDA.md`.

### Qué cambió tras recibir los contratos canónicos

| ID | Primera pasada | Estado final | Por qué cambió |
|---|---|---|---|
| A1 | INDETERMINABLE | PARCIAL 30% | Sin contrato en la primera pasada |
| A3 | 90%, «solo falta avisar de la deuda» | PARCIAL 60% | Ese aviso **no es requisito**; lo que falta es la sucesión del propietario, que no se había auditado |
| A4 | «decisión pendiente sobre ADR-028» | PENDIENTE 5%, contrato **cerrado** | La decisión ya estaba tomada: archivado ≠ eliminado |
| A5 | RESUELTO 100% | PARCIAL 40% + conflicto | Se auditó la Tarea 3 del plan A19 |
| A6 | RESUELTO 100% | PARCIAL 85% | Se auditó la Tarea 4 del plan A19; la evidencia real estaba mal colocada en N2 |
| A7 | «bloqueado por el modelo» | PENDIENTE 0% | Nunca fue el batch de unidades |
| A8 | PENDIENTE 0% | PENDIENTE 0% ✔ | Interpretación confirmada correcta |
| A9 | «contrato solo conocido por su etiqueta» | PENDIENTE 0% + ADR previo | Contrato recibido |
| A10 | PARCIAL 90% | **RESUELTO + DEUDA ACEPTADA** | El residual es deuda aceptada con test, no motivo para mantenerlo abierto |
| A11 | Cuatro IDs (a/b/c/d) | **Un único ID RESUELTO**, con a–d como subworkflows | Corrección canónica |
| A13 | INDETERMINABLE | PARCIAL 30% | Contrato recibido |
| A14 | «0%, hipótesis App Check» | **NO IMPLEMENTADO A PROPÓSITO / CONDICIONAL** | La hipótesis era errónea: A14 es `balanceSummaries`. App Check sale de A14 |
| A16 | 25% («chip + cola») | PARCIAL 35% | El contrato es mucho más ancho |
| A18/A20 | Evidencia mezclada | A18 = autoridad · A20 = superficies y desglose | Recolocación |
| N1 | INDETERMINABLE | Contrato en discusión + técnico 10% | Contrato recibido; H1 encaja aquí |
| N2 | 40% | PARCIAL 25% | Al separar A5/A6/A7 pierde la parte de entrada e identidad |

### Evidencia utilizada

**Git.** `git log --all` con cuerpos completos (los mensajes de commit de este
proyecto son la mejor documentación que tiene), `git show --stat`,
`git log --diff-filter=D` para descartar que el backlog se hubiera borrado.

**Código.** Rules (2.425 líneas), `recompute.ts` (1.435), el repositorio de
sesiones, el detalle de ticket, la hoja de asignación por unidades, la web de
invitados completa, y las 14 features de la app.

**Tests ejecutados** (todos en verde, solo lectura):

| Suite | Resultado |
|---|---|
| `dart test` en `packages/domain` | **130** ✅ |
| `dart test` en `packages/ocr_parser` | **33** ✅ |
| `flutter test` en `apps/mobile` | **650** ✅ / 5 skip |
| `npm test` en `backend/functions` | **203** ✅ / 0 fail |
| `vitest run` en `apps/guest_web` | **63** ✅ / 9 archivos |

**No ejecutado:** los **472** tests de Rules (requieren levantar el emulador; se
contaron por inspección de los 11 ficheros de
`backend/firestore/test/`), la suite de integración de functions, `svelte-check`
y el análisis estático. No hacía falta: la sesión no tocó código.

**Herramientas.** Bash (grep, sed, find, git), lectura directa de ficheros y
ejecución de suites en segundo plano. Sin subagentes: el trabajo era secuencial y
dependiente, y cada búsqueda condicionaba la siguiente.

### Hallazgos que deben sobrevivir

**H1 — `notifyOnSettlement` no tiene cadena funcional completa de FCM.**
Severidad media. Ningún cliente registra `fcmTokens` (`grep` devuelve una única
línea: la lectura en `notify.ts:60`); `firebase_messaging` no está en
`pubspec.yaml`; solo cubre la ruta legacy `settlements`, no `economicPayments`;
y avisa a `session.ownerUid`, que desde ADR-038 **no es necesariamente el
receptor económico**. Registrado en `docs/BACKLOG_SALDA.md` § N1 y ya presente
como DT-1 en `docs/BIBLIA_SALDA.md` §44. **No tomar la existencia de la Function
como prueba de que las notificaciones funcionan.**

**H2 — ADR-038 faltaba en el registro de ADRs.** Severidad baja. Vivía solo en
`docs/RELACIONES_ECONOMICAS.md` y `docs/ESPACIOS.md`. Es justo el ADR que fija
quién puede confirmar un cobro. **Corregido en esta sesión**: registrado en
`docs/BIBLIA_SALDA.md` §55.

**H3 — Colisión de numeración** entre el backlog y las tareas internas del plan
de A19. Severidad media, documental. **Corregido**: aviso destacado al principio
de `docs/BACKLOG_SALDA.md`, invariante C1 e indicación en `CLAUDE.md`.

**Residual de A10.** Quien administra recibe una **denegación limpia** al
intentar modificar una unidad recién autoseleccionada por su dueño: la
procedencia vacía no se reescribe, así que firmar deniega y no firmar también.
Está fijado por test
(`backend/firestore/test/unit_assignment.test.mjs:448`), que además comprueba
que la denegación sea limpia y no un presupuesto de expresiones agotado. Es
**DEUDA ACEPTADA**, no A10 pendiente.

**UX de A19 no bloqueante.** Las tres observaciones del smoke manual (importe
congelado visible durante una reapertura, participante `active: false` sin
explicación, ausencia de acción explícita de «volver a elegir») siguen siendo
observaciones. **No convertirlas retroactivamente en fallo de A19**, que queda
RESUELTO.

### Documentación obsoleta encontrada y qué se hizo

| Documento | Problema | Acción |
|---|---|---|
| ADR-028 | «Archivar como única baja» | Marcado **superado en ese punto** por el contrato de A4 |
| ADR-021 | «Lo no reclamado recae en el pagador» | **NO** superado: sigue vigente. Anotada la tensión con A9 |
| ADR-036 rev. 2 | Selector de identidades retirado por suplantación | **NO** superado: sigue vigente. Anotado el conflicto abierto con A5 |
| ADR-035 | «MANUAL no aplica» | Anotada la tensión con el alcance futuro de A5 |
| §55 registro de ADRs | Faltaba ADR-038 | Registrado |
| DT-4 | «El feed `activity/` se escribe pero no se muestra» | Corregido: P6 tiene UI real |
| R1.4 / R3.20 / §54 | Timeline pendiente · chat «a evaluar» · «Grupo = `sessions/{sid}`» | Corregidos: P6 hecho, P7 hecho, §54 derogado por ADR-030 |
| «251 tests» / «~180 tests» / «48 tests de reglas» | Cifras que inducen a error | Corregidas a las reales |
| `CLAUDE.md` §5 | `ai_providers` «esqueleto para M6», árbol de features obsoleto | Corregido |

### Qué debe anticipar una sesión futura

1. **Leer `docs/BACKLOG_SALDA.md` antes de tocar cualquier A#.** No deducir su
   significado de un commit ni de un plan.
2. **Tres bloques están bloqueados por una decisión, no por código**: A5 (vs
   ADR-036 rev. 2), A9 (vs ADR-021) y N3 (diseño del reembolso). Empezar a
   programarlos sin ADR es trabajo perdido.
3. **A13 no puede mostrar «revisión» hasta que A8 exista**, y **A1 depende de
   A13** para su segunda línea. Ese orden importa.
4. **A10, A11, A12, A15, A17, A18, A19, A20 y A2 están cerrados.** Si algo
   parece un bug en ellos, es un bug nuevo, no el ID reabierto.
5. Los mensajes de commit de este proyecto son largos a propósito y contienen la
   causa raíz. Leerlos con `git log --format=%B` antes de tocar su área.
6. Una sesión fresca por bug o bloque coherente. No encadenar un bug nuevo
   después de cerrar el actual.

### Qué NO se hizo, a propósito

Ni una línea de código funcional. Ni Rules, ni Functions, ni app, ni
`guest_web`. Sin `firebase deploy` de ningún tipo. `salda-prod` intacto. Sin
tocar `main`, sin reescribir historial y sin absorber en el commit los cambios
locales preexistentes de `.claude/*`, `.gitignore` ni los dos hunks de
`CLAUDE.md` que documentaban el deploy de A19.
