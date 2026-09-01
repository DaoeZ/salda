# A19 — Cierre de consumo (`picking.open`) · Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** que un gasto repartido por líneas no entre en las cuentas hasta que todas las personas implicadas hayan dicho «he terminado», y que cualquier cambio posterior de consumo reabra automáticamente esa declaración.

**Architecture:** dos campos nuevos en el documento del ticket (`pickingModelVersion: 1` y `picking: { open, lastTarget, fingerprint }`). `picking.open` es el mapa de quien todavía no ha terminado; un ticket `byItem` es económicamente firme cuando ese mapa, filtrado por participantes activos, está vacío. Las Rules exigen —con **un único** `getAfter`— que toda escritura de reparto deje abierto al pid afectado, así que un «he terminado» obsoleto es imposible. `recompute` filtra los tickets no firmes antes de repartir y reabre por su cuenta cuando cambia la huella de topología. `assignment` no cambia ni un byte, no hay motor económico nuevo y no hay Functions nuevas: `recomputeOnTicket` y `recomputeOnLine` ya cubren ambas escrituras.

**Tech Stack:** Firestore Security Rules · Cloud Functions v2 TypeScript (solo `recompute`, ya existente) · Flutter + Riverpod v3 · Svelte 5 + TS · `@firebase/rules-unit-testing` + Emulator Suite · `fake_cloud_firestore` · vitest · `node --test`.

**Spec:** este plan implementa el modelo aprobado por el usuario el 2026-08-31 sobre las mediciones de las dos rondas de investigación A19, resumidas en «Mediciones que sostienen este plan». El contrato vivo se escribe en la Tarea 14 (`docs/CIERRE_DE_CONSUMO.md`); desde ahí, plan y contrato se leen juntos. El documento exploratorio `docs/superpowers/plans/2026-08-30-a19-borrador-de-consumo-v3.md` queda **derogado**: ninguna de sus decisiones aplica.

## Global Constraints

- **Idioma:** UI y documentación en español (ARB); código, identificadores y nombres de archivo en inglés. Comentarios en español explicando el PORQUÉ, no el qué.
- **Commits:** en español, imperativos, prefijo `A19: …`, cuerpo con viñetas y SIEMPRE la línea `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`. **Nunca `git push`, `firebase deploy` ni tocar `salda-prod` sin petición explícita del usuario en ese turno.**
- **Nunca un commit en rojo.** Si dos tareas no pueden quedar verdes por separado, van en un solo commit (indicado en cada tarea).
- **Dinero:** céntimos `int` envueltos en `Money`. JAMÁS `double`.
- **Los motores no se tocan:** `SplitEngine`, `BalanceEngine`, `EconomicLedger` y los vectores dorados (`packages/domain/test/golden/*.json`) quedan **intactos**. A19 solo decide QUÉ tickets entran en el cálculo, nunca CÓMO se calcula. Si una tarea parece obligar a tocar un motor o un vector dorado, PARA (Gate 3).
- **`assignment` no cambia:** ni forma, ni `schemaVersion`, ni `units`, ni `by`. Prohibido `schemaVersion: 3`, `pending` por unidad, generaciones, `unitIds` generacionales, mapas invertidos y colecciones auxiliares de picking.
- **Un solo motor económico firme.** Prohibido `provisional.balances` y cualquier segunda proyección global.
- **Presupuesto de Rules:** la rama de reparto por unidades admite **UN** acceso de documento adicional (`getAfter`) y ni uno más. Está medido: con dos, el camino de A10 devuelve `maximum of 1000 expressions`. Toda denegación nueva se prueba con el helper `assertDeniegaLimpio`.
- **`maxInstances: 3` y `europe-west1`** en `setGlobalOptions` (`backend/functions/src/index.ts:15-19`) no se tocan.
- **Sin migración de datos históricos.** Un ticket sin `pickingModelVersion: 1` se comporta exactamente como hoy, para siempre.
- **Verificación por fase** (todas, antes de cerrar cualquier tarea que toque su área):
  - `dart analyze --fatal-infos` (raíz)
  - `dart test` en `packages/domain` y `packages/ocr_parser`
  - `flutter test` en `apps/mobile`
  - `npm test` en `backend/functions`
  - `npm run build` en `apps/guest_web`
  - Reglas: `firebase emulators:exec --only firestore,storage --project demo-salda "npm --prefix backend/firestore test"`
  - Integración de functions: `firebase emulators:exec --only firestore --project demo-salda "npm --prefix backend/functions run test:integration"`

---

## Mediciones que sostienen este plan (no repetir la investigación)

| Hecho | Cómo se midió |
|---|---|
| Las escrituras punteadas por par (unidad, persona) **no se pisan**: dos personas, dos dispositivos del mismo uid, ráfagas de 8 y offline con reconexión conservan todo | sonda `a19_reset`, casos A–F |
| Un `WriteBatch` con **dos mutaciones al mismo documento** se deniega ya con n=2 | sonda `a19_reset`, caso K |
| Un `WriteBatch` con **dos documentos distintos** (línea + ticket) es PERMITIDO | sonda `a19_cierre_b`, caso 1 |
| Rules **puede** exigir la reapertura en el mismo commit vía `getAfter` | sonda `a19_cierre_b`, casos 2–4 |
| Con **dos** accesos al ticket (`get` + `getAfter`) el camino de A10 agota el presupuesto | sonda `a19_cierre`, caso 3: `maximum of 1000 expressions` |
| Con **un** `getAfter` todo pasa: A10 a un manual, invitada web, 24 unidades seguidas, denegaciones limpias | sonda `a19_cierre_b`, casos 3, 4, 7, 8 |
| Ticket **sin** `pickingModelVersion` se comporta como hoy | sonda `a19_cierre_b`, caso 5 |
| Cliente antiguo + pid abierto → permitido; cliente antiguo + pid cerrado → denegado limpio | sonda `a19_cierre_b`, casos 6 y 2 |
| Poda de A11c **con** reapertura en el mismo batch: PERMITIDO | sonda `a19_cierre_b`, caso 9 |
| Si la obligación de un ticket cobrado desaparece, el modelo la lee como sobrepago y **fabrica una liquidación inversa accionable** | sonda `a19_reapertura`, P3: aparece `pending_p1_p2 = 5000` sin que nadie lo pida. Es la razón de `firmContribution` |
| Un pago `confirmed` nunca se pierde ni se falsifica al recalcular | sonda `a19_reapertura`, P2→P3: la confirmada y su `economicPayments/legacy_…` quedan intactas |
| `BalanceEngine` **lanza** si el consumo no suma el total (`consumptionMismatch`) o si un pid no está en el universo (`unknownParticipant`) | `balance_engine.dart:113-130` y `:141-148`, espejo en `balanceEngine.ts:89-95` |
| Desactivar a alguien con una liquidación **confirmada** hace que `computeAggregates` **lance** y la sesión entera deje de recalcularse. **Ocurre hoy, sin A19** | sonda `a19_inactivo`, caso 2: `unknownParticipant Liquidación congelada con participante desconocido` |
| Sanear la contribución congelada doblando el consumo sobre el pagador **tampoco funciona**: lanza igual, por la liquidación congelada | sonda `a19_inactivo`, caso 3 |
| Incluir al actor histórico en el universo del libro lo resuelve: `outstanding` 0 y 0, ninguna liquidación, obligación intacta | sonda `a19_inactivo`, casos 4 y 5 |
| Nada en el código escribe `active: false` en un participante: se crea en `true` y no se modifica | `firestore_session_repository.dart:170`, sin ningún otro escritor |
| `recompute` **no borra ningún `ticketEntitlement`**: no hay bucle de borrado y es deliberado | `recompute.ts:984-990` |
| El Admin SDK admite la precondición `lastUpdateTime` (aborta con código 9) | sonda `a19_reapertura`, prueba B1 |
| Los triggers **no tienen `retry`** configurado: un commit fallido hoy se pierde | `backend/functions/src/index.ts:15-19` y `recompute.ts:1077-1110`, sin `retry` |
| `ticketParticipants` es `{pagador} ∪ {consumo > 0}`: **no sirve** como censo de quién debe terminar | `recompute.ts:337-341` |
| El censo correcto es `activeIds` = participantes de sesión con `active !== false` | `recompute.ts:269-272`, es lo que recibe `SplitEngine` |

---

## Contrato de datos (el que implementa todo el plan)

```
sessions/{sid}/accounts/{aid}/tickets/{tid}
  … campos actuales, intactos …
  pickingModelVersion: 1              // discriminante de protocolo; ausente = legacy
  picking: {
    open: { '{pid}': true, … },       // quien todavía NO ha terminado de elegir
    lastTarget: '{pid}',              // pid que toca ESTA escritura (lo valida Rules)
    fingerprint: '{huella}',          // topología+modo; SOLO la escribe recompute
    firmContribution: {               // última economía FIRME del ticket;
      paidBy: '{pid}',                // SOLO la escribe recompute
      grandTotal: 6000,
      consumption: { '{pid}': 1000, … }   // solo importes > 0
    }
  }
```

- **Firme** ⟺ `pickingModelVersion != 1` **o** modo efectivo `equal` **o** (`open` filtrado por activos vacío **y** `fingerprint` coincide con la calculada).
- `assignment` **no cambia**. `unitIds` **no cambia**. No hay subcolección.
- `fingerprint = '{modo}|{lineId}:{unitIds unidos por coma};…'` con las líneas ordenadas por id. La escribe y la compara **solo `recompute`**: no se espeja en Dart ni en TypeScript de cliente.
- Cambia la huella ⟺ cambia el modo efectivo, o el conjunto de líneas, o los `unitIds` de alguna línea. Nombre, precio, cantidad-sin-cambio-de-unidades, total, comercio y fecha **no** la cambian.
- `firmContribution` es **exactamente** el `TicketContribution` que `BalanceEngine` ya recibe (`paidBy`, `grandTotal`, `consumption`). No es una copia de `balances` ni una segunda proyección: es la entrada mínima de un ticket al motor que ya existe, congelada. La escribe solo `recompute`, en el mismo batch en que el ticket queda firme. **Se usa tal cual, sin reinterpretarla según quién siga activo**: ver «Dos universos» abajo.

### Dos universos: quién reparte y quién figura en el libro

`activeIds` hace hoy dos trabajos que son incompatibles en cuanto existe economía congelada:

| Universo | Para qué | Quién entra |
|---|---|---|
| **Reparto** (`activeIds`) | `splitTicket` y `sanitizeLine`: quién puede recibir consumo NUEVO | solo `active !== false` |
| **Libro** (`ledgerIds`) | `computeBalance`: quién puede ser nombrado en un saldo | los activos **más** los actores con peso económico ya contraído |

«Peso económico ya contraído» son dos cosas concretas y acotadas: los dos extremos de una liquidación **confirmada**, y los pids que figuran en una `firmContribution` que se está usando.

Estar en el libro **no** es estar activo: no da permisos, no permite seleccionar, no entra en `picking.open`, no recibe consumo nuevo y no vuelve a ser miembro de nada. Solo significa que el motor puede *nombrarlo* para cuadrar una deuda que ya existía.

Sin esta separación, desactivar a alguien que tiene una liquidación confirmada hace que `BalanceEngine` lance `unknownParticipant` (`balance_engine.dart:141-148`, espejo en `balanceEngine.ts:89-95`) y **la sesión entera deja de recalcularse**. Está medido, y ocurre **hoy, sin A19**: la economía congelada solo lo haría alcanzable con normalidad.

### Qué entra y qué no en la economía de un ticket NO firme

| Salida de `recompute` | Ticket no firme |
|---|---|
| `accountTotals[aid].grandTotal` y `totals.grandTotal` | **SÍ, con el total VIVO.** Es «lo que se pagó», no un balance: ocultarlo haría bailar el total gastado de la sesión sin motivo |
| `contributions` → `balances`, `settlements`, `totals.settlementRequired`, `pendingSettlements` | **Con `firmContribution` si existe; nada si no existe.** Ver «Reapertura» abajo |
| `economicEntries` (obligaciones P5) | **Derivadas de `firmContribution` si existe; ninguna si no existe** |
| `ticketEntitlements` (derecho histórico A11d) | **SÍ, exactamente como hoy.** A19 no lo toca: ver «Derecho histórico» abajo |
| `ticketParticipants` + `ticketParticipantProjections` (ADR-036) | **SÍ.** El enlace de ticket sirve precisamente para preguntar qué consumió cada cual: bloquearlo mientras se elige sería al revés |

### Reapertura: por qué se congela la contribución y no se retira

Un ticket que **nunca** ha sido firme no ha podido generar ningún pago, así que retirarlo de la economía es seguro: no hay nada con lo que quedar descuadrado.

Un ticket que **ya fue firme** es otra cosa. Sus obligaciones pudieron cobrarse, y un pago `confirmed` **nunca se borra** (`recompute.ts:445-449` congela las liquidaciones confirmadas; `EconomicLedger` netea pagos contra obligaciones por pareja y moneda, `economic_ledger.dart:96-142`). Si al reabrir se retirase la obligación y se conservase el pago, el modelo leería un **sobrepago** y fabricaría la deuda inversa:

```
obligación del ticket = 0   ·   pago confirmado = 60,00 €
→ EconomicLedger: crédito de 60,00 € a favor de quien pagó
→ BalanceEngine: outstanding ±60,00 € → liquidación INVERSA de 60,00 €
```

Esa liquidación sería **nueva, accionable y provocada solo por el estado temporal de edición**: cualquiera podría marcarla como pagada y el receptor confirmarla, cobrando una deuda que no existe. Viola de lleno la invariante de A19.

**Solución:** mientras el ticket está reabierto, su aportación a la economía es la **última firme**, congelada en `picking.firmContribution`. Las selecciones nuevas no entran en el motor; las obligaciones no cambian; los pagos siguen cuadrando con ellas; **no aparece nada nuevo**. Al volver a cerrarse, se recalcula con el reparto real y la reconciliación (crédito, liquidación inversa por la diferencia) la produce el modelo económico de siempre, en el momento correcto: al cerrar, no al editar.

Consecuencia aceptada y documentada: si A11c cambia el `grandTotal` mientras el ticket está reabierto, `totals.grandTotal` (vivo) y `balances` (congelados) discrepan temporalmente. Es el precio honesto de no inventar economía: la alternativa —repartir la diferencia por nuestra cuenta— sería fabricar consumo que nadie declaró. Se resuelve solo al cerrar.

### Derecho histórico (A11d): A19 no lo toca

`ticketEntitlements` **no es economía desechable**: es autoridad de lectura y es monótona por contrato. `recompute` **ya no borra ninguna** —no hay bucle de borrado, y el comentario de `recompute.ts:984-990` dice que es deliberado—, así que un entitlement concedido sobrevive a cualquier reapertura sin que haya que hacer nada.

La **concesión** sigue exactamente como hoy: se deriva de `participatingPids = {pagador} ∪ {pid con consumo VIVO > 0}` (`recompute.ts:337-341`), con independencia de que el ticket sea firme. Razones:

- **El pagador la obtiene desde el primer recompute**, porque `participatingPids` siempre lo incluye. Sin esto, alguien que paga un ticket y es expulsado del grupo mientras el reparto sigue abierto perdería la capacidad de auditar el gasto que pagó él.
- **Un consumidor provisional también la obtiene**, y es coherente: A11d ya tolera que una corrección posterior le quite el consumo y le deje el derecho («un derecho concedido no se retira nunca»). Además no abre nada nuevo — hoy cualquier miembro del contexto puede autoseleccionarse en un ticket de su grupo y obtener el entitlement igual.
- **La mera pertenencia no concede nada**: sin consumo y sin ser pagador, no hay `participatingPid` y no hay entitlement.

Distinguir los dos conceptos es el punto: **firmeza económica** decide si el dinero cuenta; **derecho histórico** decide quién puede leer el gasto. A19 solo gobierna lo primero.

---

## Mapa de archivos

**Se modifican:**

