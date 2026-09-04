# BACKLOG DE SALDA — A1–A20 + N1–N3

> **Este documento es la fuente ÚNICA y versionada del estado de A1–A20 y N1–N3.**
> Antes de tocar código de cualquiera de estos identificadores, léelo. Si una
> conversación, un plan o un mensaje de commit dice otra cosa sobre un A#, manda
> este archivo.
>
> **Orden de lectura de una sesión nueva:** `CLAUDE.md` → **este archivo** →
> `docs/BIBLIA_CODIGO_SALDA.md` → el código, los tests y Git.
>
> **Origen:** creado el 2026-09-04 al cerrar la auditoría de estado real
> A1–A20 + N1–N3. Hasta esa fecha el backlog vivía SOLO en conversaciones, lo
> que provocó que A12 siguiera figurando como pendiente meses después de
> haberse cerrado con reproducción y fix. Ese fallo es la razón de que este
> archivo exista.

---

## ⚠️ AVISO CRÍTICO: colisión de numeración

El plan de A19 (`docs/superpowers/plans/2026-08-31-a19-cierre-de-consumo.md`) y
varios mensajes de commit usan etiquetas **`A1`, `A2`, `A3`, `A4`, `A5`, `A6`,
`A7`** como **números de tarea internos de aquel plan**. **NO son los IDs de
este backlog.**

| Etiqueta en el plan/commit de A19 | Qué significa ALLÍ | Qué NO es |
|---|---|---|
| `A19 (A2/A3)` — commit `0e7a99b` | Firmar `assignment.by` solo al asignar el consumo de otra persona | **No** es A2 «Eliminar tickets» ni A3 «Abandonar grupo» |
| `A19 (A4)` — commit `ce4a08f` | Un participante `active: false` ni elige ni cuenta | **No** es A4 «Eliminar grupo con papelera» |
| `A19 (A5/A6)` — commit `5c7b877` | La web dice por qué le rechazan una escritura · lista de tickets en vivo | **No** es A5 «Enlace único de grupo» ni A6 «Reserva de identidad guest» |
| `A7` (sonda K del plan) | Un `WriteBatch` con dos mutaciones al mismo documento se deniega | **No** es A7 «Liberación de identidad por anfitrión» |

**Regla permanente: nunca inferir el significado de un A# a partir de la
etiqueta de un plan interno o de un mensaje de commit. Consultar SIEMPRE este
archivo primero.** Las etiquetas antiguas conservan su significado únicamente
dentro del documento donde nacieron.

---

## Resumen de estados

*Fotografía de la auditoría del 2026-09-04. Los porcentajes son orientativos —
sirven para distinguir «no existe» de «falta un camino»— y **no** son contrato.*

| ID | Nombre canónico | Estado | % (2026-09-04) |
|---|---|---|---|
| A1 | Home más visual + fotos | PARCIAL | 30% |
| A2 | Eliminar tickets (lifecycle del gasto) | **RESUELTO** | 100% |
| A3 | Abandonar un grupo | PARCIAL | 60% |
| A4 | Eliminar grupo con papelera, historial y aviso | PENDIENTE (contrato cerrado) | 5% |
| A5 | Enlace único de grupo para guests/manuales | PARCIAL + conflicto de diseño | 40% |
| A6 | Reserva persistente de identidad guest | PARCIAL (muy avanzado) | 85% |
| A7 | Liberación de identidad por anfitrión/admin | PENDIENTE | 0% |
| A8 | Revisión explícita del ticket | PENDIENTE / no implementado | 0% |
| A9 | Reparto inteligente en relaciones de dos personas | PENDIENTE + ADR previo | 0% |
| A10 | Asignación administrativa del consumo | **RESUELTO + DEUDA ACEPTADA** | 100% |
| A11 | Roles y permisos de grupo para gastos | **RESUELTO** | 100% |
| A12 | OCR: productos fantasma del desglose fiscal | **RESUELTO** | 100% |
| A13 | Indicadores de atención por espacio | PARCIAL | 30% |
| A14 | `balanceSummaries` o proyección equivalente | NO IMPLEMENTADO A PROPÓSITO / CONDICIONAL A MÉTRICAS | n/a |
| A15 | Revisar el ticket aunque el total cuadre | **RESUELTO** | 100% |
| A16 | Offline-first | PARCIAL | 35% |
| A17 | Autoridad de cobro: quién confirma | **RESUELTO** | 100% |
| A18 | Liquidación por obligación concreta | **RESUELTO** | 100% |
| A19 | Cierre de consumo (`picking.open`) | **RESUELTO** | 100% |
| A20 | Confirmar cobros desde cualquier superficie de balance | **RESUELTO** | 100% |
| N1 | Sistema de notificaciones | EN DISCUSIÓN (producto) + PARCIAL (técnico) | 10% técnico |
| N2 | Web completa | PARCIAL | 25% |
| N3 | Reconciliación / reembolso | EN DISCUSIÓN + contención parcial | 15% |

---

# A1 — Home más visual + fotos

**Estado: PARCIAL (~30%).**

## Contrato

Filas de espacios con más presencia visual: avatar claramente mayor, nombre más
protagonista, saldo relevante a la derecha. **Eliminar la segunda línea genérica
«Espacios».** Segunda línea con contexto útil **cuando exista**: «Falta tu
revisión», último ticket/fecha, «Todo al día»… Nunca usar «Grupo»/«Relación»
por defecto como información secundaria inútil.

Fotos:
- Relación con usuario registrado → **foto real de su perfil**.
- Grupo → **foto propia**, editable por quien tenga autoridad.
- Persona manual/sin cuenta → inicial + color como fallback, con **foto manual
  opcional**.
- Si una identidad manual se vincula después, por defecto **prevalece la foto
  real del perfil**.

## Qué existe hoy

- `apps/mobile/lib/features/home/presentation/home_space_row.dart` y
  `apps/mobile/lib/features/spaces/presentation/space_row.dart`: avatar
  `radius: 19`, título en `titleSmall`, saldo a la derecha con `MoneyText`
  (signo, tono y multi-moneda).
- `SaldaAvatar` (`apps/mobile/lib/core/ui/badges.dart:82`): iniciales + color
  FNV-1a sobre `TokenColors.avatarPalette`, o un emoji (`space.avatarEmoji`).
  Forma del avatar como discriminante: círculo = relación, cuadrado = grupo.
- `space_row.dart` sí pone contexto útil: número de personas y badge de
  «contexto no listo para repartir».

## Qué falta

1. **La segunda línea genérica sigue viva.** `home_space_row.dart` cae en
   `l10n.spacesTitle` = **«Espacios»** siempre que no haya vinculación manual
   pendiente. Es exactamente lo que el contrato manda quitar.
2. **Contexto útil**: solo existe `manualLinkPendingInSpace`. Faltan los estados
   accionables (ver A13, del que A1 debe beber) y «Todo al día».
