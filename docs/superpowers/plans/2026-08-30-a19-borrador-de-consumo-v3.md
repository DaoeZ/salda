# A19 — Borrador de consumo (assignment schemaVersion 3) · Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** que elegir tu consumo sea un borrador personal —symétrico, visible y sin efecto económico— que solo entra en las cuentas cuando pulsas «He terminado», y que esa confirmación sea atómica por ticket.

**Architecture:** el reparto por unidades pasa a `schemaVersion: 3` **indexado por persona** (`units.{pid}.{unitId}`), de modo que la regla de negocio «solo puedo cambiar mi consumo» se valida en Security Rules con un número **constante** de expresiones por escritura, sin enumerar unidades. Sobre esa forma, el borrador vive en la misma línea bajo un **alcance** (`pending.{pid}.{cycle}_{generation}.{unitId}`) que hace imposible que un borrador de un ciclo de membresía anterior —o de una topología de unidades anterior— resucite. «He terminado» es **un `WriteBatch` con una escritura por línea**: todo o nada. No hay Function nueva, ni colección paralela, ni cambios en los motores económicos.

**Tech Stack:** Firestore Security Rules · Cloud Functions v2 (TypeScript, solo `recompute` existente) · Flutter + Riverpod v3 (app) · Svelte 5 + TS (web de invitados) · `@firebase/rules-unit-testing` + Emulator Suite · `fake_cloud_firestore` (tests de app) · vitest (web) · `node --test` (functions y reglas).

**Spec:** este plan implementa las decisiones cerradas por el usuario el 2026-08-30 y las mediciones de la ronda de investigación A19 (resumidas en §Mediciones). El contrato que se escribe en la Tarea 1 (`docs/BORRADOR_DE_CONSUMO.md`) pasa a ser la especificación viva; a partir de la Tarea 2 el plan y ese documento se leen juntos.

## Global Constraints

- **Idioma:** UI y documentación en español (ARB); código, identificadores y nombres de archivo en inglés. Comentarios en español explicando el PORQUÉ.
- **Commits:** en español, imperativos, prefijo `A19: …`, cuerpo con viñetas y SIEMPRE la línea `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`. **Nunca `git push` ni `deploy` sin petición explícita del usuario.**
- **Política de commits (manda sobre la plantilla de las tareas):** el commit que cierra cada tarea es una *sugerencia*, no una ceremonia. La regla real es: **cada punto revisado tiene que quedar verde y recuperable**. Si dos tareas son inseparables —dejarlas separadas dejaría el repositorio en un estado intermedio artificial, como Rules que aceptan v3 sin que ningún cliente lo escriba a medias— se agrupan en un solo commit con el mensaje combinado. Si una tarea es una unidad real y queda verde, commit propio. Nunca un commit con tests en rojo, y nunca dividir un cambio que solo compila junto.
- **Dinero:** céntimos `int` envueltos en `Money`. JAMÁS `double`.
- **Los motores no se tocan:** `SplitEngine`, `BalanceEngine`, `EconomicLedger` y los **vectores dorados** (`packages/domain/test/golden/*.json`) quedan **intactos**. Los adaptadores transponen a `unitConsumers` (unidad → pids), que es lo que los motores ya esperan. Si una tarea parece obligar a tocar un motor o un vector dorado, PARA y consulta.
- **`pending` no entra jamás en la economía:** `sanitizeLine` no lo lee; `computeAggregates` no lo ve.
- **Sin cap de producto:** ninguna regla, cliente ni copy puede imponer un número máximo de unidades por línea o por persona. Si una medición durante la implementación revela un techo, PARA y consulta (fallback documentado: finalización en servidor, descartada salvo imposibilidad).
- **Sin TTL, sin lease, sin heartbeat.** El borrador es durable y se invalida solo por alcance (ciclo de membresía o generación de unidades).
- **Toda denegación nueva de Rules se prueba con `assertDeniegaLimpio`**: un rechazo tiene que ser un rechazo, no un «maximum of 1000 expressions».
- **Presupuesto de Rules:** cada familia v3 debe validar en expresiones **constantes** respecto al número de unidades. Está prohibido introducir bucles desenrollados por unidad.
- **`maxInstances: 3` y `europe-west1`** en las Functions no se tocan.
- **Verificación por fase (todas, antes de cerrar cualquier tarea que toque su área):** `dart analyze --fatal-infos` en la raíz · `dart test` en `packages/domain` y `packages/ocr_parser` · `flutter test` en `apps/mobile` · `npm test` en `backend/functions` · `npm run build` en `apps/guest_web` · reglas con `firebase emulators:exec --only firestore,storage --project demo-salda "npm --prefix backend/firestore test"`.

---

## Mediciones que sostienen este plan (no repetir la investigación)

| Hecho | Medido |
|---|---|
| El presupuesto de 1000 expresiones es **por escritura de documento**, no por batch | 12 líneas × 12 unidades = 144 confirmaciones en un `WriteBatch` → PERMITIDA |
| Firestore **sí** admite dos mutaciones al mismo documento en un batch | commit OK con Rules desactivadas |
| …pero la segunda se evalúa **acumulativamente** (`resource.data` = pre-batch) | escritura acumulativa PERMITIDA; disjunta DENEGADA |
| Con `units.{unidad}.{pid}` el techo por línea es **6** con manejo completo de `by` | lote 6 ok · 7–8 «maximum of 1000» |
| Con `units.{pid}.{unidad}` **no hay techo** | 24 unidades en una escritura y 12 líneas × 24 en un batch → PERMITIDAS; abuso sobre consumo ajeno DENEGADO limpio |
| El borrador con **alcance como clave** conserva las intenciones de dos dispositivos simultáneos | ambos PERMITIDOS, `{u1:true, u2:true}`; el alcance viejo queda inerte y no se puede finalizar |
| La generación disciplinada bloquea saltos, retrocesos, topología sin generación y generación sin topología | las cuatro DENEGADAS limpias |
| Una línea `schemaVersion 2` **sin** `unitsGeneration` funciona con `0` implícito | borrador + finalizar PERMITIDOS |

---

## Contrato de datos (el que implementa todo el plan)

```
sessions/{sid}/accounts/{aid}/tickets/{tid}/lines/{lid}
  name, quantityMilli, unitPrice, totalPrice, order
  unitIds: ['u0', 'u1', …]            // posicionales, derivados de quantityMilli
  unitsGeneration: 0                  // sube 1 SI Y SOLO SI cambia unitIds
  assignment: {
    type: 'units',
    schemaVersion: 3,
    units:   { '{pid}': { '{unitId}': true } },              // consumo confirmado
    by:      { '{pid}': { '{unitId}': '{assignerUid}' } },   // procedencia A10
    pending: { '{pid}': { '{cycle}_{gen}': { '{unitId}': true|false } } },
    lastEditorPid: '{pid}',
    lastEditedUnit: '{unitId}'         // solo lo declaran las escrituras de UNA unidad
  }
```

- `true` en `pending` = «quiero entrar»; `false` = «quiero salir»; ausencia = sin cambio.
- `{cycle}` = milisegundos de `spaces/{spaceId}/members/{uid}.joinedAt` del ciclo vigente, o `0` si quien escribe no es miembro (invitado por enlace).
- `{gen}` = `unitsGeneration` de la línea (0 si el campo no existe).
- Invariante de A10 que sobrevive: **no hay firma sin asignación detrás** — `by[pid]` siempre es un subconjunto de `units[pid]`.
- Los borradores de alcances caducos quedan en el documento como datos muertos: nadie los lee, nadie los puede finalizar, y desaparecen con la poda A11c o con el borrado del ticket.

---

## Orden de despliegue y compatibilidad entre capas

**Invariante de rollout, que manda sobre el orden de las tareas:** en ningún momento puede existir una capa que **escriba** un formato que otra capa todavía no **entienda**. De ahí sale este orden, y por eso las tareas están numeradas así:

| Paso | Quién | Qué gana | Qué sigue escribiendo | Quién lo entiende ya |
|---|---|---|---|---|
| 1 (T2, T3) | `recompute` | **lee** v2 y v3 | nada (nunca escribe líneas) | — |
| 2 (T4–T6) | Rules | **aceptan** v2 y v3 | — | recompute ya lee v3 |
| 3 (T7–T11) | app y web | **leen** v2 y v3 · **escriben** v3 | v3 | Rules y recompute |
| 4 (T12) | herramienta Admin | transpone v2 → v3 | v3 | todos |
| 5 (T13) | Rules y clientes | dejan de **producir** v2 | v3 | todos, y la lectura de v2 se queda |

Reglas que se derivan y que ningún agente puede saltarse:

- **Nunca adelantar el paso 3 al 2.** Si un cliente escribiera v3 antes de que las Rules lo acepten, cada toque sería un `permission-denied`.
- **Nunca adelantar el paso 5.** Retirar la escritura v2 mientras exista una build instalada que escribe v2 la deja rota. Precondición explícita de T13: la app y la web nuevas están en TODOS los dispositivos en uso (hoy: los del usuario) y el `--dry-run` de la herramienta reporta cero líneas v2.
- **Orden de despliegue en `salda-dev`, cuando el usuario lo pida** (los despliegues los ejecuta el usuario; ningún agente hace `firebase deploy`): primero Functions (`recompute` lector de v3), después las Rules, y solo entonces la app y la web. Al revés, un cliente nuevo escribiría v3 contra unas Rules viejas —rechazo— o contra un `recompute` que no lo entiende —cuentas en blanco—.
- **La lectura de v2 no se retira nunca.** No es deuda: es lo que hace seguros los backups antiguos y cualquier documento legacy que aparezca. Cuesta cero presupuesto de Rules porque vive en los adaptadores, no en las reglas.
- Durante los pasos 2–4 conviven ambos formatos y **todo el mundo entiende los dos**. Ese es el único periodo con dos familias de Rules vivas, y termina en el paso 5.

## File Structure

**Documentación (contrato antes que código: es la mitigación del riesgo «deriva de dos clientes»)**
- Crear `docs/BORRADOR_DE_CONSUMO.md` — contrato A19 completo: forma v3, alcance, familias de Rules, protocolo de escritura de ambos clientes, migración.
- Modificar `docs/REPARTO_POR_UNIDADES.md` — v2 pasa a ser modelo histórico legible; enlaza al nuevo contrato.
- Modificar `docs/BIBLIA_SALDA.md` — ADR-040 (person-first + borrador con alcance) con las mediciones.
- Modificar `CLAUDE.md` §2 — punto exacto del proyecto.

**Backend — Functions (lectura dual; nunca escribe líneas)**
- Modificar `backend/functions/src/recompute.ts` — `sanitizeLine` entiende v2 y v3; `recomputeOnLine` ignora los cambios que no mueven economía.
- Modificar `backend/functions/src/test/recompute.test.ts` — paridad v2↔v3 y guard.

**Backend — Rules (todo O(1) por escritura)**
- Modificar `backend/firestore/firestore.rules` — familias v3: `canPickOrAssignUnitV3`, `canDraftOwnUnitV3`, `canFinalizeOwnBranchV3`; disciplina de `unitsGeneration`; poda A11c extendida a `pending`.
- Crear `backend/firestore/test/unit_draft_v3.test.mjs` — la matriz completa de A19.
- Modificar `backend/firestore/test/unit_assignment.test.mjs` — A10 sobre v3 (las de v2 se conservan hasta la Tarea 12).

**App (Flutter)**
- Modificar `apps/mobile/lib/features/sessions/domain/session_models.dart` — `TicketLine` con lectura dual, `unitsGeneration` y borrador.
- Modificar `apps/mobile/lib/features/sessions/data/firestore_session_repository.dart` — escritores v3: borrador, finalizar (UN batch), asignación A10, conversión.
- Crear `apps/mobile/lib/features/sessions/domain/draft_scope.dart` — cálculo del alcance, espejo exacto de Rules.
- Modificar `apps/mobile/lib/features/sessions/application/session_providers.dart` — ciclo de membresía y estado del borrador.
- Modificar `apps/mobile/lib/features/sessions/presentation/ticket_detail_screen.dart` y `unit_assignment_sheet.dart` — toque = borrador, «He terminado», estados y accesibilidad.
- Modificar `apps/mobile/lib/features/sessions/presentation/ticket_navigation.dart` — cabecera del ticket en vivo.
- Modificar `apps/mobile/lib/l10n/app_es.arb` (+ `flutter gen-l10n`).
- Modificar `apps/mobile/lib/features/settings/data/backup_service.dart` — el import transpone v2 → v3.
- Tests: `apps/mobile/test/unit_assignment_test.dart`, `ticket_lines_test.dart`, `ticket_navigation_test.dart` y nuevo `apps/mobile/test/consumption_draft_test.dart`.

**Web (Svelte)**
- Modificar `apps/guest_web/src/lib/assignment.ts` — lectura dual, `draftUpdate`, `finalizeUpdate`, alcance.
- Modificar `apps/guest_web/src/lib/session.svelte.ts` — borrador, «He terminado» en batch, ticket en vivo.
- Modificar `apps/guest_web/src/views/PickItems.svelte` — estados y botón.
- Tests: `apps/guest_web/src/lib/assignment.test.ts`.

**Migración**
- Crear `backend/functions/tools/migrate-assignments-v3.mjs` — transposición lossless con Admin SDK, idempotente, `--dry-run` y verificación.

---

### Task 1: Contrato escrito (docs) antes que código

**Files:**
- Create: `docs/BORRADOR_DE_CONSUMO.md`
- Modify: `docs/REPARTO_POR_UNIDADES.md`, `docs/BIBLIA_SALDA.md`, `CLAUDE.md`

**Interfaces:**
- Consumes: nada.
- Produces: el vocabulario exacto de claves (`units`, `by`, `pending`, `unitsGeneration`, alcance `{cycle}_{gen}`) que TODAS las tareas siguientes citan literalmente.

- [ ] **Step 1: Escribir `docs/BORRADOR_DE_CONSUMO.md`**

Secciones obligatorias, en este orden:

1. **Qué problema resuelve**: elegir consumo dejaba de ser un borrador — cada toque movía dinero. A19 separa intención (borrador) de hecho económico (confirmado).
2. **Forma v3** — copiar literalmente el bloque «Contrato de datos» de este plan.
3. **Por qué person-first**: con `units.{unidad}.{pid}`, «solo puedo cambiar mi consumo» es O(n) y Security Rules no itera mapas; medido: techo de 6 unidades por línea. Con `units.{pid}.{unidad}` es O(1) y no hay techo (medido: 24 unidades en una escritura, 12 líneas × 24 en un batch).
4. **Alcance del borrador**: `{cycle}_{gen}` es parte de la IDENTIDAD, no del contenido. Consecuencias: un borrador de un ciclo anterior no resucita, una corrección de topología no arrastra intenciones viejas, y dos dispositivos de la misma persona escriben claves distintas sin pisarse (medido).
5. **Reglas de generación**: `unitsGeneration` sube exactamente 1 si y solo si cambia `unitIds`; renombrar o corregir precios no la mueve. Línea sin el campo = 0 implícito.
6. **Protocolo de escritura** (idéntico en app y web):
   - toque = una clave hoja de `pending.{pid}.{scope}.{unitId}` (`true`/`false`/borrar);
   - «He terminado» = un `WriteBatch` con **una** escritura por línea, que mueve `units.{pid}`, `by.{pid}` y limpia `pending.{pid}.{scope}`;
   - A10 (admin) sigue siendo inmediato y de un par por escritura, y limpia el `pending` de ESE par.