| Archivo | Responsabilidad que gana |
|---|---|
| `backend/functions/src/recompute.ts` | Huella, puerta de firmeza, reapertura por topología, CAS + reintento acotado |
| `backend/firestore/firestore.rules` | `reopensPicking` en la rama de líneas; rama de escritura de `picking` en el ticket; `active` en `canPickOwnUnit` |
| `apps/mobile/lib/features/sessions/data/firestore_session_repository.dart` | Siembra al crear; batch línea+ticket; `finishPicking`; firma `by` condicional |
| `apps/mobile/lib/features/sessions/data/session_repository.dart` | Firmas nuevas de la interfaz |
| `apps/mobile/lib/features/sessions/domain/session_models.dart` | `SessionTicket.pickingOpen` / `usesPicking`; `SessionParticipant` ya trae `active` |
| `apps/mobile/lib/features/sessions/presentation/ticket_detail_screen.dart` | Banner de estado, «He terminado», cerrar por otra persona, aviso al reabrir |
| `apps/mobile/lib/features/sessions/presentation/unit_assignment_sheet.dart` | Pasa `myPid` y `usesPicking` a la escritura |
| `apps/mobile/lib/l10n/app_es.arb` | Copy de A19 y del error de cliente desactualizado |
| `apps/guest_web/src/lib/session.svelte.ts` | Tickets en vivo (A6), batch de reapertura, `finishPicking`, superficie de error (A5) |
| `apps/guest_web/src/lib/assignment.ts` | `pickingUpdate` (la mitad de ticket del batch) |
| `apps/guest_web/src/views/PickItems.svelte` | Banner, «He terminado», mensaje de error |

**Se crean:**

| Archivo | Responsabilidad |
|---|---|
| `backend/firestore/test/picking.test.mjs` | Toda la matriz de Rules de A19 |
| `backend/functions/src/test/integration/picking.it.test.ts` | Firmeza, reapertura, topología, CAS |
| `apps/mobile/test/picking_test.dart` | Siembra, batch, «He terminado», reapertura, `by`, inactivos |
| `apps/guest_web/src/lib/picking.test.ts` | Contrato de escritura idéntico al de la app |
| `docs/CIERRE_DE_CONSUMO.md` | Contrato vivo de A19 (ADR-041) |

---

## Gates (únicos motivos para PARAR y consultar)

1. **Presupuesto de Rules.** Cualquier `maximum of 1000 expressions` en una rama nueva, o la necesidad de un segundo acceso de documento en la rama de reparto. PARA.
2. **CAS/reintento incapaz de garantizar estado fresco.** Si la Tarea 6 no consigue demostrar que un conflicto acaba en un recompute con datos frescos. PARA.
3. **Incompatibilidad económica real** no detectada en la investigación: cualquier necesidad de tocar `SplitEngine`, `BalanceEngine`, `EconomicLedger` o un vector dorado. PARA.
4. **Necesidad demostrada de reestructurar `assignment`.** PARA.

Si ninguno ocurre, el plan se ejecuta entero sin más decisiones de arquitectura.

## Orden de rollout (manda sobre el orden de las tareas)

Invariante: **en ningún momento puede existir una capa que escriba un formato que otra todavía no entienda.**

| Paso | Tareas | Quién | Qué gana | Qué escribe |
|---|---|---|---|---|
| 0 | 1–4 | app y web | arreglos locales A2–A6, independientes de A19 | nada nuevo |
| 1 | 5–6 | `recompute` | **entiende** `picking`; CAS | nada de `picking` salvo `fingerprint` y la reapertura |
| 2 | 7–8 | Rules | **aceptan** `picking` y exigen la reapertura | — |
| 3 | 9–11 | app | crea, escribe y enseña `picking` | `pickingModelVersion: 1` |
| 4 | 12–13 | web | escribe y enseña `picking` | igual que la app |
| 5 | 14 | docs | contrato vivo | — |

Despliegue solo a **`salda-dev`**, y solo cuando el usuario lo pida. Nunca `salda-prod`.

---

# FASE 0 — Bugs locales (A2–A6)

### Tarea 1: A3/A2 — firmar `by` solo al asignar el consumo de otra persona

**Objetivo:** que la app deje de firmar TODA autoselección como si fuera una asignación administrativa. Esto restaura el invariante que las propias Rules documentan («sin firma, la asignación es una autoselección») y elimina de paso la denegación espuria A2: hoy, si Jorge se marca `u0` y una administradora marca esa misma casilla con la pantalla un instante desfasada, Rules deniegan porque una firma viva no se puede reescribir, y la app enseña «puede que la cuenta ya esté cerrada», que además es falso.

**Files:**
- Modify: `apps/mobile/lib/features/sessions/data/session_repository.dart:73-79`
- Modify: `apps/mobile/lib/features/sessions/data/firestore_session_repository.dart:491-508`
- Modify: `apps/mobile/lib/features/sessions/presentation/ticket_detail_screen.dart:691-704`
- Modify: `apps/mobile/lib/features/sessions/presentation/unit_assignment_sheet.dart:130-152`
- Test: `apps/mobile/test/unit_assignment_test.dart`
- Test: `backend/firestore/test/unit_assignment.test.mjs`

**Interfaces:**
- Produces: `SessionRepository.setUnitConsumer(String linePath, {required int unit, required String participantId, required bool selected, String? myPid})`. `myPid` es el participante que representa a quien escribe; `null` significa «no soy participante de este gasto» (administrador del grupo), y entonces siempre se firma.

- [ ] **Step 1: Escribir el test rojo de la app**

En `apps/mobile/test/unit_assignment_test.dart`:

```dart
test('marcarse a uno mismo NO firma la procedencia', () async {
  final repo = await _repoConTicketDeUnidades();
  await repo.setUnitConsumer(
    _linePath,
    unit: 0,
    participantId: 'p2',
    selected: true,
    myPid: 'p2',
  );
  final line = await repo.firestore.doc(_linePath).get();
  final assignment = line.data()!['assignment'] as Map<String, dynamic>;
  expect((assignment['units'] as Map)['u0'], {'p2': true});
  expect((assignment['by'] as Map?)?['u0'], anyOf(isNull, isEmpty));
});

test('asignar a OTRA persona sí firma con el uid de quien escribe', () async {
  final repo = await _repoConTicketDeUnidades();
  await repo.setUnitConsumer(
    _linePath,
    unit: 0,
    participantId: 'p3',
    selected: true,
    myPid: 'p2',
  );
  final line = await repo.firestore.doc(_linePath).get();
  final assignment = line.data()!['assignment'] as Map<String, dynamic>;
  expect(((assignment['by'] as Map)['u0'] as Map)['p3'], 'uid-jorge');
});
```

Reutiliza el helper de fixture que ya exista en el archivo; si no lo hay, extrae uno de los tests actuales (`_repoConTicketDeUnidades` debe devolver el `FirestoreSessionRepository` sobre `fake_cloud_firestore` con `uid()` devolviendo `'uid-jorge'` y participantes `p2`/`p3`).

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/unit_assignment_test.dart --plain-name "NO firma"`
Expected: FAIL — hoy `by.u0.p2` vale `uid-jorge`, no está vacío.

- [ ] **Step 3: Implementación mínima**

En `session_repository.dart`, añadir el parámetro a la firma abstracta:

```dart
  /// Marca o desmarca a [participantId] en una unidad.
  ///
  /// [myPid] es MI participante en este gasto (null si no soy participante).
  /// Sirve para una sola cosa: decidir si la escritura firma la procedencia.
  Future<void> setUnitConsumer(
    String linePath, {
    required int unit,
    required String participantId,
    required bool selected,
    String? myPid,
  });
```

En `firestore_session_repository.dart`, sustituir el cuerpo de `setUnitConsumer`:

```dart
  @override
  Future<void> setUnitConsumer(
    String linePath, {
    required int unit,
    required String participantId,
    required bool selected,
    String? myPid,
  }) {
    // A3: firmar significa «esto se lo puse yo a OTRA persona». Marcarse a
    // uno mismo no lleva firma, y esa ausencia es informativa: las Rules la
    // interpretan como autoselección. Firmarlo todo borraba la distinción
    // que A10 existe para conservar, y además hacía imposible que un
    // administrador tocara una casilla que su dueño acababa de marcar (una
    // firma viva no se puede reescribir): el resultado era el deseado y la
    // app enseñaba un error.
    final asignaAOtraPersona = myPid == null || myPid != participantId;
    return firestore.doc(linePath).update({
      'assignment.type': 'units',
      'assignment.schemaVersion': 2,
      'assignment.lastEditorPid': participantId,
      'assignment.lastEditedUnit': 'u$unit',
      'assignment.units.u$unit.$participantId': selected
          ? true
          : FieldValue.delete(),
      'assignment.by.u$unit.$participantId': selected && asignaAOtraPersona
          ? uid()
          : FieldValue.delete(),
    });
  }
```

En `ticket_detail_screen.dart`, en `toggleUnit` (`:693-703`), añadir `myPid: pid`:

```dart
    Future<void> toggleUnit(int unit) => guard(
      () => ref
          .read(sessionRepositoryProvider)
          .setUnitConsumer(
            line.path,
            unit: unit,
            participantId: pid!,
            selected: !line.unitIsMine(unit, pid),
            myPid: pid,
          ),
    );
```

En `unit_assignment_sheet.dart`, la hoja necesita saber cuál es mi pid. Añadir el parámetro `myPid` a `showUnitAssignmentSheet` y a `_UnitAssignmentSheet`, propagarlo desde `openUnitAssignment` en `ticket_detail_screen.dart` (donde `pid` ya está en ámbito) y pasarlo en `_set`:

```dart
      await ref
          .read(sessionRepositoryProvider)
          .setUnitConsumer(
            linePath,
            unit: unit,
            participantId: participantId,
            selected: selected,
            myPid: myPid,
          );
```

- [ ] **Step 4: Ejecutar y verificar que pasa**

Run: `flutter test test/unit_assignment_test.dart`
Expected: PASS

- [ ] **Step 5: Test de Rules que fija la ausencia de error espurio**

En `backend/firestore/test/unit_assignment.test.mjs`, dentro del describe de A10:

```js
it('la admin puede marcar una unidad que su dueño acaba de autoseleccionar',
  async () => {
    // Autoselección REAL: sin firma (es lo que escribe el cliente arreglado).
    await assertSucceeds(asignarSinFirma(JORGE, 'p2'));
    // La admin llega con la pantalla desfasada y marca la misma casilla.
    // No cambia nada del reparto, así que no puede fallar.
    await assertSucceeds(asignar(JEFA, 'p2', { firma: null }));
  });
```

`asignar(..., { firma: null })` ya existe en el archivo y escribe `deleteField()` en `by`; la escritura resultante deja la asignación como estaba y no reescribe ninguna firma viva. Si el helper no admite `firma: null` para el caso «seleccionado», ajústalo para que con `firma === null` omita por completo la clave `assignment.by...` en vez de borrarla.

- [ ] **Step 6: Verificar reglas**

Run: `firebase emulators:exec --only firestore,storage --project demo-salda "npm --prefix backend/firestore test"`
Expected: PASS, sin ningún `maximum of`.

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/features/sessions apps/mobile/test/unit_assignment_test.dart backend/firestore/test/unit_assignment.test.mjs
git commit -m "A19 (A2/A3): la firma dice quien te lo asigno, no que te marcaste tu"
```

**Criterio para avanzar:** `flutter test` y los tests de reglas en verde; `dart analyze --fatal-infos` a cero.

---

### Tarea 2: A4 — un participante desactivado ni elige ni cuenta

**Objetivo:** hoy `canPickOwnUnit` no comprueba `active`, así que alguien desactivado en la sesión que siga siendo miembro del grupo puede marcar unidades; la app lo pinta como consumidor y `recompute` lo descarta (`known = activeIds`), mandando esa unidad al pagador. Pantalla y dinero dicen cosas distintas.

**Files:**
- Modify: `backend/firestore/firestore.rules:2253-2262` (`canPickOwnUnit`)
- Modify: `apps/mobile/lib/features/sessions/presentation/ticket_detail_screen.dart:521-531` y `:786-808`
- Test: `backend/firestore/test/unit_assignment.test.mjs`
- Test: `apps/mobile/test/unit_assignment_test.dart`

- [ ] **Step 1: Test rojo de Rules**

```js
it('un participante desactivado NO puede autoseleccionarse', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), 'sessions/sg1/participants/p2'), {
      active: false,
    });
  });
  await assertDeniegaLimpio(asignarSinFirma(JORGE, 'p2'));
});
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `firebase emulators:exec --only firestore,storage --project demo-salda "npm --prefix backend/firestore test"`
Expected: FAIL — hoy la escritura se PERMITE.

- [ ] **Step 3: Implementación mínima en Rules**

```
    function canPickOwnUnit(sid, aid, tid) {
      let session = sessionData(sid);
      let ticket = get(/databases/$(database)/documents/sessions/$(sid)/accounts/$(aid)/tickets/$(tid)).data;
      let mode = ticket.get('splitModeOverride', session.splitModeDefault);
      let editor = request.resource.data.assignment.get('lastEditorPid', '');
      return participatesInSplit(sid)
        && session.status == 'open'
        && mode == 'byItem'
        && validUnitWrite(editor)
        && claimedBy(sid, editor) == request.auth.uid
        // A4: quien ya no participa en el reparto no recibe consumo NUEVO,
        // tampoco el suyo propio. `recompute` ya lo descartaba (`known` son
        // los activos), así que sin esto la pantalla enseñaba un consumidor
        // que el dinero no reconocía y la unidad recaía en el pagador.
        && participantData(sid, editor).get('active', true) == true;
    }
```

`participantData` ya se usa en `canAssignWithProvenance` y no añade acceso nuevo en el camino que importa (`claimedBy` ya lee ese mismo documento; si el presupuesto se resintiera, es Gate 1).

- [ ] **Step 4: Ejecutar y verificar que pasa**

Run: `firebase emulators:exec --only firestore,storage --project demo-salda "npm --prefix backend/firestore test"`
Expected: PASS, incluidas todas las pruebas previas de A10 y sin ningún `maximum of`.

- [ ] **Step 5: Test rojo de la app**

En `apps/mobile/test/unit_assignment_test.dart`, un test de widget sobre `TicketDetailScreen`:

```dart
testWidgets('un consumidor desactivado no se pinta en la unidad', (tester) async {
  // Participantes: p1 (activa, dueña) y p2 (INACTIVA) marcada en u0.
  await _pumpTicketDetail(tester, participantesInactivos: {'p2'},
      unidadesMarcadas: {0: {'p2'}});
  expect(find.textContaining('Jorge'), findsNothing);
  expect(find.textContaining('sin reclamar'), findsOneWidget);
});
```

- [ ] **Step 6: Ejecutar y verificar que falla**

Run: `flutter test test/unit_assignment_test.dart --plain-name "desactivado no se pinta"`
Expected: FAIL — el nombre aparece.

- [ ] **Step 7: Implementación mínima en la app**

En `ticket_detail_screen.dart`, `_TicketLinesSection` ya calcula `activePids` (`:565-568`). Pásalo a `_LineTile` como `activePids` y filtra en los dos sitios donde se listan consumidores:

```dart
  /// Consumidores que el motor reconoce. Quien ya no participa sigue en el
  /// documento —no se le borra el consumo por dejar de estar activo— pero
  /// `recompute` lo descarta, así que pintarlo mentiría sobre el reparto.
  List<String> _consumidoresVigentes(int unit) => [
    for (final pid in line.consumersOf(unit))
      if (activePids.contains(pid)) pid,
  ];
```

Úsalo en `unitDescriptions` (`:747-758`), en `unitChip` (`:788-792`) y en el contador de `unitCompactSummary` (`:779-784`). Y en `myPid` (`:521-531`) exige además que el participante esté activo:

```dart
    final myPid =
        (myUid.isEmpty
            ? null
            : participants
                  .where((p) => p.active && p.claimedByDevice == myUid)
                  .map((p) => p.id)
                  .firstOrNull) ??
        (canEdit
            ? participants
                  .where((p) => p.active && p.isOwner)
                  .map((p) => p.id)
                  .firstOrNull
            : null);