3. **Fotos: 0%.** `SaldaAvatar` no acepta imagen. No hay foto de grupo, ni campo
   de foto en `profiles/{uid}`, ni foto manual opcional, ni regla de precedencia
   al vincular. El único `NetworkImage` del proyecto es el de Google en
   `apps/mobile/lib/features/settings/presentation/settings_screen.dart:230`, y
   no llega a ninguna fila.

## Dependencias

- La segunda línea depende de **A13** (señales fiables). No inventar señales
  locales para rellenarla.
- Las fotos son un **subsistema aparte** (Storage, Rules, subida, precedencia):
  no mezclarlas con el retoque visual de las filas.

---

# A2 — Eliminar tickets (lifecycle del gasto)

**Estado: RESUELTO (100%).**

## Contrato

Eliminar un gasto de verdad, con autoridad demostrable en backend, evidencia de
quién lo hizo, aviso previo cuando hay pagos, purga en cascada y conservación de
los pagos independientes. **A2 es exclusivamente el ciclo de vida de UN ticket**
—no de un grupo, que es A4—.

## Qué existe

- **ADR-040** (`docs/BIBLIA_SALDA.md`) y `docs/ESPACIOS.md` § «Eliminar un gasto».
- Commit `68fc292` «A2: eliminar un gasto de verdad, y que se sepa quién lo eliminó».
- **Hard delete** + evidencia inmutable `sessions/{sid}/ticketRemovals/{tid}`
  (`ticketId`, `accountId`, `merchantName`, `grandTotal`, `removedBy`,
  `removedAt`, `schemaVersion`) escrita en el MISMO commit:
  `apps/mobile/lib/features/sessions/data/firestore_session_repository.dart:663-690`.
- Rules: `backend/firestore/firestore.rules:1880` (`ticketRemovals`) y `:2034`
  (`existsAfter` + `getAfter` sobre la evidencia).
- Purga: `cleanupOnTicketDelete` (`backend/functions/src/cleanup.ts`), idempotente.
- Atribución en P6: `backend/functions/src/activity.ts:565` firma el hecho con
  quien borró, no con el dueño de la sesión.
- UI con aviso de impacto (confirmados y declaraciones pendientes) en
  `ticket_detail_screen.dart:200-290`; autoridad en `canDeleteTicketProvider`.
- Un pago **no depende** de que su obligación siga existiendo
  (`docs/RELACIONES_ECONOMICAS.md:67`).

## Tests

`backend/firestore/test/ticket_deletion.test.mjs` (21 casos: matriz de
autoridad, sesión cerrada, evidencia obligatoria) ·
`backend/functions/src/test/integration/ticketDeletion.it.test.ts` (vectores
económicos A–E) · `backend/functions/src/test/activity.test.ts` ·
`apps/mobile/test/ticket_deletion_test.dart`.

## Deuda aceptada

`ticketEntitlements` **no se borran** al eliminar un ticket: son monotónicos
frente a correcciones, y esa decisión es de A11d, no de A2.

---

# A3 — Abandonar un grupo

**Estado: PARCIAL (~60%).**

## Contrato

Debe poder abandonarse un grupo **aunque existan saldos**. Al abandonar:
- deja de ser miembro activo;
- no participa en gastos nuevos;
- historial, tickets y consumos sobreviven;
- los saldos históricos siguen vivos hasta liquidarse;
- puede seguir consultando y liquidando lo que le corresponda.

**Sucesión del propietario**, en este orden exacto:
1. si existe otro **admin** válido → transferir la propiedad con criterio determinista;
2. si no → **miembro REGISTRADO** adecuado / más antiguo;
3. **nunca** convertir automáticamente a un guest o a un manual en propietario;
4. si no existe usuario registrado capaz de asumirla → **bloquear** la salida del owner.

> **No es requisito** mostrar cuánto debes antes de salir. No usar su ausencia
> como motivo para dejar A3 abierto.

## Qué existe hoy

- `spaces_repository.dart:992` `leave()`: borra **solo** la membresía y **no**
  comprueba saldos (correcto según contrato).
- **Derecho histórico garantizado**: `ticketEntitlements` no se retiran jamás
  (`backend/functions/src/recompute.ts:204-209`), que es lo que permite a quien
  se fue seguir auditando y liquidando su deuda. Reforzado por ADR-039.
- UI: `space_management_screen.dart:1098` (tile «Salir») y `:1191` (`_leave`).
- Rules y concurrencia probadas en `backend/firestore/test/group_member_removal.test.mjs` (33 casos).

## Qué falta

**La sucesión del propietario no existe en ninguno de sus cuatro pasos.**

- `canLeave = !owner && isFullAccount` (`space_management_screen.dart:1076`): al
  propietario **ni siquiera se le muestra «Salir»**.
- `leave()` lanza `SpaceFailureCode.ownerCannotLeave` en seco; si se alcanzara,
  la UI muestra un `spaceActionError` genérico, sin explicación ni salida.
- `transferOwnership` (`spaces_repository.dart:701`) existe pero es una acción
  **manual y separada**: elegir a dedo un miembro desde la gestión (`:964`).
- No hay criterio determinista, ni caída al miembro registrado más antiguo, ni
  exclusión explícita de guest/manual como sucesores, ni bloqueo razonado.

## Dependencias

Toca el ciclo de vida del espacio, igual que **A4**. Conviene resolver A3 antes,
porque A4 hereda la pregunta «¿quién manda aquí?».

---

# A4 — Eliminar grupo con papelera, historial y aviso

**Estado: PENDIENTE (~5%). La decisión de producto está CERRADA.**

## Contrato

**Archivado ≠ Eliminado.** Son dos cosas distintas y ambas deben existir.

- Solo el **owner** puede eliminar.
- Se puede eliminar **incluso con saldos pendientes**, mediante confirmación reforzada.
- Desde ese momento el grupo **deja de afectar a la economía activa**: queda congelado.
- El owner lo ve inmediatamente en **«Eliminados»**.
- Los demás miembros **reciben/ven un aviso individual y deben reconocerlo**.
- **Restauración durante 7 días**; restaurar recupera grupo, tickets, personas y
  balances **para todos**.
- Pasados los 7 días queda como **historial readonly**.
- El historial **no afecta a los balances activos**.

## Qué existe hoy

Prácticamente nada del contrato.

- `enum SpaceStatus { active, archived }` (`space_models.dart:16`).
- `setStatus()` + tile Archivar/Reactivar (`space_management_screen.dart:1090`).
- `backend/firestore/firestore.rules:925-985`: **`spaces` no tiene `allow delete`**.

## Qué falta

Todo: estado `deleted`, papelera, pantalla «Eliminados», ventana de 7 días,
purga posterior, aviso individual por miembro, reconocimiento, restauración,
congelación económica e historial readonly.

**Archivar no es un sustituto parcial**: no saca al espacio de la economía
activa (cero referencias a `archived` en `economic_repository.dart`,
`recompute.ts` y `economicPayments.ts`), que es justo lo primero que el contrato
exige de un grupo eliminado.

## Decisión cerrada / documentación superada

