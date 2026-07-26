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
  linkedUid: null → uid        ← lo único que se escribe

spaces/{spaceId}/manualLinkRequests/{manualId}_{uid}
  manualId · uid · displayName? · status: pending|accepted|rejected
  createdAt · updatedAt · schemaVersion: 1
```

`recompute` carga los alias del espacio (`manualId → linkedUid`) y los pasa a
`accountUidsOf`, que ahora resuelve un actor manual vinculado a su UID **solo
a efectos de audiencia**. Nada más cambia: mismos ids de documento, mismos
actores, mismos importes, mismos balances, mismas liquidaciones.

## Seguridad: aprobación del anfitrión

Vincular es apropiarse de un historial económico, así que hacen falta **dos
partes**:

1. **La persona pide** — crea `manualLinkRequests/{manualId}_{uid}` para sí
   misma. Rules exige `uid == auth.uid`: nadie pide en nombre de otro. Vale
   tanto para una cuenta como para un invitado.
2. **El anfitrión decide** — solo él pasa la solicitud a `accepted` o
   `rejected`, y **aceptar escribe el `linkedUid` en el MISMO batch**,
   validado con `getAfter`. Sin ese emparejamiento no existe forma de
   escribir un vínculo.

Invariantes que Rules impone:

- un manual **no puede nacer vinculado**;
- **vincular es irreversible**: ni se revincula ni se desvincula, porque eso
  reescribiría a quién pertenece un historial ya escrito;
- no se solicita sobre un manual ya vinculado;
- las solicitudes **no son enumerables** salvo por el anfitrión;
- las solicitudes **no se borran**: son el rastro de que hubo aprobación.

## Migración

**No hay migración.** Es la propiedad que hizo elegir el alias: los
documentos existentes siguen siendo válidos tal cual. Un `linkedUid` nulo
—el estado de todo lo escrito hasta hoy— se comporta exactamente como antes.

## Qué se conserva

Gastos, balances, pagos, actividad e historial: intactos, con pruebas que lo
demuestran comparando el agregado antes y después de vincular (mismos ids,
mismos actores, mismos importes, mismos `settlementSync`, mismo pid).

## Pruebas

- `recompute.test.ts` (4): el actor no cambia · la persona pasa a ser lectora
  · balances e importes no se mueven · entre dos manuales, vincular a uno ya
  publica la deuda.
- `rules.test.mjs`, bloque «vinculación de identidad» (11): casi todas
  negativas — suplantación sin aprobación, pedir en nombre de otro,
  autoaprobarse, escribir el vínculo sin solicitud, revincular, desvincular,
  solicitar sobre uno ya vinculado, enumerar, borrar el rastro.

## Interfaz

- **Quien lo pide**: en el ticket abierto por enlace, tras identificarse como
  un MANUAL, aparece «Soy yo». La tarjeta muestra después el estado
  (pendiente / vinculada), así que nadie se queda sin saber qué pasó.
- **El anfitrión**: en el detalle del grupo, sobre las invitaciones, ve
  «Solicitudes de identidad» con quién dice ser quién y dos botones,
  **Aceptar** y **Rechazar**. El texto avisa de lo que implica aceptar: esa
  persona pasará a ver sus gastos y su saldo, y no cambia nada de lo ya
  registrado.

Fuera de alcance por decisión del sprint: consolidar en una sola fila los
saldos de alguien que tuviera obligaciones propias *y* heredadas en el mismo
contexto. `resolveActorIdentity` queda escrita para cuando se aborde.