```

- [ ] **Step 8: Ejecutar y verificar que pasa**

Run: `flutter test test/unit_assignment_test.dart`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add backend/firestore/firestore.rules backend/firestore/test apps/mobile/lib apps/mobile/test
git commit -m "A19 (A4): quien ya no participa ni elige ni aparece consumiendo"
```

**Criterio para avanzar:** reglas y `flutter test` en verde; ninguna denegación con `maximum of`.

---

### Tarea 3: A5 — la web dice cuándo le rechazan una escritura

**Objetivo:** hoy `PickItems.svelte` llama a `guest.setLineUnit()` sin capturar nada: un rechazo de Rules es una promesa no capturada, la casilla revierte sola y el invitado no ve explicación. Con A19 aparece una denegación más (pid ya cerrado desde un cliente desactualizado), así que esto deja de ser cosmético.

**Files:**
- Modify: `apps/guest_web/src/lib/session.svelte.ts:99-107` y `:255-280`
- Modify: `apps/guest_web/src/views/PickItems.svelte:56-95`
- Test: `apps/guest_web/src/lib/session.error.test.ts` (crear)

- [ ] **Step 1: Test rojo**

Crear `apps/guest_web/src/lib/session.error.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { describeWriteError } from './session.svelte';

describe('mensajes de escritura rechazada', () => {
  it('permiso denegado explica que la selección no se guardó', () => {
    expect(describeWriteError({ code: 'permission-denied' })).toMatch(
      /no se pudo guardar/i,
    );
  });

  it('cualquier otro fallo cae en un mensaje genérico de conexión', () => {
    expect(describeWriteError({ code: 'unavailable' })).toMatch(/conexión/i);
  });
});
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `npm --prefix apps/guest_web test`
Expected: FAIL — `describeWriteError` no existe.

- [ ] **Step 3: Implementación mínima**

En `session.svelte.ts`, exportar el traductor y añadir el estado de error a la clase:

```ts
/** Traduce el fallo de una escritura a algo que una persona entienda. */
export function describeWriteError(error: unknown): string {
  const code = (error as { code?: string } | null)?.code ?? '';
  if (code === 'permission-denied') {
    return 'No se pudo guardar. Puede que la cuenta ya esté cerrada o que ' +
      'alguien haya cerrado el reparto; recarga la página.';
  }
  return 'No se pudo guardar. Revisa tu conexión e inténtalo otra vez.';
}
```

En la clase `GuestSession`, junto al resto de runas:

```ts
  error = $state<string | null>(null);

  /** Envuelve una escritura para que un rechazo se vea, no se pierda. */
  private async write(action: () => Promise<void>): Promise<void> {
    try {
      this.error = null;
      await action();
    } catch (failure) {
      this.error = describeWriteError(failure);
    }
  }
```

Y envolver las escrituras que dispara el invitado: `toggleLine`, `setLineUnits`, `setLineUnit`, `markPaid`, `confirmReceived`. Ejemplo con `setLineUnit`:

```ts
  async setLineUnit(line: LineInfo, unit: number, selected: boolean): Promise<void> {
    if (!this.myPid) return;
    await this.write(() =>
      updateDoc(doc(db, line.path), unitUpdate(unit, this.myPid!, selected, deleteField())),
    );
  }