**ADR-028** («archivar como única baja») queda **superado EN ESE PUNTO** por
este contrato. No reabrir la decisión: archivar y eliminar coexisten como
estados distintos. Ver la nota de supersesión en `docs/BIBLIA_SALDA.md`
(ADR-028) y en `docs/ESPACIOS.md`.

---

# A5 — Enlace único de grupo para guests y personas manuales

**Estado: PARCIAL (~40%) + CONFLICTO DE DISEÑO ABIERTO.**

## Contrato

- **Un único enlace compartible** del grupo/contexto. **No** un enlace distinto
  dirigido a cada persona.
- Si una **cuenta conocida** abre el enlace, resolver la identidad por UID
  cuando sea posible.
- **Sin app / sin cuenta → web.**
- La web muestra **únicamente las identidades guest/manual disponibles**.
- El usuario elige: «Soy Tete», «Soy Tato»…
- **No** obligar a instalar la app ni a crear una cuenta.

## Qué existe hoy

**La mitad de app está completa y es sólida** (ADR-035, Sprint 4):

- `spaceLinks/{token}`: el ID del documento **ES** el secreto (128 bits vía
  `ShareCode`). `get` abierto a quien acierta el token —para previsualizar el
  nombre—, `list` reservado al propietario: un enlace nunca es enumerable.
- Canje en **UN** batch: prueba de conocimiento `spaces/{id}/joinGrants/{uid}`
  (solo escritura) + membresía, validada con `existsAfter`. La membresía
  **revalida el enlace en cada canje**: revocar cierra la puerta al instante.
- Rotar / revocar / caducidad opcional e inmutable (`expiresAt`).
- App: `createJoinLink`, `rotateJoinLink`, `revokeJoinLink`, `previewJoinLink`,
  `joinWithLink` (`spaces_repository.dart:798-941`), `space_link_screen.dart`,
  `join_space_screen.dart`, `pendingGroupLinkProvider`.
- Deep link `/g/{token}` con intent-filter `autoVerify` y `assetlinks.json`
  servido en `salda-dev`.

## Qué falta

1. **La mitad web no existe.** `/g/{token}` en la web cae en
   `apps/guest_web/src/views/OpenInAppView.svelte`: «Ábrelo en la app», sin
   enlace a tienda ni aterrizaje. El requisito «sin app/cuenta → web» está al 0%.
2. **MANUAL no aplica** por decisión explícita de ADR-035 («no tiene
   dispositivo»), así que hoy el enlace de grupo no puede ofrecer identidades
   manuales.

## ⚠️ Conflicto de diseño abierto (decidir antes de implementar)

El contrato A5 pide *un enlace para todos + selector «Soy Tete / Soy Tato»*.
Eso es **exactamente el esquema 1 de los enlaces de ticket, retirado por
vulnerabilidad** en **ADR-036 rev. 2** (`docs/ENLACES_TICKET.md`):

> «Rules solo comprobaba "ese pid participa en este ticket", así que consentía
> la elección. Consecuencia: un enlace generado para Pedro servía para quedarse
> con la identidad económica de Ana, y de ahí —vía ADR-037— para pedir la
> vinculación de su historial.»

**A5 no puede implementarse hasta decir cómo evita esa suplantación.** Ni
ADR-035 ni ADR-036 quedan superados: la tensión está abierta y documentada en
ambos. Requiere un ADR propio.

## Dependencias

Bloquea a **A6** (dónde vive la reserva de identidad), **A7** (dónde vive la
liberación) y **N2 bloque B** (vista de contexto para invitados).

---

# A6 — Reserva persistente de identidad guest

**Estado: PARCIAL, muy avanzado (~85%).**

## Contrato

Al elegir «Soy Tete»:
- queda **reservado** para ese navegador/sesión, de forma persistente;
- **otro usuario no puede reclamar Tete**;
- idealmente **no caduca** por tiempo;
- permanece hasta que el propio invitado la libere/cambie, o hasta que un
  admin/anfitrión autorizado la libere (eso último es **A7**).

UX: mostrar «Participas como Tete» y permitir «Cambiar persona / No soy Tete».
**Liberar la identidad NO borra las acciones históricas.**

## Qué existe hoy

- **Exclusión mutua garantizada en servidor.**
  `backend/firestore/firestore.rules:1935-1942`:
  `hasOnly(['claimedByDevice'])`; reclamar exige que el valor previo sea `''` o
  el propio uid; liberar solo si era suyo. Ningún cliente puede robar una
  identidad ya reclamada.
- **Sin caducidad**: no hay TTL en ninguna parte.
- Persistencia por sesión en `localStorage`, degradando sin romper
  (`apps/guest_web/src/lib/identity.ts`).
- `claim()` / `release()` en `apps/guest_web/src/lib/session.svelte.ts:306,320`.
- `WhoAreYou.svelte` marca las personas ocupadas y avisa cuando una está `taken`.
- **«No soy {nombre}»** en `apps/guest_web/src/views/Summary.svelte:203`.
- Liberar solo toca `claimedByDevice`: el consumo y las declaraciones quedan.

## Qué falta

1. Rótulo explícito **«Participas como X»**: hoy la única señal es el texto del
   botón de liberar, al final del resumen.
2. La reserva está atada a `sessions/{sid}`, **no al contexto/grupo**. Si A5
   llega a ofrecer un enlace de grupo con identidades, la reserva tendrá que
   subir de nivel.

## Dependencias

El punto 2 depende de la decisión de **A5**. No terminar A6 antes que A5.

---

# A7 — Liberación de identidad por anfitrión/admin

**Estado: PENDIENTE (0%).**

> **No es** «confirmar todo el consumo en lote». Esa era una sonda interna del
> plan de A19. Ver el aviso de colisión al principio del documento.

## Contrato

- El anfitrión o un admin autorizado puede **liberar una identidad guest ya
  reclamada**.
- **No** usar un PIN individual como mecanismo principal.
- Liberar **no borra** el consumo ni las acciones históricas.
- Conservar **trazabilidad**: quién actuó bajo esa identidad y cuándo.

## Qué existe hoy

Nada. `grep claimedByDevice` sobre `apps/mobile/lib` devuelve **solo lecturas**:
ninguna pantalla la escribe para otro participante. Y
`backend/firestore/firestore.rules:1941` únicamente permite limpiarla a quien la
posee.

El único mecanismo de revocación actual es
`regenerateShareCode` (`firestore_session_repository.dart:726-739`), que rota el
código y borra `guestAccess` pero **no toca `claimedByDevice`**: la identidad
sigue reservada a un uid que ya no puede entrar.

## Qué falta

1. Acción de liberar en la app, con su autoridad de contexto.
2. Ampliar Rules para admitir esa autoridad sin abrir la puerta a nadie más.
3. Trazabilidad. Hoy solo existe parcialmente: `assignment.by.{unitId}.{pid}`
   registra el uid de las asignaciones administrativas (A10) y los settlements
   llevan `stateHistory`, pero **una autoselección de invitado no registra uid a
   propósito** (ADR-010/A10: «sin firma, la asignación es una autoselección»).

## Dependencias

