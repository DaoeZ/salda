# Cierre de consumo (A19) — contrato

> Contrato vivo de A19. Complementa `docs/REPARTO_POR_UNIDADES.md` (P2.2), que
> sigue describiendo CÓMO se reparte; esto describe CUÁNDO ese reparto cuenta
> como dinero. Decisión: ADR-041 en `docs/BIBLIA_SALDA.md`.

## El problema

Elegir qué consumiste se escribía y se publicaba a la vez. Cada toque
disparaba un recompute que creaba liquidaciones y obligaciones P5 firmes a
partir de un reparto a medio hacer. Y como lo no reclamado recae en quien
pagó (ADR-021), los estados intermedios no eran «aproximados»: con 1 de 6
unidades marcadas, a la pagadora se le imputaban 50 de 60 €, y esa deuda era
marcable y confirmable por cualquiera.

La causa raíz no es concurrencia —las escrituras punteadas por par (unidad,
persona) ya eran correctas— sino una **ambigüedad**: «todavía no he mirado» y
«no consumí nada» son indistinguibles mirando las líneas. Falta un bit.

## El dato

Dos campos en el documento del ticket. Nada más: ni colección auxiliar, ni
`schemaVersion` nuevo, ni cambio en `assignment`.

```
sessions/{sid}/accounts/{aid}/tickets/{tid}
  pickingModelVersion: 1              // ausente = gasto anterior al protocolo
  picking: {
    open: { '{pid}': true, … },       // quién NO ha terminado de elegir
    lastTarget: '{pid}',              // a quién afecta ESTA escritura
    fingerprint: '{huella}',          // topología + modo · SOLO recompute
    firmContribution: {               // última economía FIRME · SOLO recompute
      paidBy, grandTotal, consumption: { '{pid}': céntimos }
    }
  }
```

**Firme** ⟺ `pickingModelVersion != 1` **o** modo efectivo `equal` **o**
(`open` filtrado por activos vacío **y** la huella coincide).

## Ciclo de vida

| Suceso | Efecto |
|---|---|
| Se crea el gasto | Nace con `pickingModelVersion: 1` y `open` sembrado con los participantes activos, en el MISMO batch. No hay ventana en la que ya cuente y todavía no sepa a quién espera |
| Alguien elige o cambia su consumo | Su pid vuelve a `open`, en el mismo commit. Lo exigen las Rules |
| A10 cambia el consumo de otra persona | Reabre a ESA persona, mismo commit |
| «He terminado» | El pid sale de `open`. Cada cual el suyo; A10, el de quien no puede pulsar (un MANUAL, alguien que se fue) |
| Cambia la topología (`unitIds`, líneas, modo) | `recompute` reabre a TODOS los activos. Una unidad nueva no puede volverse residual del pagador sin que nadie haya podido reclamarla |
| Cambia nombre, precio o total | **No** reabre: no altera QUÉ consumió nadie |
| Un pendiente deja de estar activo | Deja de bloquear. Sin esto, un expulsado congelaría el gasto para siempre |

## Economía

Un ticket **no firme** no aporta a `balances`, `settlements`,
`totals.settlementRequired` ni `economicEntries`. Sí aporta a
`accountTotals.grandTotal` y `totals.grandTotal`: lo pagado es descriptivo,
no un balance.

**Un ticket reabierto no se retira: se congela.** Aporta su
`picking.firmContribution` —el `TicketContribution` que `BalanceEngine` ya
recibe, guardado tal cual al cerrar—. Retirarlo dejaría un pago `confirmed`
sin la obligación que lo justificaba, el modelo lo leería como sobrepago y
**fabricaría una liquidación inversa por el importe entero, nueva y
cobrable, solo por estar editando**. Congelándolo no aparece nada: las
obligaciones siguen cuadrando con los pagos hasta que el reparto se cierre
otra vez, y entonces `BalanceEngine` y `EconomicLedger` hacen la
reconciliación con sus reglas de siempre.

La contribución congelada se usa **literal**: no se sanea ni se reinterpreta
según quién siga activo hoy.

### Dos universos

`activeIds` hacía dos trabajos incompatibles. Se separan:

