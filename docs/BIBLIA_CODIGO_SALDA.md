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

---

# Entradas cronológicas

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