```

En `PickItems.svelte`, pintar el aviso justo debajo de la cabecera:

```svelte
{#if guest.error}
  <p class="error" role="alert">{guest.error}</p>
{/if}
```

con el estilo del proyecto (reutiliza la clase de error de `ErrorView.svelte`; si no existe una utilitaria, añade una regla local con el token de color de error ya generado en `tokens.g.css`).

- [ ] **Step 4: Ejecutar y verificar que pasa**

Run: `npm --prefix apps/guest_web test`
Expected: PASS

- [ ] **Step 5: Comprobar tipos y build**

Run: `npm --prefix apps/guest_web run build`
Expected: build correcto y `svelte-check` a cero. El presupuesto de peso (`scripts/check-size.mjs`, 220 KB gzip) debe seguir en verde.

- [ ] **Step 6: Commit**

```bash
git add apps/guest_web/src
git commit -m "A19 (A5): la web dice por que no se guardo tu seleccion"
```

**Criterio para avanzar:** vitest, `svelte-check` y presupuesto de peso en verde.

---

### Tarea 4: A6 — la lista y la cabecera de tickets de la web, en vivo

**Objetivo:** `loadTickets()` usa `getDocs` una sola vez y se protege con `ticketsLoaded`, que nunca se resetea. Un ticket añadido no aparece; una corrección A11c de total o comercio no se ve; un cambio de `splitModeOverride` deja `pickable` obsoleto; un ticket borrado sigue listado. Las líneas sí son en vivo. **Además, esta tarea es requisito de A19**: `picking.open` vive en el documento del ticket, así que sin este listener la web no puede enseñar quién falta.

**Files:**
- Modify: `apps/guest_web/src/lib/session.svelte.ts:318-364`

- [ ] **Step 1: Escribir el test rojo**

En `apps/guest_web/src/lib/session.error.test.ts` (o un archivo nuevo `tickets.test.ts`) no se puede montar Firestore, así que el test cubre la parte pura: extraer la construcción de `TicketInfo` a una función y probarla.

```ts
import { ticketInfoFrom } from './session.svelte';

it('el modo de reparto sale del ticket y, si no, de la sesión', () => {
  expect(ticketInfoFrom({ id: 't1', data: { merchant: { name: 'Bar' },
    grandTotal: 1000, splitModeOverride: 'byItem' } }, 'Cuenta', 'equal').pickable)
    .toBe(true);
  expect(ticketInfoFrom({ id: 't1', data: { grandTotal: 1000 } }, 'Cuenta', 'byItem')
    .pickable).toBe(true);
  expect(ticketInfoFrom({ id: 't1', data: { grandTotal: 1000 } }, 'Cuenta', 'equal')
    .pickable).toBe(false);
});
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `npm --prefix apps/guest_web test`
Expected: FAIL — `ticketInfoFrom` no existe.

- [ ] **Step 3: Implementación mínima**

Extraer el constructor puro y sustituir los `getDocs` por `onSnapshot` anidados. La estructura mínima que resuelve el problema sin rehacer la web:

```ts
/** Construcción pura de la ficha de un ticket (testeable sin Firestore). */
export function ticketInfoFrom(
  ticket: { id: string; data: Record<string, unknown> },
  accountName: string,
  sessionMode: 'equal' | 'byItem' | undefined,
): Omit<TicketInfo, 'lines'> {
  const merchant = ticket.data.merchant as { name?: string } | undefined;
  return {
    id: ticket.id,
    merchantName: merchant?.name ?? accountName ?? '',
    grandTotal: (ticket.data.grandTotal as number) ?? 0,
    pickable:
      ((ticket.data.splitModeOverride as string) ?? sessionMode) === 'byItem',
  };
}

/**
 * Tickets y líneas EN VIVO. Antes era una foto única: un gasto añadido, una
 * corrección de total o un cambio de modo no llegaban nunca, y desde A19
 * tampoco llegaría `picking.open`, que vive en el propio ticket.
 */
loadTickets(): void {
  if (this.ticketsLoaded) return;
  this.ticketsLoaded = true;
  this.stopTickets.push(
    onSnapshot(
      query(collection(db, 'sessions', this.sid, 'accounts'), orderBy('order')),
      (accounts) => {
        for (const account of accounts.docs) {
          if (this.watchedAccounts.has(account.id)) continue;
          this.watchedAccounts.add(account.id);
          this.stopTickets.push(
            onSnapshot(collection(account.ref, 'tickets'), (tickets) => {
              this.mergeTickets(account, tickets);
            }),
          );
        }
      },
    ),
  );
}
```

`mergeTickets` mantiene un `Map<string, TicketInfo>` por id, aplica `ticketInfoFrom`, arranca el listener de líneas del ticket la primera vez que lo ve, retira los que desaparecen (con su listener) y vuelca el mapa ordenado a `this.tickets`. Conserva el listener de líneas existente (`:345-360`) tal cual: ya es en vivo y funciona.

Guardar los `unsubscribe` de líneas en un `Map<string, () => void>` para poder cortarlos cuando un ticket se borra; en `connect()` los listeners ya existentes no cambian.

- [ ] **Step 4: Ejecutar y verificar que pasa**

Run: `npm --prefix apps/guest_web test`
Expected: PASS

- [ ] **Step 5: Comprobación manual contra el emulador**

```bash
node backend/functions/tools/seed-emulator.mjs
```
Con `npm --prefix apps/guest_web run dev`, abrir `/s/e2e1#k=E2E-SECRET-CODE-16CH`, y desde la consola del emulador: añadir un ticket a la sesión (aparece sin recargar), cambiar `splitModeOverride` (la pestaña de productos aparece o desaparece), corregir el `grandTotal` (se actualiza), borrar un ticket (desaparece).

- [ ] **Step 6: Build y presupuesto**

Run: `npm --prefix apps/guest_web run build`
Expected: verde, incluido `scripts/check-size.mjs`.

- [ ] **Step 7: Commit**

```bash
git add apps/guest_web/src
git commit -m "A19 (A6): la web deja de ver una foto congelada de los gastos"
```

**Criterio para avanzar:** vitest, build, presupuesto de peso y la comprobación manual, los cuatro en verde.

---

# FASE 1 — El backend entiende el protocolo

### Tarea 5: `recompute` calcula la huella, decide la firmeza y reabre por topología

**Objetivo:** que `recomputeSession` sepa qué tickets son firmes y deje fuera de la economía a los que no lo son, y que reabra a todos los activos cuando cambie la topología de unidades o el modo. Es la primera capa del rollout: se despliega **antes** de que ningún cliente escriba `picking`, y no cambia nada para los datos existentes porque todo va detrás de `pickingModelVersion === 1`.

**Files:**
- Modify: `backend/functions/src/recompute.ts` (tipos `LineDoc`/`TicketDoc`, lectura de líneas `:670-676`, bucle de tickets `:292-436`, batch final `:927-1060`)
- Test: `backend/functions/src/test/recompute.test.ts` (unitario de la huella y la puerta)
- Test: `backend/functions/src/test/integration/picking.it.test.ts` (crear)

**Interfaces:**
- Produces:
  - `export function pickingFingerprint(mode: SplitMode, lines: readonly LineDoc[]): string`
  - `export function ticketIsFirm(ticket: TicketDoc, mode: SplitMode, activeIds: readonly string[]): boolean`
  - `export function frozenContribution(ticket: TicketDoc): TicketContribution | undefined`
  - `LineDoc` gana `unitIds?: string[]`; `TicketDoc` gana `pickingModelVersion?: number` y `picking?: { open?: Record<string, boolean>; fingerprint?: string; firmContribution?: { paidBy: string; grandTotal: number; consumption: Record<string, number> } }`.

- [ ] **Step 1: Test rojo unitario de la huella y la puerta**

En `backend/functions/src/test/recompute.test.ts`:

```ts
test('la huella cambia con la topología y con el modo, no con el precio', () => {
  const lines = [
    { id: 'l1', totalPrice: 1000, unitIds: ['u0', 'u1'] },
    { id: 'l0', totalPrice: 500, unitIds: ['u0'] },
  ];
  const base = pickingFingerprint('byItem', lines);
  // Mismo contenido, otro orden de lectura: misma huella.
  assert.equal(pickingFingerprint('byItem', [...lines].reverse()), base);
  // Cambia el precio: NO reabre.
  assert.equal(
    pickingFingerprint('byItem', [
      { id: 'l1', totalPrice: 9999, unitIds: ['u0', 'u1'] },
      { id: 'l0', totalPrice: 500, unitIds: ['u0'] },
    ]),
    base,
  );
  // Se poda una unidad: reabre.
  assert.notEqual(
    pickingFingerprint('byItem', [
      { id: 'l1', totalPrice: 1000, unitIds: ['u0'] },
      { id: 'l0', totalPrice: 500, unitIds: ['u0'] },
    ]),
    base,
  );
  // Desaparece una línea: reabre.
  assert.notEqual(pickingFingerprint('byItem', [lines[0]]), base);
  // Cambia el modo: reabre.
  assert.notEqual(pickingFingerprint('equal', lines), base);
});

test('un ticket legacy es firme siempre; uno byItem solo con open vacío', () => {
  const legacy = { pickingModelVersion: undefined, picking: undefined, lines: [] };
  assert.equal(ticketIsFirm(legacy as never, 'byItem', ['p1']), true);

  const abierto = {
    pickingModelVersion: 1,
    picking: { open: { p2: true }, fingerprint: pickingFingerprint('byItem', []) },
    lines: [],
  };

  assert.equal(ticketIsFirm(abierto as never, 'byItem', ['p1', 'p2']), false);
  // p2 ya no está activo: deja de bloquear.
  assert.equal(ticketIsFirm(abierto as never, 'byItem', ['p1']), true);
  // A partes iguales las líneas no cuentan: siempre firme.
  assert.equal(ticketIsFirm(abierto as never, 'equal', ['p1', 'p2']), true);
});
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `npm --prefix backend/functions test`
Expected: FAIL — las funciones no existen.

- [ ] **Step 3: Implementación mínima**

En `recompute.ts`, junto a los tipos:

```ts
/**
 * Huella de la TOPOLOGÍA de reparto de un ticket (A19).
 *
 * Cambia si y solo si cambia algo que invalida una elección ya hecha: el
 * modo efectivo, el conjunto de líneas o los `unitIds` de alguna. NO cambia
 * con el nombre, el precio ni el total, porque corregir un importe no altera
 * QUÉ consumió nadie.
 *
 * Vive solo en el servidor: ningún cliente la calcula ni la escribe, así que
 * no hay una tercera implementación que mantener en paridad.
 */
export function pickingFingerprint(
  mode: SplitMode,
  lines: readonly LineDoc[],
): string {
  const parts = [...lines]
    .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
    .map((line) => `${line.id}:${[...(line.unitIds ?? [])].join(',')}`);
  return `${mode}|${parts.join(';')}`;
}

/**
 * ¿Entra este ticket en la economía firme? (A19)
 *
 * Un ticket sin `pickingModelVersion` es de antes del protocolo y se comporta
 * como siempre. A partes iguales el reparto no mira las líneas, así que no
 * hay nada que esperar. En «cada uno lo suyo» hace falta que todos los
 * activos hayan terminado Y que la topología no haya cambiado desde el
 * cierre: si cambió, este mismo recompute está a punto de reabrir el ticket.
 */
export function ticketIsFirm(
  ticket: TicketDoc,
  mode: SplitMode,
  activeIds: readonly string[],
): boolean {
  if (ticket.pickingModelVersion !== 1) return true;
  if (mode === 'equal') return true;
  const stored = ticket.picking?.fingerprint;
  if (stored !== undefined &&
      stored !== pickingFingerprint(mode, ticket.lines)) {
    return false;
  }
  return Object.keys(ticket.picking?.open ?? {})
    .every((pid) => !activeIds.includes(pid));
}
```

Añadir a `LineDoc` el campo `unitIds?: string[]` y leerlo en el barrido (`:670-676`):

```ts
            lines: linesSnap.docs.map((l) => ({
              id: l.id,
              totalPrice: (l.data().totalPrice as number) ?? 0,
              quantityMilli: l.data().quantityMilli as number | undefined,
              unitIds: l.data().unitIds as string[] | undefined,
              assignment: l.data().assignment,
            })),
```

Añadir a `TicketDoc` los campos `pickingModelVersion` y `picking`, y leerlos junto al resto (`:661-669`).

Añadir el reconstructor de la contribución congelada, junto a las otras dos funciones:

```ts
/**
 * Aportación económica de un ticket REABIERTO: la última que fue firme.
 *
 * No se retira, se congela. Retirarla dejaría un pago `confirmed` sin la
 * obligación que lo justificaba, y el modelo leería eso como un sobrepago:
 * aparecería una liquidación INVERSA por el importe entero, nueva y
 * cobrable, provocada solo por el hecho de estar editando. Congelándola no
 * aparece nada: las obligaciones siguen cuadrando con los pagos hasta que
 * el reparto se cierre otra vez y el motor de siempre haga la reconciliación.
 *
 * `undefined` = el ticket nunca llegó a ser firme, así que no ha podido
 * generar ningún pago y sale de la economía sin descuadrar nada.
 */
export function frozenContribution(
  ticket: TicketDoc,
): TicketContribution | undefined {
  const frozen = ticket.picking?.firmContribution;
  if (!frozen) return undefined;
  // Se devuelve TAL CUAL, sin reinterpretarla según quién siga activo hoy.
  // Congelada significa congelada: el `paidBy`, el total y el consumo son
  // los del cierre. Quien figure aquí y ya no esté activo entra igualmente
  // en el universo del libro (ver `ledgerIds`), que es lo que permite que
  // la economía del último cierre siga cuadrando byte a byte.
  return {
    paidBy: frozen.paidBy,
    grandTotal: frozen.grandTotal,
    consumption: { ...frozen.consumption },
  };
}
```

En el bucle de tickets de `computeAggregates` (`:292-436`), después de calcular `mode` y `consumption` (que **siempre** se calcula, en vivo):

```ts
      const firm = ticketIsFirm(ticket, mode, activeIds);
      // Firme: la economía es la del reparto real. Reabierto: la última que
      // fue firme. Nunca cerrado: ninguna.
      const economic: TicketContribution | undefined = firm
        ? { paidBy, grandTotal: ticket.grandTotal, consumption }
        : frozenContribution(ticket);
```

y entonces:
- `accountTotal += ticket.grandTotal` se queda **fuera** de la condición (lo pagado es lo pagado, y se usa el total VIVO);
- `contributions.push(economic)` y todo el bloque de `economicEntries` (`:388-436`) se ejecutan **si `economic !== undefined`**, y **usando `economic.consumption` y `economic.paidBy`**, no los vivos. Cambiar `for (const [pid, amount] of Object.entries(consumption))` por `Object.entries(economic.consumption)` y `payerActor = actorByPid.get(economic.paidBy)`. Así una obligación de un ticket reabierto es byte a byte la misma que antes de reabrirlo, y `comparable()` la deja intacta en el batch;
- `ticketParticipants.push({...})`, el marcador de proyección y **`ticketEntitlements.push({...})`** quedan **fuera** de la condición y siguen derivándose del consumo **VIVO**, exactamente como hoy, con este comentario:

```ts
      // Ni la proyección de participación ni el derecho histórico esperan al
      // cierre, y son cosas distintas de la economía firme:
      //
      // - el enlace de ticket (ADR-036) existe justamente para preguntarle a
      //   alguien qué consumió: bloquearlo mientras se elige sería al revés;
      // - el derecho histórico (A11d) es autoridad de LECTURA y es monótono.
      //   El pagador lo necesita desde el primer instante: si se le concediera
      //   solo al cerrar, alguien expulsado del grupo mientras el reparto
      //   sigue abierto perdería el gasto que pagó él. Y a quien ya lo tiene
      //   no se le retira nunca: `recompute` no borra entitlements (ver el
      //   comentario de la escritura, más abajo), así que una reapertura no
      //   puede quitárselo a nadie.
```

Añadir a `RecomputeResult` el sello de la contribución firme, junto al resto de `pickingWrites` (ver más abajo): cuando `firm` es cierto y `economic` difiere de `ticket.picking?.firmContribution`, hay que persistirlo.

**Separar el universo del LIBRO del universo del REPARTO.** Hoy `activeIds` hace dos trabajos incompatibles, y por eso la economía congelada no se puede sostener sin esto. Recoger, dentro del bucle, los pids con peso económico ya contraído:

```ts
  // Actores históricos: figuran en una economía ya contraída aunque hoy no
  // participen. Se recogen aquí y se usan más abajo para el libro.
  const historicPids = new Set<string>();
  /* … dentro del bucle, cuando se usa una contribución congelada … */
      if (economic && !firm) {
        historicPids.add(economic.paidBy);
        for (const pid of Object.keys(economic.consumption)) {
          historicPids.add(pid);
        }
      }
```

y, justo antes de llamar a `computeBalance` (`:474-478`), construir el universo del libro:

```ts
  // Una liquidación CONFIRMADA es peso económico contraído: sus dos extremos
  // tienen que existir en el libro aunque uno ya no participe.
  for (const settlement of frozen) {
    historicPids.add(settlement.from);
    historicPids.add(settlement.to);
  }

  // El universo del LIBRO no es el del REPARTO (A19).
  //
  // `activeIds` decide quién puede recibir consumo NUEVO: eso sigue igual y
  // es lo que se le pasa a `splitTicket` y a `sanitizeLine`. El libro, en
  // cambio, tiene que poder NOMBRAR a cualquiera con peso económico ya
  // contraído — quien confirmó un cobro, y quien figura en la economía
  // congelada de un ticket reabierto—, porque si no puede nombrarlo no
  // puede cuadrarlo.
  //
  // Medido: con un único universo, desactivar a alguien que tiene una
  // liquidación confirmada hace que `BalanceEngine` lance
  // `unknownParticipant` y la sesión ENTERA deja de recalcularse. Ocurre hoy,
  // sin A19, y la economía congelada lo haría alcanzable con normalidad.
  //
  // Estar en el libro NO es estar activo: no da permisos, no permite
  // seleccionar, no entra en `picking.open` y no recibe consumo nuevo.
  const ledgerIds = [
    ...activeIds,
    ...[...historicPids].filter((pid) => !known.has(pid)).sort(),
  ];
```

y usarlo **solo** en la llamada al motor de balance:

```ts
  const balance = computeBalance({
    participantIds: ledgerIds,
    tickets: contributions,
    frozenSettlements: frozen,
  });
```

`splitTicket({ participantIds: activeIds, … })` y `sanitizeLine(l, known, paidBy)` **no cambian**: quien ya no participa sigue sin recibir consumo nuevo, que es justo lo que arregla A4. Los pids extra van ordenados alfabéticamente al final para que el desempate de `_simplify` siga siendo determinista, y como su `outstanding` es 0 no generan ninguna liquidación.

**Esto no toca ningún motor.** `BalanceEngine`, su espejo TS y los vectores dorados quedan intactos: lo único que cambia es qué lista de participantes le pasa `recompute`.

Añadir a `RecomputeResult` la lista de escrituras de picking:

```ts
  pickingWrites: {
    accountId: string;
    ticketId: string;
    fingerprint?: string;          // sellar la topología
    reopen?: boolean;              // devolver a TODOS los activos a `open`
    firmContribution?: TicketContribution;  // congelar la economía del cierre
  }[];
```

y poblarla en el mismo bucle:

```ts
      if (ticket.pickingModelVersion === 1) {
        const fingerprint = pickingFingerprint(mode, ticket.lines);
        const stored = ticket.picking?.fingerprint;
        // Al cerrar, la economía del cierre se congela: es la que sostendrá
        // los pagos si alguien vuelve a abrir el reparto después.
        const freeze = firm &&
          comparableContribution(economic) !==
            comparableContribution(frozenAsStored(ticket));
        if (stored !== fingerprint || freeze) {
          pickingWrites.push({
            accountId: account.id,
            ticketId: ticket.id,
            ...(stored !== fingerprint ? { fingerprint } : {}),
            // La PRIMERA vez solo se sella la huella: el ticket acaba de
            // nacer con su `open` ya sembrado por quien lo creó y no hay
            // nada que reabrir. Después, cualquier cambio de topología
            // devuelve a TODOS los activos a elegir — una unidad nueva no
            // puede convertirse en residual del pagador sin que nadie haya
            // tenido ocasión de reclamarla.
            ...(stored !== undefined && stored !== fingerprint
              ? { reopen: true }
              : {}),
            ...(freeze ? { firmContribution: economic } : {}),
          });
        }
      }
```

`comparableContribution` es una serialización estable con las claves de `consumption` ordenadas (mismo patrón que el `comparable()` que ya usa `recomputeSession` para los `economicEntries`, `recompute.ts:849-857`), y `frozenAsStored(ticket)` devuelve `ticket.picking?.firmContribution` normalizado igual. Sin esa comparación, cada recompute reescribiría el ticket y dispararía otro `recomputeOnTicket` en cascada.

**Orden importante:** `firmContribution` se congela con el consumo del cierre, y `frozenContribution()` lo lee en ejecuciones POSTERIORES. En la ejecución que cierra el ticket se usa el vivo (`firm === true`), así que no hay dependencia circular.

En `recomputeSession`, incluir `pickingWrites` en el cálculo de `unchanged` (`:912-925`):

```ts
  const unchanged =
    result.pickingWrites.length === 0 &&
    entitlementWrites.size === 0 &&
    /* … el resto, sin cambios … */;
```

y en el batch (junto a las demás escrituras, antes de `batch.commit()`):

```ts
  // Reapertura, sello de topología y congelación de la economía firme
  // (A19). Rutas punteadas, nunca el mapa entero: si alguien está pulsando
  // «he terminado» a la vez, se funden en vez de pisarse.
  for (const write of result.pickingWrites) {
    const ticketRef = sessionRef
      .collection('accounts').doc(write.accountId)
      .collection('tickets').doc(write.ticketId);
    batch.update(ticketRef, {
      ...(write.fingerprint !== undefined
        ? { 'picking.fingerprint': write.fingerprint }
        : {}),
      ...(write.reopen
        ? Object.fromEntries(
            snapshot.participants
              .filter((p) => p.active !== false)
              .map((p) => [`picking.open.${p.id}`, true]),
          )
        : {}),
      // La economía del cierre, congelada entera y de una pieza: si se
      // guardara por campos sueltos, una escritura a medias dejaría un
      // consumo que no suma el total y BalanceEngine lanzaría.
      ...(write.firmContribution !== undefined
        ? { 'picking.firmContribution': write.firmContribution }
        : {}),
    });
  }
```

- [ ] **Step 4: Ejecutar y verificar que pasa**

Run: `npm --prefix backend/functions test`
Expected: PASS, incluidos todos los tests previos de `recompute` y los vectores dorados.

- [ ] **Step 5: Tests de integración**

Crear `backend/functions/src/test/integration/picking.it.test.ts` siguiendo el patrón de `assignedConsumption.it.test.ts` (mismo `harness.js`, misma siembra). Cubrir:

```ts
it('un ticket abierto no genera economía firme', async () => {
  await sembrarTicketAbierto();            // pickingModelVersion 1, open {p1,p2}
  await marcarUnidad('u0', 'p2');
  await recomputeSession('s1');
  const session = (await db().doc('sessions/s1').get()).data()!;
  assert.deepEqual(session.balances, {});
  assert.equal((await db().collection('sessions/s1/settlements').get()).size, 0);
  assert.equal((await db().collection('economicEntries').get()).size, 0);
  // Lo pagado sí se cuenta: es descriptivo, no un balance.
  assert.equal(session.totals.grandTotal, 6000);
});

it('al cerrar el último pendiente, la economía aparece completa', async () => {
  await sembrarTicketAbierto();
  await marcarUnidad('u0', 'p2');
  await cerrar('p1'); await cerrar('p2');
  await recomputeSession('s1');
  const session = (await db().doc('sessions/s1').get()).data()!;
  assert.equal(session.balances.p2.consumed, 1000);
  assert.equal(session.balances.p1.consumed, 5000); // residual del pagador
  assert.equal((await db().collection('economicEntries').get()).size, 1);
});

it('un ticket abierto no bloquea la economía de los demás', async () => {
  await sembrarDosTickets({ segundoAbierto: true });
  await recomputeSession('s1');
  const session = (await db().doc('sessions/s1').get()).data()!;
  // El cerrado reparte; el abierto no aporta nada al balance.
  assert.equal(session.balances.p2.consumed, 2000);
});

// ── El caso que obligó a congelar la contribución ─────────────────────
it('reabrir un ticket ya cobrado NO fabrica una deuda inversa', async () => {
  // 1. Jorge se lleva las 6 unidades (60 €), todos terminan.
  await sembrarTicketAbierto();
  for (let u = 0; u < 6; u++) await marcarUnidad(`u${u}`, 'p2');
  await cerrar('p1'); await cerrar('p2');
  await recomputeSession('s1');
  const entries = await db().collection('economicEntries').get();
  assert.equal(entries.size, 1);
  assert.equal(entries.docs[0].data().amount, 6000);

  // 2. Alba confirma que ha cobrado los 60 €.
  const st = (await db().collection('sessions/s1/settlements').get()).docs[0];
  await st.ref.update({ state: 'confirmed' });
  await recomputeSession('s1');
  const pagos = await db().collection('economicPayments').get();
  assert.equal(pagos.docs.filter((d) => d.data().status === 'confirmed').length, 1);

  // 3. Jorge reabre y se queda con una sola unidad.
  for (let u = 1; u < 6; u++) await desmarcarUnidad(`u${u}`, 'p2');
  await recomputeSession('s1');

  const sesion = (await db().doc('sessions/s1').get()).data()!;
  const liquidaciones = await db().collection('sessions/s1/settlements').get();

  // NO aparece la liquidación inversa de 60 €, ni ninguna otra nueva: la
  // única que existe es la confirmada de antes.
  assert.equal(liquidaciones.size, 1);
  assert.equal(liquidaciones.docs[0].data().state, 'confirmed');
  assert.equal(liquidaciones.docs[0].data().amount, 6000);
  assert.equal(sesion.pendingSettlements, 0);
  // Nadie queda con saldo pendiente por el hecho de estar editando.
  assert.equal(sesion.balances.p1.outstanding, 0);
  assert.equal(sesion.balances.p2.outstanding, 0);
  // La obligación NO cambia mientras se edita: sigue siendo la del cierre.
  const durante = await db().collection('economicEntries').get();
  assert.equal(durante.size, 1);
  assert.equal(durante.docs[0].data().amount, 6000);
  // Y el pago confirmado sigue intacto.
  const pagosDurante = await db().collection('economicPayments').get();
  assert.equal(
    pagosDurante.docs.filter((d) => d.data().status === 'confirmed').length, 1);
});

it('al volver a cerrar, la reconciliación la hace el modelo de siempre',
  async () => {
    // Mismo montaje que el test anterior, dejado con una sola unidad.
    await escenarioReabiertoTrasCobro();   // helper del bloque anterior
    await cerrar('p1'); await cerrar('p2');
    await recomputeSession('s1');

    // Obligación final: 10 €. Pago confirmado: 60 €. Diferencia: 50 € a
    // favor de Jorge, expresada con las reglas económicas existentes.
    const entries = await db().collection('economicEntries').get();
    assert.equal(entries.size, 1);
    assert.equal(entries.docs[0].data().amount, 1000);

    const liquidaciones = await db().collection('sessions/s1/settlements').get();
    const inversa = liquidaciones.docs.find((d) => d.data().state !== 'confirmed');
    assert.equal(inversa!.data().from, 'p1');   // Alba devuelve
    assert.equal(inversa!.data().to, 'p2');     // a Jorge
    assert.equal(inversa!.data().amount, 5000);
    // La confirmada nunca se tocó.
    assert.ok(liquidaciones.docs.some(
      (d) => d.data().state === 'confirmed' && d.data().amount === 6000));
  });

it('un ticket que NUNCA fue firme sale de la economía sin congelar nada',
  async () => {
    await sembrarTicketAbierto();
    await marcarUnidad('u0', 'p2');
    await recomputeSession('s1');
    const ticket = (await db().doc(TICKET).get()).data()!;
    assert.equal(ticket.picking.firmContribution, undefined);
    assert.deepEqual((await db().doc('sessions/s1').get()).data()!.balances, {});
  });

// ── El actor histórico que deja de estar activo ───────────────────────
it('un ticket reabierto sigue cuadrando aunque su consumidor pase a '
  + 'active:false', async () => {
  // Alba paga 60, Jorge consume 60, todos terminan.
  await sembrarTicketAbierto();
  for (let u = 0; u < 6; u++) await marcarUnidad(`u${u}`, 'p2');
  await cerrar('p1'); await cerrar('p2');
  await recomputeSession('s1');

  // Jorge paga y Alba confirma la recepción.
  const st = (await db().collection('sessions/s1/settlements').get()).docs[0];
  assert.equal(st.data().amount, 6000);
  await st.ref.update({ state: 'confirmed' });
  await recomputeSession('s1');
  const cerrado = (await db().doc('sessions/s1').get()).data()!;
  assert.equal(cerrado.balances.p1.outstanding, 0);
  assert.equal(cerrado.balances.p2.outstanding, 0);

  // El ticket se REABRE y, además, Jorge deja de estar activo.
  await desmarcarUnidad('u5', 'p2');
  await db().doc('sessions/s1/participants/p2').update({ active: false });
  await recomputeSession('s1');   // no debe lanzar

  const sesion = (await db().doc('sessions/s1').get()).data()!;
  // La economía del último cierre sigue siendo EXACTAMENTE la misma.
  assert.equal(sesion.balances.p1.paid, 6000);
  assert.equal(sesion.balances.p1.consumed, 0);
  assert.equal(sesion.balances.p2.consumed, 6000);
  // Nadie queda a deber nada por este cambio de ciclo de vida.
  assert.equal(sesion.balances.p1.outstanding, 0);
  assert.equal(sesion.balances.p2.outstanding, 0);
  // NO aparece la liquidación inversa: la única es la confirmada de antes.
  const liq = await db().collection('sessions/s1/settlements').get();
  assert.equal(liq.size, 1);
  assert.equal(liq.docs[0].data().state, 'confirmed');
  assert.equal(sesion.pendingSettlements, 0);
  // Ni obligación inversa, ni obligación nueva: la del cierre, intacta.
  const entries = await db().collection('economicEntries').get();
  assert.equal(entries.size, 1);
  assert.equal(entries.docs[0].data().debtorUid, 'uid-jorge');
  assert.equal(entries.docs[0].data().creditorUid, 'uid-alba');
  assert.equal(entries.docs[0].data().amount, 6000);
  // Y el pago confirmado sigue donde estaba.
  const pagos = await db().collection('economicPayments').get();
  assert.equal(
    pagos.docs.filter((d) => d.data().status === 'confirmed').length, 1);
});

// ── RECIERRE: DOS escenarios distintos que NO hay que confundir ───────
//
// Los dos parten del mismo sitio (firme 60 · pagado y confirmado 60 ·
// reabierto) y se separan en si Jorge está activo cuando se vuelve a
// cerrar. Los números NO coinciden y ninguno es un error del otro.
//
//   A · Jorge ACTIVO al recerrar, con 1 de 6 unidades suyas
//       → p1 consumed 5000 · p2 consumed 1000
//       → reconciliación p1 → p2 de 5000 contra el pago confirmado de 6000
//
//   B · Jorge TODAVÍA INACTIVO al recerrar
//       → sus unidades quedan sin dueño y recaen en quien pagó (ADR-021)
//       → p1 consumed 6000 · p2 no consume nada nuevo
//       → el pago confirmado de 6000 sigue congelado y cuadrando

it('RECIERRE A · Jorge vuelve a estar activo y se queda 1 de 6', async () => {
  await sembrarTicketAbierto();
  for (let u = 0; u < 6; u++) await marcarUnidad(`u${u}`, 'p2');
  await cerrar('p1'); await cerrar('p2');
  await recomputeSession('s1');
  const st = (await db().collection('sessions/s1/settlements').get()).docs[0];
  await st.ref.update({ state: 'confirmed' });
  await recomputeSession('s1');

  // Se reabre y Jorge se queda con una sola unidad. Sigue ACTIVO.
  for (let u = 1; u < 6; u++) await desmarcarUnidad(`u${u}`, 'p2');
  await cerrar('p1'); await cerrar('p2');
  await recomputeSession('s1');

  const sesion = (await db().doc('sessions/s1').get()).data()!;
  assert.equal(sesion.balances.p1.consumed, 5000);
  assert.equal(sesion.balances.p2.consumed, 1000);
  const entries = await db().collection('economicEntries').get();
  assert.equal(entries.docs[0].data().amount, 1000);
  // Reconciliación contra el pago confirmado de 6000: Alba devuelve 5000.
  const liq = await db().collection('sessions/s1/settlements').get();
  const inversa = liq.docs.find((d) => d.data().state !== 'confirmed')!;
  assert.equal(inversa.data().from, 'p1');
  assert.equal(inversa.data().to, 'p2');
  assert.equal(inversa.data().amount, 5000);
});

it('RECIERRE B · Jorge sigue inactivo: estar en el libro no es estar '
  + 'activo, y sus unidades recaen en quien pagó', async () => {
  await sembrarTicketAbierto();
  for (let u = 0; u < 6; u++) await marcarUnidad(`u${u}`, 'p2');
  await cerrar('p1'); await cerrar('p2');
  await recomputeSession('s1');
  await desmarcarUnidad('u5', 'p2');
  await db().doc('sessions/s1/participants/p2').update({ active: false });
  await recomputeSession('s1');
  const ticket = (await db().doc(TICKET).get()).data()!;
  // Sigue en `open` como dato, pero no bloquea: `ticketIsFirm` filtra por
  // activos. Cerrar por Alba basta para volver a cerrar el reparto.
  assert.ok(ticket.picking.open.p2);
  await cerrar('p1');
  await recomputeSession('s1');
  const sesion = (await db().doc('sessions/s1').get()).data()!;
  // Al cerrar, el reparto vigente NO cuenta a Jorge: las unidades que
  // seguían marcadas para él quedan sin dueño y recaen en quien pagó. Es
  // el número del escenario B; en el A serían 5000.
  assert.equal(sesion.balances.p1.consumed, 6000);
});

it('una liquidación confirmada de alguien desactivado no rompe el '
  + 'recompute (regresión previa a A19)', async () => {
  await sembrarTicketLegacy();      // sin pickingModelVersion
  await marcarTodoPara('p2');
  await recomputeSession('s1');
  const st = (await db().collection('sessions/s1/settlements').get()).docs[0];
  await st.ref.update({ state: 'confirmed' });
  await db().doc('sessions/s1/participants/p2').update({ active: false });
  // Antes de esta tarea esto lanzaba `unknownParticipant` y la sesión
  // dejaba de recalcularse entera.
  await recomputeSession('s1');
  const sesion = (await db().doc('sessions/s1').get()).data()!;
  assert.equal(sesion.balances.p2.outstanding, 0);
});

it('cambiar la topología reabre a TODOS los activos', async () => {
  await sembrarTicketAbierto();
  await cerrar('p1'); await cerrar('p2');
  await recomputeSession('s1');                       // firme, huella sellada
  await db().doc(LINEA).update({ unitIds: ['u0', 'u1', 'u2'] });
  await recomputeSession('s1');
  const ticket = (await db().doc(TICKET).get()).data()!;
  assert.deepEqual(ticket.picking.open, { p1: true, p2: true });
  assert.equal((await db().collection('economicEntries').get()).size, 0);
});

it('cambiar nombre o precio NO reabre', async () => {
  await sembrarTicketAbierto();
  await cerrar('p1'); await cerrar('p2');
  await recomputeSession('s1');
  await db().doc(LINEA).update({ name: 'Caña', totalPrice: 7000 });
  await recomputeSession('s1');
  const ticket = (await db().doc(TICKET).get()).data()!;
  assert.deepEqual(ticket.picking.open ?? {}, {});
  assert.equal((await db().collection('economicEntries').get()).size, 1);
});

it('un pid inactivo que quedó en open no bloquea el cierre', async () => {
  await sembrarTicketAbierto();
  await cerrar('p1');
  await db().doc('sessions/s1/participants/p2').update({ active: false });
  await recomputeSession('s1');
  assert.ok((await db().doc('sessions/s1').get()).data()!.balances.p1);
});

it('recompute repetido sobre el mismo estado es idempotente', async () => {
  await sembrarTicketAbierto();
  await cerrar('p1'); await cerrar('p2');
  await recomputeSession('s1');
  const v1 = (await db().doc('sessions/s1').get()).data()!.computeVersion;
  await recomputeSession('s1');
  assert.equal((await db().doc('sessions/s1').get()).data()!.computeVersion, v1);
});

// ── Derecho histórico (A11d): A19 no puede tocarlo ────────────────────
const entitlements = async () =>
  (await db().collection('sessions/s1/ticketEntitlements').get())
    .docs.map((d) => d.data().uid).sort();

it('el pagador tiene derecho histórico desde el primer recompute, con el '
  + 'ticket todavía abierto', async () => {
  await sembrarTicketAbierto();          // Alba (p1, uid ALBA) paga
  await recomputeSession('s1');
  assert.deepEqual(await entitlements(), [ALBA]);
});

it('quien consume de forma provisional también lo obtiene', async () => {
  await sembrarTicketAbierto();
  await marcarUnidad('u0', 'p2');
  await recomputeSession('s1');
  assert.deepEqual(await entitlements(), [ALBA, JORGE].sort());
});

it('un entitlement existente SOBREVIVE a una reapertura', async () => {
  await sembrarTicketAbierto();
  await marcarUnidad('u0', 'p2');
  await cerrar('p1'); await cerrar('p2');
  await recomputeSession('s1');
  const antes = await entitlements();
  // Jorge se lo quita todo y el ticket queda reabierto.
  await desmarcarUnidad('u0', 'p2');
  await recomputeSession('s1');
  assert.deepEqual(await entitlements(), antes);
});

it('tras cerrar de nuevo el derecho sigue siendo el correcto', async () => {
  await sembrarTicketAbierto();
  await marcarUnidad('u0', 'p2');
  await cerrar('p1'); await cerrar('p2');
  await recomputeSession('s1');
  await desmarcarUnidad('u0', 'p2');
  await cerrar('p1'); await cerrar('p2');
  await recomputeSession('s1');
  // No se retira a Jorge aunque ya no consuma: A11d es monótono.
  assert.deepEqual(await entitlements(), [ALBA, JORGE].sort());
});

it('la mera pertenencia al grupo no concede derecho histórico', async () => {
  await sembrarTicketAbierto();          // EDGAR es miembro y no consume
  await cerrar('p1'); await cerrar('p2'); await cerrar('p3');
  await recomputeSession('s1');
  assert.ok(!(await entitlements()).includes(EDGAR));
});
```

- [ ] **Step 6: Ejecutar la integración**

Run: `firebase emulators:exec --only firestore --project demo-salda "npm --prefix backend/functions run test:integration"`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add backend/functions/src
git commit -m "A19: las cuentas esperan a que todo el mundo termine de elegir"
```

**Criterio para avanzar:** `npm test` e integración en verde, vectores dorados intactos, ningún cambio en `packages/domain`.

---

### Tarea 6: CAS y reintento acotado en `recompute`

**Objetivo:** cerrar la carrera estructural B1, que este modelo convierte en crítica: la invocación A lee el ticket abierto, la B lo lee cerrado y publica la economía firme, y si A commitea después, borra lo que B acaba de escribir y deja el ticket cerrado sin cuentas.

**Comprobado antes de implementar:** los triggers **no tienen `retry`** (`backend/functions/src/index.ts:15-19` y `recompute.ts:1077-1110`), así que hoy un commit fallido se pierde sin más. Por eso el reintento tiene que ser explícito y dentro de la propia ejecución.

**Files:**
- Modify: `backend/functions/src/recompute.ts:633` (firma), `:927-1060` (batch final)
- Test: `backend/functions/src/test/integration/picking.it.test.ts`

**Interfaces:**
- Consumes: `ticketIsFirm` y `pickingFingerprint` de la Tarea 5.
- Produces: `recomputeSession(sid: string, attempt?: number): Promise<void>` — el segundo parámetro es interno; los triggers siguen llamando con un solo argumento.

- [ ] **Step 1: Test rojo**

```ts
it('un recompute obsoleto no puede borrar la economía firme', async () => {
  await sembrarTicketAbierto();
  await marcarUnidad('u0', 'p2');

  // A empieza con el ticket TODAVÍA abierto.
  const lecturaVieja = recomputeSession('s1');
  // B: se cierra el reparto y se publica la economía firme.
  await cerrar('p1');
  await cerrar('p2');
  await recomputeSession('s1');
  await lecturaVieja;

  // Sea cual sea el orden de llegada, el estado final es el más reciente.
  const session = (await db().doc('sessions/s1').get()).data()!;
  assert.equal(session.balances.p2.consumed, 1000);
  assert.equal((await db().collection('economicEntries').get()).size, 1);
});

it('un conflicto CAS acaba en un recompute con datos frescos', async () => {
  await sembrarTicketAbierto();
  await cerrar('p1'); await cerrar('p2');
  const sesion = db().doc('sessions/s1');
  const antes = (await sesion.get()).updateTime;
  // Escritura ajena que invalida cualquier lectura anterior.
  await sesion.update({ updatedAt: FieldValue.serverTimestamp() });
  await recomputeSession('s1');
  const despues = (await sesion.get()).data()!;
  assert.ok(despues.balances.p2);          // se recalculó, no se perdió
  assert.ok((await sesion.get()).updateTime.toMillis() > antes.toMillis());
});
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `firebase emulators:exec --only firestore --project demo-salda "npm --prefix backend/functions run test:integration"`
Expected: el primer test puede pasar por suerte (depende del entrelazado) y el segundo falla o resulta trivial. **Si el primero pasa de forma estable sin la protección, déjalo igualmente: es la prueba de regresión que fija el invariante.** Lo que debe fallar de forma determinista es la ausencia de la precondición, que se comprueba en el Step 4.

- [ ] **Step 3: Implementación mínima**

```ts
/** ¿Abortó el commit porque otra ejecución escribió antes? (gRPC 9) */
const isStaleWrite = (error: unknown): boolean =>
  (error as { code?: number } | null)?.code === 9;

export async function recomputeSession(
  sid: string,
  attempt = 0,
): Promise<void> {
  const db = getFirestore();
  const sessionRef = db.doc(`sessions/${sid}`);
  const sessionSnap = await sessionRef.get();
  if (!sessionSnap.exists) return; // borrada: cleanup se encarga
  /* … todo el cuerpo actual, sin cambios … */
```

En el batch final, poner la precondición sobre el documento que ya se actualiza siempre:

```ts
  // Serialización de resultados (A19). El batch entero aborta si alguien
  // escribió la sesión después de nuestra lectura, así que una ejecución
  // que llegó tarde con datos viejos no puede sobrescribir la economía que
  // otra acaba de publicar. Los triggers de Firestore NO reintentan (no
  // llevan `retry`), así que el reintento tiene que ser nuestro.
  batch.update(
    sessionRef,
    {
      totals: result.sessionTotals,
      balances: result.balances,
      pendingSettlements: result.pendingSettlements,
      participantsCount: snapshot.participants.length,
      computeVersion: FieldValue.increment(1),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { lastUpdateTime: sessionSnap.updateTime },
  );
```

y envolver el commit:

```ts
  try {
    await batch.commit();
  } catch (error) {
    if (isStaleWrite(error) && attempt < 2) {
      logger.info('Recompute obsoleto; se repite con datos frescos', {
        sid,
        attempt,
      });
      return recomputeSession(sid, attempt + 1);
    }
    throw error;
  }
```

Tres intentos como máximo, cada uno releyendo todo desde cero. Sin bucle infinito, sin transacción, sin tocar la estructura de `recomputeSession`.

- [ ] **Step 4: Verificar que la precondición está viva**

Añadir un test que la ejercite directamente y falle si se quita:

```ts
it('el batch lleva precondición: una lectura vieja no escribe', async () => {
  await sembrarTicketAbierto();
  const sesion = db().doc('sessions/s1');
  const vieja = (await sesion.get()).updateTime;
  await sesion.update({ updatedAt: FieldValue.serverTimestamp() });
  const batch = db().batch();
  batch.update(sesion, { totals: { grandTotal: 1 } }, { lastUpdateTime: vieja });
  await assert.rejects(batch.commit(), (e: { code?: number }) => e.code === 9);
});
```

- [ ] **Step 5: Ejecutar todo**

Run: `firebase emulators:exec --only firestore --project demo-salda "npm --prefix backend/functions run test:integration"`
Run: `npm --prefix backend/functions test`
Expected: PASS los dos.

**Gate 2:** si tras esto no puedes demostrar que un conflicto acaba en un recompute con datos frescos, PARA y consulta antes de seguir.

- [ ] **Step 6: Commit**

```bash
git add backend/functions/src
git commit -m "A19: un recompute que llega tarde no puede pisar unas cuentas mas nuevas"
```

**Criterio para avanzar:** ambos comandos en verde y Gate 2 no disparado.

---

# FASE 2 — Rules

### Tarea 7: Rules aceptan `picking` y exigen la reapertura

**Objetivo:** hacer imposible por construcción un «he terminado» obsoleto, y abrir la puerta a las dos acciones nuevas (terminar y reabrir) con la frontera de autoridad correcta.

**Tarea inseparable:** las dos ramas (la de líneas y la del ticket) van en el **mismo commit**. Con solo la primera, ningún cliente podría reabrir y toda escritura de reparto sobre un ticket A19 quedaría bloqueada; con solo la segunda, la reapertura no sería obligatoria.

**Files:**
- Modify: `backend/firestore/firestore.rules:2046-2055` (rama de líneas), `:1980-1995` (rama de ticket del dueño), `:2133-2137` (junto a `onlyAssignmentChanged`)
- Test: `backend/firestore/test/picking.test.mjs` (crear)

**Interfaces:**
- Produces: contrato de escritura que app y web deben cumplir exactamente:
  - **Reabrir/elegir** = `WriteBatch` de dos documentos: la línea como hoy, y el ticket con `{'picking.lastTarget': pid, 'picking.open.{pid}': true}`.
  - **Terminar** = `update` del ticket con `{'picking.lastTarget': pid, 'picking.open.{pid}': deleteField()}`.

- [ ] **Step 1: Escribir el test rojo completo**

Crear `backend/firestore/test/picking.test.mjs` partiendo del fixture de `unit_assignment.test.mjs` (mismos actores ALBA/JEFA/ADMIN/JORGE/INVITADA, misma sesión de grupo), con el ticket sembrado con `pickingModelVersion: 1` y `picking: { open: { p1: true, p2: true, p3: true, p5: true } }`, y una línea de 6 unidades. Helpers:

```js
/** Elegir consumo: linea + reapertura del pid, en UN batch de dos docs. */
const elegir = (actor, pid, { unit = 'u0', selected = true, firma, reabre = true } = {}) => {
  const f = db(actor);
  const b = writeBatch(f);
  b.update(doc(f, L), {
    'assignment.type': 'units',
    'assignment.schemaVersion': 2,
    'assignment.lastEditorPid': pid,
    'assignment.lastEditedUnit': unit,
    [`assignment.units.${unit}.${pid}`]: selected ? true : deleteField(),
    ...(firma ? { [`assignment.by.${unit}.${pid}`]: firma } : {}),
    ...(selected ? {} : { [`assignment.by.${unit}.${pid}`]: deleteField() }),
  });
  if (reabre) {
    b.update(doc(f, T), { 'picking.lastTarget': pid, [`picking.open.${pid}`]: true });
  }
  return b.commit();
};

const terminar = (actor, pid) =>
  updateDoc(doc(db(actor), T), {
    'picking.lastTarget': pid,
    [`picking.open.${pid}`]: deleteField(),
  });
```

Casos obligatorios (todos con `assertDeniegaLimpio` en las denegaciones):

```js
describe('A19 · elegir y terminar', () => {
  it('un participante activo elige lo suyo', async () =>
    assertSucceeds(elegir(JORGE, 'p2')));

  it('un participante DESACTIVADO no elige', async () => { /* active:false → deniega */ });

  it('un ex-miembro del grupo no elige', async () => { /* borrar membresía → deniega */ });

  it('con la sesión cerrada nadie elige', async () => { /* status closed → deniega */ });

  it('la autoselección NO lleva firma de tercero', async () =>
    assertSucceeds(elegir(JORGE, 'p2', { firma: undefined })));

  it('A10 asigna a otra persona CON procedencia', async () =>
    assertSucceeds(elegir(JEFA, 'p3', { firma: JEFA })));

  it('A10 sin firma sobre un tercero queda denegado', async () =>
    assertDeniegaLimpio(elegir(JEFA, 'p3', { firma: undefined })));

  it('admin y autoselección sobre la misma unidad no producen falso error',
    async () => {
      await assertSucceeds(elegir(JORGE, 'p2'));
      await assertSucceeds(elegir(JEFA, 'p2', { firma: null }));
    });

  it('quien ya terminó NO puede cambiar sin reabrirse', async () => {
    await terminar(JORGE, 'p2');
    await assertDeniegaLimpio(elegir(JORGE, 'p2', { unit: 'u1', reabre: false }));
  });

  it('cambio y reapertura son atómicos y se permiten juntos', async () => {
    await terminar(JORGE, 'p2');
    await assertSucceeds(elegir(JORGE, 'p2', { unit: 'u1' }));
  });

  it('A10 cambia el consumo de un MANUAL y lo reabre en el mismo commit',
    async () => {
      await terminar(JEFA, 'p3');
      await assertDeniegaLimpio(elegir(JEFA, 'p3', { firma: JEFA, reabre: false }));
      await assertSucceeds(elegir(JEFA, 'p3', { firma: JEFA }));
    });

  it('la invitada web sigue exactamente el mismo protocolo', async () => {
    await assertSucceeds(elegir(INVITADA, 'p5', { unit: 'u3' }));
    await assertSucceeds(terminar(INVITADA, 'p5'));
    await assertDeniegaLimpio(elegir(INVITADA, 'p5', { unit: 'u4', reabre: false }));
  });

  it('cada cual cierra SU pid', async () => assertSucceeds(terminar(JORGE, 'p2')));

  it('A10 cierra el pid de otra persona', async () => {
    await assertSucceeds(terminar(JEFA, 'p2'));
    await assertSucceeds(terminar(ALBA, 'p3'));
  });

  it('un participante normal NO cierra el pid de otra persona', async () =>
    assertDeniegaLimpio(terminar(JORGE, 'p1')));

  it('nadie toca la huella de topología', async () =>
    assertDeniegaLimpio(
      updateDoc(doc(db(ALBA), T), {
        'picking.lastTarget': 'p1',
        'picking.fingerprint': 'inventada',
      }),
    ));

  it('nadie toca la economía congelada, ni siquiera el dueño', async () =>
    assertDeniegaLimpio(
      updateDoc(doc(db(ALBA), T), {
        'picking.lastTarget': 'p1',
        'picking.firmContribution': {
          paidBy: 'p1', grandTotal: 6000, consumption: { p2: 6000 },
        },
      }),
    ));

  it('terminar sigue permitido en un ticket que ya tiene economía congelada',
    async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(doc(ctx.firestore(), T), {
          'picking.firmContribution': {
            paidBy: 'p1', grandTotal: 6000, consumption: { p2: 6000 },
          },
        });
      });
      await assertSucceeds(terminar(JORGE, 'p2'));
    });

  it('una escritura de picking no puede colar otro campo del ticket', async () =>
    assertDeniegaLimpio(
      updateDoc(doc(db(JORGE), T), {
        'picking.lastTarget': 'p2',
        'picking.open.p2': deleteField(),
        grandTotal: 1,
      }),
    ));

  it('un ticket SIN pickingModelVersion se comporta como hoy', async () => {
    /* resembrar sin el campo → elegir(..., { reabre: false }) PERMITIDO */
  });

  it('cliente antiguo con el pid abierto sigue pudiendo editar', async () =>
    assertSucceeds(elegir(JORGE, 'p2', { reabre: false })));

  it('cliente antiguo con el pid cerrado queda denegado', async () => {
    await terminar(JORGE, 'p2');
    await assertDeniegaLimpio(elegir(JORGE, 'p2', { unit: 'u2', reabre: false }));
  });

  it('presupuesto: 24 unidades seguidas con el getAfter extra', async () => {
    /* poner unitIds de 24 y hacer 24 `elegir` seguidos, todos PERMITIDOS */
  });
});
```

> **Regresión de presupuesto.** El caso «A10 asigna a un MANUAL y lo reabre» es la prueba que fija el límite: con **dos** accesos al ticket en esa rama devolvía `maximum of 1000 expressions`. `assertDeniegaLimpio` ya falla ante ese mensaje, y este caso lo cubre por el lado permitido.

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `firebase emulators:exec --only firestore,storage --project demo-salda "npm --prefix backend/firestore test"`
Expected: FAIL — las escrituras de `picking` se deniegan (no hay rama) y las que deberían denegarse pasan.

- [ ] **Step 3: Implementación mínima**

Junto a `onlyAssignmentChanged` (`:2133`), añadir:

```
    // ── A19: cerrar y reabrir la elección de consumo ─────────────────────
    // Un ticket bajo el protocolo nuevo solo acepta un cambio de reparto si,
    // TRAS el commit, el pid afectado sigue abierto. Así es imposible que un
    // «he terminado» sobreviva a un cambio de la selección que declaraba.
    //
    // UN SOLO acceso de documento, y es deliberado: con `get` + `getAfter`
    // el camino de A10 agota el presupuesto de 1000 expresiones (medido). El
    // «after» sirve para las dos preguntas porque `pickingModelVersion` no
    // cambia en una escritura de reparto.
    function reopensPicking(sid, aid, tid) {
      let after = getAfter(/databases/$(database)/documents/sessions/$(sid)/accounts/$(aid)/tickets/$(tid)).data;
      return after.get('pickingModelVersion', 0) != 1
        || after.get('picking', {}).get('open', {})
             .get(request.resource.data.assignment.get('lastEditorPid', ''), false) == true;
    }

    function onlyPickingChanged() {
      return request.resource.data.diff(resource.data).affectedKeys()
        .hasOnly(['picking']);
    }

    function pickingTarget() {
      return request.resource.data.picking.get('lastTarget', '');
    }

    // Forma de UNA escritura de picking: una sola persona, y nada más.
    //
    // La huella y la economía congelada son del SERVIDOR. Si un cliente
    // pudiera tocar la huella, fingiría que la topología no cambió y dejaría
    // firme un reparto que acaba de perder unidades; si pudiera tocar
    // `firmContribution`, reescribiría a mano cuánto debe cada cual en un
    // ticket reabierto, que es la deuda que sostiene los pagos ya cobrados.
    function validPickingWrite() {
      let now = request.resource.data.picking;
      let old = resource.data.get('picking', {});
      let target = pickingTarget();
      return request.resource.data.get('pickingModelVersion', 0) == 1
        && target != ''
        && now.keys().hasOnly(
             ['open', 'lastTarget', 'fingerprint', 'firmContribution'])
        && now.get('fingerprint', '') == old.get('fingerprint', '')
        && now.get('firmContribution', {}) == old.get('firmContribution', {})
        && now.get('open', {}).diff(old.get('open', {}))
             .affectedKeys().hasOnly([target]);
    }