7. **Invariantes**: `by[pid] ⊆ units[pid]`; `pending` nunca entra en la economía; una escritura solo mueve la rama de una persona.
8. **Compatibilidad**: v2 se lee (transponiendo) y se convierte una sola vez; después nadie escribe v2.

- [ ] **Step 2: Actualizar `docs/REPARTO_POR_UNIDADES.md`**

Añadir al principio un bloque «Estado» que diga: v2 (`units.{unidad}.{pid}`) es el modelo **histórico legible**; el vigente es v3, descrito en `docs/BORRADOR_DE_CONSUMO.md`. No borrar la descripción de v2: sigue siendo la referencia de lectura dual.

- [ ] **Step 3: ADR-040 en `docs/BIBLIA_SALDA.md`**

Título: «ADR-040 · Consumo indexado por persona (schemaVersion 3) y borrador con alcance». Incluir: contexto (A19 exige confirmación atómica por ticket), decisión, alternativas descartadas (v5 con tope 6 = número mágico en producto; Function de finalización = otra autoridad, más infraestructura y peor offline), y la tabla de mediciones de §Mediciones.

- [ ] **Step 4: Actualizar `CLAUDE.md` §2**

Una entrada nueva al final del «Punto exacto»: A19 en curso, contrato en `docs/BORRADOR_DE_CONSUMO.md`, v3 person-first, sin Function nueva.

- [ ] **Step 5: Commit**

```bash
git add docs/BORRADOR_DE_CONSUMO.md docs/REPARTO_POR_UNIDADES.md docs/BIBLIA_SALDA.md CLAUDE.md
git commit -m "$(cat <<'EOF'
A19: fijar el contrato del borrador de consumo antes de tocar código

- docs/BORRADOR_DE_CONSUMO.md: forma v3 person-first, alcance del borrador
  (ciclo de membresía + generación de unidades) y protocolo de escritura
  común a app y web.
- ADR-040 con las mediciones que descartan el tope de 6 unidades y la
  Function de finalización.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `sanitizeLine` entiende v3 (lectura dual en la autoridad económica)

El servidor entiende v3 **antes** de que ningún cliente lo escriba. Orden no negociable.

**Files:**
- Modify: `backend/functions/src/recompute.ts:552-587` (`sanitizeLine`)
- Test: `backend/functions/src/test/recompute.test.ts`

**Interfaces:**
- Consumes: el contrato de la Tarea 1.
- Produces: `sanitizeLine(line, known, payerId): SplitLine` con `unitConsumers: Record<string, string[]>` idéntico para una línea v2 y su transposición v3.

- [ ] **Step 1: Escribir el test que falla**

En `backend/functions/src/test/recompute.test.ts`, junto a los tests de unidades existentes:

```typescript
test('v3: el consumo indexado por persona produce el mismo reparto que v2', () => {
  const v2 = {
    id: 'l1',
    totalPrice: 1200,
    quantityMilli: 3000,
    assignment: {
      type: 'units',
      schemaVersion: 2,
      units: { u0: { p2: true }, u1: { p2: true, p3: true } },
    },
  };
  const v3 = {
    id: 'l1',
    totalPrice: 1200,
    quantityMilli: 3000,
    assignment: {
      type: 'units',
      schemaVersion: 3,
      units: { p2: { u0: true, u1: true }, p3: { u1: true } },
    },
  };
  const known = new Set(['p1', 'p2', 'p3']);
  const desdeV2 = sanitizeLine(v2 as never, known, 'p1');
  const desdeV3 = sanitizeLine(v3 as never, known, 'p1');
  assert.deepEqual(desdeV3.unitConsumers, desdeV2.unitConsumers);
  assert.deepEqual(desdeV3.unitConsumers, { '0': ['p2'], '1': ['p2', 'p3'] });
});

test('v3: el orden de los consumidores de una unidad es estable', () => {
  const linea = {
    id: 'l1',
    totalPrice: 900,
    quantityMilli: 3000,
    assignment: {
      type: 'units',
      schemaVersion: 3,
      units: { p3: { u0: true }, p2: { u0: true } },
    },
  };
  // El orden lo fija el censo de participantes (p1..pN), no el mapa.
  const r = sanitizeLine(linea as never, new Set(['p1', 'p2', 'p3']), 'p1');
  assert.deepEqual(r.unitConsumers, { '0': ['p2', 'p3'] });
});

test('v3: un pid desconocido se ignora y no rompe el reparto', () => {
  const linea = {
    id: 'l1',
    totalPrice: 600,
    quantityMilli: 2000,
    assignment: {
      type: 'units',
      schemaVersion: 3,
      units: { p2: { u0: true }, fantasma: { u1: true } },
    },
  };
  const r = sanitizeLine(linea as never, new Set(['p1', 'p2']), 'p1');
  assert.deepEqual(r.unitConsumers, { '0': ['p2'] });
});

test('v3: `pending` no toca la economía', () => {
  const conBorrador = {
    id: 'l1',
    totalPrice: 1000,
    quantityMilli: 2000,
    assignment: {
      type: 'units',
      schemaVersion: 3,
      units: { p2: { u0: true } },
      pending: { p2: { '17_0': { u1: true } }, p3: { '17_0': { u0: false } } },
    },
  };
  const r = sanitizeLine(conBorrador as never, new Set(['p1', 'p2', 'p3']), 'p1');
  assert.deepEqual(r.unitConsumers, { '0': ['p2'] });
});
```

Si `sanitizeLine` no está exportada, exportarla en el mismo commit (el resto de sus tests ya la usan; comprobar con `grep -n "sanitizeLine" backend/functions/src/test/recompute.test.ts`).

- [ ] **Step 2: Ejecutar y ver fallar**

Run: `npm --prefix backend/functions test`
Expected: FAIL — la rama v3 no existe; `unitConsumers` sale vacío.

- [ ] **Step 3: Implementar la lectura dual**

En `recompute.ts`, dentro de `sanitizeLine`, sustituir la condición de entrada al modelo por unidades y añadir la rama v3 **antes** de la de v2:

```typescript
  // v3 (A19): el consumo se indexa por PERSONA. Se transpone al mismo
  // `unitConsumers` que ya consume el motor: la economía no cambia, cambia
  // dónde está escrito. El orden de los consumidores lo fija el censo
  // (`known`), no el mapa, para que el reparto sea determinista.
  if (line.assignment?.schemaVersion === 3 && rawType === 'units') {
    const unitConsumers: Record<string, string[]> = {};
    for (const pid of known) {
      const mias = line.assignment?.units?.[pid] ?? {};
      for (const [unitId, selected] of Object.entries(mias)) {
        if (!selected) continue;
        const unit = Number.parseInt(unitId.slice(1), 10);
        if (!unitId.startsWith('u') || Number.isNaN(unit)) continue;
        if (unit < 0 || unit >= units) continue;
        (unitConsumers[String(unit)] ??= []).push(pid);
      }
    }
    return {
      id: line.id,
      totalPrice: line.totalPrice,
      units,
      unitConsumers,
      assignment: { type: 'unassigned', weights: {} },
    };
  }
```

Comprobar el tipo `LineDoc`: `assignment.units` pasa a ser `Record<string, Record<string, boolean>>` en ambas formas, así que el tipo no cambia; añadir a `LineDoc` el campo opcional `unitsGeneration?: number` (aún no se usa aquí, pero el documento lo trae).

- [ ] **Step 4: Ejecutar los tests**

Run: `npm --prefix backend/functions test`
Expected: PASS — 189 anteriores + los 4 nuevos. **Los vectores dorados siguen en verde: si alguno cambia, has tocado el motor y hay que revertir.**

- [ ] **Step 5: Commit**

```bash
git add backend/functions/src/recompute.ts backend/functions/src/test/recompute.test.ts
git commit -m "$(cat <<'EOF'
A19: recompute entiende el consumo indexado por persona

- sanitizeLine transpone `units.{pid}.{unidad}` (v3) al mismo unitConsumers
  que ya consumía de v2: los motores y los vectores dorados no se tocan.
- `pending` sigue siendo invisible para la economía.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `recomputeOnLine` deja de recalcular por borradores

**Files:**
- Modify: `backend/functions/src/recompute.ts:1077` (`recomputeOnLine`)
- Test: `backend/functions/src/test/recompute.test.ts`

**Interfaces:**
- Consumes: nada de tareas anteriores.
- Produces: `lineChangeMovesMoney(before, after): boolean` exportada para test.

- [ ] **Step 1: Escribir el test que falla**

```typescript
test('guard: un cambio solo de borrador no mueve dinero', () => {
  const antes = {
    totalPrice: 1000, quantityMilli: 2000,
    assignment: { type: 'units', schemaVersion: 3, units: { p2: { u0: true } } },
  };
  const despues = {
    totalPrice: 1000, quantityMilli: 2000,
    assignment: {
      type: 'units', schemaVersion: 3, units: { p2: { u0: true } },
      pending: { p2: { '17_0': { u1: true } } },
      lastEditorPid: 'p2', lastEditedUnit: 'u1',
    },
  };
  assert.equal(lineChangeMovesMoney(antes, despues), false);
});

test('guard: confirmar consumo SÍ mueve dinero', () => {
  const antes = {
    totalPrice: 1000, quantityMilli: 2000,
    assignment: { type: 'units', schemaVersion: 3, units: { p2: { u0: true } } },
  };
  const despues = {
    totalPrice: 1000, quantityMilli: 2000,
    assignment: { type: 'units', schemaVersion: 3, units: { p2: { u0: true, u1: true } } },
  };
  assert.equal(lineChangeMovesMoney(antes, despues), true);
});

test('guard: corregir precio o cantidad SÍ mueve dinero', () => {
  const base = {
    totalPrice: 1000, quantityMilli: 2000,
    assignment: { type: 'units', schemaVersion: 3, units: {} },
  };
  assert.equal(lineChangeMovesMoney(base, { ...base, totalPrice: 1200 }), true);
  assert.equal(lineChangeMovesMoney(base, { ...base, quantityMilli: 3000 }), true);
});

test('guard: crear o borrar la línea SIEMPRE mueve dinero', () => {
  const linea = {
    totalPrice: 500, quantityMilli: 1000,
    assignment: { type: 'units', schemaVersion: 3, units: {} },
  };
  assert.equal(lineChangeMovesMoney(undefined, linea), true);
  assert.equal(lineChangeMovesMoney(linea, undefined), true);
});
```

- [ ] **Step 2: Ejecutar y ver fallar**

Run: `npm --prefix backend/functions test`
Expected: FAIL — `lineChangeMovesMoney is not defined`.

- [ ] **Step 3: Implementar el guard**

En `recompute.ts`, junto a `sanitizeLine`:

```typescript
/**
 * ¿Este cambio de línea puede alterar una sola cuenta?
 *
 * `recomputeOnLine` es un trigger sin filtro de campos: cada toque provisional
 * de A19 lo despertaba y le costaba ~30 lecturas antes de descubrir que no
 * había nada que cambiar. Con `maxInstances: 3`, cuatro personas eligiendo a la
 * vez hacían cola por nada. El borrador (`pending`) y los campos declarativos
 * de la escritura (`lastEditorPid`, `lastEditedUnit`) NO son economía.
 */
export function lineChangeMovesMoney(
  before: LineDoc | undefined,
  after: LineDoc | undefined,
): boolean {
  if (!before || !after) return true;
  if ((before.totalPrice ?? 0) !== (after.totalPrice ?? 0)) return true;
  if ((before.quantityMilli ?? 1000) !== (after.quantityMilli ?? 1000)) return true;
  const a = before.assignment ?? {};
  const b = after.assignment ?? {};
  if ((a.type ?? '') !== (b.type ?? '')) return true;
  if ((a.schemaVersion ?? 0) !== (b.schemaVersion ?? 0)) return true;
  if (JSON.stringify(a.units ?? {}) !== JSON.stringify(b.units ?? {})) return true;
  return JSON.stringify(a.participants ?? {}) !== JSON.stringify(b.participants ?? {});
}
```

Y al principio del trigger:

```typescript
export const recomputeOnLine = onDocumentWritten(
  'sessions/{sid}/accounts/{aid}/tickets/{tid}/lines/{lid}',
  async (event) => {
    const before = event.data?.before?.data() as LineDoc | undefined;
    const after = event.data?.after?.data() as LineDoc | undefined;
    if (!lineChangeMovesMoney(before, after)) return;
    // …lo que ya hacía…
  },
);
```

Comprobar la forma real del handler antes de editar: `sed -n '1070,1100p' backend/functions/src/recompute.ts`.

- [ ] **Step 4: Ejecutar los tests**

Run: `npm --prefix backend/functions test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/functions/src/recompute.ts backend/functions/src/test/recompute.test.ts
git commit -m "$(cat <<'EOF'
A19: no recalcular la sesión por un borrador

- recomputeOnLine sale antes de leer nada cuando el cambio no toca precio,
  cantidad ni consumo confirmado: los toques provisionales dejan de
  despertar la function y de hacer cola con maxInstances 3.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Rules — familia A10 sobre v3 (asignar y elegir, O(1))

**Files:**
- Modify: `backend/firestore/firestore.rules` (bloque `match /lines/{lid}` y funciones de reparto, a partir de la línea 2018 y 2123)
- Test: `backend/firestore/test/unit_assignment.test.mjs` (añadir un `describe` v3; los casos v2 se conservan)

**Interfaces:**
- Consumes: contrato de la Tarea 1.
- Produces: en Rules — `usesPersonModel()`, `v3AssignmentKeys()`, `personBranchOnly(pid)`, `signaturesWithinConsumption(pid)`, `canPickOrAssignUnitV3(sid, aid, tid)`. Los tres primeros los reutilizan las Tareas 5 y 6.

- [ ] **Step 1: Escribir los tests que fallan**

En `backend/firestore/test/unit_assignment.test.mjs`, añadir al final:

```javascript
/** Línea v3: el consumo se indexa por persona. */
const lineaV3 = (ctx, extra = {}) => setDoc(
  doc(ctx.firestore(), G),
  {
    name: 'Cañas', totalPrice: 2400, quantityMilli: 12000, order: 0,
    unitIds: ['u0','u1','u2','u3','u4','u5','u6','u7','u8','u9','u10','u11'],
    unitsGeneration: 0,
    assignment: { type: 'units', schemaVersion: 3, units: {}, ...extra },
  },
);

/** A10 en v3: un par (persona, unidad) por escritura, con su firma. */
const asignarV3 = (actor, pid, { unit = 'u0', selected = true, firma } = {}) => {
  const rubrica = firma === undefined ? actor : firma;
  return updateDoc(doc(db(actor), G), {
    'assignment.type': 'units',
    'assignment.schemaVersion': 3,
    'assignment.lastEditorPid': pid,
    'assignment.lastEditedUnit': unit,
    [`assignment.units.${pid}.${unit}`]: selected ? true : deleteField(),
    [`assignment.by.${pid}.${unit}`]:
      selected && rubrica !== null ? rubrica : deleteField(),
  });
};