Después de **A5**/**A6**: hay que saber dónde vive la reserva antes de decidir
quién puede romperla.

---

# A8 — Revisión explícita del ticket

**Estado: PENDIENTE / NO IMPLEMENTADO (0%).**

## Contrato

«He revisado el ticket y doy por comprobada mi situación respecto a él.»

- **Abrir un ticket NO equivale a revisarlo.**
- Estados visibles: `Falta tu revisión`, `Revisado`, `No participaste`.
- Acción explícita **«No consumí nada»**.
- Finalización/revisión explícita por parte de la persona.
- **Estado persistente real**, no inventado localmente en el cliente.
- El orden general de tickets sigue siendo cronológico / por actividad: **no**
  se reordena globalmente según el estado personal de revisión.

## ⚠️ A8 NO es A19

Son conceptos distintos y no deben mezclarse:

| | A19 `picking.open` | A8 revisión |
|---|---|---|
| Significa | «he terminado de elegir / repartir mi consumo» | «he revisado el ticket y doy por buena mi situación» |
| Efecto | El gasto entra en la economía firme | Ninguno sobre el dinero |
| Modelo | `picking: { open, lastTarget, fingerprint, firmContribution }` | **No existe** |

**No contar `picking.open` como implementación de A8.** Y si `picking.open` se
usa como señal de atención en A13, su rótulo debe ser equivalente a
**«Falta terminar el reparto»** — nunca «Falta tu revisión», que pertenece a A8.

## Qué existe hoy

Nada. `grep` de `reviewState|reviewedBy|reviewedAt|ticketReview` sobre todo el
repositorio no devuelve un solo resultado. El commit `fb93e09` (A11c) lo excluyó
explícitamente de su alcance y dejó anotada la pregunta que A8 debe responder:
que una modificación económicamente relevante **no deje una revisión falsa
vigente**.

## Qué falta

El modelo entero: dónde vive el estado, quién lo escribe, qué lo invalida, cómo
se proyecta a la lista de tickets y a las señales de A13.

## Dependencias

Debe cerrarse **antes** de que A13 muestre nada llamado «revisión»: una señal de
atención no puede fingir un estado que no existe.

---

# A9 — Reparto inteligente en relaciones de exactamente dos personas

**Estado: PENDIENTE (0%) + decisión/ADR previa.**

## Contrato

Caso Edgar–Alba:
- Edgar marca lo suyo y marca lo compartido;
- si **solo existen dos personas**, los productos restantes pueden **inferirse**
  como de Alba;
- objetivo: que Alba no tenga que entrar solo para marcar el complemento obvio;
- **el pagador NO debe quedarse automáticamente con lo que nadie marcó por el
  mero hecho de ser pagador**;
- debe existir **confirmación / UX clara** antes de hacer firme la inferencia.

## Qué existe hoy

Nada. No hay ningún caso especial para contextos de dos personas en
`apps/mobile/lib/features/sessions`.

## ⚠️ Tensión con ADR-021 (decisión pendiente, no superada)

Lo vigente hoy es **lo contrario** de A9, y es deliberado:

> `backend/functions/src/recompute.ts:755-760` — «sin consumidores (sin
> reclamar): la cubre `payerId` como `one`. Esto es lo que elimina la "media
> previa": lo que nadie ha cogido es de quien paga.»

Eso es **ADR-021**, que **sigue siendo la regla actual implementada** y **no
queda superada**. A9 propone una **excepción futura acotada al caso bilateral**.

## Qué falta

1. Un ADR que decida si la excepción se acepta, con qué confirmación y qué pasa
   si la contraparte discrepa después.
2. Solo entonces, la implementación.

---

# A10 — Asignación administrativa del consumo

**Estado: RESUELTO + DEUDA ACEPTADA (100%).**

## Contrato

Quien tenga permiso puede asignar directamente productos/gastos a Edgar, Alba o
Tete, o compartirlos entre varios, **sin obligarles a autorreclamarse**.

Matriz de autoridad (`docs/ESPACIOS.md` § «Repartir el consumo de otras personas»):

| Actor | Lo suyo | Lo de otra persona | A un MANUAL |
|---|---|---|---|
| Creador del gasto (dueño de la sesión) | sí | sí | sí |
| Propietario / administrador del **grupo** | sí | sí | sí |
| Miembro normal del grupo | sí | no | no |
| Contraparte de una **relación** | sí | no | no |
| Ajeno o expulsado | no | no | no |

## Qué existe

- **Misma asignación económica, distinta autoridad**: se escribe en el modelo
  por unidades de siempre (`assignment.units.{unitId}.{pid}`). No hay un segundo
  sistema de asignaciones.
- UI: `apps/mobile/lib/features/sessions/presentation/unit_assignment_sheet.dart`
  — lista **todos** los participantes activos (cuenta, MANUAL e invitado) con
  `CheckboxListTile`, de modo que compartir entre varios es marcar varios.
- Autoridad en cliente: `canAssignConsumptionProvider`
  (`session_providers.dart:121`), solo en «cada uno lo suyo» y con sesión abierta.
- **Procedencia por PAR**: `assignment.by.{unitId}.{pid} = uid`. Rules exigen que
  el uid sea el de quien escribe; la firma se retira con su asignación; sin firma
  la escritura es una autoselección y exige `claimedBy(pid) == uid`.
- **Repartir no es editar**: la rama de asignación exige que la escritura toque
  únicamente `assignment`.
- Válida al instante: la persona beneficiaria no tiene que entrar a confirmarla.

## Tests

`backend/firestore/test/unit_assignment.test.mjs` — **52 casos en 9 bloques**:
quién reparte en grupo · el creador con procedencia · sobre quién se puede
asignar · compartir, retirar y reasignar · la firma no se puede falsear ·
repartir NO es editar · retirar el consumo que te asignaron · relaciones ·
fronteras de siempre. Más `assignedConsumption.it.test.ts` (la economía de una
asignación de tercero) y `unit_assignment_test.dart` (14 casos de UI).

## DEUDA ACEPTADA

**Quien administra recibe una denegación limpia al tocar una unidad que su dueño
acaba de autoseleccionarse.** La asignación existe y su procedencia —vacía, por
ser autoselección— no se reescribe: firmar deniega, y no firmar también, porque
asignar por otra persona exige firma. Es una limitación de Rules, no del cliente.

Está **fijada por test**
(`backend/firestore/test/unit_assignment.test.mjs:448`, «la admin todavía no
puede marcar lo que su dueño autoseleccionó»), que además comprueba que la
denegación sea **limpia** y no un presupuesto de expresiones agotado.

**Esto NO reabre A10.** El workflow normal está completo. Si algún día molesta
en uso real, se trata como deuda propia, no como A10 pendiente.

## Límite conocido

A10 solo escribe en el modelo por unidades. Convertir una línea del modelo de
pesos **no es lossless**, así que esa conversión sigue siendo del dueño de la
sesión y explícita.

---

# A11 — Roles y permisos de grupo para gastos

**Estado: RESUELTO (100%).**

A11 es **un único identificador canónico**, dividido deliberadamente en cuatro
subworkflows durante su ejecución. Los cuatro están cerrados. **No crear cuatro
IDs independientes en el roadmap.**

## Contrato

- **Creador del ticket**: conserva sus permisos para editar/corregir su propio ticket.
- **Admin / propietario del grupo**: pueden editar/corregir también tickets
  creados por otros miembros.
- **Miembro normal**: audita y gestiona **únicamente su consumo**; no edita el
  contenido fuente de tickets ajenos.
- **Relaciones**: no adquieren admins ni edición administrativa.
- **Administrar un gasto NO equivale a administrar pagos.** Un admin puede
  corregir el ticket que originó una deuda, pero **no** adquiere autoridad para
  confirmar que un usuario registrado ha recibido dinero: esa es A17/A18 y sigue
  intacta.

## A11a — Gestión de administradores

Commit `26f8c36`. `members/{uid}.role: 'admin'|'member'`, solo lo concede el
propietario, nadie nace admin, un INVITADO no puede serlo y **una RELACIÓN no
entra en el sistema de roles**. UI en `space_management_screen.dart`.
Tests: 4 de Rules + 12 de app (`space_admin_roles_test.dart`).

## A11b — Lectura / auditoría de tickets

Commit `dd8c1bc`. `auditableByContext` (nacido como `auditableByGroup` y
ampliado a relaciones durante A10) abre a los miembros del contexto la lectura de
participantes, cuentas, tickets y líneas, con espejo en `storage.rules` para la
foto. **Deliberadamente NO abre `sessions/{sid}`**: ahí vive el `shareCode`, y
ampliar la lectura no puede ampliar la escritura por detrás.
Tests: `group_ticket_audit.test.mjs` (20) · `storage_receipt_access.test.mjs` (13).

## A11c — Corrección administrativa

Commit `fb93e09`. Quien administra el grupo corrige el gasto de otro. Es
autoridad **propia**, no una extensión de la auditoría. `ticket_correction.dart`,
`ticket_correction_sheets.dart`, `canCorrectTicketProvider`
(`session_providers.dart:86`).
Tests: `group_ticket_correction.test.mjs` (16) · `ticketCorrection.test.ts`.

## A11d — Expulsión, historial y readmisión

Commits `6607fd5` y `3f04762`, **ADR-039**. Expulsión atómica en UN batch de
tres escrituras: evidencia por CICLO (`removals/{uid}_{joinedAtMillis}`),
bloqueo separado (`entryBlocks/{uid}`) y borrado de la membresía. Derecho
histórico intacto vía `ticketEntitlements`. Reentrada solo con invitación
posterior al bloqueo; vuelve como miembro nuevo.
Tests: `group_member_removal.test.mjs` (33) · `group_ticket_history.test.mjs` (17).

---

# A12 — OCR: productos fantasma del desglose fiscal

**Estado: RESUELTO (100%). NO volver a listarlo como pendiente.**

## Contrato

Un ticket no puede dar por buenos productos que no existen solo porque las
cuentas cuadren.

## Qué se hizo

Commit `8d03c50`. **Reproducido**, no sospechado:

```
BASE IMPONIBLE 13,19
IVA 21%         2,77
TOTAL          15,96
```

daba **dos productos fantasma** —la base y la cuota— que sumaban exactamente el
total: cuadraba al céntimo, sin issues, sin aviso y con cero productos reales.

**Causa raíz:** el desglose fiscal impreso ANTES del total y sin la cabecera
combinada que buscaba `_taxZoneHeader` caía en la regla genérica «nombre +
importe», con confianza 0,78 —por encima del umbral de aviso—, y `_noise` no
contemplaba conceptos fiscales.

**Fix:** filtro fiscal **estrecho a propósito** (exige el concepto fiscal
completo, porque «BASE PIZZA» y «CUOTA MENSUAL CLUB» son productos y tienen que
seguir siéndolo), con **dos fixtures en ambas direcciones**. No se reconstruye
el impuesto desde una línea suelta: el importe pagado ya vive en el `grandTotal`,
que es lo único demostrable.

Postmortem permanente: `docs/BIBLIA_SALDA.md` §48.1, entrada **E9**.

---

# A13 — Indicadores de atención por espacio

**Estado: PARCIAL (~30%).**

## Contrato

El badge/punto significa **«aquí hay algo que probablemente tienes que mirar»**,
NO «aquí ocurrió algo».

Fuentes posibles: ticket pendiente de revisión (A8), invitación, solicitud, pago
por confirmar, vinculación fallida, mensaje sin leer **solo si existe fuente
fiable**, y otros estados realmente accionables.

**No inventar un «unread» local.**

## Qué existe hoy

- **Vinculaciones manuales pendientes, por espacio**: `home_screen.dart:175,307`
  → `home_space_row.dart:74-97` (icono + texto en `c.warning`).
- **Invitaciones**: tarjetas propias en la parte alta de Inicio
  (`home_screen.dart:220-239`), no como badge por fila.
- Badge de «contexto no listo para repartir» en `space_row.dart`.
- Resumen económico global en `balance_hero.dart`.

## Qué falta

Señales autoritativas que **ya existen en datos y no se usan** como atención por
espacio:

| Señal | Dónde vive | Rótulo correcto |
|---|---|---|
| Reparto sin cerrar | `picking.open` (A19) | **«Falta terminar el reparto»** — nunca «Falta tu revisión» |
| Cobro por confirmar | settlements `marked`, `economicPayments` pending | «Tienes un cobro por confirmar» |
| Vinculación fallida | `manualLinkRequests` en `failed` | «Vinculación fallida» |
| Solicitudes | amistades / invitaciones | ya existe, falta agregarlo por fila |

Falta la agregación por espacio y el punto/badge en la fila.

**Mensajes sin leer**: correctamente NO implementado — el chat no tiene una
fuente fiable de lectura y el contrato prohíbe inventarla.

## Dependencias

- **A8** debe existir antes de mostrar cualquier señal llamada «revisión».
- **A1** bebe de A13 para su segunda línea: hacer A13 primero.

---

# A14 — `balanceSummaries` o proyección equivalente

**Estado: NO IMPLEMENTADO A PROPÓSITO / CONDICIONAL A MÉTRICAS.**

> A14 **no es** App Check. App Check es DT-3 y es un asunto distinto, sin ID de
> backlog asignado.

## Contrato

Materializar una proyección de balances **solo si es necesario**:
- balances personales y de terceros en grupos grandes;
- **sin límites arbitrarios**;
- Home compacta, pero con acceso a «Ver todos»;
- proyección/materialización **únicamente** si el modelo actual no escala o no
  permite consultar correctamente.

**Regla: no implementar arquitectura preventiva.**

## Por qué hoy NO se implementa

El modelo actual **resuelve correctamente**:

- `economicEntriesProvider` / `economicPaymentsProvider` consultan
  `where('memberUids', arrayContains: uid())` y `EconomicLedger` netea **en
  cliente** (`apps/mobile/lib/features/economy/data/economic_repository.dart`).
- `withinSpace(spaceId)` da el saldo por contexto sin consulta adicional.
- **Sin límites arbitrarios**: Inicio lista todos los espacios con búsqueda
  (`home_screen.dart:418-427`), no un top-N. `rebuildMyEconomicRelations` es un
  warm-up, no una materialización.

## Riesgo conocido y no medido

La lectura de entries/payments propios **no está paginada**, así que su coste
crece con el histórico.

## Disparador para reabrirlo

Que Inicio o Economía tarden de forma perceptible en uso real, o que aparezca un
grupo grande de verdad. **Hasta entonces, fuera del roadmap activo.**

---

# A15 — Revisar el ticket aunque el total cuadre

**Estado: RESUELTO (100%).**

## Contrato

Que las cuentas salgan no significa que el ticket esté bien leído. Debe poderse
editar productos, revisar el ticket y llamar a la IA **aunque el total cuadre**,
y distinguir un total matemáticamente correcto de un OCR semánticamente correcto.

## Qué existe

Commit `8d03c50`:

- **El estado verde habla SOLO de aritmética**: `"reviewBalanced": "El total
  cuadra"` (antes «El ticket cuadra») + `reviewBalancedHint`: «Que cuadre solo
  dice que las cuentas salen. Revisa el establecimiento, los nombres y las
  cantidades.»
- **«Analizar con IA» es una acción propia y permanente**
  (`review_screen.dart:279`). Vivía DENTRO del aviso de baja confianza, así que
  cuadrar —o pulsar «Editar a mano»— la hacía desaparecer justo cuando el
  usuario sospechaba algo. Sigue sin lanzarse sola.
- Aviso antes de que la IA sobrescriba trabajo manual
  (`reviewAiOverwriteTitle/Body/Confirm`) y aviso de que **sin foto original la
  IA revisará los datos extraídos, no el ticket** (`reviewAiWithoutPhoto`).
- **El total ya se puede corregir** antes de guardar, cambiando solo el total y
  sin inventar una línea de ajuste.
- **Tolerancia de cuadre unificada**: `receiptBalanceToleranceCents = 2` en
  `packages/domain/lib/src/receipt/receipt_extraction.dart:157`, **fuente
  única** usada por el parser, el borrador de revisión y la validación de la
  respuesta de IA. Antes eran tres copias de `max(2 céntimos, 1 %)` y un ticket
  de 15,96 € daba por bueno un descuadre de 15 céntimos.
- **Precio a la izquierda** (`1,15 MACARRON ROMERO 1 KG 5,75`): no se inventa la
  cantidad, se baja la confianza y se marca para revisión. Postmortem **E10**.
- El precio unitario se retira cuando deja de poder demostrarse.

## Tests

2 fixtures de corpus nuevas, 11 regresiones de parser y 18 de app, incluido el
round-trip completo: corregir la cantidad a 5 en la revisión y comprobar que el
gasto guardado nace con **cinco** unidades repartibles.

---

# A16 — Offline-first

**Estado: PARCIAL (~35%).**

## Contrato

Sin conexión debe poder estudiarse/soportarse: crear ticket · foto local · OCR
local si el pipeline lo permite · entrada y corrección manual ·
establecimiento/fecha/hora/productos · asignar a participantes cacheados ·
calcular balances localmente · terminar reparto · navegar y consultar el ticket ·
**mostrar claramente lo pendiente de sincronizar** · cola persistente ·
sincronizar al reconectar · resolver conflictos · **revalidar permisos al
reconectar** · pagos/liquidaciones según el alcance offline que finalmente se
cierre.

> `persistenceEnabled: true` es **base técnica**, no equivale por sí sola a A16.

## Qué existe hoy

- `FirebaseFirestore.instance.settings = Settings(persistenceEnabled: true)`
  (`apps/mobile/lib/core/firebase/firebase_bootstrap.dart:40`).
- **Foto local durable**: `ReceiptImageStore`
  (`apps/mobile/lib/features/scan/data/receipt_storage.dart`) copia a
  app-documents ligada al ticket, sobrevive al cierre de la app, con lectura
  local-primero memoizada.
- **OCR on-device** (ML Kit): funciona sin red.
- **Borrador persistente** en `shared_preferences` con banner de recuperación.
- **`EconomicLedger` corre en cliente** sobre las entries cacheadas.
- Navegar y consultar tickets sale de la caché de Firestore.
- La cola de escrituras de Firestore sincroniza sola al reconectar.

## Qué falta

1. **Cero UX offline**: sin chip de estado, sin cola visible, sin «pendiente de
   sincronizar». `hasPendingWrites` solo se usa en `chat_repository.dart:100`.
2. **Consistencia**: `economicEntries` las escribe `recompute` en servidor, así
   que tras editar sin red los balances quedan **rancios sin decirlo**; terminar
   un reparto offline no mueve nada visible.
3. Sin resolución de conflictos explícita.
4. **Sin revalidación de permisos al reconectar**: una escritura encolada que
   Rules rechacen al sincronizar **falla en silencio** en la app. La web sí lo
   dice, vía `describeWriteError` (`apps/guest_web/src/lib/session.svelte.ts`);
   ese patrón es el que hay que portar.
5. Alcance offline de pagos y liquidaciones sin cerrar.

---

# A17 — Autoridad de cobro: quién confirma

**Estado: RESUELTO (100%).**

## Contrato

**El receptor del dinero es quien confirma que lo ha recibido.** Ser propietario
o administrador de un espacio **no** da acceso al saldo de una cuenta ajena;
solo permite **representar** a un participante MANUAL, que por definición no
puede confirmar nada. Vincular ese manual (ADR-037) termina la representación
sin revocar nada.

## Qué existe

**ADR-038** (commit `8d5ffba`), documentado en
`docs/RELACIONES_ECONOMICAS.md` § «Permisos y liquidación por obligación».

- `economicActingRole` / `canConfirmReceipt` en
  `packages/domain/lib/src/identity/economic_authority.dart:46,76`, con **espejo
  TS** en `backend/functions/src/domain/economicAuthority.ts`: un único
  predicado para interfaz, Functions y (en su forma de lectura) Rules.
- `resolveEconomicPayment` acepta representación y **solo consulta el espacio
  cuando hay una identidad sin cuenta implicada** (entre dos cuentas, coste cero).
- Cliente: `canViewerConfirmReceipt`
  (`apps/mobile/lib/features/economy/presentation/obligation_settlement.dart:59`).
  Un administrador **nunca** ve la acción sobre el cobro de una cuenta ajena.
- Rules: `members/{uid}.role` como única delegación; lectura extra de
  obligaciones con parte manual para quien administra su espacio, filtrada por
  `hasManualParty` (derivado e inmutable) para que la consulta sea demostrable.

---

# A18 — Liquidación por obligación concreta

**Estado: RESUELTO (100%).**

## Contrato

Un saldo agregado nunca se convierte en una obligación nueva ni pierde su
ticket. Se liquidan obligaciones **concretas**.

## Qué existe

`settleEconomicEntries` (`backend/functions/src/economicPayments.ts`):

- Liquida obligaciones concretas y escribe **UN pago por cada una**
  (`allocations` + `economicEntryId`).
- Importe por defecto = lo pendiente de esa deuda; **el parcial es la excepción**.
- **Dos techos obligatorios**: lo vivo en la obligación y lo vivo en el saldo
  bilateral. El segundo impide cobrar dos veces una deuda ya saldada por una
  liquidación de sesión, que no deja asignación por ticket.
- **Idempotente** por id determinista.
- Si el actor obra por el lado acreedor la liquidación nace `confirmed`; por el
  deudor, `pending`: **«Ya he pagado» es un aviso, nunca una precondición.**
- Un pago legado no lo resuelve la callable de P5 por diseño: la app escribe en
  su `settlements/{id}`.

Tests: 32 casos nuevos de planificación y validación en functions,
`settleEconomicEntries.test.ts`, `economicPayments.test.ts`.

---

# A19 — Cierre de consumo (`picking.open`)

**Estado: RESUELTO (100%). Desplegado en `salda-dev` el 2026-09-03.**

## Contrato

Un gasto repartido por líneas **no entra en las cuentas** hasta que todas las
personas implicadas hayan dicho «he terminado», y cualquier cambio posterior de
consumo **reabre automáticamente** esa declaración.

Contrato vivo: **`docs/CIERRE_DE_CONSUMO.md`** · **ADR-041**.

## Qué existe

- `pickingModelVersion: 1` + `picking: { open, lastTarget, fingerprint,
  firmContribution }` en el documento del ticket. Un ticket sin
  `pickingModelVersion` se comporta como antes, **para siempre**.
- El gasto **nace** bajo el protocolo y con todo el mundo pendiente, en el MISMO
  batch que lo crea (`firestore_session_repository.dart:290`).
- `ticketIsFirm` (`recompute.ts:709`) filtra los tickets no firmes antes de
  repartir; `frozenContribution` (`:741`) congela —no retira— la última economía
  firme de un ticket reabierto, que es lo que impide fabricar una liquidación
  inversa cobrable.
- `activeIds` (`:296`) decide quién recibe consumo nuevo; `ledgerIds` (`:559`)
  amplía el universo del libro con los actores históricos, y es lo que permite
  que la economía del último cierre siga cuadrando byte a byte.
- **CAS**: el batch entero aborta con `lastUpdateTime` (`:1177`) si alguien
  escribió la sesión después de la lectura.
- Rules: `firestore.rules:2182-2212`, con **UN solo** acceso de documento
  adicional (`getAfter`), izado a la rama.
- App: `finishPicking` + «He terminado» + «Terminar por {name}» (A10 cierra por
  quien no puede pulsar) + aviso de reapertura con impacto de pagos confirmados.
- Web: `PickItems.svelte:126-146` + `finishPicking`.
- `assignment` no cambió ni un byte; ningún motor económico nuevo; ninguna
  Function nueva.

## Techo de Rules que NO se puede romper

La rama de `lines/{lid}` admite **UN** acceso de documento adicional y
`validUnitWrite` se evalúa **una sola vez**, izada a la rama. Con dos accesos, el
camino de A10 sobre un MANUAL agota las 1000 expresiones. Lo vigila
`backend/firestore/test/picking.test.mjs`.

## Observaciones de UX del smoke (no bloqueantes)

Documentadas al cerrar A19 y **no** convertibles retroactivamente en fallo de
A19:
- el resumen sigue mostrando el importe congelado durante una reapertura;
- a un participante `active: false` no se le explica que ya no participa;
- no hay acción explícita de «volver a elegir»: se reabre tocando una unidad.

---

# A20 — Confirmar cobros desde cualquier superficie de balance

**Estado: RESUELTO (100%).**

## Contrato

Copy canónico: **«Confirmar recepción»**.

Cuando una superficie muestra un balance bilateral —Economía, portada de
relación, portada de grupo cuando corresponda, «Balance con X» y equivalentes—,
el saldo agregado debe permitir abrir el **desglose real de obligaciones**. **No
crear una deuda global nueva.**

Ejemplo: `Test te debe 14,73 €` = Familycash 6,75 € + otro ticket 7,98 €.

Cada obligación conserva su origen/ticket, es auditable, se confirma
individualmente, admite pago parcial como excepción y recalcula el agregado. El
receptor puede confirmar **aunque el pagador no haya pulsado «Ya he pagado»**.

Además: «Pagos por confirmar» representa **solo declaraciones reales
pendientes**; las deudas sin declaración siguen siendo confirmables por el
receptor desde el desglose.

## Qué existe

Commit `5cc4007`, sobre ADR-038.

**Hoja única** `apps/mobile/lib/features/economy/presentation/obligation_settlement.dart`,
abierta desde **cinco superficies**:

| Superficie | Fichero |
|---|---|
| Economía global | `economic_overview_screen.dart:246` |
| «Balance con X» | `economic_relation_screen.dart:265` |
| Resumen económico de espacio | `space_economic_summary.dart:227` |
| Portada de relación y de grupo | `space_cover_content.dart:135` y `:386` |

- `"economyConfirmPayment": "Confirmar recepción"` ·
  `"economySettleSelected": "Confirmar recepción ({count})"` ·
  `"economyMarkPaid": "Ya he pagado"`. **Mismo par en la web de invitados.**
- `SpaceBalanceDetailScreen` dejó de ser un callejón sin salida: lista las deudas
  con su origen y permite cobrarlas.
- La pareja deudor/acreedor viaja **explícita**: quien representa a alguien sin
  cuenta no es parte de esa deuda.
- Marcar varias es comodidad de interfaz: salen **N** liquidaciones, cada una con
  su ticket.

Tests: 16 nuevos de app (obligaciones individuales, parciales, agregado que no
funde, representación y su negativa, superficies).

---

# N1 — Sistema de notificaciones

**Estado: contrato EN DISCUSIÓN de producto · infraestructura técnica PARCIAL (~10%).**

## Contrato (en discusión)

Eventos posibles: alguien declara «Ya he pagado» · cobro pendiente de confirmar ·
ticket nuevo que requiere revisión · ticket revisado que cambia · un admin
asigna o corrige consumo · invitaciones, vinculaciones e identidad · expulsión o
cambio de rol cuando proceda.

**Regla: push ≠ indicador interno (A13). No queremos spam por mera actividad.**

Antes de implementar hay que cerrar: **eventos · permisos del SO · preferencias ·
deduplicación · comportamiento en app y en web**.

## Estado técnico real (hallazgo H1)

Existe **un solo** trigger: `notifyOnSettlement`
(`backend/functions/src/notify.ts:13`), sobre
`sessions/{sid}/settlements/{stid}`, con dos eventos (`pending→marked` y «todas
confirmadas»).

**No tiene cadena funcional completa de FCM:**

1. **Ningún cliente registra `fcmTokens`.** `grep fcmTokens` sobre todo el
   repositorio devuelve **una única línea**: la lectura en `notify.ts:60`. Sin
   tokens no hay envío: la Function está desplegada y **no puede disparar nunca**.
2. **No hay `firebase_messaging`** en `apps/mobile/pubspec.yaml`: sin SDK, sin
   permiso de SO, sin registro de token.
3. **Cubre solo la ruta legacy**: `economicPayments` (P5) no tiene trigger de aviso.
4. **⚠️ Destinatario posiblemente incorrecto respecto a ADR-038**:
   `ownerTokens(session.ownerUid)` avisa al dueño de la sesión, pero desde
   ADR-038 el receptor económico **no es necesariamente el owner**. Cablear N1
   tal cual avisaría a quien no cobra.
5. Sin preferencias, sin deduplicación, sin comportamiento definido en web.

> **No tomar la existencia de la Function como prueba de que las notificaciones
> funcionan.** Registrado también como **DT-1** en `docs/BIBLIA_SALDA.md` §44.

---

# N2 — Web completa

**Estado: PARCIAL (~25%).**

## Contrato

**Bloque A — usuario con cuenta:** cliente web funcional de primera clase —
Inicio, grupos y relaciones, tickets y fotos, reparto, Economía, pagos,
actividad, gestión y perfil donde proceda.

**Bloque B — guest sin cuenta:** vista **GLOBAL del grupo**, no solo sesiones y
tickets sueltos — cuánto debe y le deben, balances por contraparte, tickets,
actividad, foto/líneas/reparto, origen de las deudas, picking, cambios en
realtime y una economía comprensible.

> **Diferencia con A5/A6/A7:** aquéllos son **entrada e identidad** del invitado.
> **N2 es la experiencia funcional una vez autorizado.**

## Qué existe hoy

Para un invitado ya autorizado de **una sesión** (`apps/guest_web/`):

- Resumen con balances autoritativos (nunca calculados en la web) y métodos de
  pago configurados.
- «Ya he pagado» y «Confirmar recepción», con el mismo copy que la app.
- Elegir productos con el modelo de unidades y **«He terminado»** (A19).
- Ticket completo con sus líneas.
- Barra de progreso de liquidación.
- **Todo en realtime**: sesión, participantes, liquidaciones, tickets y líneas
  por `onSnapshot`.
- Errores de escritura **visibles** (`describeWriteError`).
- 63 tests vitest en 9 archivos, `svelte-check` a cero, ~188,6/220 KB gz.

## Qué falta

- **Bloque A: 0%.** No existe cliente web de primera clase: ni Inicio, ni
  espacios, ni Economía global, ni actividad, ni gestión, ni perfil.
- **Bloque B: ~35%.** La web es **por sesión, no por contexto**: sin vista global
  del grupo, sin balances por contraparte, sin actividad, sin origen de las
  deudas a través de varios tickets, y **sin foto del ticket** (DT-13).

## Dependencias

Depende especialmente de **A5**, **A6**, **A7** (entrada e identidad) y de **N3**
(la economía dinámica no puede darse por definitiva sin cerrar el reembolso).

---

# N3 — Reconciliación / reembolso

**Estado: EN DISCUSIÓN + contención parcial existente gracias a A19 (~15%).**

## Contrato (en discusión)

**No** una simplificación global arbitraria. Sí un **reembolso LOCAL y
trazable** cuando un pago **real y confirmado** del mismo ticket queda por
encima de la obligación después de cambiar el reparto.

Pregunta abierta que hay que responder: si un pago confirmado sobrevive a la
eliminación de su ticket (A2), **¿cómo explica Salda después ese pago?**
Ejemplo: ticket eliminado donde Tete debía 20 € a Edgar; pago que permanece,
Tete → Edgar 10 €. Después del borrado el balance puede indicar «Edgar debe 10 €
a Tete», y hay que decidir si el pago por sí mismo conserva contexto suficiente
o hace falta un tombstone/snapshot mínimo.

## Qué existe hoy: contención, no solución

`frozenContribution` (`backend/functions/src/recompute.ts:725-751`):

> «No se retira, se congela. Retirarla dejaría un pago `confirmed` sin la
> obligación que lo justificaba, y el modelo leería eso como un sobrepago:
> aparecería una liquidación INVERSA por el importe entero, nueva y cobrable,
> provocada solo por el hecho de estar editando.»

Medido en la sonda `a19_reapertura` (P3) y fijado por
`backend/functions/src/test/integration/picking.it.test.ts:166` («reabrir un
ticket ya cobrado NO fabrica una deuda inversa») y
`backend/functions/src/test/picking.test.ts:189`.

Eso **evita el falso sobrepago durante una reapertura**. No resuelve el
sobrepago **real**.

## Qué falta

El caso de reembolso real no tiene modelo ni UI. Hay que cerrar el diseño
económico —sin crear un segundo motor— antes de implementar.

## Dependencias

**Debe resolverse antes de considerar definitiva la economía dinámica de N2.**

---

# Roadmap activo y dependencias

Una **sesión fresca por bug o bloque coherente**. No agrupar temas
independientes solo porque estén al mismo porcentaje.

| Orden | Bloque | Naturaleza | Depende de |
|---|---|---|---|
| 1 | **A5** — decisión de seguridad: enlace único + identidad vs ADR-036 rev.2 | ADR, sin código | — |
| 2 | **A9** — decisión/ADR sobre la excepción bilateral a ADR-021 | ADR, sin código | — |
| 3 | **N3** — cerrar el diseño económico del reembolso local y trazable | ADR, sin código | — |
| 4 | **A3** — completar el abandono y la sucesión del propietario | Implementación | — |
| 5 | **A8** — revisión explícita del ticket (modelo propio) | Implementación | — |
| 6 | **A13** — señales de atención por espacio | Implementación | A8 (no fingir «revisión» antes de que exista) |
| 7 | **A1 fase 1** — Home sin ruido: quitar «Espacios», contexto útil, presencia | Implementación | A13 |
| 8 | **A1 fase 2** — fotos (subsistema: Storage, Rules, subida, precedencia) | Implementación | — |
| 9 | **A5 implementación** — mitad web del enlace de grupo | Implementación | decisión 1 |
| 10 | **A6** — cierre, coordinado con el modelo definitivo de A5 | Implementación | A5 |
| 11 | **A7** — liberación de identidad por anfitrión/admin | Implementación | A5, A6 |
| 12 | **A9 implementación** | Implementación | decisión 2 |
| 13 | **N3 implementación** | Implementación | decisión 3 |
| 14 | **A4** — ciclo completo de eliminación y restauración de grupos | Implementación | A3 |
| 15 | **A16** — offline-first completo | Implementación | — |
| 16 | **N1** — cerrar el contrato y después cablear las notificaciones | ADR + implementación | — |
| 17 | **N2** — web completa | Implementación | A5, A6, A7, N3 |
| — | **A14** | Fuera del roadmap activo mientras las métricas no lo justifiquen | — |

**A10 no necesita otra sesión de implementación para «cerrarlo»**: queda
RESUELTO + DEUDA ACEPTADA.

**Fuera de este backlog** pero pendiente: App Check (DT-3), Crashlytics/Analytics
(DT-2) y el resto de la deuda técnica de `docs/BIBLIA_SALDA.md` §44.