```

En la rama de líneas (`:2046`), anteponer la condición:

```
            allow update: if onlyAssignmentChanged()
              ? (usesUnitModel()
                ? (reopensPicking(sid, aid, tid)
                  && (canPickOwnUnit(sid, aid, tid)
                  || canAssignWithProvenance(sid, aid, tid)))
                : ((isOwner(sid) && isOpen(sid))
                  || canPickOwnShare(sid, aid, tid)))
              : ((isOwner(sid) && isOpen(sid)
                  && (!usesUnitModel() || unitsOnlyPruned()))
                || canCorrectLine(sid, aid, tid));
```

En `match /tickets/{tid}`, añadir la rama de picking **antes** de la de A11c:

```
          // A19: terminar de elegir, o volver a quedar abierto. Una entrada
          // del mapa por escritura, la propia o —con la autoridad de A10—
          // la de otra persona: un MANUAL no puede pulsar nada y alguien que
          // se fue de la cena tampoco, así que sin esto un solo ausente
          // dejaría las cuentas bloqueadas para siempre.
          allow update: if onlyPickingChanged()
            && isOpen(sid)
            && validPickingWrite()
            && (claimedBy(sid, pickingTarget()) == request.auth.uid
              || isOwner(sid)
              || managesGroupOf(resource.data.get('spaceId', '')));