describe('A10 sobre v3 (consumo por persona)', () => {
  beforeEach(async () => {
    await env.withSecurityRulesDisabled((ctx) => lineaV3(ctx));
  });

  it('la creadora del gasto asigna a sí misma, a otro y a un MANUAL', async () => {
    await assertSucceeds(asignarV3(ALBA, 'p1'));
    await assertSucceeds(asignarV3(ALBA, 'p2', { unit: 'u1' }));
    await assertSucceeds(asignarV3(ALBA, 'p3', { unit: 'u2' }));
  });

  it('un miembro normal solo se asigna a sí mismo', async () => {
    await assertSucceeds(asignarV3(JORGE, 'p2'));
    await assertDeniegaLimpio(asignarV3(JORGE, 'p1', { unit: 'u1' }));
    await assertDeniegaLimpio(asignarV3(JORGE, 'p3', { unit: 'u2' }));
  });

  it('una escritura no puede mover dos ramas de personas', async () => {
    await assertDeniegaLimpio(updateDoc(doc(db(ALBA), G), {
      'assignment.type': 'units',
      'assignment.schemaVersion': 3,
      'assignment.lastEditorPid': 'p2',
      'assignment.lastEditedUnit': 'u0',
      'assignment.units.p2.u0': true,
      'assignment.by.p2.u0': ALBA,
      'assignment.units.p3.u0': true,
    }));
  });

  it('una escritura no puede mover dos unidades de la misma persona', async () => {
    await assertDeniegaLimpio(updateDoc(doc(db(ALBA), G), {
      'assignment.type': 'units',
      'assignment.schemaVersion': 3,
      'assignment.lastEditorPid': 'p2',
      'assignment.lastEditedUnit': 'u0',
      'assignment.units.p2.u0': true,
      'assignment.by.p2.u0': ALBA,
      'assignment.units.p2.u1': true,
      'assignment.by.p2.u1': ALBA,
    }));
  });

  it('asignar a otra persona SIEMPRE queda firmado por quien lo hace', async () => {
    await assertDeniegaLimpio(asignarV3(ALBA, 'p2', { firma: null }));
    await assertDeniegaLimpio(asignarV3(ALBA, 'p2', { firma: JORGE }));
  });

  it('marcarse a uno mismo no necesita firma (autoselección)', async () => {
    await assertSucceeds(updateDoc(doc(db(JORGE), G), {
      'assignment.type': 'units',
      'assignment.schemaVersion': 3,
      'assignment.lastEditorPid': 'p2',
      'assignment.lastEditedUnit': 'u0',
      'assignment.units.p2.u0': true,
    }));
  });

  it('retirar una asignación se lleva su firma; dejarla huérfana se deniega',
    async () => {
      await assertSucceeds(asignarV3(ALBA, 'p2'));
      await assertDeniegaLimpio(updateDoc(doc(db(JORGE), G), {
        'assignment.type': 'units',
        'assignment.schemaVersion': 3,
        'assignment.lastEditorPid': 'p2',
        'assignment.lastEditedUnit': 'u0',
        'assignment.units.p2.u0': deleteField(),
      }));
      await assertSucceeds(asignarV3(JORGE, 'p2', { selected: false }));
    });

  it('la firma de una asignación viva no se reescribe', async () => {
    await assertSucceeds(asignarV3(ALBA, 'p2'));
    await assertDeniegaLimpio(asignarV3(JORGE, 'p2', { firma: JORGE }));
  });

  it('un ex-miembro no reparte ni recibe consumo nuevo', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const { deleteDoc } = await import('firebase/firestore');
      await deleteDoc(doc(ctx.firestore(), `spaces/gr1/members/${JORGE}`));
    });
    await assertDeniegaLimpio(asignarV3(JORGE, 'p2'));
  });
});
```

- [ ] **Step 2: Ejecutar y ver fallar**

Run: `firebase emulators:exec --only firestore,storage --project demo-salda "npm --prefix backend/firestore test"`
Expected: FAIL — v3 no tiene familia: todas las escrituras se deniegan (incluidas las que deben pasar).

- [ ] **Step 3: Implementar la familia v3**

En `firestore.rules`, junto a `usesUnitModel()`:

```javascript
    // ── Modelo por PERSONA (A19, schemaVersion 3) ───────────────────────
    // La regla de negocio es «solo puedo cambiar MI consumo». Indexado por
    // unidad, comprobarlo obliga a recorrer unidad por unidad, y Rules no
    // itera mapas: había que desenrollar el bucle y el presupuesto de 1000
    // expresiones ponía un techo de 6 unidades por línea. Indexado por
    // persona, la misma regla es UNA comprobación, sea cual sea la cantidad.
    function usesPersonModel() {
      return resource.data.get('assignment', {}).get('schemaVersion', 0) == 3;
    }

    function v3AssignmentKeys() {
      return request.resource.data.assignment.keys().hasOnly([
        'type', 'schemaVersion', 'units', 'by', 'pending',
        'lastEditorPid', 'lastEditedUnit'
      ])
        && request.resource.data.assignment.type == 'units'
        && request.resource.data.assignment.schemaVersion == 3;
    }

    // En una escritura solo se mueve la rama de UNA persona: ni el consumo
    // ajeno, ni la procedencia ajena, ni el borrador ajeno.
    function personBranchOnly(pid) {
      let now = request.resource.data.assignment;
      let old = resource.data.assignment;
      return pid != ''
        && now.get('units', {}).diff(old.get('units', {}))
            .affectedKeys().hasOnly([pid])
        && now.get('by', {}).diff(old.get('by', {}))
            .affectedKeys().hasOnly([pid])
        && now.get('pending', {}).diff(old.get('pending', {}))
            .affectedKeys().hasOnly([pid]);
    }

    // Invariante de A10 que sobrevive a la inversión: no queda firma sin
    // asignación detrás. Aquí cuesta UNA comprobación para toda la línea.
    function signaturesWithinConsumption(pid) {
      return request.resource.data.assignment.get('by', {}).get(pid, {})
        .keys().hasOnly(
          request.resource.data.assignment.get('units', {}).get(pid, {}).keys());
    }

    // ── Elegir o asignar UNA unidad (A10 en v3) ─────────────────────────
    function canPickOrAssignUnitV3(sid, aid, tid) {
      let session = sessionData(sid);
      let ticket = get(/databases/$(database)/documents/sessions/$(sid)/accounts/$(aid)/tickets/$(tid)).data;
      let mode = ticket.get('splitModeOverride', session.splitModeDefault);
      let now = request.resource.data.assignment;
      let old = resource.data.assignment;
      let target = now.get('lastEditorPid', '');
      let unitKey = now.get('lastEditedUnit', '');
      let oldMias = old.get('units', {}).get(target, {});
      let newMias = now.get('units', {}).get(target, {});
      let oldFirmas = old.get('by', {}).get(target, {});
      let newFirmas = now.get('by', {}).get(target, {});
      let selected = newMias.get(unitKey, false);
      return session.status == 'open'
        && mode == 'byItem'
        && usesPersonModel()
        && v3AssignmentKeys()
        && unitKey != ''
        && resource.data.get('unitIds', ['u0']).hasAny([unitKey])
        && personBranchOnly(target)
        // …y dentro de esa rama, UNA sola unidad.
        && newMias.diff(oldMias).affectedKeys().hasOnly([unitKey])
        && newFirmas.diff(oldFirmas).affectedKeys().hasOnly([unitKey])
        && selected is bool
        && signaturesWithinConsumption(target)
        && (selected
          ? (oldMias.get(unitKey, false) == true
            // La asignación ya existía: su procedencia NO se reescribe.
            ? newFirmas.get(unitKey, '') == oldFirmas.get(unitKey, '')
            : newFirmas.get(unitKey, request.auth.uid) == request.auth.uid)
          : !(unitKey in newFirmas))
        // El borrador de ESE par se resuelve con la asignación; el de los
        // demás no se toca (lo garantiza personBranchOnly).
        && draftPairResolved(target, unitKey, ticket.get('spaceId', ''))
        && (
          // Autoselección…
          (participatesInSplit(sid) && claimedBy(sid, target) == request.auth.uid)
          // …o autoridad sobre el gasto, siempre firmada.
          || ((isOwner(sid) || managesGroupOf(ticket.get('spaceId', '')))
            && (!selected
              || newFirmas.get(unitKey, '') == request.auth.uid)
            && exists(/databases/$(database)/documents/sessions/$(sid)/participants/$(target))
            && participantData(sid, target).get('active', true) == true)
        );
    }
```

`draftPairResolved` se escribe en la Tarea 5 (usa el alcance). Para que esta tarea compile por sí sola, añadir ya su versión definitiva —es corta— junto a las funciones de alcance de la Tarea 5, o dejar aquí un `true` temporal y sustituirlo en la Tarea 5. **Si eliges el `true` temporal, el test «el admin resuelve el borrador de ese par» de la Tarea 5 es el que lo caza.**

Y en el bloque `match /lines/{lid}`, ampliar la rama de reparto:

```javascript
            allow update: if onlyAssignmentChanged()
              ? (usesPersonModel()
                ? canPickOrAssignUnitV3(sid, aid, tid)
                : usesUnitModel()
                ? (canPickOwnUnit(sid, aid, tid)
                  || canAssignWithProvenance(sid, aid, tid))
                : ((isOwner(sid) && isOpen(sid))
                  || canPickOwnShare(sid, aid, tid)))
              : ((isOwner(sid) && isOpen(sid)
                  && (!usesUnitModel() || unitsOnlyPruned()))
                || canCorrectLine(sid, aid, tid));
```

`usesPersonModel()` es el discriminante barato: una línea v3 no evalúa jamás la familia v2 ni al revés.

- [ ] **Step 4: Ejecutar los tests**

Run: `firebase emulators:exec --only firestore,storage --project demo-salda "npm --prefix backend/firestore test"`
Expected: PASS — los 442 anteriores + los nuevos de v3. Ninguna denegación con «maximum of».

- [ ] **Step 5: Commit**

```bash
git add backend/firestore/firestore.rules backend/firestore/test/unit_assignment.test.mjs
git commit -m "$(cat <<'EOF'
A19: A10 sobre el consumo indexado por persona

- Familia v3: una escritura mueve la rama de UNA persona y UNA unidad,
  con la misma procedencia firmada de A10 y sin firmas huérfanas.
- El discriminante por schemaVersion evita que v2 y v3 se evalúen a la vez.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Rules — borrador con alcance (ciclo + generación)

**Files:**
- Modify: `backend/firestore/firestore.rules`
- Create: `backend/firestore/test/unit_draft_v3.test.mjs`

**Interfaces:**
- Consumes: `usesPersonModel()`, `v3AssignmentKeys()`, `personBranchOnly(pid)` (Tarea 4).
- Produces: `currentCycle(spaceId)`, `draftScope(spaceId)`, `draftPairResolved(pid, unitKey, spaceId)`, `canDraftOwnUnitV3(sid, aid, tid)`.

- [ ] **Step 1: Escribir el test que falla**

Crear `backend/firestore/test/unit_draft_v3.test.mjs` con el andamiaje de `unit_assignment.test.mjs` (copiar `before`/`after`/`beforeEach` y adaptarlos: sesión `sg1` en el grupo `gr1`, participantes `p1` Alba dueña, `p2` Jorge, `p3` Edgar, línea `l1` con 12 unidades, `unitsGeneration: 0`, `assignment` v3 vacío), más:

```javascript
/** Milisegundos del ciclo de membresía vigente. */
async function ciclo(uid) {
  let ms = 0;
  await env.withSecurityRulesDisabled(async (ctx) => {
    const m = await getDoc(doc(ctx.firestore(), `spaces/gr1/members/${uid}`));
    ms = m.data()?.joinedAt?.toMillis?.() ?? 0;
  });
  return ms;
}

const alcance = (ms, gen) => `${ms}_${gen}`;

/** Un toque del borrador: una sola clave hoja. */
const tocar = (actor, pid, scope, unit, quiero) =>
  updateDoc(doc(db(actor), L1), {
    'assignment.type': 'units',
    'assignment.schemaVersion': 3,
    'assignment.lastEditorPid': pid,
    'assignment.lastEditedUnit': unit,
    [`assignment.pending.${pid}.${scope}.${unit}`]:
      quiero === null ? deleteField() : quiero,
  });

describe('A19: borrador personal', () => {
  it('entrar, salir y retirar el borrador; la economía no se mueve', async () => {
    const s = alcance(await ciclo(JORGE), 0);
    await assertSucceeds(tocar(JORGE, 'p2', s, 'u0', true));
    await assertSucceeds(tocar(JORGE, 'p2', s, 'u0', false));
    await assertSucceeds(tocar(JORGE, 'p2', s, 'u0', null));
    const linea = await leerLinea();
    assert.deepEqual(linea.assignment.units, {});
    assert.equal(linea.assignment.by, undefined);
  });

  it('dos personas en la misma unidad no se pisan', async () => {
    const sJ = alcance(await ciclo(JORGE), 0);
    const sE = alcance(await ciclo(EDGAR), 0);
    await assertSucceeds(tocar(JORGE, 'p2', sJ, 'u0', true));
    await assertSucceeds(tocar(EDGAR, 'p3', sE, 'u0', true));
    const linea = await leerLinea();
    assert.equal(linea.assignment.pending.p2[sJ].u0, true);
    assert.equal(linea.assignment.pending.p3[sE].u0, true);
  });

  it('no puedo escribir el borrador de otra persona, ni siendo dueña', async () => {
    const s = alcance(await ciclo(JORGE), 0);
    await assertDeniegaLimpio(tocar(JORGE, 'p3', s, 'u0', true));
    await assertDeniegaLimpio(tocar(ALBA, 'p2', s, 'u0', true));
  });

  it('el borrador no puede colar consumo ni firma', async () => {
    const s = alcance(await ciclo(JORGE), 0);
    await assertDeniegaLimpio(updateDoc(doc(db(JORGE), L1), {
      'assignment.type': 'units', 'assignment.schemaVersion': 3,
      'assignment.lastEditorPid': 'p2', 'assignment.lastEditedUnit': 'u0',
      [`assignment.pending.p2.${s}.u0`]: true,
      'assignment.units.p2.u0': true,
    }));
    await assertDeniegaLimpio(updateDoc(doc(db(JORGE), L1), {
      'assignment.type': 'units', 'assignment.schemaVersion': 3,
      'assignment.lastEditorPid': 'p2', 'assignment.lastEditedUnit': 'u0',
      [`assignment.pending.p2.${s}.u0`]: true,
      'assignment.by.p2.u0': JORGE,
    }));
  });

  it('un toque escribe UNA unidad', async () => {
    const s = alcance(await ciclo(JORGE), 0);
    await assertDeniegaLimpio(updateDoc(doc(db(JORGE), L1), {
      'assignment.type': 'units', 'assignment.schemaVersion': 3,
      'assignment.lastEditorPid': 'p2', 'assignment.lastEditedUnit': 'u0',
      [`assignment.pending.p2.${s}.u0`]: true,
      [`assignment.pending.p2.${s}.u1`]: true,
    }));
  });

  it('el alcance tiene que ser el vigente', async () => {
    const c = await ciclo(JORGE);
    await assertDeniegaLimpio(tocar(JORGE, 'p2', alcance(c, 7), 'u0', true));
    await assertDeniegaLimpio(tocar(JORGE, 'p2', alcance(c - 1000, 0), 'u0', true));
    await assertDeniegaLimpio(tocar(JORGE, 'p2', 'basura', 'u0', true));
  });

  it('sesión cerrada, modo equal, unidad inexistente y expulsado: denegados',
    async () => {
      const s = alcance(await ciclo(JORGE), 0);
      await assertDeniegaLimpio(tocar(JORGE, 'p2', s, 'u99', true));
      await conSesion({ status: 'closed' },
        () => assertDeniegaLimpio(tocar(JORGE, 'p2', s, 'u0', true)));
      await conTicket({ splitModeOverride: 'equal' },
        () => assertDeniegaLimpio(tocar(JORGE, 'p2', s, 'u0', true)));
      await env.withSecurityRulesDisabled(async (ctx) => {
        const { deleteDoc } = await import('firebase/firestore');
        await deleteDoc(doc(ctx.firestore(), `spaces/gr1/members/${JORGE}`));
      });
      await assertDeniegaLimpio(tocar(JORGE, 'p2', s, 'u0', true));
    });

  it('una línea v2 no admite borrador', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), L1), {
      name: 'Cañas', totalPrice: 1200, quantityMilli: 3000, order: 0,
      unitIds: ['u0', 'u1', 'u2'],
      assignment: { type: 'units', schemaVersion: 2, units: {} },
    }));
    const s = alcance(await ciclo(JORGE), 0);
    await assertDeniegaLimpio(tocar(JORGE, 'p2', s, 'u0', true));
  });

  it('el admin asigna y resuelve el borrador de ESE par, no el ajeno', async () => {
    const sJ = alcance(await ciclo(JORGE), 0);
    const sE = alcance(await ciclo(EDGAR), 0);
    await assertSucceeds(tocar(JORGE, 'p2', sJ, 'u0', true));
    await assertSucceeds(tocar(EDGAR, 'p3', sE, 'u0', true));
    await assertSucceeds(updateDoc(doc(db(ALBA), L1), {
      'assignment.type': 'units', 'assignment.schemaVersion': 3,
      'assignment.lastEditorPid': 'p2', 'assignment.lastEditedUnit': 'u0',
      'assignment.units.p2.u0': true,
      'assignment.by.p2.u0': ALBA,
      [`assignment.pending.p2.${sJ}.u0`]: deleteField(),
    }));
    const linea = await leerLinea();
    assert.deepEqual(linea.assignment.units, { p2: { u0: true } });
    assert.equal(linea.assignment.pending.p3[sE].u0, true);
  });

  it('el admin no puede borrar el borrador de otra persona', async () => {
    const sE = alcance(await ciclo(EDGAR), 0);
    await assertSucceeds(tocar(EDGAR, 'p3', sE, 'u0', true));
    await assertDeniegaLimpio(updateDoc(doc(db(ALBA), L1), {
      'assignment.type': 'units', 'assignment.schemaVersion': 3,
      'assignment.lastEditorPid': 'p2', 'assignment.lastEditedUnit': 'u0',
      'assignment.units.p2.u0': true,
      'assignment.by.p2.u0': ALBA,
      [`assignment.pending.p3.${sE}.u0`]: deleteField(),
    }));
  });
});
```