| Universo | Para qué | Quién entra |
|---|---|---|
| **Reparto** (`activeIds`) | `splitTicket`, `sanitizeLine`: quién recibe consumo NUEVO | solo `active !== false` |
| **Libro** (`ledgerIds`) | `computeBalance`: quién puede ser NOMBRADO en un saldo | los activos **más** los actores con peso económico contraído |

«Peso contraído» = los dos extremos de una liquidación **confirmada**, y los
pids de una `firmContribution` en uso. Estar en el libro **no** es estar
activo: no da permisos, no permite seleccionar, no entra en `open` y no
recibe consumo nuevo.

Sin esta separación, desactivar a alguien con una liquidación confirmada
hacía que `computeBalance` lanzara `unknownParticipant` y **la sesión entera
dejaba de recalcularse**. Ocurría ya, sin A19.

### Recierre: dos escenarios que no hay que confundir

Ambos parten de: firme 60 € · pagado y confirmado 60 € · reabierto.

- **A · la persona sigue ACTIVA** y se queda 1 de 6 → `p1` consume 50, `p2`
  consume 10, y aparece la reconciliación `p1 → p2` de 50 €.
- **B · la persona sigue INACTIVA** → sus unidades quedan sin dueño y recaen
  en quien pagó (ADR-021) → `p1` consume 60. El pago confirmado sigue
  congelado.

## Autoridad

| Actor | Elegir lo suyo | Terminar lo suyo | Terminar por otro |
|---|---|---|---|
| Participante con pid reclamado y activo | Sí | Sí | No |
| Invitado del enlace | Sí | Sí | No |
| Dueño de la sesión / admin del grupo (A10) | Sí | Sí | **Sí** |
| Participante `active: false` | **No** (A4) | — | — |
| MANUAL | No puede actuar | — | Lo cierra A10 |

La huella y la economía congelada **no las escribe ningún cliente**: solo
`recompute`. El dueño perdió además su puerta trasera — por su rama de
siempre ya no puede tocar `picking`.

## Compatibilidad

- Ticket **sin** `pickingModelVersion`: se comporta exactamente como antes,
  para siempre. Sin migración de datos históricos.
- Cliente **antiguo** + ticket nuevo con el pid **abierto**: sigue pudiendo
  editar con normalidad.
- Cliente **antiguo** + pid ya **cerrado**: escritura denegada. Degrada
  denegando, nunca corrompiendo: un cliente viejo no puede dejar un
  «he terminado» obsoleto.

## Restricción de Rules que NO se puede romper

La rama de reparto por unidades admite **UN** acceso de documento adicional
(`reopensPicking` usa un solo `getAfter`), y `validUnitWrite` se evalúa **una
sola vez**, izada a la rama. Antes la llamaban las dos funciones de autoridad
por separado y el camino de A10 la pagaba dos veces: con esa duplicación,
añadir la comprobación de reapertura agotaba las 1000 expresiones (medido:
22–24 denegaciones sucias). Si alguien vuelve a meter `validUnitWrite` dentro
de `canPickOwnUnit` o `canAssignWithProvenance`, o añade un segundo acceso,
el presupuesto revienta en el camino de A10 sobre un MANUAL, que es el que
cae primero. `backend/firestore/test/picking.test.mjs` lo vigila.

## Serialización de resultados

`recomputeSession` escribe con precondición `lastUpdateTime` sobre la sesión y
reintenta hasta 3 veces releyendo todo. Los triggers de Firestore **no llevan
`retry`**, así que un commit abortado se habría perdido y el estado obsoleto
se habría quedado. Sin esto, la carrera «A leyó el ticket abierto, B lo leyó
cerrado y publicó, A commitea después» borraba la economía recién publicada.

## Lo que A19 NO toca

`assignment` (ni forma, ni `schemaVersion`, ni `units`, ni `by`),
`SplitEngine`, `BalanceEngine`, `EconomicLedger`, los vectores dorados,
`ticketEntitlements` (A11d sigue siendo monótono y el pagador lo obtiene
desde el primer recompute, con el gasto aún abierto), `ticketParticipants`
(ADR-036: el enlace de ticket existe para preguntar qué consumió alguien,
bloquearlo mientras se elige sería al revés), el backup, los índices y las
Functions —no hay ninguna nueva: `recomputeOnTicket` ya cubría la ruta.