```

Y cerrar la puerta trasera del dueño en la rama `allow create, update` (`:1980-1990`), para que **todas** las escrituras de picking pasen por la misma validación:

```
          allow create, update: if isOwner(sid) && isOpen(sid)
            && request.resource.data.grandTotal is int
            && request.resource.data.paidByParticipantId is string
            // El picking se escribe por su propia puerta, también para el
            // dueño: por esta rama podría vaciar `open` de golpe y dar por
            // cerrado un reparto que nadie ha terminado. Al CREAR sí lo
            // escribe, que es cuando se siembra.
            && (resource == null
              || !request.resource.data.diff(resource.data)
                   .affectedKeys().hasAny(['picking']))
            && (futureSessionData(sid).get('contextModelVersion', 0) == 0
              || (request.resource.data.get('contextModelVersion', 0) == 1
                && request.resource.data.spaceId
                  == futureSessionData(sid).spaceId))
            && (request.resource.data.get('spaceId', '') == ''
              || (request.resource.data.spaceId is string
                && isSpaceMember(request.resource.data.spaceId)));
```

- [ ] **Step 4: Ejecutar y verificar que pasa**

Run: `firebase emulators:exec --only firestore,storage --project demo-salda "npm --prefix backend/firestore test"`
Expected: PASS toda la suite —`picking.test.mjs`, `unit_assignment.test.mjs`, `rules.test.mjs`, `group_ticket_*`— y **ni un solo** `maximum of`.

**Gate 1:** cualquier `maximum of 1000 expressions` aquí = PARA y consulta. No añadas un segundo acceso de documento a la rama de reparto para resolverlo.

- [ ] **Step 5: Commit**

```bash
git add backend/firestore
git commit -m "A19: no se puede cambiar lo que consumiste sin volver a quedar eligiendo"
```

**Criterio para avanzar:** suite completa de reglas en verde y Gate 1 no disparado.

---

### Tarea 8: Sembrar el protocolo al crear el ticket (Rules + app, mismo commit)

**Objetivo:** que un ticket `byItem` nazca ya con el protocolo activo, en el **mismo batch** que lo crea. Sin esto existiría la ventana «ticket creado → economía firme → después aparece picking», que es exactamente A1.

**Tarea inseparable:** la siembra en la app y la aceptación en Rules van juntas. Rules ya acepta `picking` en `create` desde la Tarea 7 (la rama del dueño no lo excluye al crear), así que aquí solo se verifica; si algún test demuestra lo contrario, se ajusta en este mismo commit.

**Files:**
- Modify: `apps/mobile/lib/features/sessions/data/firestore_session_repository.dart:149-232` y `:235-311`
- Test: `apps/mobile/test/picking_test.dart` (crear)
- Test: `backend/firestore/test/picking.test.mjs`

**Interfaces:**
- Produces: `_writeAccountWithTicket(..., required List<String> pickingPids)`.

- [ ] **Step 1: Test rojo**

Crear `apps/mobile/test/picking_test.dart`:

```dart
test('un ticket nuevo nace con el protocolo activo y todos pendientes', () async {
  final repo = _repo();
  final creada = await repo.createSession(_input(
    participantNames: ['Alba', 'Jorge', 'Tete'],
    splitModeDefault: SplitMode.byItem,
  ));
  final ticket = await repo.firestore.doc(creada.ticketPath).get();
  expect(ticket.data()!['pickingModelVersion'], 1);
  expect((ticket.data()!['picking'] as Map)['open'],
      {'p0': true, 'p1': true, 'p2': true});
});