Añadir los ayudantes `leerLinea()`, `conSesion(patch, fn)` y `conTicket(patch, fn)` en el mismo archivo (leen/escriben con `withSecurityRulesDisabled` y restauran el valor anterior al salir).

- [ ] **Step 2: Ejecutar y ver fallar**

Run: `firebase emulators:exec --only firestore --project demo-salda "npm --prefix backend/firestore test"`
Expected: FAIL — no existe la familia de borrador.

- [ ] **Step 3: Implementar alcance y familia de borrador**

```javascript
    // ── Alcance del borrador (A19) ──────────────────────────────────────
    // El ciclo de membresía y la generación de unidades forman parte de la
    // IDENTIDAD del borrador, no de su contenido. Así, readmitir a alguien o
    // corregir la cantidad de una línea no «invalida» nada: deja el borrador
    // anterior en otra clave, inalcanzable, y no obliga a que el primer toque
    // del alcance nuevo reescriba el mapa —que es justo lo que perdía la
    // intención de un segundo dispositivo escribiendo a la vez—.
    function currentCycle(spaceId) {
      return (spaceId != ''
        && exists(/databases/$(database)/documents/spaces/$(spaceId)/members/$(request.auth.uid)))
        ? spaceMemberJoinedAt(spaceId).toMillis()
        : 0;
    }

    function draftScope(spaceId) {
      return string(currentCycle(spaceId)) + '_'
        + string(resource.data.get('unitsGeneration', 0));
    }

    // Una asignación confirmada resuelve el borrador de SU MISMO par: queda
    // resuelto, no fantasma. El de otras personas no se toca nunca.
    function draftPairResolved(pid, unitKey, spaceId) {
      let scope = draftScope(spaceId);
      let oldMio = resource.data.assignment.get('pending', {}).get(pid, {});
      let newMio = request.resource.data.assignment.get('pending', {}).get(pid, {});
      return newMio.diff(oldMio).affectedKeys().hasOnly([scope])
        && newMio.get(scope, {}).diff(oldMio.get(scope, {}))
            .affectedKeys().hasOnly([unitKey])
        && !(unitKey in newMio.get(scope, {}));
    }

    // ── Escribir MI borrador (A19) ──────────────────────────────────────
    function canDraftOwnUnitV3(sid, aid, tid) {
      let session = sessionData(sid);
      let ticket = get(/databases/$(database)/documents/sessions/$(sid)/accounts/$(aid)/tickets/$(tid)).data;
      let mode = ticket.get('splitModeOverride', session.splitModeDefault);
      let now = request.resource.data.assignment;
      let old = resource.data.assignment;
      let pid = now.get('lastEditorPid', '');
      let unitKey = now.get('lastEditedUnit', '');
      let scope = draftScope(ticket.get('spaceId', ''));
      let oldMio = old.get('pending', {}).get(pid, {}).get(scope, {});
      let newMio = now.get('pending', {}).get(pid, {}).get(scope, {});
      return participatesInSplit(sid)
        && session.status == 'open'
        && mode == 'byItem'
        && usesPersonModel()
        && v3AssignmentKeys()
        && unitKey != ''
        && resource.data.get('unitIds', ['u0']).hasAny([unitKey])
        // Un borrador NO es economía: units y by quedan exactamente igual.
        && now.get('units', {}) == old.get('units', {})
        && now.get('by', {}) == old.get('by', {})
        && personBranchOnly(pid)
        && now.get('pending', {}).get(pid, {})
            .diff(old.get('pending', {}).get(pid, {}))
            .affectedKeys().hasOnly([scope])
        && newMio.diff(oldMio).affectedKeys().hasOnly([unitKey])
        && (!(unitKey in newMio) || newMio[unitKey] is bool)
        && claimedBy(sid, pid) == request.auth.uid;
    }
```

Y el discriminante derivado en `match /lines/{lid}` (una escritura que no cambia `units` es un borrador):

```javascript
            allow update: if onlyAssignmentChanged()
              ? (usesPersonModel()
                ? (request.resource.data.assignment.get('units', {})
                    == resource.data.assignment.get('units', {})
                  ? canDraftOwnUnitV3(sid, aid, tid)
                  : canPickOrAssignUnitV3(sid, aid, tid))
                : usesUnitModel()
                ? (canPickOwnUnit(sid, aid, tid)
                  || canAssignWithProvenance(sid, aid, tid))
                : ((isOwner(sid) && isOpen(sid))
                  || canPickOwnShare(sid, aid, tid)))
              : (…sin cambios…);
```

**No declares el tipo de operación en un campo.** Se midió: un campo declarado (`op`) se queda GUARDADO en el documento y la siguiente escritura hereda la familia equivocada; la asignación administrativa quedaba denegada por un `op: 'draft'` viejo.

- [ ] **Step 4: Ejecutar los tests**

Run: `firebase emulators:exec --only firestore --project demo-salda "npm --prefix backend/firestore test"`
Expected: PASS, sin ningún «maximum of».

- [ ] **Step 5: Commit**

```bash
git add backend/firestore/firestore.rules backend/firestore/test/unit_draft_v3.test.mjs
git commit -m "$(cat <<'EOF'
A19: el borrador de consumo vive en la línea, con alcance

- pending.{pid}.{ciclo}_{generación}.{unidad}: la identidad del borrador
  incluye el ciclo de membresía y la topología de la línea, así que un
  borrador viejo no resucita y no hay que limpiarlo para empezar otro.
- Un toque escribe una sola clave hoja: dos dispositivos de la misma
  persona no se pisan.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Rules — «He terminado» (rama completa en O(1)) y generación disciplinada

**Files:**
- Modify: `backend/firestore/firestore.rules`
- Test: `backend/firestore/test/unit_draft_v3.test.mjs`

**Interfaces:**
- Consumes: todo lo de las Tareas 4 y 5.
- Produces: `canFinalizeOwnBranchV3(sid, aid, tid)`, `generationIsCoherent()`.

- [ ] **Step 1: Escribir los tests que fallan**

Añadir a `unit_draft_v3.test.mjs`:

```javascript
/** «He terminado» de UNA línea: mi rama entera, en una escritura. */
const finalizarDatos = (pid, scope, plan) => {
  const data = {
    'assignment.type': 'units',
    'assignment.schemaVersion': 3,
    'assignment.lastEditorPid': pid,
  };
  for (const [unit, quiero] of Object.entries(plan)) {
    data[`assignment.units.${pid}.${unit}`] = quiero ? true : deleteField();
    if (!quiero) data[`assignment.by.${pid}.${unit}`] = deleteField();
    data[`assignment.pending.${pid}.${scope}.${unit}`] = deleteField();
  }
  return data;
};

describe('A19: He terminado', () => {
  it('confirma entradas y salidas —incluida una firmada por el admin— en UNA escritura',
    async () => {
      const s = alcance(await ciclo(JORGE), 0);
      await assertSucceeds(updateDoc(doc(db(ALBA), L1), {
        'assignment.type': 'units', 'assignment.schemaVersion': 3,
        'assignment.lastEditorPid': 'p2', 'assignment.lastEditedUnit': 'u0',
        'assignment.units.p2.u0': true, 'assignment.by.p2.u0': ALBA,
      }));
      await assertSucceeds(tocar(JORGE, 'p2', s, 'u0', false));
      await assertSucceeds(tocar(JORGE, 'p2', s, 'u1', true));
      await assertSucceeds(tocar(JORGE, 'p2', s, 'u2', true));
      await assertSucceeds(updateDoc(doc(db(JORGE), L1),
        finalizarDatos('p2', s, { u0: false, u1: true, u2: true })));
      const linea = await leerLinea();
      assert.deepEqual(linea.assignment.units.p2, { u1: true, u2: true });
      assert.deepEqual(linea.assignment.by.p2, {});
      assert.deepEqual(linea.assignment.pending.p2[s], {});
    });

  it('12 unidades de una línea, sin techo de presupuesto', async () => {
    const s = alcance(await ciclo(JORGE), 0);
    const plan = {};
    for (let i = 0; i < 12; i++) {
      await assertSucceeds(tocar(JORGE, 'p2', s, `u${i}`, true));
      plan[`u${i}`] = true;
    }
    await assertSucceeds(updateDoc(doc(db(JORGE), L1),
      finalizarDatos('p2', s, plan)));
    assert.equal(Object.keys((await leerLinea()).assignment.units.p2).length, 12);
  });

  it('el batch del ticket es todo o nada', async () => {
    const s = alcance(await ciclo(JORGE), 0);
    await assertSucceeds(tocar(JORGE, 'p2', s, 'u0', true));
    await assertSucceeds(tocarEn(L2, JORGE, 'p2', s, 'u0', true));
    const f = db(JORGE);
    const bueno = writeBatch(f);
    bueno.update(doc(f, L1), finalizarDatos('p2', s, { u0: true }));
    bueno.update(doc(f, L2), finalizarDatos('p2', s, { u0: true }));
    await assertSucceeds(bueno.commit());

    const malo = writeBatch(f);
    malo.update(doc(f, L1), finalizarDatos('p2', s, { u1: true }));
    malo.update(doc(f, L2), finalizarDatos('p3', s, { u1: true })); // pid ajeno
    await assertDeniegaLimpio(malo.commit());
    assert.equal((await leerLinea()).assignment.units.p2.u1, undefined);
  });

  it('no puedo arrastrar a nadie más ni reescribir su firma', async () => {
    const s = alcance(await ciclo(JORGE), 0);
    await assertSucceeds(tocar(JORGE, 'p2', s, 'u0', true));
    await assertDeniegaLimpio(updateDoc(doc(db(JORGE), L1), {
      'assignment.type': 'units', 'assignment.schemaVersion': 3,
      'assignment.lastEditorPid': 'p2',
      'assignment.units.p2.u0': true,
      'assignment.units.p3.u0': true,
      [`assignment.pending.p2.${s}.u0`]: deleteField(),
    }));
    await assertDeniegaLimpio(updateDoc(doc(db(JORGE), L1), {
      'assignment.type': 'units', 'assignment.schemaVersion': 3,
      'assignment.lastEditorPid': 'p2',
      'assignment.units.p2.u0': true,
      'assignment.by.p3.u1': JORGE,
      [`assignment.pending.p2.${s}.u0`]: deleteField(),
    }));
  });

  it('no puedo firmarme a mí mismo lo que me pongo yo', async () => {
    const s = alcance(await ciclo(JORGE), 0);
    await assertSucceeds(tocar(JORGE, 'p2', s, 'u0', true));
    await assertDeniegaLimpio(updateDoc(doc(db(JORGE), L1), {
      'assignment.type': 'units', 'assignment.schemaVersion': 3,
      'assignment.lastEditorPid': 'p2',
      'assignment.units.p2.u0': true,
      'assignment.by.p2.u0': JORGE,
      [`assignment.pending.p2.${s}.u0`]: deleteField(),
    }));
  });

  it('salir sin llevarse la firma se deniega (nada de firmas huérfanas)',
    async () => {
      const s = alcance(await ciclo(JORGE), 0);
      await assertSucceeds(updateDoc(doc(db(ALBA), L1), {
        'assignment.type': 'units', 'assignment.schemaVersion': 3,
        'assignment.lastEditorPid': 'p2', 'assignment.lastEditedUnit': 'u0',
        'assignment.units.p2.u0': true, 'assignment.by.p2.u0': ALBA,
      }));
      await assertSucceeds(tocar(JORGE, 'p2', s, 'u0', false));
      await assertDeniegaLimpio(updateDoc(doc(db(JORGE), L1), {
        'assignment.type': 'units', 'assignment.schemaVersion': 3,
        'assignment.lastEditorPid': 'p2',
        'assignment.units.p2.u0': deleteField(),
        [`assignment.pending.p2.${s}.u0`]: deleteField(),
      }));
    });

  it('no puedo finalizar con un alcance que no es el vigente', async () => {
    const c = await ciclo(JORGE);
    const s = alcance(c, 0);
    await assertSucceeds(tocar(JORGE, 'p2', s, 'u0', true));
    await assertDeniegaLimpio(updateDoc(doc(db(JORGE), L1),
      finalizarDatos('p2', alcance(c, 9), { u0: true })));
  });
});

describe('A19: expulsión, readmisión y carrera de dispositivos', () => {
  it('el borrador de un ciclo anterior no se finaliza ni se retoma, y el nuevo conserva ambos toques',
    async () => {
      const c1 = await ciclo(JORGE);
      await assertSucceeds(tocar(JORGE, 'p2', alcance(c1, 0), 'u9', true));
      await env.withSecurityRulesDisabled(async (ctx) => {
        const { deleteDoc } = await import('firebase/firestore');
        await deleteDoc(doc(ctx.firestore(), `spaces/gr1/members/${JORGE}`));
      });
      await new Promise((r) => setTimeout(r, 20));
      await env.withSecurityRulesDisabled((ctx) => setDoc(
        doc(ctx.firestore(), `spaces/gr1/members/${JORGE}`),
        { uid: JORGE, joinedAt: serverTimestamp() }));
      const c2 = await ciclo(JORGE);
      assert.notEqual(c1, c2);
      const s2 = alcance(c2, 0);

      // Dos dispositivos de la MISMA persona, a la vez, sobre el alcance nuevo.
      const [r1, r2] = await Promise.allSettled([
        tocar(JORGE, 'p2', s2, 'u1', true),
        tocar(JORGE, 'p2', s2, 'u2', true),
      ]);
      assert.equal(r1.status, 'fulfilled');
      assert.equal(r2.status, 'fulfilled');
      const linea = await leerLinea();
      assert.deepEqual(linea.assignment.pending.p2[s2], { u1: true, u2: true });
      assert.deepEqual(linea.assignment.pending.p2[alcance(c1, 0)], { u9: true });

      await assertDeniegaLimpio(updateDoc(doc(db(JORGE), L1),
        finalizarDatos('p2', alcance(c1, 0), { u9: true })));
    });
});

describe('A19: disciplina de unitsGeneration', () => {
  it('renombrar no mueve la generación ni invalida el borrador', async () => {
    const s = alcance(await ciclo(JORGE), 0);
    await assertSucceeds(tocar(JORGE, 'p2', s, 'u0', true));
    await assertSucceeds(updateDoc(doc(db(ALBA), L1), { name: 'Cañas dobles' }));
    await assertSucceeds(updateDoc(doc(db(JORGE), L1),
      finalizarDatos('p2', s, { u0: true })));
  });

  it('cambiar unitIds obliga a subir la generación exactamente 1', async () => {
    await assertDeniegaLimpio(updateDoc(doc(db(ALBA), L1), {
      quantityMilli: 6000, unitIds: ['u0','u1','u2','u3','u4','u5'],
    }));
    await assertDeniegaLimpio(updateDoc(doc(db(ALBA), L1), {
      quantityMilli: 6000, unitIds: ['u0','u1','u2','u3','u4','u5'],
      unitsGeneration: 5,
    }));
    await assertSucceeds(updateDoc(doc(db(ALBA), L1), {
      quantityMilli: 6000, unitIds: ['u0','u1','u2','u3','u4','u5'],
      unitsGeneration: 1,
    }));
  });

  it('subir la generación sin tocar unitIds se deniega', async () => {
    await assertDeniegaLimpio(updateDoc(doc(db(ALBA), L1), { unitsGeneration: 1 }));
    await assertDeniegaLimpio(updateDoc(doc(db(ALBA), L1), {
      name: 'Otro', unitsGeneration: 1,
    }));
  });

  it('un borrador no puede tocar la generación', async () => {
    const s = alcance(await ciclo(JORGE), 0);
    await assertDeniegaLimpio(updateDoc(doc(db(JORGE), L1), {
      unitsGeneration: 1,
      'assignment.type': 'units', 'assignment.schemaVersion': 3,
      'assignment.lastEditorPid': 'p2', 'assignment.lastEditedUnit': 'u0',
      [`assignment.pending.p2.${s}.u0`]: true,
    }));
  });

  it('tras subir la generación, el borrador viejo queda fuera de alcance',
    async () => {
      const c = await ciclo(JORGE);
      await assertSucceeds(tocar(JORGE, 'p2', alcance(c, 0), 'u0', true));
      await assertSucceeds(updateDoc(doc(db(ALBA), L1), {
        quantityMilli: 6000, unitIds: ['u0','u1','u2','u3','u4','u5'],
        unitsGeneration: 1,
      }));
      await assertDeniegaLimpio(updateDoc(doc(db(JORGE), L1),
        finalizarDatos('p2', alcance(c, 0), { u0: true })));
      await assertSucceeds(tocar(JORGE, 'p2', alcance(c, 1), 'u0', true));
    });

  it('una línea SIN el campo funciona con 0 implícito', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), L1), {
      name: 'Pan', totalPrice: 300, quantityMilli: 3000, order: 3,
      unitIds: ['u0', 'u1', 'u2'],
      assignment: { type: 'units', schemaVersion: 3, units: {} },
    }));
    const s = alcance(await ciclo(JORGE), 0);
    await assertSucceeds(tocar(JORGE, 'p2', s, 'u0', true));
    await assertSucceeds(updateDoc(doc(db(JORGE), L1),
      finalizarDatos('p2', s, { u0: true })));
  });

  it('la poda A11c se lleva los borradores de las unidades que mueren',
    async () => {
      const s = alcance(await ciclo(JORGE), 0);
      await assertSucceeds(tocar(JORGE, 'p2', s, 'u11', true));
      await assertDeniegaLimpio(updateDoc(doc(db(ALBA), L1), {
        quantityMilli: 6000, unitIds: ['u0','u1','u2','u3','u4','u5'],
        unitsGeneration: 1,
        'assignment.units.p2.u11': deleteField(),
      }));
    });
});
```

El último caso fija el criterio: **corregir la topología no puede dejar consumo confirmado en unidades que ya no existen**; los borradores caducos sí pueden quedarse (están fuera de alcance por construcción).

- [ ] **Step 2: Ejecutar y ver fallar**

Run: `firebase emulators:exec --only firestore --project demo-salda "npm --prefix backend/firestore test"`
Expected: FAIL.

- [ ] **Step 3: Implementar finalización y generación**

```javascript
    // ── «He terminado» (A19) ────────────────────────────────────────────
    // Confirma MI rama entera de esta línea: entradas, salidas y la limpieza
    // de mi borrador. Cuesta lo mismo con 2 unidades que con 24, porque no
    // hay nada que recorrer: se comprueba que solo se ha movido mi rama.
    function canFinalizeOwnBranchV3(sid, aid, tid) {
      let session = sessionData(sid);
      let ticket = get(/databases/$(database)/documents/sessions/$(sid)/accounts/$(aid)/tickets/$(tid)).data;
      let mode = ticket.get('splitModeOverride', session.splitModeDefault);
      let now = request.resource.data.assignment;
      let old = resource.data.assignment;
      let pid = now.get('lastEditorPid', '');
      let scope = draftScope(ticket.get('spaceId', ''));
      let firmasAntes = old.get('by', {}).get(pid, {});
      let firmasAhora = now.get('by', {}).get(pid, {});
      return participatesInSplit(sid)
        && session.status == 'open'
        && mode == 'byItem'
        && usesPersonModel()
        && v3AssignmentKeys()
        && claimedBy(sid, pid) == request.auth.uid
        && personBranchOnly(pid)
        // Mi consumo solo puede quedarse en unidades que existen.
        && now.get('units', {}).get(pid, {}).keys()
            .hasOnly(resource.data.get('unitIds', ['u0']))
        // Mis firmas solo pueden PERDERSE: nadie se firma a sí mismo una
        // autoselección, y la procedencia ajena ya la protege personBranchOnly.
        && firmasAhora.diff(firmasAntes).addedKeys().size() == 0
        && firmasAhora.diff(firmasAntes).changedKeys().size() == 0
        && signaturesWithinConsumption(pid)
        // Y el borrador que se limpia es el mío, del alcance vigente.
        && now.get('pending', {}).get(pid, {})
            .diff(old.get('pending', {}).get(pid, {}))
            .affectedKeys().hasOnly([scope]);
    }

    // ── Generación de unidades (A19) ────────────────────────────────────
    // La topología de una línea son sus `unitIds`, derivados de la cantidad.
    // La generación sube EXACTAMENTE 1 cuando esa topología cambia, y no se
    // mueve por corregir el nombre o el precio: si se moviera, cada
    // corrección tiraría borradores que siguen siendo válidos.
    function generationIsCoherent() {
      let oldGen = resource.data.get('unitsGeneration', 0);
      let newGen = request.resource.data.get('unitsGeneration', 0);
      return request.resource.data.get('unitIds', [])
          == resource.data.get('unitIds', [])
        ? newGen == oldGen
        : newGen == oldGen + 1;
    }
```

Enganches en `match /lines/{lid}`:

```javascript
            allow update: if onlyAssignmentChanged()
              ? (usesPersonModel()
                ? (request.resource.data.assignment.get('units', {})
                    == resource.data.assignment.get('units', {})
                  ? canDraftOwnUnitV3(sid, aid, tid)
                  : request.resource.data.assignment.get('lastEditedUnit', '') == ''
                  ? canFinalizeOwnBranchV3(sid, aid, tid)
                  : canPickOrAssignUnitV3(sid, aid, tid))
                : …v2 sin cambios…)
              : ((isOwner(sid) && isOpen(sid)
                  && generationIsCoherent()
                  && (!usesUnitModel() || unitsOnlyPruned())
                  && (!usesPersonModel() || personUnitsOnlyPruned()))
                || canCorrectLine(sid, aid, tid));
```

El discriminante entre A10 y finalizar es **derivado del cambio**, no declarado: A10 declara `lastEditedUnit` (una unidad); «He terminado» no lo declara.

Añadir además `personUnitsOnlyPruned()` para la corrección A11c sobre v3 —el equivalente de `unitsOnlyPruned()`, también O(1):

```javascript
    // Corregir el contenido puede PODAR consumo de unidades que dejan de
    // existir, y nada más: ni repartir, ni cambiar de modelo.
    function personUnitsOnlyPruned() {
      let now = request.resource.data.assignment;
      let old = resource.data.assignment;
      let ids = request.resource.data.get('unitIds', []);
      return now.get('type', '') == old.get('type', '')
        && now.get('schemaVersion', 0) == old.get('schemaVersion', 0)
        && now.get('participants', {}) == old.get('participants', {});
    }
```

y en `canCorrectLine`, añadir `'unitsGeneration'` al `hasOnly` de claves afectadas y `&& generationIsCoherent()`. **Comprobación de la poda por consumo:** el test «la poda A11c se lleva los borradores…» exige que el consumo confirmado no sobreviva a la unidad; eso ya lo garantiza la rama de finalizar (`keys().hasOnly(unitIds)`) para el consumo propio y, para la corrección, hay que añadir en `canCorrectLine`/rama del dueño la comprobación por rama de quien se está podando. Si esa comprobación resultara O(n) sobre las personas, **PARA y consulta**: podar es una acción de administración, no de reparto, y el criterio acordado es que ninguna familia enumere.

- [ ] **Step 4: Ejecutar los tests**

Run: `firebase emulators:exec --only firestore,storage --project demo-salda "npm --prefix backend/firestore test"`
Expected: PASS, todo el conjunto (442 previos + A19), sin «maximum of» en ninguna denegación.

- [ ] **Step 5: Commit**

```bash
git add backend/firestore/firestore.rules backend/firestore/test/unit_draft_v3.test.mjs
git commit -m "$(cat <<'EOF'
A19: confirmar el borrador de una línea entera en una sola escritura

- canFinalizeOwnBranchV3 valida «solo se ha movido mi rama» con un número
  constante de expresiones: 12 unidades por línea y 12 líneas por batch
  pasan sin acercarse al límite de Rules.
- unitsGeneration sube 1 si y solo si cambian los unitIds.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: App — leer v3 y el borrador

**Files:**
- Modify: `apps/mobile/lib/features/sessions/domain/session_models.dart:225-269`
- Create: `apps/mobile/lib/features/sessions/domain/draft_scope.dart`
- Modify: `apps/mobile/lib/features/sessions/data/firestore_session_repository.dart:400-447` (`watchTicketLines`)
- Test: `apps/mobile/test/ticket_lines_test.dart`, `apps/mobile/test/consumption_draft_test.dart` (nuevo)

**Interfaces:**
- Consumes: contrato de la Tarea 1.
- Produces:
  - `String draftScope({required int cycleMillis, required int generation})` → `'$cycleMillis_$generation'`.
  - `TicketLine.unitsGeneration: int`, `TicketLine.draft: Map<String, Map<String, bool>>` (pid → unitId → intención) **ya filtrado al alcance vigente**, `TicketLine.assignmentSchemaVersion`.
  - `TicketLine.draftOf(String pid, int unit) → bool?` y `TicketLine.confirmedConsumers(int unit) → Set<String>` (lo que hoy hace `consumersOf`).

- [ ] **Step 1: Escribir el test que falla**

`apps/mobile/test/consumption_draft_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/sessions/domain/draft_scope.dart';
import 'package:salda_mobile/features/sessions/domain/session_models.dart';

void main() {
  test('el alcance del borrador es ciclo y generación', () {
    expect(draftScope(cycleMillis: 1788, generation: 0), '1788_0');
    expect(draftScope(cycleMillis: 0, generation: 3), '0_3');
  });

  test('v3: el consumo confirmado se lee transpuesto por unidad', () {
    final line = TicketLine.fromAssignment(
      id: 'l1',
      path: 'p',
      name: 'Cañas',
      quantityMilli: 3000,
      totalPrice: const Money(1200),
      unitsGeneration: 0,
      assignment: const {
        'type': 'units',
        'schemaVersion': 3,
        'units': {
          'p2': {'u0': true, 'u1': true},
          'p3': {'u1': true},
        },
      },
      scope: '0_0',
    );
    expect(line.confirmedConsumers(0), {'p2'});
    expect(line.confirmedConsumers(1), {'p2', 'p3'});
    expect(line.confirmedConsumers(2), isEmpty);
  });

  test('v2 se sigue leyendo igual (lectura dual)', () {
    final line = TicketLine.fromAssignment(
      id: 'l1',
      path: 'p',
      name: 'Cañas',
      quantityMilli: 3000,
      totalPrice: const Money(1200),
      unitsGeneration: 0,
      assignment: const {
        'type': 'units',
        'schemaVersion': 2,
        'units': {
          'u0': {'p2': true},
          'u1': {'p2': true, 'p3': true},
        },
      },
      scope: '0_0',
    );
    expect(line.confirmedConsumers(0), {'p2'});
    expect(line.confirmedConsumers(1), {'p2', 'p3'});
  });

  test('solo se lee el borrador del alcance VIGENTE', () {
    final line = TicketLine.fromAssignment(
      id: 'l1',
      path: 'p',
      name: 'Cañas',
      quantityMilli: 3000,
      totalPrice: const Money(1200),
      unitsGeneration: 1,
      assignment: const {
        'type': 'units',
        'schemaVersion': 3,
        'units': <String, Object?>{},
        'pending': {
          'p2': {
            '100_0': {'u0': true}, // ciclo/generación anteriores
            '100_1': {'u1': true, 'u2': false},
          },
        },
      },
      scope: '100_1',
    );
    expect(line.draftOf('p2', 0), isNull);
    expect(line.draftOf('p2', 1), isTrue);
    expect(line.draftOf('p2', 2), isFalse);
  });

  test('el estado visible combina confirmado y borrador', () {
    final line = TicketLine.fromAssignment(
      id: 'l1',
      path: 'p',
      name: 'Cañas',
      quantityMilli: 2000,
      totalPrice: const Money(800),
      unitsGeneration: 0,
      assignment: const {
        'type': 'units',
        'schemaVersion': 3,
        'units': {
          'p2': {'u0': true},
        },
        'pending': {
          'p2': {
            '0_0': {'u0': false, 'u1': true},
          },
        },
      },
      scope: '0_0',
    );
    expect(line.confirmedConsumers(0), {'p2'});
    expect(line.draftOf('p2', 0), isFalse); // «pendiente de quitar»
    expect(line.draftOf('p2', 1), isTrue); // «por confirmar»
  });
}
```