test('añadir un ticket a una sesión siembra solo con los activos', () async {
  final repo = _repo();
  final creada = await repo.createSession(_input(
    participantNames: ['Alba', 'Jorge'], splitModeDefault: SplitMode.byItem));
  await repo.firestore
      .doc('sessions/${creada.sessionId}/participants/p1')
      .update({'active': false});
  final path = await repo.addTicket(creada.sessionId, _ticket(),
      payerPid: 'p0', spaceId: 'gr1');
  final ticket = await repo.firestore.doc(path).get();
  expect((ticket.data()!['picking'] as Map)['open'], {'p0': true});
});
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/picking_test.dart`
Expected: FAIL — los campos no existen.

- [ ] **Step 3: Implementación mínima**

En `_writeAccountWithTicket`, añadir el parámetro y los dos campos al `batch.set(ticketRef, {…})`:

```dart
      // A19: el gasto nace bajo el protocolo y con todo el mundo pendiente,
      // en el MISMO batch que lo crea. No puede existir un instante en el
      // que el ticket ya cuente para las cuentas y todavía no sepa a quién
      // está esperando: ese instante era el bug.
      //
      // Se siembra también en «a partes iguales», donde la puerta no se
      // aplica: si alguien cambia el modo después, la huella de topología
      // cambia y `recompute` reabre a todo el mundo.
      'pickingModelVersion': 1,
      'picking': {'open': {for (final pid in pickingPids) pid: true}},
```

En `createSession`, pasar los pids recién escritos:

```dart
    final ticketPath = _writeAccountWithTicket(
      batch,
      sessionRef: sessionRef,
      accountIndex: 0,
      accountName: input.accountName ?? input.ticket.merchantName,
      ticket: input.ticket,
      payerPid: 'p${input.payerIndex}',
      spaceId: input.spaceId,
      splitMode: input.splitModeDefault,
      pickingPids: [
        for (var i = 0; i < input.participantNames.length; i++) 'p$i',
      ],
    );
```

En `addTicket`, leer los participantes activos antes del batch:

```dart
    final participants = await sessionRef.collection('participants').get();
    // Solo quien sigue en el reparto. A quien ya no está no se le espera:
    // `recompute` lo descarta igual.
    final pickingPids = [
      for (final p in participants.docs)
        if ((p.data()['active'] as bool?) ?? true) p.id,
    ];
```

y pasarlos al helper.

- [ ] **Step 4: Ejecutar y verificar que pasa**

Run: `flutter test test/picking_test.dart`
Expected: PASS

- [ ] **Step 5: Verificar que Rules aceptan la creación**

Añadir a `backend/firestore/test/picking.test.mjs`:

```js
it('el dueño crea un ticket con el protocolo sembrado', async () =>
  assertSucceeds(
    setDoc(doc(db(ALBA), 'sessions/sg1/accounts/a1/tickets/t9'), {
      kind: 'manual', grandTotal: 1000, paidByParticipantId: 'p1',
      merchant: { name: 'Bar' }, spaceId: 'gr1', contextModelVersion: 1,
      splitModeOverride: 'byItem',
      pickingModelVersion: 1,
      picking: { open: { p1: true, p2: true } },
    }),
  ));
```

Run: `firebase emulators:exec --only firestore,storage --project demo-salda "npm --prefix backend/firestore test"`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add apps/mobile backend/firestore/test
git commit -m "A19: un gasto nuevo nace sabiendo a quien esta esperando"
```

**Criterio para avanzar:** `flutter test` y reglas en verde.

---

# FASE 3 — App

### Tarea 9: El modelo del ticket conoce `picking`

**Objetivo:** que `SessionTicket` transporte el estado de picking desde el stream que ya existe (`accountTicketsProvider`), para que la pantalla pueda pintarlo sin listeners nuevos.

**Files:**
- Modify: `apps/mobile/lib/features/sessions/domain/session_models.dart:176-215`
- Modify: `apps/mobile/lib/features/sessions/data/firestore_session_repository.dart:313-336` (`_ticketFrom`)
- Test: `apps/mobile/test/picking_test.dart`

**Interfaces:**
- Produces: `SessionTicket.usesPicking` (`bool`), `SessionTicket.pickingOpen` (`Set<String>`).

- [ ] **Step 1: Test rojo**

```dart
test('el ticket transporta quién falta por terminar', () async {
  final repo = _repo();
  final creada = await repo.createSession(_input(
    participantNames: ['Alba', 'Jorge'], splitModeDefault: SplitMode.byItem));
  final tickets = await repo.watchTickets(creada.sessionId, 'a0').first;
  expect(tickets.single.usesPicking, isTrue);
  expect(tickets.single.pickingOpen, {'p0', 'p1'});
});
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/picking_test.dart --plain-name "quién falta"`
Expected: FAIL — los getters no existen.

- [ ] **Step 3: Implementación mínima**

En `session_models.dart`, añadir al constructor y a los campos de `SessionTicket`:

```dart
    this.pickingModelVersion = 0,
    this.pickingOpen = const <String>{},
```

```dart
  /// A19: 1 = el gasto espera a que todo el mundo termine de elegir. 0 (o
  /// ausente) = gasto anterior al protocolo, se comporta como siempre.
  final int pickingModelVersion;

  /// pids que todavía NO han dicho «he terminado».
  final Set<String> pickingOpen;

  bool get usesPicking => pickingModelVersion == 1;
```

En `_ticketFrom`:

```dart
      pickingModelVersion: (data['pickingModelVersion'] as int?) ?? 0,
      pickingOpen: {
        for (final entry in (((data['picking'] as Map?)?['open'] as Map?) ??
                const {})
            .entries)
          if (entry.value == true) entry.key as String,
      },
```

- [ ] **Step 4: Ejecutar y verificar que pasa**

Run: `flutter test test/picking_test.dart`
Expected: PASS

- [ ] **Step 5: Commit** — agrupar con la Tarea 10, que no puede quedar verde sin este modelo. No commitear por separado.

---

### Tarea 10: Escrituras de la app — reapertura atómica y «He terminado»

**Objetivo:** que toda escritura de reparto sobre un ticket A19 lleve la reapertura en el mismo commit, y añadir la acción de terminar. Va en el **mismo commit que la Tarea 9**.

**Files:**
- Modify: `apps/mobile/lib/features/sessions/data/session_repository.dart`
- Modify: `apps/mobile/lib/features/sessions/data/firestore_session_repository.dart:491-508`
- Modify: `apps/mobile/lib/features/sessions/presentation/ticket_detail_screen.dart:691-704`
- Modify: `apps/mobile/lib/features/sessions/presentation/unit_assignment_sheet.dart`
- Test: `apps/mobile/test/picking_test.dart`

**Interfaces:**
- Consumes: `SessionTicket.usesPicking` (Tarea 9); `myPid` (Tarea 1).
- Produces:
  - `setUnitConsumer(String linePath, {required int unit, required String participantId, required bool selected, String? myPid, bool usesPicking = false})`
  - `Future<void> finishPicking(String ticketPath, {required String participantId})`
  - `Future<void> reopenPicking(String ticketPath, {required String participantId})`

- [ ] **Step 1: Test rojo**

```dart
test('elegir consumo reabre al participante en el mismo commit', () async {
  final repo = await _repoConTicketA19();          // p0 y p1 abiertos
  await repo.finishPicking(_ticketPath, participantId: 'p1');
  await repo.setUnitConsumer(_linePath,
      unit: 0, participantId: 'p1', selected: true, myPid: 'p1',
      usesPicking: true);
  final ticket = await repo.firestore.doc(_ticketPath).get();
  expect((ticket.data()!['picking'] as Map)['open'],
      containsPair('p1', true));
  expect((ticket.data()!['picking'] as Map)['lastTarget'], 'p1');
});

test('en un ticket legacy no se escribe picking', () async {
  final repo = await _repoConTicketLegacy();
  await repo.setUnitConsumer(_linePath,
      unit: 0, participantId: 'p1', selected: true, myPid: 'p1',
      usesPicking: false);
  final ticket = await repo.firestore.doc(_ticketPath).get();
  expect(ticket.data()!.containsKey('picking'), isFalse);
});

test('He terminado saca mi pid de la lista de pendientes', () async {
  final repo = await _repoConTicketA19();
  await repo.finishPicking(_ticketPath, participantId: 'p1');
  final ticket = await repo.firestore.doc(_ticketPath).get();
  expect(((ticket.data()!['picking'] as Map)['open'] as Map)
      .containsKey('p1'), isFalse);
});
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/picking_test.dart`
Expected: FAIL — `finishPicking` no existe y `setUnitConsumer` no toca el ticket.

- [ ] **Step 3: Implementación mínima**

```dart
  @override
  Future<void> setUnitConsumer(
    String linePath, {
    required int unit,
    required String participantId,
    required bool selected,
    String? myPid,
    bool usesPicking = false,
  }) async {
    final lineRef = firestore.doc(linePath);
    final asignaAOtraPersona = myPid == null || myPid != participantId;

    final batch = firestore.batch();
    batch.update(lineRef, {
      'assignment.type': 'units',
      'assignment.schemaVersion': 2,
      'assignment.lastEditorPid': participantId,
      'assignment.lastEditedUnit': 'u$unit',
      'assignment.units.u$unit.$participantId': selected
          ? true
          : FieldValue.delete(),
      'assignment.by.u$unit.$participantId': selected && asignaAOtraPersona
          ? uid()
          : FieldValue.delete(),
    });
    // A19: cambiar lo que alguien consume lo devuelve a «eligiendo», en el
    // MISMO commit. Las Rules lo exigen, y con razón: si la reapertura
    // pudiera llegar después, entre las dos escrituras existiría un instante
    // con un «he terminado» vigente sobre una selección que ya cambió, y esa
    // foto es exactamente la que publicaría unas cuentas equivocadas.
    //
    // Un gasto anterior al protocolo no lleva esta mitad: escribirle
    // `picking` haría que las Rules rechazasen el batch entero.
    if (usesPicking) {
      batch.update(lineRef.parent.parent!, {
        'picking.lastTarget': participantId,
        'picking.open.$participantId': true,
      });
    }
    await batch.commit();
  }

  @override
  Future<void> finishPicking(
    String ticketPath, {
    required String participantId,
  }) => firestore.doc(ticketPath).update({
    'picking.lastTarget': participantId,
    'picking.open.$participantId': FieldValue.delete(),
  });

  @override
  Future<void> reopenPicking(
    String ticketPath, {
    required String participantId,
  }) => firestore.doc(ticketPath).update({
    'picking.lastTarget': participantId,
    'picking.open.$participantId': true,
  });
```

Declarar las tres firmas en `session_repository.dart` con sus docs `///`.

En `ticket_detail_screen.dart`, `toggleUnit` pasa `usesPicking: ticket.usesPicking` (el `SessionTicket` está en ámbito en `_TicketLinesSection`; propágalo a `_LineTile` como campo `usesPicking` y `ticketPath`). Igual en `unit_assignment_sheet.dart`.

- [ ] **Step 4: Ejecutar y verificar que pasa**

Run: `flutter test test/picking_test.dart`
Expected: PASS

- [ ] **Step 5: Commit (agrupado con la Tarea 9)**

```bash
git add apps/mobile
git commit -m "A19: cambiar tu consumo te devuelve a eligiendo, en el mismo commit"
```

**Criterio para avanzar:** `flutter test` completo en verde y `dart analyze --fatal-infos` a cero.

---

### Tarea 11: UX de A19 en la app

**Objetivo:** que en un ticket abierto se vea quién falta, quién terminó, y que la economía todavía no es firme; con «He terminado» como acción principal y la posibilidad de cerrar por otra persona con la autoridad de A10. Copy simple, sin workflow de revisión.

**Files:**
- Modify: `apps/mobile/lib/features/sessions/presentation/ticket_detail_screen.dart` (`_TicketLinesSection`, `:480-620`)
- Modify: `apps/mobile/lib/l10n/app_es.arb`
- Test: `apps/mobile/test/picking_test.dart`

**Interfaces:**
- Consumes: `SessionTicket.pickingOpen` / `usesPicking`; `finishPicking`; `canAssignConsumptionProvider`; `ticketPaymentImpactProvider`.

- [ ] **Step 1: Añadir el copy al ARB**

En `apps/mobile/lib/l10n/app_es.arb`:

```json
  "pickingOpenTitle": "Aún estáis eligiendo",
  "pickingOpenBody": "Este gasto no entra en las cuentas hasta que todo el mundo termine.",
  "pickingWaitingFor": "Falta {names}",
  "@pickingWaitingFor": { "placeholders": { "names": { "type": "String" } } },
  "pickingClosedTitle": "Reparto cerrado",
  "pickingClosedBody": "Las cuentas de este gasto ya son firmes.",
  "pickingFinishAction": "He terminado",
  "pickingFinishForOther": "Terminar por {name}",
  "@pickingFinishForOther": { "placeholders": { "name": { "type": "String" } } },
  "pickingReopenTitle": "¿Volver a abrir el reparto?",
  "pickingReopenBody": "Este gasto ya estaba cerrado y hay {count} pago(s) confirmado(s) por {amount}. Las cuentas se quedan como están mientras lo revisáis; al volver a cerrarlo se ajustará la diferencia.",
  "@pickingReopenBody": { "placeholders": { "count": { "type": "int" }, "amount": { "type": "String" } } },
  "pickingReopenAction": "Cambiar de todas formas",
  "pickingStaleClient": "No se pudo guardar. Actualiza la app para poder cambiar un reparto ya cerrado."
```

Regenerar: `flutter gen-l10n` desde `apps/mobile`.

- [ ] **Step 2: Test rojo**

```dart
testWidgets('un ticket abierto dice quién falta y ofrece He terminado',
    (tester) async {
  await _pumpTicketDetail(tester, pickingOpen: {'p0', 'p1'}, myPid: 'p1');
  expect(find.text('Aún estáis eligiendo'), findsOneWidget);
  expect(find.textContaining('Falta Alba'), findsOneWidget);
  expect(find.text('He terminado'), findsOneWidget);
});

testWidgets('cuando no falta nadie, el reparto se declara cerrado',
    (tester) async {
  await _pumpTicketDetail(tester, pickingOpen: const {}, myPid: 'p1');
  expect(find.text('Reparto cerrado'), findsOneWidget);
  expect(find.text('He terminado'), findsNothing);
});

testWidgets('con autoridad A10 se puede terminar por otra persona',
    (tester) async {
  await _pumpTicketDetail(tester,
      pickingOpen: {'p2'}, myPid: 'p1', canAssign: true);
  expect(find.text('Terminar por Tete'), findsOneWidget);
});
```

- [ ] **Step 3: Ejecutar y verificar que falla**

Run: `flutter test test/picking_test.dart --plain-name "quién falta"`
Expected: FAIL

- [ ] **Step 4: Implementación mínima**

Añadir un widget `_PickingBanner` en `ticket_detail_screen.dart` y colocarlo en `_TicketLinesSection` justo antes de `SaldaCardList` (donde hoy va `ticketPickHint`, `:594-598`), solo cuando `ticket.usesPicking && mode == SplitMode.byItem`:

```dart
/// Estado del reparto (A19): a quién se está esperando y qué significa.
///
/// El banner existe porque «todavía no he mirado» y «no consumí nada» son
/// indistinguibles mirando las líneas: sin alguien que lo diga, lo no
/// reclamado recae en quien pagó y las cuentas salían mal a mitad de la cena.
class _PickingBanner extends ConsumerWidget {
  const _PickingBanner({
    required this.ticketPath,
    required this.pendientes,
    required this.myPid,
    required this.canAssign,
    required this.names,
  });

  final String ticketPath;
  final List<String> pendientes;   // pids activos que faltan, en orden
  final String? myPid;
  final bool canAssign;
  final Map<String, String> names;
  …
}
```

Contenido:
- `pendientes.isEmpty` → título `pickingClosedTitle`, cuerpo `pickingClosedBody`, sin acciones.
- si no → título `pickingOpenTitle`, cuerpo `pickingOpenBody`, línea `pickingWaitingFor` con los nombres unidos por «, » y « y » antes del último, un `FilledButton` con `pickingFinishAction` si `myPid` está entre los pendientes, y —si `canAssign`— un `TextButton` por cada pendiente distinto de `myPid` con `pickingFinishForOther`.