`TicketLine.fromAssignment` es un constructor de fábrica nuevo que encapsula el parseo (hoy vive suelto dentro de `watchTicketLines`); moverlo al modelo es lo que permite testear el parseo sin Firestore.

- [ ] **Step 2: Ejecutar y ver fallar**

Run: `flutter test test/consumption_draft_test.dart` (desde `apps/mobile`)
Expected: FAIL — no existe `draft_scope.dart` ni `fromAssignment`.

- [ ] **Step 3: Implementar**

`apps/mobile/lib/features/sessions/domain/draft_scope.dart`:

```dart
/// Alcance de un borrador de consumo (A19).
///
/// Espejo EXACTO de `draftScope()` en firestore.rules: si los dos dejaran de
/// coincidir, el borrador se escribiría en una clave que las reglas no
/// reconocen y cada toque sería un rechazo.
String draftScope({required int cycleMillis, required int generation}) =>
    '${cycleMillis}_$generation';
```

En `session_models.dart`, añadir a `TicketLine` los campos `unitsGeneration` y `draft` (pid → unidad → intención), el constructor `fromAssignment` con la lectura dual, y renombrar `consumersOf` a `confirmedConsumers` conservando `consumersOf` como alias `@Deprecated` solo si algún llamante queda fuera de esta tarea (comprobar con `grep -rn "consumersOf" apps/mobile/lib apps/mobile/test`).

```dart
  /// Consumo confirmado y borrador, leídos de las DOS formas.
  ///
  /// v2 indexa por unidad (`units.u0.p2`) y v3 por persona (`units.p2.u0`).
  /// El resto de la app solo ve el resultado transpuesto: unidad → personas,
  /// que es lo que necesita para pintar y lo que espera el motor.
  factory TicketLine.fromAssignment({
    required String id,
    required String path,
    required String name,
    required int quantityMilli,
    required Money totalPrice,
    required int unitsGeneration,
    required Map<String, Object?> assignment,
    required String scope,
  }) {
    final version = assignment['schemaVersion'] as int?;
    final units = (assignment['units'] as Map?) ?? const {};
    final consumers = <int, Set<String>>{};
    if (version == 3) {
      for (final entry in units.entries) {
        final pid = '${entry.key}';
        for (final unitEntry in ((entry.value as Map?) ?? const {}).entries) {
          final unit = _unitIndex('${unitEntry.key}');
          if (unit == null || unitEntry.value != true) continue;
          (consumers[unit] ??= <String>{}).add(pid);
        }
      }
    } else if (version == 2) {
      for (final entry in units.entries) {
        final unit = _unitIndex('${entry.key}');
        if (unit == null) continue;
        for (final member in ((entry.value as Map?) ?? const {}).entries) {
          if (member.value == true || member.value == 1) {
            (consumers[unit] ??= <String>{}).add('${member.key}');
          }
        }
      }
    }
    final draft = <String, Map<int, bool>>{};
    for (final entry in (((assignment['pending'] as Map?) ?? const {}).entries)) {
      final mine = ((entry.value as Map?) ?? const {})[scope] as Map?;
      if (mine == null) continue;
      for (final unitEntry in mine.entries) {
        final unit = _unitIndex('${unitEntry.key}');
        if (unit == null || unitEntry.value is! bool) continue;
        (draft['${entry.key}'] ??= <int, bool>{})[unit] =
            unitEntry.value as bool;
      }
    }
    return TicketLine(/* … campos … */);
  }

  static int? _unitIndex(String key) =>
      key.startsWith('u') ? int.tryParse(key.substring(1)) : null;
```

En `watchTicketLines`, sustituir el mapeo inline por `TicketLine.fromAssignment(...)`, pasando `unitsGeneration: (line.data()['unitsGeneration'] as int?) ?? 0` y el `scope` que recibe el repositorio (ver Tarea 8: el alcance depende del ciclo, que es del espacio, así que `watchTicketLines` pasa a aceptar `String scope`).

- [ ] **Step 4: Ejecutar los tests**

Run: `flutter test` (desde `apps/mobile`)
Expected: PASS, incluidos `ticket_lines_test.dart` y `unit_assignment_test.dart` existentes.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/sessions/domain/draft_scope.dart apps/mobile/lib/features/sessions/domain/session_models.dart apps/mobile/lib/features/sessions/data/firestore_session_repository.dart apps/mobile/test/consumption_draft_test.dart
git commit -m "$(cat <<'EOF'
A19: la app lee el consumo por persona y el borrador del alcance vigente

- TicketLine.fromAssignment transpone v2 y v3 al mismo mapa unidad→personas.
- El borrador de alcances caducos no se lee: no existe para la interfaz.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: App — escribir borrador, «He terminado» y A10 en v3

**Files:**
- Modify: `apps/mobile/lib/features/sessions/data/firestore_session_repository.dart:475-512`, `apps/mobile/lib/features/sessions/data/session_repository.dart` (interfaz)
- Modify: `apps/mobile/lib/features/sessions/application/session_providers.dart`
- Test: `apps/mobile/test/consumption_draft_test.dart`

**Interfaces:**
- Consumes: `draftScope(...)` (Tarea 7).
- Produces en `SessionRepository`:
  - `Future<void> setUnitDraft(String linePath, {required String participantId, required int unit, required bool? intent, required String scope})` — `null` retira el borrador.
  - `Future<void> finalizeTicketDrafts(String ticketPath, {required String participantId, required String scope, required List<LineDraftPlan> plans})` — **un solo `WriteBatch`**.
  - `Future<void> assignUnit(String linePath, {required String participantId, required int unit, required bool selected, required String scope})` — A10 v3, resuelve el borrador de ese par.
  - `class LineDraftPlan { final String linePath; final Map<int, bool> intents; }`
- Produces en providers: `membershipCycleProvider(spaceId) → AsyncValue<int>` y `draftScopeProvider((spaceId, generation)) → String`.

- [ ] **Step 1: Escribir el test que falla**

Añadir a `consumption_draft_test.dart` (usa `FakeFirebaseFirestore`, patrón de `apps/mobile/test/fakes.dart`):

```dart
  test('un toque escribe una sola clave del borrador', () async {
    final firestore = FakeFirebaseFirestore();
    final repo = FirestoreSessionRepository(firestore: firestore, uid: () => 'uid-jorge');
    await firestore.doc(linePath).set({
      'name': 'Cañas', 'quantityMilli': 3000, 'totalPrice': 1200,
      'unitIds': ['u0', 'u1', 'u2'], 'unitsGeneration': 0,
      'assignment': {'type': 'units', 'schemaVersion': 3, 'units': {}},
    });
    await repo.setUnitDraft(linePath,
        participantId: 'p2', unit: 1, intent: true, scope: '77_0');
    final data = (await firestore.doc(linePath).get()).data()!;
    expect(
      ((data['assignment'] as Map)['pending'] as Map)['p2'],
      {'77_0': {'u1': true}},
    );
    expect((data['assignment'] as Map)['units'], isEmpty);
  });

  test('retirar el borrador borra la clave, no escribe false', () async {
    // …preparar con u1: true…
    await repo.setUnitDraft(linePath,
        participantId: 'p2', unit: 1, intent: null, scope: '77_0');
    final pending = /* … */;
    expect(pending['77_0'], isEmpty);
  });

  test('He terminado escribe UN batch con una escritura por línea', () async {
    final firestore = FakeFirebaseFirestore();
    // …dos líneas con borrador de p2: l1 {u0: true, u1: false}, l2 {u0: true}…
    await repo.finalizeTicketDrafts(
      ticketPath,
      participantId: 'p2',
      scope: '77_0',
      plans: [
        LineDraftPlan(linePath: l1, intents: {0: true, 1: false}),
        LineDraftPlan(linePath: l2, intents: {0: true}),
      ],
    );
    final a1 = ((await firestore.doc(l1).get()).data()!['assignment'] as Map);
    expect((a1['units'] as Map)['p2'], {'u0': true});
    expect(((a1['pending'] as Map)['p2'] as Map)['77_0'], isEmpty);
    final a2 = ((await firestore.doc(l2).get()).data()!['assignment'] as Map);
    expect((a2['units'] as Map)['p2'], {'u0': true});
  });

  test('salir de una unidad se lleva mi firma', () async {
    // …línea con units.p2.u0 = true y by.p2.u0 = 'uid-alba'…
    await repo.finalizeTicketDrafts(ticketPath,
        participantId: 'p2', scope: '77_0',
        plans: [LineDraftPlan(linePath: l1, intents: {0: false})]);
    final a = ((await firestore.doc(l1).get()).data()!['assignment'] as Map);
    expect((a['units'] as Map)['p2'], isEmpty);
    expect((a['by'] as Map)['p2'], isEmpty);
  });

  test('A10: asignar resuelve el borrador de ESE par', () async {
    // …borrador de p2 en u0 y borrador de p3 en u0…
    await repo.assignUnit(l1,
        participantId: 'p2', unit: 0, selected: true, scope: '77_0');
    final a = ((await firestore.doc(l1).get()).data()!['assignment'] as Map);
    expect((a['units'] as Map)['p2'], {'u0': true});
    expect(((a['pending'] as Map)['p2'] as Map)['77_0'], isEmpty);
    expect(((a['pending'] as Map)['p3'] as Map)['77_0'], {'u0': true});
  });
```

- [ ] **Step 2: Ejecutar y ver fallar**

Run: `flutter test test/consumption_draft_test.dart`
Expected: FAIL — los métodos no existen.

- [ ] **Step 3: Implementar los escritores**

```dart
  @override
  Future<void> setUnitDraft(
    String linePath, {
    required String participantId,
    required int unit,
    required bool? intent,
    required String scope,
  }) => firestore.doc(linePath).update({
    'assignment.type': 'units',
    'assignment.schemaVersion': 3,
    'assignment.lastEditorPid': participantId,
    'assignment.lastEditedUnit': 'u$unit',
    // Una clave hoja por toque: dos dispositivos de la misma persona
    // escriben claves distintas y Firestore las fusiona (A19).
    'assignment.pending.$participantId.$scope.u$unit':
        intent ?? FieldValue.delete(),
  });

  @override
  Future<void> finalizeTicketDrafts(
    String ticketPath, {
    required String participantId,
    required String scope,
    required List<LineDraftPlan> plans,
  }) async {
    // UN batch: o entran todas mis decisiones de este ticket, o ninguna.
    // Nunca una finalización económica a medias (A19).
    final batch = firestore.batch();
    for (final plan in plans) {
      if (plan.intents.isEmpty) continue;
      final updates = <String, Object?>{
        'assignment.type': 'units',
        'assignment.schemaVersion': 3,
        'assignment.lastEditorPid': participantId,
        // Sin `lastEditedUnit`: es lo que distingue «he terminado» de una
        // asignación de A10, y las Rules eligen familia con ese dato.
        'assignment.lastEditedUnit': '',
      };
      for (final entry in plan.intents.entries) {
        final unitId = 'u${entry.key}';
        updates['assignment.units.$participantId.$unitId'] =
            entry.value ? true : FieldValue.delete();
        if (!entry.value) {
          // La procedencia se va con la asignación: nunca una firma huérfana.
          updates['assignment.by.$participantId.$unitId'] = FieldValue.delete();
        }
        updates['assignment.pending.$participantId.$scope.$unitId'] =
            FieldValue.delete();
      }
      batch.update(firestore.doc(plan.linePath), updates);
    }
    await batch.commit();
  }

  @override
  Future<void> assignUnit(
    String linePath, {
    required String participantId,
    required int unit,
    required bool selected,
    required String scope,
  }) => firestore.doc(linePath).update({
    'assignment.type': 'units',
    'assignment.schemaVersion': 3,
    'assignment.lastEditorPid': participantId,
    'assignment.lastEditedUnit': 'u$unit',
    'assignment.units.$participantId.u$unit':
        selected ? true : FieldValue.delete(),
    'assignment.by.$participantId.u$unit': selected ? uid() : FieldValue.delete(),
    // La asignación resuelve el borrador de ESE par: queda resuelto, no
    // fantasma. El de otras personas no se toca.
    'assignment.pending.$participantId.$scope.u$unit': FieldValue.delete(),
  });
```

`convertLineToUnitAssignment` pasa a escribir `'assignment.schemaVersion': 3` con `units` vacío (una línea sin asignaciones se convierte sin transponer nada).

Providers nuevos en `session_providers.dart`:

```dart
/// Ciclo de membresía vigente (A11d) en milisegundos, o 0 si quien mira no es
/// miembro del espacio. Espejo de `currentCycle()` en las reglas.
final membershipCycleProvider = FutureProvider.autoDispose
    .family<int, String>((ref, spaceId) async {
      if (spaceId.isEmpty) return 0;
      final uid = ref.watch(currentUserIdFromSpacesProvider);
      if (uid.isEmpty) return 0;
      final member = await FirebaseFirestore.instance
          .doc('spaces/$spaceId/members/$uid')
          .get();
      final joinedAt = member.data()?['joinedAt'] as Timestamp?;
      return joinedAt?.millisecondsSinceEpoch ?? 0;
    });
```

- [ ] **Step 4: Ejecutar los tests**

Run: `flutter test` (desde `apps/mobile`) y `dart analyze --fatal-infos` (desde la raíz)
Expected: PASS y cero avisos.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/sessions apps/mobile/test/consumption_draft_test.dart
git commit -m "$(cat <<'EOF'
A19: escritores del borrador y de «He terminado» en la app

- Un toque = una clave hoja del borrador; «He terminado» = un WriteBatch con
  una escritura por línea, todo o nada.
- Salir de una unidad se lleva la firma de A10; asignar resuelve el borrador
  de ese par y no toca el ajeno.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: App — cabecera del ticket en vivo

**Files:**
- Modify: `apps/mobile/lib/features/sessions/presentation/ticket_navigation.dart:44-49` (`historicTicketProvider`)
- Modify: `apps/mobile/lib/features/sessions/data/firestore_session_repository.dart:347-382` (`fetchHistoricTicket` → `watchHistoricTicket`)
- Test: `apps/mobile/test/ticket_navigation_test.dart`

**Interfaces:**
- Consumes: nada.
- Produces: `Stream<HistoricTicket?> watchHistoricTicket(String sessionId, String ticketId)` y `historicTicketProvider` como `StreamProvider`.

**Por qué aquí:** el alcance del borrador depende de `unitsGeneration` (línea, ya en vivo) y el selector depende de `splitModeOverride` (ticket). Hoy el ticket llega por una lectura única: `sessionTicketProvider` prefiere `historicTicketProvider`, y recompute concede `ticketEntitlements/{tid}_{uid}` a todo el que participa económicamente, así que **para casi todos el ticket de la pantalla es un snapshot congelado**. Con A19, un cambio de modo dejaría un selector operable en falso.

- [ ] **Step 1: Escribir el test que falla**

```dart
  testWidgets('el detalle refleja un cambio de modo sin reabrir', (tester) async {
    final firestore = FakeFirebaseFirestore();
    // …sembrar sesión, entitlement, cuenta y ticket con splitModeOverride byItem…
    await tester.pumpWidget(/* TicketRoute con overrides de repositorio */);
    await tester.pumpAndSettle();
    expect(find.text('Elige lo que has consumido'), findsOneWidget);

    await firestore.doc(ticketPath).update({'splitModeOverride': 'equal'});
    await tester.pumpAndSettle();
    expect(find.text('Elige lo que has consumido'), findsNothing);
  });
```

(Ajustar los textos a las claves ARB reales: `l10n.ticketPickHint` / `l10n.ticketSplitEqualHint`.)

- [ ] **Step 2: Ejecutar y ver fallar**

Run: `flutter test test/ticket_navigation_test.dart`
Expected: FAIL — el ticket no se actualiza.

- [ ] **Step 3: Implementar**

Convertir la lectura del ticket en stream conservando la lectura única del derecho:

```dart
  @override
  Stream<HistoricTicket?> watchHistoricTicket(String sessionId, String ticketId) {
    final viewer = uid();
    if (viewer.isEmpty) return Stream.value(null);
    // El DERECHO es un hecho que no cambia mientras la pantalla está abierta
    // (proyección monótona, A11d): una lectura. El TICKET sí cambia —modo de
    // reparto, comercio, total— y por eso se observa.
    return Stream.fromFuture(
      _sessions
          .doc(sessionId)
          .collection('ticketEntitlements')
          .doc('${ticketId}_$viewer')
          .get(),
    ).asyncExpand((entitlement) {
      final data = entitlement.data();
      final accountId = data?['accountId'] as String?;
      if (data == null || accountId == null || accountId.isEmpty) {
        return Stream.value(null);
      }
      return _sessions
          .doc(sessionId)
          .collection('accounts')
          .doc(accountId)
          .collection('tickets')
          .doc(ticketId)
          .snapshots()
          .map((ticket) => !ticket.exists
              ? null
              : HistoricTicket(
                  ticket: _ticketFrom(ticket),
                  participantNames: { /* …igual que antes… */ },
                ));
    });
  }
```

y en `ticket_navigation.dart`, `historicTicketProvider` pasa a `StreamProvider.autoDispose.family`. `sessionTicketProvider` no cambia de forma.

- [ ] **Step 4: Ejecutar los tests**

Run: `flutter test` (desde `apps/mobile`)
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/sessions
git commit -m "$(cat <<'EOF'
A19: la cabecera del ticket deja de ser un snapshot congelado

- watchHistoricTicket observa el documento del ticket: el modo de reparto,
  el comercio y el total se refrescan sin reabrir la pantalla. El derecho
  histórico sigue siendo una sola lectura.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: App — interfaz del borrador y «He terminado»

**Files:**
- Modify: `apps/mobile/lib/features/sessions/presentation/ticket_detail_screen.dart`, `unit_assignment_sheet.dart`
- Modify: `apps/mobile/lib/l10n/app_es.arb` (+ `flutter gen-l10n`)
- Test: `apps/mobile/test/unit_assignment_test.dart`, `apps/mobile/test/consumption_draft_test.dart`

**Interfaces:**
- Consumes: `TicketLine.confirmedConsumers`, `TicketLine.draftOf`, `setUnitDraft`, `finalizeTicketDrafts`, `draftScopeProvider`.
- Produces: nada para tareas posteriores.

**Vocabulario (cerrado por el usuario, va tal cual al ARB):**
- `Sin asignar` — nadie.
- Nombres sin calificativo — consumo confirmado.
- `Por confirmar: Jorge` — borrador de entrada.
- `Pendiente de quitar: Jorge` — borrador de salida.
- Estado mixto: **no** se construye una frase combinatoria; confirmados y pendientes se muestran como dos informaciones separadas en la fila.

- [ ] **Step 1: Escribir los tests que fallan**

```dart
  testWidgets('un toque no mueve dinero: escribe borrador y muestra "por confirmar"',
      (tester) async { /* … */ });

  testWidgets('la fila muestra confirmados y pendientes por separado',
      (tester) async {
    // units.p3.u0 = true, pending.p2.<scope>.u0 = true
    // Espera: 'Edgar' visible como confirmado y 'Por confirmar: Jorge' aparte.
  });

  testWidgets('«He terminado» aparece solo con borrador y confirma el ticket entero',
      (tester) async { /* … */ });

  testWidgets('cada unidad expone su estado a accesibilidad', (tester) async {
    // Semantics(label: 'Unidad 2, por confirmar, Jorge', button: true)
  });
```

- [ ] **Step 2: Ejecutar y ver fallar**

Run: `flutter test test/unit_assignment_test.dart test/consumption_draft_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implementar**

1. En la fila de unidades: el toque llama a `setUnitDraft` con la intención **contraria al estado efectivo** (`draftOf(pid, unit) ?? confirmedConsumers(unit).contains(pid)`), y si la intención coincide con lo confirmado, retira el borrador (`intent: null`) en vez de escribir un no-cambio.
2. Cabecera de línea: `N unidades · X,XX € c/u`, con el precio unitario derivado de `totalPrice / units` (el campo `unitPrice` se pierde al corregir; no fiarse de él).
3. Botón «He terminado» por ticket, visible solo si hay borrador propio; muestra cuántas decisiones sin confirmar hay («3 sin confirmar»), que es la mitigación del riesgo «creí que ya estaba».
4. Reemplazar los `FilterChip` numerados por filas verticales `nº · estado · personas` (una lista compacta escala mejor a 10–24 unidades y soporta el copy largo; sin virtualización).
5. `Semantics` por unidad con etiqueta y estado; los `Tooltip` actuales no son etiqueta accesible.
6. Aviso de compartir portado de la web (`PickItems.svelte:requestUnit` + `needsShareConfirmation`).
7. ARB: `unitStateUnassigned`, `unitStateToConfirm`, `unitStatePendingRemoval`, `finishPickingButton`, `finishPickingCount`, `unitSemanticsLabel`.

- [ ] **Step 4: Ejecutar**

Run: `flutter gen-l10n` y luego `flutter test` (desde `apps/mobile`); `dart analyze --fatal-infos` en la raíz.
Expected: PASS y cero avisos. **Los goldens que cambien hay que regenerarlos y revisarlos visualmente** (`flutter test --update-goldens` solo tras comprobar el cambio).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib apps/mobile/test
git commit -m "$(cat <<'EOF'
A19: elegir consumo es un borrador hasta pulsar «He terminado»

- La fila de unidades separa lo confirmado de lo pendiente (por confirmar /
  pendiente de quitar) y expone el estado a accesibilidad.
- Contador de decisiones sin confirmar: nadie se va creyendo que ya está.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Web — borrador, «He terminado» y ticket en vivo

**Files:**
- Modify: `apps/guest_web/src/lib/assignment.ts`, `apps/guest_web/src/lib/session.svelte.ts:320-364`, `apps/guest_web/src/views/PickItems.svelte`
- Test: `apps/guest_web/src/lib/assignment.test.ts`

**Interfaces:**
- Consumes: contrato de la Tarea 1 (mismas claves que la app).
- Produces: `unitConsumers(assignment, unit)` con lectura dual, `draftUpdate(unit, pid, scope, intent, remove)`, `finalizeUpdate(pid, scope, intents, remove)`, `draftScope(cycleMillis, generation)`.

**Nota de identidad:** el invitado por enlace **no es miembro** del espacio, así que su ciclo es `0` (igual que en Rules). La generación la lee de la línea (`unitsGeneration`), que ya llega por el listener de líneas.

- [ ] **Step 1: Escribir los tests que fallan**

```typescript
describe('A19: borrador de consumo', () => {
  it('lee el consumo confirmado en las dos formas', () => {
    const v2 = { type: 'units', schemaVersion: 2, units: { u0: { p2: true } } };
    const v3 = { type: 'units', schemaVersion: 3, units: { p2: { u0: true } } };
    expect(unitConsumers(v2 as never, 0)).toEqual(['p2']);
    expect(unitConsumers(v3 as never, 0)).toEqual(['p2']);
  });

  it('un toque escribe una sola clave hoja', () => {
    expect(draftUpdate(1, 'p2', '0_0', true, DEL)).toEqual({
      'assignment.type': 'units',
      'assignment.schemaVersion': 3,
      'assignment.lastEditorPid': 'p2',
      'assignment.lastEditedUnit': 'u1',
      'assignment.pending.p2.0_0.u1': true,
    });
  });

  it('retirar el borrador borra la clave', () => {
    expect(draftUpdate(1, 'p2', '0_0', null, DEL)['assignment.pending.p2.0_0.u1'])
      .toBe(DEL);
  });

  it('finalizar mueve mi rama y limpia mi borrador, sin declarar unidad', () => {
    expect(finalizeUpdate('p2', '0_0', { 0: true, 2: false }, DEL)).toEqual({
      'assignment.type': 'units',
      'assignment.schemaVersion': 3,
      'assignment.lastEditorPid': 'p2',
      'assignment.lastEditedUnit': '',
      'assignment.units.p2.u0': true,
      'assignment.pending.p2.0_0.u0': DEL,
      'assignment.units.p2.u2': DEL,
      'assignment.by.p2.u2': DEL,
      'assignment.pending.p2.0_0.u2': DEL,
    });
  });

  it('el borrador solo se lee del alcance vigente', () => {
    const a = {
      type: 'units', schemaVersion: 3, units: {},
      pending: { p2: { '0_0': { u0: true }, '0_1': { u1: true } } },
    };
    expect(draftOf(a as never, 'p2', '0_1')).toEqual({ 1: true });
  });
});
```

- [ ] **Step 2: Ejecutar y ver fallar**

Run: `npm --prefix apps/guest_web test`
Expected: FAIL.

- [ ] **Step 3: Implementar**

En `assignment.ts`: ampliar `Assignment` con `pending?: Record<string, Record<string, Record<string, boolean>>>` y el `units` de v3; `unitConsumers` con lectura dual por `schemaVersion`; añadir `draftScope`, `draftOf`, `draftUpdate`, `finalizeUpdate`. `unitUpdate` (v2) se conserva hasta la Tarea 13.

En `session.svelte.ts`:
- añadir `unitsGeneration` a `LineInfo` y el alcance calculado (`draftScope(0, line.unitsGeneration)`);
- el toque llama a `draftUpdate`;
- `finishPicking()` construye **un `writeBatch`** con una escritura por línea con borrador y hace `commit()`;
- en `loadTickets`, junto al listener de líneas que ya existe, añadir `onSnapshot(ticket.ref, …)` que actualice `pickable` (y de paso `merchantName`/`grandTotal`), para que un cambio de `splitModeOverride` no deje el selector operable en falso. **No** entra el alta de tickets nuevos ni Home: fuera de alcance.

En `PickItems.svelte`: los tres estados, el botón «He terminado» con el contador y el aviso de compartir que ya existe.

- [ ] **Step 4: Ejecutar**

Run: `npm --prefix apps/guest_web test` · `npm --prefix apps/guest_web run check` · `npm --prefix apps/guest_web run build`
Expected: PASS, `svelte-check` a cero y el presupuesto de peso de CI (`scripts/check-size.mjs`, 220 KB gzip) sin dispararse.

- [ ] **Step 5: Commit**

```bash
git add apps/guest_web
git commit -m "$(cat <<'EOF'
A19: la web de invitados usa el mismo borrador que la app

- Lectura dual v2/v3, toque = una clave hoja, «He terminado» = un batch.
- El documento del ticket se observa: cambiar el modo de reparto ya no deja
  un selector operable en falso.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: Transposición lossless v2 → v3 (migración e importación de backups)

**Files:**
- Create: `backend/functions/tools/migrate-assignments-v3.mjs`
- Modify: `apps/mobile/lib/features/settings/data/backup_service.dart:238-245`
- Test: `backend/functions/src/test/recompute.test.ts` (transpositor puro), `apps/mobile/test/backup_service_test.dart`

**Interfaces:**
- Consumes: nada.
- Produces: `transposeAssignmentToV3(assignment) → assignment` (misma función, dos implementaciones: una en el script Node, otra en Dart para el import; ambas con el mismo caso de prueba).

**Por qué un script y no una Function:** transponer exige leer el mapa entero y escribirlo invertido; Rules no puede verificar esa igualdad sin enumerar, así que un cliente no puede hacerlo de forma verificable. El Admin SDK sí, y no añade infraestructura: es una herramienta que se ejecuta una vez, como `tools/seed-emulator.mjs`.

- [ ] **Step 1: Escribir el test que falla**