Todas las acciones usan el `guard()` que ya existe en el archivo para enseñar el error si Rules rechazan.

Los pendientes se calculan en `_TicketLinesSection`, donde ya están `participants` y el ticket:

```dart
    // Solo se espera a quien sigue participando: a un inactivo `recompute`
    // ya no lo cuenta, así que bloquear el cierre por él sería esperar a
    // alguien que no va a cambiar ni un céntimo.
    final pendientes = [
      for (final p in participants)
        if (p.active && ticket.pickingOpen.contains(p.id)) p.id,
    ];
```

**Aviso al reabrir.** En `_LineTile`, cuando el ticket esté cerrado (`pendientes.isEmpty`) y la acción vaya a cambiar el reparto, pedir confirmación si hay dinero confirmado. Reutiliza el provider que ya existe para el aviso de borrado (`ticketPaymentImpactProvider`, `ticket_payment_impact.dart:43`):

```dart
    /// Cambiar un reparto ya cerrado lo reabre y retira sus obligaciones.
    /// Si alguien ya confirmó un cobro, esa cantidad se convierte en saldo a
    /// su favor hasta el nuevo cierre: no se pierde, pero hay que decirlo.
    Future<bool> confirmarReapertura() async {
      if (pendientes.isNotEmpty) return true;
      final impact = ref.read(ticketPaymentImpactProvider((
        sessionId: sessionId,
        ticketId: ticketId,
      )));
      if (!impact.hasConfirmed) return true;
      return await showDialog<bool>(…) ?? false;
    }
```

y llamarla al principio de `toggleUnit` y de `openUnitAssignment`.

- [ ] **Step 5: Ejecutar y verificar que pasa**

Run: `flutter test test/picking_test.dart`
Expected: PASS

> Los tests de widget de este proyecto necesitan viewport alto (`tester.view.physicalSize`, ~2000 px): la lista es perezosa y el pie no se construye. Sigue el patrón de los tests de `ReviewScreen`.

- [ ] **Step 6: Verificación completa de la app**

Run: `flutter test` (en `apps/mobile`)
Run: `dart analyze --fatal-infos` (en la raíz)
Expected: verde y cero avisos.

- [ ] **Step 7: Commit**

```bash
git add apps/mobile
git commit -m "A19: el gasto dice a quien esta esperando y tu dices cuando has terminado"
```

**Criterio para avanzar:** `flutter test` y `dart analyze --fatal-infos` en verde; los goldens existentes sin cambios inesperados.

---

# FASE 4 — Web

### Tarea 12: La web escribe el mismo contrato

**Objetivo:** que el invitado siga exactamente el mismo protocolo que la app: batch de dos documentos al elegir, y «He terminado» con `lastTarget`. Un contrato divergente es lo que produjo A3.

**Files:**
- Modify: `apps/guest_web/src/lib/assignment.ts`
- Modify: `apps/guest_web/src/lib/session.svelte.ts`
- Test: `apps/guest_web/src/lib/picking.test.ts` (crear)

**Interfaces:**
- Consumes: `unitUpdate` (ya existe, sin cambios).
- Produces:
  - `pickingOpenUpdate(pid: string): Record<string, unknown>`
  - `pickingFinishUpdate(pid: string, remove: unknown): Record<string, unknown>`
  - `GuestSession.setLineUnit(line, unit, selected)` pasa a hacer `writeBatch`; `GuestSession.finishPicking()`.

- [ ] **Step 1: Test rojo**

Crear `apps/guest_web/src/lib/picking.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { pickingFinishUpdate, pickingOpenUpdate } from './assignment';

const BORRAR = Symbol('delete');

describe('contrato de picking (idéntico al de la app)', () => {
  it('reabrir declara el objetivo y lo pone en open', () => {
    expect(pickingOpenUpdate('p2')).toEqual({
      'picking.lastTarget': 'p2',
      'picking.open.p2': true,
    });
  });

  it('terminar declara el objetivo y borra su entrada', () => {
    expect(pickingFinishUpdate('p2', BORRAR)).toEqual({
      'picking.lastTarget': 'p2',
      'picking.open.p2': BORRAR,
    });
  });
});
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `npm --prefix apps/guest_web test`
Expected: FAIL — las funciones no existen.

- [ ] **Step 3: Implementación mínima**

En `assignment.ts`:

```ts
/**
 * A19: devolver a alguien a «eligiendo». Va en el MISMO batch que el cambio
 * de reparto porque las Rules lo exigen: un «he terminado» no puede
 * sobrevivir a un cambio de la selección que declaraba.
 */
export function pickingOpenUpdate(pid: string): Record<string, unknown> {
  return { 'picking.lastTarget': pid, [`picking.open.${pid}`]: true };
}

/** «He terminado»: mi pid sale de la lista de pendientes. */
export function pickingFinishUpdate(
  pid: string,
  remove: unknown,
): Record<string, unknown> {
  return { 'picking.lastTarget': pid, [`picking.open.${pid}`]: remove };
}
```

En `session.svelte.ts`, `TicketInfo` gana `pickingModelVersion: number` y `pickingOpen: string[]` (rellenados en `ticketInfoFrom` de la Tarea 4), y las escrituras pasan a batch:

```ts
  async setLineUnit(line: LineInfo, unit: number, selected: boolean): Promise<void> {
    if (!this.myPid) return;
    const pid = this.myPid;
    await this.write(async () => {
      const batch = writeBatch(db);
      batch.update(doc(db, line.path), unitUpdate(unit, pid, selected, deleteField()));
      // Un gasto anterior al protocolo no lleva esta mitad: escribirle
      // `picking` haría que las Rules rechazasen el batch entero.
      if (line.usesPicking) {
        batch.update(doc(db, line.ticketPath), pickingOpenUpdate(pid));
      }
      await batch.commit();
    });
  }

  async finishPicking(ticket: TicketInfo): Promise<void> {
    if (!this.myPid) return;
    const pid = this.myPid;
    await this.write(() =>
      updateDoc(
        doc(db, 'sessions', this.sid, 'accounts', ticket.accountId, 'tickets', ticket.id),
        pickingFinishUpdate(pid, deleteField()),
      ),
    );
  }
```

`LineInfo` gana `ticketPath` y `usesPicking`, rellenados en el listener de líneas (el `ticket.ref.path` está en ámbito) y `TicketInfo` gana `accountId`.

Nota de peso: `writeBatch` ya viene en el bundle de Firestore que la web carga; no añade dependencia nueva. Si `check-size.mjs` se disparase, es una señal a investigar, no a subir el límite.

- [ ] **Step 4: Ejecutar y verificar que pasa**

Run: `npm --prefix apps/guest_web test`
Run: `npm --prefix apps/guest_web run build`
Expected: PASS y build en verde, presupuesto de peso incluido.

- [ ] **Step 5: Commit** — agrupar con la Tarea 13: sin la interfaz, el invitado no tendría cómo terminar y la web dejaría un ticket abierto para siempre.

---

### Tarea 13: UX de A19 en la web

**Objetivo:** el mismo mensaje que en la app, con el vocabulario del invitado. Va en el **mismo commit que la Tarea 12**.

**Files:**
- Modify: `apps/guest_web/src/views/PickItems.svelte`
- Test: comprobación manual contra el emulador (la web no tiene tests de render)

- [ ] **Step 1: Implementación mínima**

En `PickItems.svelte`, dentro de cada `<section>` de ticket seleccionable, encima de las líneas:

```svelte
{#if ticket.pickingModelVersion === 1}
  {@const pendientes = ticket.pickingOpen
    .map((pid) => names.get(pid))
    .filter((n): n is string => Boolean(n))}
  <div class="picking" class:cerrado={pendientes.length === 0}>
    {#if pendientes.length === 0}
      <strong>Reparto cerrado.</strong>
      <span>Las cuentas de este gasto ya son firmes.</span>
    {:else}
      <strong>Aún estáis eligiendo.</strong>
      <span>
        Falta {shareNames(pendientes)}. Hasta que todos terminéis, este gasto
        no entra en las cuentas.
      </span>
      {#if guest.myPid && ticket.pickingOpen.includes(guest.myPid)}
        <button class="btn" onclick={() => guest.finishPicking(ticket)}>
          He terminado
        </button>
      {/if}
    {/if}
  </div>
{/if}
```

`shareNames` ya existe en el archivo (`:96-99`). El estilo reutiliza las clases de tarjeta existentes; nada de componentes nuevos.

El pie que hoy muestra `balances.consumed` («llevas marcado») debe dejar de prometer un importe firme mientras el ticket esté abierto: sustituir por el recuento de unidades marcadas, que es información local y no accionable, o por el texto «Se calculará cuando todos terminéis». Elegir lo primero si `myConsumed` ya es 0 en tickets abiertos (lo será: el ticket no entra en `balances`).

- [ ] **Step 2: Comprobación manual contra el emulador**

```bash
node backend/functions/tools/seed-emulator.mjs
```

Con la web en `npm run dev` y la app o la consola del emulador como segundo actor, verificar:
1. el banner enumera a quien falta y se actualiza en vivo cuando otra persona termina;
2. «He terminado» quita mi nombre de la lista, en vivo, en las dos superficies;
3. volver a tocar una unidad me devuelve a la lista, en vivo;
4. un rechazo de Rules (cerrar la sesión desde la consola y tocar una unidad) enseña el mensaje de la Tarea 3;
5. un cambio de `splitModeOverride` desde la consola cambia la pestaña sin recargar (A6).

- [ ] **Step 3: Build**

Run: `npm --prefix apps/guest_web run build`
Expected: verde, `svelte-check` a cero, presupuesto de peso en verde.

- [ ] **Step 4: Commit (agrupado con la Tarea 12)**

```bash
git add apps/guest_web/src
git commit -m "A19: el invitado tambien dice cuando ha terminado de elegir"
```

**Criterio para avanzar:** vitest, build y los cinco puntos de la comprobación manual.

---

# FASE 5 — Cierre

### Tarea 14: Contrato vivo y ADR

**Objetivo:** dejar escrito el contrato de A19 donde el proyecto los guarda, y enlazarlo desde los documentos que se leen al empezar una sesión.

**Files:**
- Create: `docs/CIERRE_DE_CONSUMO.md`
- Modify: `docs/BIBLIA_SALDA.md` (ADR-041)
- Modify: `CLAUDE.md` (§2 punto exacto y §10 tabla de archivos clave)

- [ ] **Step 1: Escribir `docs/CIERRE_DE_CONSUMO.md`**

Con la estructura de los contratos existentes (`docs/REPARTO_POR_UNIDADES.md` es el más cercano): modelo de datos, invariante, ciclo de vida, autoridad por actor, qué reabre y qué no, economía mientras está abierto, reapertura de un ticket ya cobrado, compatibilidad con clientes antiguos, y la tabla de mediciones que sostiene el diseño (presupuesto de Rules incluido, con el aviso explícito de **un solo acceso de documento** en la rama de reparto).

- [ ] **Step 2: ADR-041 en la Biblia**

Contexto (A1: cada selección intermedia se publicaba como economía firme), decisión (`picking.open` en el ticket, reapertura obligatoria por Rules, tickets no firmes fuera de la economía), alternativas descartadas (`schemaVersion 3`, `pending` por unidad, generaciones, mapas invertidos, colección auxiliar, debounce de recompute) y consecuencias.

- [ ] **Step 3: Actualizar `CLAUDE.md`**

En §2, añadir A19 al punto exacto. En §10, añadir `docs/CIERRE_DE_CONSUMO.md` a la tabla. En §12, añadir la nota «un solo acceso de documento en la rama de reparto de las Rules» a las cosas raras que no hay que romper.

- [ ] **Step 4: Verificación completa del repositorio**

```bash
dart analyze --fatal-infos
dart test                      # en packages/domain y packages/ocr_parser
flutter test                   # en apps/mobile
npm --prefix backend/functions test
npm --prefix apps/guest_web run build
firebase emulators:exec --only firestore,storage --project demo-salda "npm --prefix backend/firestore test"
firebase emulators:exec --only firestore --project demo-salda "npm --prefix backend/functions run test:integration"
```

Expected: los siete en verde.

- [ ] **Step 5: Commit**

```bash
git add docs CLAUDE.md
git commit -m "docs: contrato de cierre de consumo y ADR-041"
```

**Criterio para avanzar:** los siete comandos en verde. A19 terminado.

---

## Limpieza de sondas

Las sondas de investigación viven fuera de git en `backend/firestore/node_modules/.probe/` y `backend/functions/node_modules/.probe/`. Los casos que valía la pena conservar están ya como tests permanentes (Tareas 5, 6, 7). Al cerrar la Tarea 14, borrar el contenido de ambos directorios: su valor ya está en la suite.

## Autocomprobación del plan

- **Cobertura de la especificación del usuario.** Lifecycle → T7, T8, T10. Censo de pendientes → T5 (`ticketIsFirm` con `activeIds`), T8 (siembra), T11 (filtro de activos). Topología reabre a todos → T5. Economía alternativa A con contribución congelada → T5. Reapertura de ticket cobrado → T5 (cuatro tests) y T11 (aviso). Derecho histórico intacto → T5 (cinco tests). CAS/retry → T6. Clientes antiguos → T7 (dos tests) y T10 (`usesPicking`). Realtime web → T4. A2/A3 → T1. A4 → T2. A5 → T3. A6 → T4. UX → T11 y T13. Creación atómica → T8. Rollout → tabla de rollout. Todos los tests obligatorios listados por el usuario están asignados a una tarea concreta.
- **Sin marcadores de posición.** Cada paso lleva el código o el comando exacto; las dos excepciones deliberadas son los cuerpos de `mergeTickets` (T4) y del banner (T11/T13), donde el plan fija estructura, nombres, comportamiento y criterio de aceptación porque el detalle depende de los componentes de estilo ya existentes en cada superficie.
- **Consistencia de tipos.** `usesPicking`/`pickingOpen`/`pickingModelVersion` se usan con el mismo nombre en `SessionTicket` (T9), en `setUnitConsumer` (T10), en la UI (T11) y en `TicketInfo`/`LineInfo` de la web (T12). `pickingFingerprint`/`ticketIsFirm`/`frozenContribution` se definen en T5 y solo se consumen en T5 y T6; `frozenContribution` devuelve el mismo `TicketContribution` que `BalanceEngine` ya recibe, sin tipo nuevo. `picking.firmContribution` tiene la misma forma en el contrato de datos, en T5 (escritura), en T7 (Rules que la protegen) y en los tests. El contrato de escritura de cliente (`picking.lastTarget` + `picking.open.{pid}`) es literalmente el mismo en Rules (T7), app (T10) y web (T12), y ningún cliente escribe `fingerprint` ni `firmContribution`.
- **Invariantes de la corrección del 2026-08-31.** (1) Las selecciones nuevas mientras `open` no tocan la economía firme: `contributions` y `economicEntries` salen de `firmContribution`, no del consumo vivo. (2) Un pago `confirmed` nunca se borra: recompute no los toca y las liquidaciones confirmadas siguen congeladas. (3) Reabrir no fabrica deuda inversa: la obligación no se retira, así que no hay sobrepago que interpretar. (4) Lo único accionable durante `open` procede del último reparto CERRADO, nunca del intermedio. (5) Al cerrar, la reconciliación la hacen `BalanceEngine` y `EconomicLedger` sin ayuda. (6) No hay motor nuevo: `frozenContribution` produce la misma estructura de entrada de siempre. (7) A11d no se toca.
- **Invariante de la corrección del 2026-09-01.** La economía congelada se usa **literal**: ni se sanea, ni se reinterpreta según quién siga activo. Lo que se amplía es el universo del libro (`ledgerIds`), no la contribución. Con eso, un actor histórico que pasa a `active:false` deja de poder elegir y de bloquear el cierre, pero sigue pudiendo ser nombrado en el saldo que ya tenía — y la economía del último cierre permanece idéntica hasta que el reparto se cierre otra vez. `splitTicket`, `sanitizeLine`, `BalanceEngine`, su espejo TS y los vectores dorados no cambian.