```typescript
test('transposición v2 → v3: lossless en units y en by', () => {
  const v2 = {
    type: 'units',
    schemaVersion: 2,
    units: { u0: { p2: true }, u1: { p2: true, p3: true } },
    by: { u1: { p3: 'uid-alba' } },
    lastEditorPid: 'p2',
    lastEditedUnit: 'u1',
  };
  assert.deepEqual(transposeAssignmentToV3(v2), {
    type: 'units',
    schemaVersion: 3,
    units: { p2: { u0: true, u1: true }, p3: { u1: true } },
    by: { p3: { u1: 'uid-alba' } },
    lastEditorPid: 'p2',
    lastEditedUnit: 'u1',
  });
});

test('transposición: idempotente sobre una línea que ya es v3', () => {
  const v3 = { type: 'units', schemaVersion: 3, units: { p2: { u0: true } } };
  assert.deepEqual(transposeAssignmentToV3(v3), v3);
});

test('transposición: una selección falsa no se convierte en consumo', () => {
  const v2 = { type: 'units', schemaVersion: 2, units: { u0: { p2: false } } };
  assert.deepEqual(transposeAssignmentToV3(v2).units, {});
});

test('transposición: el modelo histórico por pesos no se toca', () => {
  const legacy = { type: 'shared', participants: { p2: 2 } };
  assert.deepEqual(transposeAssignmentToV3(legacy), legacy);
});

test('transposición: una selección escrita como 1 se normaliza a true', () => {
  // La app histórica aceptaba `1` además de `true` al leer (P2.2). Si se
  // copiara tal cual, `units[pid][unit] == true` dejaría de cumplirse en
  // Rules y esa persona no podría retirar su propio consumo.
  const v2 = { type: 'units', schemaVersion: 2, units: { u0: { p2: 1 } } };
  assert.deepEqual(transposeAssignmentToV3(v2).units, { p2: { u0: true } });
});

test('transposición: un pid desconocido se CONSERVA (esto no interpreta, transpone)', () => {
  const v2 = {
    type: 'units', schemaVersion: 2,
    units: { u0: { fantasma: true } },
  };
  assert.deepEqual(transposeAssignmentToV3(v2).units, { fantasma: { u0: true } });
});

test('transposición: una firma sin asignación detrás se descarta y se reporta', () => {
  // A10 no permite crearlas, pero si un documento antiguo la trae, copiarla
  // rompería el invariante `by[pid] ⊆ units[pid]` y dejaría a esa persona sin
  // poder escribir NADA en la línea.
  const v2 = {
    type: 'units', schemaVersion: 2,
    units: { u0: { p2: true } },
    by: { u0: { p2: 'uid-alba', p3: 'uid-alba' } },
  };
  const r = transposeAssignmentToV3(v2);
  assert.deepEqual(r.units, { p2: { u0: true } });
  assert.deepEqual(r.by, { p2: { u0: 'uid-alba' } });
  assert.deepEqual(r.dropped, [{ pid: 'p3', unitId: 'u0', reason: 'firma sin asignación' }]);
});

test('transposición: v2 no tiene borrador, y no se inventa', () => {
  const v2 = { type: 'units', schemaVersion: 2, units: { u0: { p2: true } } };
  assert.equal('pending' in transposeAssignmentToV3(v2), false);
});

test('transposición: un assignment con forma inesperada NO se convierte', () => {
  // schemaVersion 2 y tipo que no es `units`: no existe por construcción.
  // Convertirlo a ciegas sería reinterpretar economía. Se deja igual y se
  // reporta para mirarlo a mano.
  const raro = { type: 'shared', schemaVersion: 2, participants: { p2: 1 } };
  assert.deepEqual(transposeAssignmentToV3(raro), raro);
});
```

Y en el script, sobre la línea completa (no solo el `assignment`):

```javascript
test('la línea migrada recibe unitIds y unitsGeneration cuando le faltan', () => {
  // Sin `unitIds`, Rules aplica el valor por defecto `['u0']`: una línea de 3
  // cañas quedaría con consumo confirmado en unidades que la regla de
  // finalizar considera inexistentes, y esa persona no podría confirmar nada.
  const linea = {
    name: 'Cañas', quantityMilli: 3000, totalPrice: 1200,
    assignment: { type: 'units', schemaVersion: 2, units: { u2: { p2: true } } },
  };
  assert.deepEqual(migrateLine(linea), {
    ...linea,
    unitIds: ['u0', 'u1', 'u2'],
    unitsGeneration: 0,
    assignment: { type: 'units', schemaVersion: 3, units: { p2: { u2: true } } },
  });
});

test('una cantidad rara (no entera o < 2) es UNA unidad, y sus unitIds son ["u0"]', () => {
  // Espejo exacto de SplitLine.unitsFromQuantityMilli: 0,466 kg no son 466
  // unidades, es una.
  const linea = {
    name: 'Fruta', quantityMilli: 466, totalPrice: 300,
    assignment: { type: 'units', schemaVersion: 2, units: { u0: { p2: true } } },
  };
  assert.deepEqual(migrateLine(linea).unitIds, ['u0']);
});

test('una línea con unitIds que no cubren su consumo se REPORTA y no se migra', () => {
  const linea = {
    name: 'Cañas', quantityMilli: 2000, totalPrice: 800,
    unitIds: ['u0', 'u1'],
    assignment: { type: 'units', schemaVersion: 2, units: { u7: { p2: true } } },
  };
  assert.equal(migrateLine(linea), null); // null = «no toco esto, mírala tú»
});

test('migrar dos veces no cambia nada', () => {
  const linea = {
    name: 'Cañas', quantityMilli: 2000, totalPrice: 800,
    unitIds: ['u0', 'u1'], unitsGeneration: 0,
    assignment: { type: 'units', schemaVersion: 2, units: { u0: { p2: true } } },
  };
  const una = migrateLine(linea);
  assert.equal(migrateLine(una), null); // ya está en v3: nada que hacer
});
```

- [ ] **Step 2: Ejecutar y ver fallar**

Run: `npm --prefix backend/functions test`
Expected: FAIL.

- [ ] **Step 3: Implementar el transpositor y el script**

`transposeAssignmentToV3` en `backend/functions/src/recompute.ts` (exportada, junto a `sanitizeLine`) y el script:

```javascript
#!/usr/bin/env node
/**
 * MIGRACIÓN DE UN SOLO USO. No es una vía de escritura del producto.
 *
 * Transpone las líneas `assignment.schemaVersion: 2` a `3` (A19). No
 * reinterpreta economía: quien consumía una unidad la sigue consumiendo y
 * cada firma de A10 viaja con su par.
 *
 * Salvaguardas, todas obligatorias:
 *  - SIMULA POR DEFECTO. Sin `--apply` no escribe una sola línea.
 *  - Exige `--project` explícito y ABORTA si el proyecto contiene `prod`
 *    (`salda-prod` es una frontera dura del repositorio) o si no está en la
 *    lista blanca `['demo-salda', 'salda-dev']`.
 *  - Idempotente: una segunda pasada reporta 0 cambios.
 *  - Verifica cada línea antes de darla por buena (transpone de vuelta y
 *    compara); si una no cuadra, NO la escribe, la reporta y termina con
 *    código 1 sin tocar el resto del lote.
 *  - Lo que no entiende, no lo toca: lo lista para revisión humana.
 *  - Nadie la importa. Vive en tools/ como `seed-emulator.mjs` y ningún
 *    código de producción la referencia; si alguna vez hiciera falta
 *    convertir en caliente, eso es otra decisión y otro documento.
 *
 *   node backend/functions/tools/migrate-assignments-v3.mjs --project demo-salda
 *   node backend/functions/tools/migrate-assignments-v3.mjs --project salda-dev --apply
 */
```

Recorre `collectionGroup('lines')`, filtra `assignment.schemaVersion == 2`, escribe en lotes de 400 **solo con `--apply`**, y termina imprimiendo cuatro cifras: migrables, migradas, ya en v3, y **no tocadas por forma inesperada** (con su ruta completa, para mirarlas a mano). El criterio de éxito de la migración es `no tocadas == 0`.

**Prohibido en esta herramienta:** borrar documentos, tocar `sessions/*` fuera de `lines`, escribir agregados, regenerar `shareCode`, o aceptar un flag que salte la verificación.

En `backup_service.dart`, el import transpone antes de escribir cada línea: así, restaurar un backup antiguo nunca reintroduce v2.

- [ ] **Step 4: Ejecutar**

Run: `npm --prefix backend/functions test` · `flutter test test/backup_service_test.dart` · el script contra el emulador con datos sembrados (`node backend/functions/tools/seed-emulator.mjs` y luego el script con `--dry-run` y sin él).
Expected: PASS; el script deja las líneas en v3 y una segunda pasada no cambia nada.

- [ ] **Step 5: Commit**

```bash
git add backend/functions/tools/migrate-assignments-v3.mjs backend/functions/src/recompute.ts backend/functions/src/test/recompute.test.ts apps/mobile/lib/features/settings/data/backup_service.dart apps/mobile/test/backup_service_test.dart
git commit -m "$(cat <<'EOF'
A19: transposición lossless de v2 a v3

- Herramienta Admin idempotente con verificación de ida y vuelta: nadie
  cambia de consumo ni pierde su procedencia al migrar.
- Importar un backup antiguo transpone: v2 no vuelve a entrar por esa vía.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: Dejar de PRODUCIR v2 y verificación integral

**Qué significa exactamente esta tarea** (y qué no):

| Se retira | Se queda para siempre |
|---|---|
| `canPickOwnUnit` y `canAssignWithProvenance` (familias que **escriben** v2) | La **lectura** de v2 en `sanitizeLine`, `TicketLine.fromAssignment` y `unitConsumers` — es la red de los backups antiguos |
| `setUnitConsumer` (app) y `unitUpdate` (web): los **escritores** v2 | La transposición del import de backups (T12) |
| La rama v2 del `allow update` de reparto | **Todo el modelo histórico por pesos** (`type: shared/one/all`, `canPickOwnShare`, `setLineAssignment`, `convertLineToUnitAssignment`): sigue vivo y escribible, no es v2-por-unidades y esta tarea no lo toca |
| — | `unitsOnlyPruned`, **si** sigue siendo la que valida la poda del modelo histórico. Solo se retira la parte que atendía a v2-por-unidades; comprobar sus llamantes con `grep -n "unitsOnlyPruned" backend/firestore/firestore.rules` antes de tocar nada |

**Files:**
- Modify: `backend/firestore/firestore.rules`
- Modify: `backend/firestore/test/unit_assignment.test.mjs` (los casos de ESCRITURA v2 pasan a esperar denegación; los de lectura y los del modelo por pesos siguen igual)
- Modify: `apps/guest_web/src/lib/assignment.ts`, `apps/mobile/.../firestore_session_repository.dart`

**Requisitos previos, los dos:**
1. La Tarea 12 ejecutada con `--apply` contra `salda-dev` y una pasada posterior en simulación que reporte **0 migrables y 0 no tocadas**.
2. La app y la web nuevas instaladas/desplegadas en **todos** los dispositivos en uso. Una build vieja que escriba v2 se queda rota en cuanto esta tarea entra; hoy son los dispositivos del usuario, así que basta con confirmarlo con él. **Si no puedes confirmarlo, esta tarea NO se hace y el plan termina en la Tarea 12** — el sistema queda perfectamente funcional con las dos familias vivas.

- [ ] **Step 1: Confirmar que no queda v2 y que no hay builds viejas**

Run: `node backend/functions/tools/migrate-assignments-v3.mjs --project salda-dev`
Expected: `0 migrables · 0 no tocadas`. Y preguntar al usuario, explícitamente, si queda algún dispositivo con la app anterior. Si la respuesta no es un no rotundo, **para aquí**.

- [ ] **Step 2: Cambiar los tests v2 a «denegado»**

En `unit_assignment.test.mjs`, el `describe` de v2 pasa a comprobar que una escritura de reparto sobre una línea v2 se **deniega limpiamente** (la lectura sigue funcionando: recompute y ambos clientes la entienden).

- [ ] **Step 3: Retirar las familias v2 de Rules y los escritores v2 de los clientes**

Dejar intacta la **lectura** dual en `sanitizeLine`, `TicketLine.fromAssignment` y `unitConsumers`: es la red de seguridad de los backups y no cuesta presupuesto.

- [ ] **Step 4: Verificación completa de todas las fases**

```bash
dart analyze --fatal-infos
dart test --directory packages/domain
dart test --directory packages/ocr_parser
flutter test            # desde apps/mobile
npm --prefix apps/guest_web run build
npm --prefix backend/functions test
firebase emulators:exec --only firestore,storage --project demo-salda "npm --prefix backend/firestore test"
```

Expected: todo verde. **Los vectores dorados y los tests de los motores tienen que estar intactos**: si alguno ha cambiado, se ha tocado economía y hay que revertirlo.

- [ ] **Step 5: Prueba manual en dispositivo (la que no se puede automatizar)**

Guion, con dos cuentas reales en `salda-dev`, escrito como checklist en el PR:

1. Ticket con una línea de 12 unidades. Marcar 8 unidades: **el balance no se mueve** en ninguno de los dos dispositivos.
2. «He terminado»: el balance se mueve **una sola vez** y los dos dispositivos lo ven.
3. **Offline**: activar modo avión, marcar 4 unidades en 3 líneas distintas, pulsar «He terminado». La pantalla debe mostrar el estado optimista coherente (confirmado local). Reconectar: el batch entra **entero**. Comprobar en la consola de Firestore que las tres líneas cambiaron en el mismo instante y que `recompute` corrió una vez.
4. **Offline con rechazo**: repetir con la sesión cerrada por la otra cuenta mientras se está sin red. Al reconectar, el batch debe ser rechazado **entero** y la interfaz volver al estado del servidor: ninguna línea confirmada a medias.
5. Admin asigna una unidad con borrador ajeno encima: el borrador de esa persona en ESE par desaparece, el de los demás no.
6. Expulsar y readmitir a alguien con borrador: al volver, su borrador no reaparece.
7. Corregir la cantidad de una línea con borrador: el borrador de esa línea deja de aplicarse; renombrarla no lo toca.

**Si el punto 3 o el 4 fallan, PARA y consulta.** Es la única condición que las sondas no han podido cubrir y la que decidiría si hace falta el fallback de servidor (opción B).

- [ ] **Step 6: Commit**

```bash
git add backend/firestore apps/mobile apps/guest_web
git commit -m "$(cat <<'EOF'
A19: retirar la escritura del modelo por unidad

- Tras migrar salda-dev, el reparto se escribe solo en v3. La lectura de v2
  se conserva en recompute y en ambos clientes para los backups antiguos.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**Cobertura de las condiciones del usuario:**

| Condición | Dónde |
|---|---|
| 1. La inversión resuelve también `by`, en O(1) | Tarea 4 (`signaturesWithinConsumption`, `personBranchOnly`) y Tarea 6 (`addedKeys`/`changedKeys` a cero); tests de firma huérfana, firma ajena y autofirma |
| 2. Contrato person-first + draft con alcance + sin enumeración | Tarea 1 (contrato), Tareas 4–6 (Rules), constraint global «expresiones constantes» |
| 3. v2 en lectura + conversión lossless, sin dos motores permanentes | Tarea 2 (lectura), Tarea 12 (transposición: `by`, `1`→`true`, pids desconocidos, firmas huérfanas, `unitIds` ausentes, cantidades no enteras, formas inesperadas), Tarea 13 (solo deja de PRODUCIR v2; la lectura y el modelo por pesos se quedan) |
| Rollout sin capas incompatibles | §Orden de despliegue: recompute lee v3 → Rules aceptan v3 → clientes escriben v3 → transposición → cero v2 → retirada |
| 4. Offline probado, nunca finalización parcial | Tarea 13 pasos 5.3 y 5.4, con parada obligatoria si falla |
| Sin cap de producto | Constraint global + Tarea 6 (test de 12 unidades y batch de 12 líneas) |
| Motores y vectores dorados intactos | Constraint global + comprobación explícita en Tareas 2 y 13 |

**Coherencia de nombres entre tareas:** `draftScope` (Dart, TS y Rules), `pending.{pid}.{scope}.{unitId}`, `units.{pid}.{unitId}`, `by.{pid}.{unitId}`, `unitsGeneration`, `setUnitDraft`/`finalizeTicketDrafts`/`assignUnit` (app), `draftUpdate`/`finalizeUpdate` (web), `canPickOrAssignUnitV3`/`canDraftOwnUnitV3`/`canFinalizeOwnBranchV3`/`generationIsCoherent`/`personUnitsOnlyPruned` (Rules).

**Puntos donde el plan obliga a parar y consultar:**
1. Si la poda A11c sobre v3 no se puede validar sin enumerar personas (Tarea 6, paso 3).
2. Si aparece cualquier techo de presupuesto en las familias v3 (constraint global).
3. Si el offline no da todo-o-nada (Tarea 13, paso 5).
