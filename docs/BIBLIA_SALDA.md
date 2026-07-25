# BIBLIA DEL PROYECTO SALDA

**Versión:** 1.15 · **Fecha:** 2026-07-25 · **Changelog:** v1.15 — el enlace
de grupo entra SOLO a quien ya tiene identidad, conserva el enlace mientras
uno se identifica y admite caducidad opcional (ADR-035). v1.14 — enlaces de
grupo: token opaco no enumerable con prueba de conocimiento en batch, y el
invitado por fin llega a sus contextos (ADR-035). v1.13 — modo
invitado: participante sin cuenta con identidad persistente de dispositivo y
gastos bajo permiso del anfitrión (ADR-034). v1.12 —
participantes manuales como actores económicos sin cuenta ni migración
(ADR-033). v1.11 — P7 chat
contextual privado por membresía y fecha de alta, separado de actividad y
economía (ADR-032). v1.10 — P6 actividad
como proyección de auditoría con IDs deterministas y audiencia congelada
(ADR-031). v1.9 — Relaciones y grupos pasan a ser la raíz visible; tickets
nuevos siempre contextuales y compatibilidad histórica no destructiva
(ADR-030). v1.8 — P5 relaciones
económicas explicables, neteo bilateral y pagos confirmados (ADR-029). v1.7 — P4 espacios
compartidos: contenedor social único con propietario en un solo campo,
invitaciones deterministas y tickets vinculables (ADR-028). v1.6 — P3 amistades
canónicas por pareja de UID, transacciones idempotentes y seguridad social
(ADR-027). v1.5 — P2.2 unidades
físicas independientes, compatibilidad versionada y configuración dev/release
(ADR-026). v1.4 — P2.1 reparto
por unidades (peso = unidades reclamadas, residual al pagador), selección del
creador y confirmación de pagos exclusiva del receptor (ADR-025). v1.3 — P2
identidad pública: perfil `profiles/{uid}`, unicidad de username por claims
atómicos y búsqueda por prefijo (ADR-024). v1.2 — P0.3 separa histórico
económico de estado actual y define el progreso sobre obligaciones de liquidación
(ADR-022). v1.1 — blindado el modo "cada uno paga lo suyo": las líneas no reclamadas
recaen en el pagador (ADR-021), fin de la "media previa". v1.0 primera edición.

> **Qué es este documento:** la referencia estratégica y técnica definitiva de Salda.
> Complementa —no sustituye— a `docs/ESPECIFICACION.md` (spec funcional v2.0 congelada)
> y a `CLAUDE.md` (guía operativa de traspaso). **Orden de lectura obligatorio para
> cualquier ingeniero o modelo nuevo: `CLAUDE.md` → `docs/ESPECIFICACION.md` → este
> documento.**
>
> **Etiquetas de veracidad usadas en todo el documento (regla anti-alucinación):**
> - **[HECHO]** — existe en el repo y fue verificado (commit, archivo o test citado).
> - **[DECISIÓN TOMADA]** — documentada en spec/CLAUDE.md, aún sin reflejo completo en código.
> - **[PROPUESTA]** — recomendación para el futuro; NO está decidida ni implementada.
> - **[ANÁLISIS HIPOTÉTICO]** — proyección razonada, no medida.
> - **[SUPOSICIÓN — VERIFICAR]** — creencia plausible sin verificación directa.

---

## Tabla de contenidos

- [Parte I — Producto y filosofía](#parte-i)  (§1–§7)
- [Parte II — Flujos de usuario](#parte-ii)  (§8–§16)
- [Parte III — UX y diseño](#parte-iii)  (§17–§22)
- [Parte IV — Arquitectura y dominio](#parte-iv)  (§23–§29)
- [Parte V — Backend e infraestructura](#parte-v)  (§30–§35)
- [Parte VI — Calidad, rendimiento y seguridad](#parte-vi)  (§36–§41)
- [Parte VII — Auditoría y evolución](#parte-vii)  (§42–§48)
- [Parte VIII — Visión de futuro](#parte-viii)  (§49–§50)
- [Parte IX — Roadmap y ejecución](#parte-ix)  (§51–§55, ADRs)
- [Parte X — Referencia y continuidad](#parte-x)  (§56–§63, Contrato)
- [Inconsistencias detectadas](#inconsistencias)

---

<a name="parte-i"></a>
# PARTE I — PRODUCTO Y FILOSOFÍA

## §1. Filosofía del producto

**Qué es Salda** (nombre provisional): una plataforma para organizar la economía
compartida de un grupo de personas. Nació como "Tricount automatizado con OCR"
y su centro de gravedad es hoy el **grupo** (internamente `Session`): un contenedor
con participantes, tickets, balances, pagos e historial. Los tickets son solo
generadores de movimientos económicos dentro del grupo.

**Problema que resuelve:** dividir gastos entre amigos hoy exige teclear a mano
cada gasto (Tricount/Splitwise) o hacer cuentas de servilleta. Salda elimina la
fricción de entrada (foto del ticket → OCR on-device → reparto por productos) y la
fricción de salida (los invitados no instalan nada: enlace/QR → eligen lo suyo →
marcan pagado → el anfitrión confirma).

**Principio rector:** *"Hacer que gestionar dinero entre amigos sea tan sencillo
como enviar un mensaje."* Toda decisión de producto, arquitectura o roadmap se
evalúa contra esta frase.

**Referencias de calidad:** Tricount/Splitwise (funcionalidad), Revolut (UX/UI),
WhatsApp (modelo de grupos), Notion/GitHub (timeline de actividad).

**Estado del producto** [HECHO — verificable en `git log`, 19 commits]: MVP
funcional de punta a punta sobre Firebase real (`salda-dev`), probado en un
dispositivo físico Android, con 6 bugs de la primera prueba real corregidos con
causa raíz (commit `d5e6d55`). Web de invitados desplegada en
`https://salda-dev.web.app`.

## §2. Qué NO pretende ser Salda (alcance negativo)

- **No es un banco ni un procesador de pagos.** No mueve dinero: registra deudas
  y facilita el pago externo (Bizum/PayPal/Revolut/IBAN). [HECHO: los "botones de
  pago" solo abren enlaces o copian datos — `apps/guest_web/src/lib/payments.ts`.]
- **No es una red social.** No hay feed público, ni descubrimiento de extraños,
  ni contenido. El grafo social es el grupo privado.
- **No es una app de contabilidad/empresa.** Sin facturas fiscales, sin IVA
  deducible, sin multi-empresa.
- **No es un producto de datos.** No monetiza información; minimiza lo que guarda
  (los invitados ni siquiera tienen email).
- **No compite en gamificación**: nada de confeti, rachas ni puntos (descartado
  explícitamente en spec §17).
- **No es multi-divisa en v1** (EUR; preparado para evolucionar, spec DC-8).

## §3. Principios de UX innegociables

1. **El camino feliz nunca supera 3 pantallas** (spec §2.1): cámara → revisión →
   gente/compartir.
2. **La IA es SIEMPRE el último recurso y nunca actúa sola** (DC-13): el orden fijo
   es ① repetir foto ② editar a mano ③ analizar con IA. [HECHO: banner de
   `review_screen.dart` con botón IA deshabilitado sin proveedor configurado.]
3. **Los invitados no instalan nada.** Enlace → "¿quién eres?" → listo. Máximo
   3 toques hasta "ya he pagado".
4. **Escrituras optimistas**: la UI nunca espera al servidor.
5. **Skeletons, no spinners** a pantalla completa (spec §3.8).
6. **El dinero se muestra grande, claro, con cifras tabulares y sin dramatismo.**

## §4. Principios técnicos innegociables

1. **Dinero = céntimos `int` envueltos en `Money`. JAMÁS `double`.** [HECHO:
   `packages/domain/lib/src/money.dart`, extension type.]
2. **Una única primitiva de redondeo** (`allocateProportionally`, resto mayor):
   "Σ partes == total exacto" es un invariante del sistema, no una esperanza.
3. **Los motores de dinero existen en Dart y TS y su paridad la garantizan los
   vectores dorados en CI** — nunca la disciplina. [HECHO:
   `packages/domain/test/golden/*.json` ejecutados por ambos lados.]
4. **La Cloud Function es la calculadora autoritativa** (DC-7); los clientes solo
   leen agregados. La web de invitados no contiene lógica de dinero.
5. **Denegación por defecto** en reglas de Firestore/Storage: solo `allow`
   explícitos, cada celda de la matriz con test positivo y negativo.
6. **Las API keys de IA viven solo en el dispositivo** (Keystore/Keychain), nunca
   en Firestore, logs, crashes ni backups.
7. **Evolución por extensión, no por reescritura:** toda mejora futura debe
   intentar ampliar el producto sin reescribir lo construido. Antes de proponer
   una modificación arquitectónica debe evaluarse si es posible evolucionar el
   diseño existente mediante composición o extensión. Reescribir módulos solo
   está justificado cuando el coste de mantener la solución actual es claramente
   superior al coste de la migración — y ese cálculo debe quedar explícito, no
   ser una intuición.
8. **Principio de simplicidad:** cuando dos soluciones sean funcionalmente
   equivalentes, se elige siempre la más sencilla. La complejidad debe
   justificarse con un problema real ya existente, nunca con una necesidad
   hipotética futura ("por si acaso").

## §4.1. Principios de diseño de producto innegociables

- Cada acción importante en **dos toques o menos** desde su contexto natural.
- **Nunca una cifra de dinero ambigua**: siempre con signo/dirección explícita
  ("Te deben", "Debes", "+", "−") y color acompañado de texto (accesibilidad).
- El usuario **siempre sabe quién debe a quién** en cualquier pantalla con dinero.
- **Ninguna pantalla puede bloquear al usuario sin salida** (bug 4 del MVP fue
  exactamente esto; resuelto con rutas anidadas — ADR-014).
- Siempre existe **una acción principal claramente visible** (un solo botón
  Filled por pantalla, spec §3.5).
- **Todo error indica cómo solucionarse**, no solo que ocurrió (p. ej. los errores
  de IA tipificados: "Clave inválida", "Sin crédito…").
- **El sistema nunca pierde datos silenciosamente**: draft persistente del
  wizard, subida de foto best-effort que no bloquea, backup JSON completo.
- **Toda operación importante es reversible cuando es técnicamente posible**:
  cierre de grupo reversible, liquidaciones des-confirmables por el anfitrión,
  import de backup con resumen previo. Irreversibles (borrar grupo) → doble
  confirmación explícita.
- **Los estados de pago son visibles y auditados**: pendiente → dice que pagó →
  confirmado, con historial (`stateHistory`).
- **Nada de fricción de registro para invitados**, jamás.

## §5. Visión final: cómo debe sentirse Salda terminada

Abrir Salda debe sentirse como abrir un chat: cero carga cognitiva. En un
vistazo: cuánto te deben, cuánto debes, qué grupos tienen movimiento. Crear un
gasto es hacer una foto. Repartirlo es tocar nombres. Cobrar es esperar a que
la app te diga "todos han pagado 🎉". La web del invitado se abre desde WhatsApp
antes de que termine de leerse el mensaje que la contenía (< 1 s). Nada parpadea,
nada se pierde, nada hay que explicar.

## §6. Recorrido completo del usuario (de abrir la app a cerrar un grupo)

1. **Alta** (una vez): email+contraseña o Google. [HECHO: email operativo;
   Google oculto tras flag hasta registrar SHA-1 — `AuthRepository.googleSignInAvailable`.]
2. **Inicio**: historial de grupos con tarjeta "Te deben / Debes" agregada.
3. **Nuevo gasto**: FAB → cámara/galería/gasto manual → OCR → revisión editable
   (cuadre en vivo) → gente y reparto (chips de personas frecuentes, modo, pagador)
   → crear y compartir (QR + enlace).
4. **Invitados**: abren el enlace, eligen quién son, marcan sus productos
   (modo "lo suyo"), ven cuánto deben y a quién, pagan fuera, marcan "ya he pagado".
5. **Anfitrión**: recibe los avisos, confirma pagos, añade más tickets o gastos
   manuales al grupo (multi-cuenta), consulta fotos y desgloses.
6. **Cierre**: cuando todo está saldado, cierra el grupo (solo lectura,
   reversible) o lo archiva. Exporta PDF o imagen-resumen si quiere memoria.

## §7. Modelo mental del producto

```
GRUPO (hoy: Session; kind single|multi)          ← unidad de compartición y seguridad
 ├─ Participantes (p0..pN; p0 = anfitrión)       ← identidad dentro del grupo
 ├─ Cuentas (Account: "Hotel", "Lidl"…)          ← agrupador de tickets
 │    └─ Tickets (escaneado | manual; pagador)   ← generador de movimiento económico
 │         └─ Líneas (producto, cantidad, precio, asignación)
 ├─ Balances (por participante: pagó/consumió/neto/pendiente)  ← DERIVADO (function)
 ├─ Liquidaciones (Settlement: quién paga a quién; pending→marked→confirmed)
 │                                                ← DERIVADO (function) + estado humano
 └─ Actividad (feed append-only)                 ← memoria del grupo
```

Reglas del modelo mental:
- **Todo lo económico deriva de tickets+líneas+pagador.** Balances y liquidaciones
  son SIEMPRE recalculables desde cero; solo el estado humano (marked/confirmed)
  y su historial son hechos primarios no derivables.
- **Una "cuenta suelta" es un grupo `single`** — mismo modelo, misma seguridad;
  la UI oculta la capa (ADR-003).
- **El invitado es un participante reclamado por un dispositivo**
  (`claimedByDevice = uid anónimo`), no una cuenta de usuario.

---

<a name="parte-ii"></a>
# PARTE II — FLUJOS DE USUARIO

Todos los flujos siguientes están implementados [HECHO] salvo lo marcado.

## §8. Flujo del usuario invitado

```
Enlace https://salda-dev.web.app/s/{sid}#k={shareCode}   (código en el FRAGMENT: no llega a logs)
  → SPA Svelte carga (~183 KB gz, chunk Firebase cacheable)
  → Auth anónimo transparente (sin pantalla)
  → prueba de conocimiento: setDoc sessions/{sid}/guestAccess/{uid} {shareCode}
      · código incorrecto o sesión cerrada para nuevos → vista de error amable
  → "¿Quién eres?": tarjetas con los nombres (ocupados marcados "en otro móvil")
  → claim: participants/{pid}.claimedByDevice = uid  (regla impide robar nombres)
  → "Mi resumen": Debes X € a Y · botones de pago configurados · [Ya he pagado]
  → (byItem) "Elegir mis productos": toggle por línea, en vivo, ve a los demás
  → identidad recordada en localStorage; si el anfitrión libera el nombre, se detecta
```
Casos límite cubiertos: nombre ya reclamado (aviso + pedir liberación), sesión
cerrada (solo lectura), enlace inválido, Safari privado sin localStorage
(degrada a volver a preguntar).

## §9. Flujo del usuario registrado (anfitrión)

Login (email+contraseña; recuperación por email) → Home (historial + agregado
te-deben/debes + banner de borrador recuperado si lo hay) → crear/gestionar
grupos → Ajustes (tema, métodos de pago, personas frecuentes, proveedores de IA,
backup, cerrar sesión). Cerrar sesión devuelve al login (guardia del router).

## §10. Flujo de creación y gestión de grupos

- **Creación**: siempre nace de un gasto (foto/galería/manual) — decisión de
  producto: un grupo vacío no significa nada. El nombre se sugiere del comercio.
- **Gestión** (detalle, 3 pestañas): Resumen (balances + liquidaciones accionables
  + historial de confirmados), Cuentas (tickets por cuenta → detalle con foto),
  Actividad ([DECISIÓN TOMADA] el feed se escribe en Firestore pero aún no se
  lista en la app).
- **Menú**: añadir ticket, compartir, exportar PDF, compartir imagen-resumen,
  cerrar (reversible), archivar, eliminar (doble confirmación; cascada en servidor).
- **Multi-cuenta**: añadir un ticket crea la cuenta aN; a la segunda cuenta el
  grupo pasa a `kind: multi` [HECHO: `addTicket` en `firestore_session_repository.dart`].

## §11. Flujo completo de tickets

```
FAB → hoja: [Hacer foto] [Galería] [Gasto sin ticket]
 foto/galería → image_picker (≤1600px, q92) → ML Kit on-device → LineBuilder
   (geometría re-une columnas) → EsReceiptParser (perfiles por cadena + 9 reglas)
   → ReceiptExtraction con confianza POR CAMPO + issues
 gasto manual → extracción `manual` de 1 línea (mismo camino, cero casos especiales)
REVISIÓN (draft persistente en cada edición):
   banner si needsReview (issues || confianza < 0,75) con ① repetir ② editar ③ IA
   cabecera/líneas/totales editables · cuadre en vivo · alternativas en chips
CONTINUAR:
   destino nuevo → hoja Gente y reparto (chips frecuentes; a medias | lo suyo; pagador)
   destino grupo existente → selector de pagador → se añade como cuenta nueva
CREAR → batch Firestore (grupo → participantes p0..pN con `order` → cuenta → ticket
   → líneas) → foto a Storage (best-effort) → share sheet con QR/enlace
```
Asignación de productos: el anfitrión puede asignar (hoja Una/Varias/Todos con
pesos), pero el flujo recomendado es que **cada invitado marque lo suyo desde la
web** (validado campo a campo por reglas).

## §12. Flujo de balances

Los balances NUNCA se calculan en cliente para persistir: la function `recompute`
(triggers: líneas, tickets, participantes y liquidaciones) recalcula
`balances{pid: pagó/consumió/neto/pendiente}` y los escribe en el doc del grupo;
la app y la web solo pintan. La UI separa dos verdades: `paid/consumed/net` es el
histórico económico del reparto; `outstanding` es el saldo pendiente actual tras
descontar transferencias confirmadas. El detalle del cálculo, en §26–§27.

## §13. Flujo de pagos / liquidaciones

```
recompute genera objetivos "quién paga a quién" (mínimas transferencias) con ID
DETERMINISTA pending_{from}_{to}   ← clave anti-duplicados (ADR-013)
  invitado deudor:  pending → marked   ("ya he pagado", con stateHistory)
  anfitrión:        cualquier transición; confirmed CONGELA el pago (RF-53)
  confirmadas: intocables por recompute; se descuentan del pendiente; viven en
  el "historial de pagos confirmados" de la UI (separado de los pendientes)
```
Si tras confirmar se añade un gasto, SOLO se generan pendientes por el delta:
los confirmados no "bailan" jamás (test de regresión con el caso real Lidl+55 €).

## §14. Flujo de notificaciones

[HECHO parcial] La function `notify` envía FCM al anfitrión en pending→marked y
"todos han pagado". **Gap conocido:** la app aún no registra `fcmTokens` en
users/{uid}, por lo que hoy no llega ningún push (§44 deuda técnica DT-1).
Recordatorios a invitados: [DECISIÓN TOMADA] botón "recordar por WhatsApp" y
recordatorio local programable (RF-92/96) sin implementar.

## §15. Flujo de cierre (ticket y grupo)

No existe "cerrar un ticket": la unidad de cierre es el grupo (decisión de
simplicidad, spec RF-14). Cerrar = `status: closed` → inmutable para TODOS
(reglas lo fuerzan) salvo reapertura del anfitrión; archivar = oculto al final
del historial; eliminar = borrado con cascada en servidor (function `cleanup`).

## §16. Flujo de historial / timeline

- Historial de grupos: Home, 1 lectura por grupo (agregados desnormalizados).
- Historial de pagos: sección "Pagos confirmados (N)" plegable en Resumen.
- Historial por ticket: pestaña Cuentas → ticket → foto + líneas + pagador.
- Timeline de actividad del grupo: los eventos se escriben (`activity/`,
  append-only) pero su UI está pendiente ([DECISIÓN TOMADA]; pieza natural del
  modelo "grupos", ver §54).

---

<a name="parte-iii"></a>
# PARTE III — UX Y DISEÑO

## §17. Especificación pantalla por pantalla

La especificación completa de pantallas vive en **spec §4 (app) y §4.2 (web)**;
aquí el mapa verificado de lo implementado [HECHO]:

| Pantalla | Ruta | Acciones principales |
|---|---|---|
| Login | `/login` | entrar, registrarse, recuperar contraseña |
| Home (historial) | `/home` | tarjeta te-deben/debes, lista de grupos, FAB escanear, ajustes, banner de borrador |
| Revisión | `/home/review` | editar todo, banner ①②③, Continuar |
| Gente y reparto | (hoja modal) | chips frecuentes, modo, pagador, crear y compartir |
| Compartir | `/home/session/:sid/share` | QR, copiar, share sheet, Listo |
| Detalle de grupo | `/home/session/:sid` | tabs Resumen/Cuentas/Actividad, menú (añadir ticket, PDF, imagen, cerrar, archivar, eliminar) |
| Detalle de ticket | `/home/session/:sid/ticket` | foto con zoom, líneas, pagador |
| Ajustes | `/home/settings` | tema, métodos de pago, personas frecuentes, IA, backup, salir |
| Proveedores IA | `/home/settings/ai` | configurar, probar conexión (obligatorio), preferido |
| Web: error/quién-eres/resumen/productos/ticket | `/s/:sid#k=` | ver §8 |

Navegación: **rutas anidadas bajo `/home`** — cualquier `go()` construye la pila
completa y siempre hay atrás (ADR-014).

## §18. Estados de cada pantalla

| Estado | Patrón implementado |
|---|---|
| Vacío | ilustración de líneas + 1 frase + 1 CTA (Home: "Escanea tu primer ticket") |
| Carga | skeletons shimmer (Home, web); spinner solo en pantallas puente |
| Éxito | transición directa; snackbar solo para confirmaciones |
| Error | inline junto al elemento + acción de recuperación; errores IA tipificados |
| Offline | persistencia Firestore activa; escrituras optimistas [DECISIÓN TOMADA: chip visual "sin conexión" pendiente] |
| Cerrado | MaterialBanner "solo lectura" en app y web |

## §19. Animaciones y microinteracciones clave

Especificadas en spec §3.6 (curvas M3 emphasized, 150–500 ms, container
transform, línea de escaneo, check dibujado). Estado real [HECHO parcial]: la
web implementa transiciones de progreso y estados; la app usa las transiciones
de Material por defecto. La "línea de escaneo" del OCR y los container
transforms son la principal deuda de pulido visual (DT-6).

## §20. Sistema de diseño

**Fuente única** [HECHO]: `packages/design_tokens/assets/{brand,design_tokens}.json`
→ `dart run design_tokens:generate` → `tokens.g.dart` (app) + `tokens.g.css`
(web). La CI regenera y hace `git diff --exit-code`: es imposible que app y web
diverjan de la fuente sin romper el build. Semilla `#0B6E5D`, Inter con cifras
tabulares en dinero, radios 16/28/24/12/8, espaciado en retícula de 4,
semánticos de estados (pendiente/marcado/confirmado, balance +/−) fuera del
ColorScheme M3 (extensión `SemanticColors`).

## §21. Accesibilidad

- Targets táctiles ≥ 48dp (tema y CSS los fuerzan). Cifras con signo Y texto,
  nunca solo color. `prefers-reduced-motion` respetado en la web; focos visibles.
- svelte-check con reglas a11y a CERO warnings [HECHO, tras corregir roles].
- Pendiente (DT-7): pasada de lectores de pantalla (TalkBack) en app real y
  navegación por teclado completa en la web. Objetivo WCAG en §59.

## §22. Internacionalización

- **Idioma v1: español.** TODA cadena de la app está en ARB
  (`apps/mobile/lib/l10n/app_es.arb`) desde M2; añadir idioma = añadir archivo ARB.
- La web tiene sus cadenas inline en componentes [HECHO] — aceptado para una
  sola locale; si se añade un segundo idioma, extraerlas (registrado en DT-8).
- Formatos: `Intl` es-ES para moneda (`1.234,56 €` con NBSP), fechas ISO en
  datos y localizadas en UI. Moneda única EUR (DC-8), arquitectura preparada
  para multi-moneda (campo `currency` en el grupo desde el día 1).

---

<a name="parte-iv"></a>
# PARTE IV — ARQUITECTURA Y DOMINIO

## §23. Arquitectura del sistema [HECHO]

```
┌───────────────────────── MONOREPO (pub workspace) ─────────────────────────┐
│ packages/design_tokens ──codegen──► tokens.g.dart (app) + tokens.g.css (web)│
│ packages/domain (Dart PURO)   Money · allocate · ShareCode · SplitEngine    │
│        ▲                      BalanceEngine · ReceiptExtraction · errores   │
│        │ misma semántica      └── test/golden/*.json ◄── CONTRATO ──┐       │
│ packages/ocr_parser (Dart puro)  geometría → perfiles → reglas      │       │
│ packages/ai_providers            contrato + 7 proveedores           │       │
├─────────────────────────────────────────────────────────────────────│───────┤
│ apps/mobile (Flutter)             apps/guest_web (Svelte 5)         │       │
│  Riverpod v3 · go_router anidado   SIN lógica de dinero             │       │
│  ML Kit on-device · secure storage  runas + Firebase JS             │       │
│      │ SDK (tiempo real, offline)      │ SDK (tiempo real)          │       │
│      ▼                                 ▼                            ▼       │
│ ╔══════════════════ FIREBASE (salda-dev / salda-prod) ═════════════════╗    │
│ ║ Auth (email, anónimo, [Google pendiente SHA-1])                      ║    │
│ ║ Firestore  ◄─triggers── Functions v2 (europe-west1, max 3 inst):     ║    │
│ ║   reglas §13.2           recompute (×4 triggers, motor TS espejo) ───╫────┘
│ ║   deny-by-default        notify (FCM) · cleanup (cascada+Storage)    ║
│ ║ Storage (fotos receipts/…)      Hosting (web invitados, SPA)         ║
│ ╚══════════════════════════════════════════════════════════════════════╝
```
Comunicación: SOLO SDK de Firebase (tiempo real) y triggers de Firestore. Cero
endpoints HTTP propios. La IA va directa dispositivo→proveedor (la clave nunca
transita infraestructura del proyecto).

## §24. Justificación de decisiones técnicas

Cada una tiene su ADR en §55; resumen de las capitales:
**Flutter** (ADR-001) una base APK+IPA con M3 y ML Kit de primera clase ·
**Svelte para invitados, no Flutter Web** (ADR-002) 183 KB gz frente a ~1,5 MB:
la primera impresión del invitado es sagrada · **Grupo como raíz única**
(ADR-003) un solo modelo/motor/reglas · **Function autoritativa + espejo TS +
vectores dorados** (ADR-004) el invitado ve recalculos sin que el anfitrión abra
la app y ningún cliente puede corromper agregados · **Money extension type**
(ADR-005) coste cero, `double` estructuralmente imposible · **Resto mayor único**
(ADR-006) exactitud como invariante · **Reparto del grandTotal por pesos de
consumo** (ADR-007) un solo redondeo, prorrateo de impuestos/propina gratis ·
**Parser por perfiles+reglas ordenadas** (ADR-009) incremental por construcción ·
**IDs deterministas de liquidaciones** (ADR-013) idempotencia bajo concurrencia.

## §25. Catálogo de objetos de dominio [HECHO: packages/domain]

| Objeto | Representa | Invariantes (lo que NUNCA puede ocurrir) |
|---|---|---|
| `Money` | céntimos int | nunca double; aritmética solo entera |
| `allocateProportionally` | reparto resto-mayor | Σ resultado ≠ total; no determinismo; pesos negativos |
| `ShareCode` | secreto del enlace (128 bits CSPRNG) | aparecer en logs (`toString` opaco); <16 chars |
| `SplitEngine` | consumo por ticket | perder céntimos; depender del orden de llamadas; participante fuera del resultado |
| `BalanceEngine` | netos + liquidaciones mínimas | Σ outstanding ≠ 0; > N−1 transferencias; salida no reproducible |
| `TicketContribution` | pago+consumo de un ticket | Σ consumo ≠ grandTotal (excepción `consumptionMismatch`) |
| `FrozenSettlement` | pago confirmado | ser regenerado o alterado por recompute |
| `ReceiptExtraction` | contrato OCR/IA/manual | perder el origen (`engine`); confianzas fuera de [0,1] |
| `DomainException` | error con código estable | códigos distintos entre Dart y TS |

## §26. Motor de reparto (SplitEngine) — pseudocódigo y límites

```
splitTicket(participantes[], modo, ticket{grandTotal, líneas[]}, políticaHuérfanas):
  si participantes vacío → error emptyParticipants
  pesos := modo == equal ? [1,1,…]
           : para cada línea: repartir línea.total por su asignación
             (one→todo a ese pid · shared→pesos>0 · all→iguales entre activos ·
              unassigned→error | tratar como all según política)
             y acumular céntimos por participante
  si todos los pesos son 0 (manual sin líneas) → pesos iguales
  si grandTotal == 0 → todos 0
  devolver allocateProportionally(grandTotal, pesos)   ← ÚNICO redondeo
```
Casos límite con test [HECHO, 19 vectores dorados + propiedades]:
resto de céntimos (1000/3 → 334/333/333, empate al índice menor), totales
impares (1001), impuestos/descuentos/propina implícitos en la proporción,
cuota cero (peso 0 válido → recibe 0), pesos inválidos, totales negativos
(ajustes), participante excluido (se filtra ANTES de llamar: "todos" = los
que recibe el motor).

## §27. Motor de balances (BalanceEngine) — pseudocódigo y límites

```
compute(participantes[], contribuciones[], congeladas[]):
  pagado[p]   += grandTotal de cada ticket que pagó p
  consumido[p]+= su consumo (validado: Σ == grandTotal)
  neto = pagado − consumido            (Σ neto == 0 SIEMPRE)
  pendiente = neto ± congeladas        (lo ya transferido se descuenta)
  simplificación voraz determinista: mayor deudor paga al mayor acreedor;
  empates → orden estable de participantes (campo `order`); ≤ N−1 transferencias
```
Límites cubiertos: deudas circulares (el neto las colapsa solas — nunca se
modelan como grafo), congeladas por exceso (la deuda se invierte), participante
inactivo, pagador/consumidor huérfano (recompute sanea con log — §31),
10 vectores dorados + 300 sesiones aleatorias sembradas verificando que aplicar
las liquidaciones deja a todos exactamente en paz.

## §28. Pipeline OCR completo [HECHO: packages/ocr_parser]

```
imagen → ML Kit (on-device, gratis) → OcrDocument (fragmentos + cajas)
  → LineBuilder: re-une por solapamiento vertical las columnas que ML Kit separa;
    normaliza confusiones en contexto numérico (O→0, l/I→1)
  → ReceiptParser (registry por país; v1: 'es') → EsReceiptParser:
      1) fecha/hora (ANTES de canonicalizar importes: "18.32" es hora, no 18,32 €)
      2) perfil de cadena: por nombre O POR NIF (sobrevive a cabeceras térmicas
         ilegibles); 10 perfiles: Mercadona, Carrefour, Lidl, DIA, Alcampo,
         Eroski, ALDI, Consum, Repsol, Cepsa
      3) canonicalización de importes degradados (punto decimal → coma, penaliza confianza)
      4) total: palabras clave por fuerza, fuera de la zona de IVA
      5) cuerpo: 7 reglas de línea ORDENADAS + 2 de continuación (pesables
         Mercadona y multiplicador DIA en dos filas) + descuentos/propina/subtotal
      6) IVA: tabla al pie (base/cuota)
      7) confianza POR CAMPO + issues (sumMismatch/missingTotal/noLines/missingDate)
  → ReceiptExtraction (contrato común con IA y manual)
```
**Corpus de regresión** (`test/corpus/`, 13 casos): 12/12 mustPass; métricas
100 % en comercio/fecha/hora/total/issues y 92 % en líneas. Protocolo: cada
ticket real que falle se anonimiza, entra al corpus y se arregla con una regla
nueva SIN tocar las anteriores; si un caso `mustPass:false` empieza a pasar, el
harness FALLA para obligar a promocionarlo. Limitación conocida documentada:
nombres partidos en dos filas sin marcador (no afecta al dinero).
Estrategia de fallback (DC-13): confianza < 0,75 o issues → banner ① repetir
foto ② editar ③ IA.

## §29. Contrato de proveedores de IA [HECHO: packages/ai_providers]

```dart
abstract interface class AiReceiptProvider {
  String id; String displayName;
  bool supportsVision; bool requiresApiKey; bool requiresBaseUrl;
  List<String> suggestedModels;
  Future<void> testConnection(config);            // RF-31: obligatorio antes de guardar
  Future<ReceiptExtraction> extractReceipt(input, config);
}
```
- **Prompt canónico ÚNICO** (céntimos, quantityMilli, JSON estricto) +
  `parseAiResponse` compartido: tolera vallas markdown, valida estructura y
  cuadre (descuadre → issue → revisión), produce el MISMO `ReceiptExtraction`
  que el parser.
- Proveedores: Claude, Gemini (clave SIEMPRE en cabecera, nunca en URL) y
  OpenAI-compatible genérico (base URL: Ollama/LM Studio/vLLM); OpenAI,
  DeepSeek, GLM y OpenRouter son PRESETS del genérico (cero duplicación).
- **Añadir un proveedor** = implementar la interfaz (o un preset) + registrarlo
  en `AiProviderRegistry.standard` + test con adapter Dio falso (checklist §58).
- **Lo que nunca debe romperse:** errores tipificados estables
  (invalidKey/noCredit/rateLimited/modelNotAllowed/network/badResponse/
  unsupportedInput); la clave se inyecta POR LLAMADA (jamás persiste en el
  paquete); la salida es `ReceiptExtraction` con `engine: 'ai:<id>'`;
  la IA jamás se invoca sin acción explícita del usuario.

---

<a name="parte-v"></a>
# PARTE V — BACKEND E INFRAESTRUCTURA

## §30. Modelo de datos de Firestore [HECHO]

El esquema completo con tipos está en **spec §7** (fuente normativa) y en
`CLAUDE.md §6`. Resumen operativo con lo que el código escribe hoy:

```
users/{uid}: schemaVersion, displayName, paymentMethods{bizumPhone,paypalLink,
             revolutTag,iban}   [aiPolicy y fcmTokens: DECISIÓN TOMADA, sin escribir]
users/{uid}/frequentPeople/{slug}: name, usageCount, lastUsedAt
sessions/{sid}: schemaVersion, ownerUid, kind single|multi, name, currency,
   category, status open|closed|archived, closedAt?, shareCode(128b),
   splitModeDefault, ownerParticipantId, paymentMethodsSnapshot,
   AGREGADOS solo-función: totals{grandTotal,settlementRequired,
   settledConfirmed,settledMarked},
   balances{pid:{paid,consumed,net,outstanding}}, pendingSettlements,
   participantsCount, computeVersion, createdAt, updatedAt
 /participants/{p0..pN}: name, isOwner, order, claimedByDevice, active
 /guestAccess/{uid}: shareCode            ← prueba de conocimiento del invitado
 /accounts/{a0..aN}: name, order, createdAt, totals{grandTotal}(solo-función)
   /tickets/{auto}: kind, merchant{name,brandKey}, date, time,
      paidByParticipantId, ocr{engine,confidence}, taxes[], discounts[], tip,
      grandTotal, imagePath?, createdAt
     /lines/{l0..lN}: name, quantityMilli, unitPrice?, totalPrice, order,
        assignment{type, participants{pid:peso}, lastEditorPid?}
 /settlements/{pending_{from}_{to} | legacy}: from, to, amount,
      state pending|marked|confirmed, stateHistory[], createdAt, updatedAt
 /activity/{auto}: type, actor|actorPid, at   (append-only)
Storage: receipts/{sid}/{ticketId}/original.jpg
```

## §31. Cloud Functions [HECHO: backend/functions/src]

| Función | Trigger | Responsabilidad | Idempotencia |
|---|---|---|---|
| `recompute` (×4 bindings: OnLine, OnTicket, OnParticipant, OnSettlement) | onDocumentWritten | recalcula totales de cuenta, balances, pendientes y sincroniza liquidaciones con el motor TS espejo | total: IDs deterministas `pending_{from}_{to}`; escribe SOLO si algo cambió (sin cambio → sin bump de computeVersion → convergencia sin bucles); N ejecuciones concurrentes escriben el mismo doc con el mismo contenido |
| `notify` | onDocumentUpdated settlements | FCM al anfitrión (pending→marked; "todos han pagado") | sin efectos si no hay tokens |
| `cleanup` | onDocumentDeleted sessions (retry: true) | recursiveDelete de subcolecciones + purga de Storage | reintentable por diseño |

Saneamiento en recompute: asignaciones a pids desconocidos se ignoran (log) y
un pagador borrado recae en el owner (log) — datos huérfanos jamás rompen el
recálculo. Región europe-west1, 256 MiB, `maxInstances: 3` (techo de coste,
NO subir sin aprobación del usuario).

## §32. Reglas de seguridad, regla por regla

Archivo [HECHO]: `backend/firestore/firestore.rules` (comentado en el propio
archivo) + `storage.rules` espejo. Esencia:

- `users/**`: solo su dueño con email verificado; nunca anónimo o pendiente.
- `sessions` create: cuenta verificada o invitado móvil, `status: open`, shareCode ≥16,
  agregados a cero (a partir de ahí solo la función los escribe — deny por diff).
- lectura: owner por query (`ownerUid == uid`) o invitado con
  `exists(guestAccess/{uid})` — la **prueba de conocimiento**: crear guestAccess
  exige presentar el shareCode correcto con la sesión abierta.
- update owner: nunca ownerUid/totals/balances/computeVersion; cerrada → solo
  reabrir/archivar. delete: solo owner.
- `participants`: invitado SOLO `claimedByDevice` (reclamar libre / liberar el suyo).
- `lines` update invitado: SOLO su entrada del mapa (`assignment.lastEditorPid`
  declarado y verificado contra su claim), peso 1, modo efectivo byItem, sesión
  abierta, y jamás convertir a "all".
- `settlements`: create/delete solo owner (necesario para importar backups,
  RF-91; los invitados jamás); update owner = transiciones de estado; invitado =
  SOLO pending→marked donde él es `from`.
- `activity`: append-only para miembros.
- Storage: owner RW (JPEG ≤2 MB), invitado R vía `firestore.exists(guestAccess)`.

**54 tests, una celda positiva y negativa por regla**, contra el emulador en CI
[HECHO: `backend/firestore/test/rules.test.mjs`].

## §33. Índices y por qué

`firestore.indexes.json` [HECHO]: `sessions(ownerUid, updatedAt desc)` (historial)
y `sessions(ownerUid, status, updatedAt desc)` (filtros por estado). No hay más
porque todas las demás lecturas son por documento o subcolección pequeña con un
solo orderBy.

## §34. Modelo de permisos: cliente vs servidor

| Se valida en CLIENTE (UX) | Se valida en SERVIDOR (verdad) |
|---|---|
| formularios, cuadre en vivo, navegación | TODO lo anterior otra vez vía reglas |
| cálculo optimista de balances | recompute autoritativo (Admin SDK) |
| — | pertenencia (owner/guestAccess), transiciones de estado, shape de docs |

**Nunca se confía al cliente:** agregados de dinero, creación de liquidaciones
(salvo owner para backup), identidad de invitado (claim verificado), shareCode
(comparado por la regla), estados de pago ajenos.

## §35. Costes por servicio

[HECHO] Presupuesto real configurado por el usuario: **3 €/mes con alertas**
(la spec preveía techo 5 €). [ANÁLISIS HIPOTÉTICO, tarifas 2026]:

| Nivel de uso | Firestore | Functions | Storage | Total/mes |
|---|---|---|---|---|
| Personal (≤10 grupos/mes) | < 1 % cuota gratis | < 1k invocaciones | ~50 MB | **0 €** |
| 100 usuarios activos | ~5k lect/día (gratis) | ~20k/mes (gratis) | 1–2 GB (~0,05 €) | **< 0,20 €** |
| 10k usuarios | ~1 M lect/día ≈ 15 €/mes | ~2 M/mes (límite gratis) | 50 GB ≈ 1,2 € | **~20 €** (revisar §43) |

Optimizaciones YA aplicadas: 1 lectura por grupo en el historial (agregados
desnormalizados), listeners autoDispose por pantalla, recompute escribe solo si
cambia, imágenes ≤1600px q92, chunk web de Firebase cacheable entre deploys,
alertas de métricas recomendadas en spec §12.4.

---

<a name="parte-vi"></a>
# PARTE VI — CALIDAD, RENDIMIENTO Y SEGURIDAD

## §36. Estrategia de testing [HECHO: 251 tests]

| Capa | Tipo | Qué cubre | Dónde |
|---|---|---|---|
| domain (61) | unitario + propiedades sembradas + **golden** | motores exactos, roundtrips, 33 vectores compartidos | packages/domain/test |
| ocr_parser (22) | unitario + **corpus 13 casos** con harness de métricas | geometría, patrones, parser completo, regresión | packages/ocr_parser/test |
| functions TS (55) | unitario + **golden (los MISMOS json)** + regresiones reales | paridad Dart↔TS, recompute idempotente/concurrente, progreso | backend/functions/src/test |
| reglas (54) | integración contra Emulator Suite | cada celda de la matriz, positivo y negativo | backend/firestore/test |
| app (56) | widget + repos con fake_cloud_firestore + controladores con fakes | flujos, identidad, drafts, backup, IA, progreso y reactividad | apps/mobile/test |
| web (21) | vitest de lógica pura + svelte-check + presupuesto de peso | enlace, assignment, dinero, pagos, progreso y frontera económica | apps/guest_web/src/lib |

**Deliberadamente sin cubrir (y por qué):** UI Svelte por componentes (4 vistas
sencillas; la lógica que importa está extraída y testeada), E2E automatizado con
dispositivo (se hace manual con el teléfono; Playwright sería coste > valor hoy),
integración de functions desplegadas (el núcleo puro + reglas + golden cubren el
riesgo real).

## §37. Rendimiento

Aplicado [HECHO]: OCR on-device < 3 s típico; web 183 KB gz < presupuesto 220 KB
(script `check-size.mjs` FALLA la CI si se supera); 1 lectura/grupo en historial;
escrituras optimistas; imágenes lazy. Objetivos numéricos en §59.
Futuras (por prioridad): compilar release con `--split-per-abi`, precache del
chunk Firebase en la web, container transforms sin jank (probar en gama media).

## §38. Seguridad: modelo de amenazas

**Asunción base:** grupos de confianza social (amigos); el anfitrión es
semi-confiable dentro de SU grupo; los invitados son anónimos no confiables;
Internet es hostil.

| Superficie | Amenaza | Mitigación [HECHO salvo nota] |
|---|---|---|
| Enlace compartido | terceros con el enlace | shareCode 128 bits CSPRNG en fragment (no llega a logs), regenerable con revocación de guestAccess |
| Invitado malicioso | tocar dinero/estados ajenos | reglas: solo SU claim, SU entrada de línea (peso 1), SUS pending→marked |
| Cliente comprometido | corromper agregados | agregados solo-función; recompute regenera desde datos primarios |
| API pública del proyecto | scripts contra Firestore | App Check [DECISIÓN TOMADA: registrar y forzar tras validar en dispositivo] |
| Claves IA | exfiltración local | Keystore/Keychain, sin backup, scrubbing implícito (nunca se loguean), inyección por llamada |
| Secretos de infraestructura | filtración en repo | no hay: config cliente es pública por diseño (ADR-016); credenciales CLI en keyring del SO |

## §39. Privacidad y RGPD

Datos personales tratados: email y nombre del anfitrión (Auth), nombres de pila
de participantes (los pone el anfitrión; sin contacto), fotos de tickets
(pueden revelar hábitos), métodos de cobro del anfitrión (teléfono Bizum/IBAN,
que ÉL decide compartir con su grupo). Base legal razonable: ejecución del
servicio solicitado + interés legítimo del grupo [SUPOSICIÓN — VERIFICAR con
revisión legal antes de publicar en Play].
Implementado que ayuda: región europe-west1, minimización (invitados sin email),
borrado en cascada (cleanup), exportación completa (backup JSON = portabilidad),
shareCode en fragment. Pendiente ANTES de release pública (DT-9): política de
privacidad visible, flujo de borrado de cuenta de usuario completo (RF-05),
retención definida para fotos de grupos cerrados.

## §40. Taxonomía de errores

| Categoría | Ejemplos | Al usuario | Registro |
|---|---|---|---|
| Dominio (esperados) | `DomainException{unassignedLine, consumptionMismatch…}` códigos estables Dart=TS | inline accionable | no es error de sistema |
| Extracción | `ReceiptIssue{sumMismatch…}` | banner ①②③ | métrica de corpus |
| IA tipificados | `AiErrorCode{invalidKey, noCredit…}` | snackbar con causa y remedio | debugPrint |
| Auth | `AuthFailure{invalid-credential…}` | mensaje específico | — |
| Infra inesperados | excepciones no capturadas | genérico + reintento | Crashlytics [DECISIÓN TOMADA: SDK aún no integrado — DT-2] |

## §41. Observabilidad

Hoy [HECHO]: `logger` estructurado en functions (visible con
`firebase functions:log`; fue EXACTAMENTE lo que permitió diagnosticar la carrera
de liquidaciones en producción), stateHistory como auditoría de pagos,
computeVersion como latido del recálculo. CI como detector de regresión previa
al deploy. Pendiente (DT-2): Crashlytics + Analytics mínimos en app, y las
alertas de métricas GCP de spec §12.4 (lecturas/día, invocaciones/día) para
detectar regresiones de coste antes que la factura.

---

<a name="parte-vii"></a>
# PARTE VII — AUDITORÍA Y EVOLUCIÓN

## §42–§43.2. Riesgos, escalabilidad y registro formal

### §43. Límites conocidos del diseño actual

- **recompute lee el árbol entero del grupo** en cada disparo: perfecto hasta
  ~centenares de líneas por grupo; un grupo con miles de tickets lo degradaría
  (lecturas y latencia). Mitigación natural: recompute incremental por cuenta
  [PROPUESTA, solo si aparece el problema real].
- **1 doc de sesión concentra los agregados**: contención de escritura si
  decenas de ediciones/segundo en el MISMO grupo (irreal en el caso de uso).
- **El historial pagina de 20 en 20** pero la tarjeta te-deben/debes suma sobre
  lo cargado: con cientos de grupos abiertos sería parcial (DT-5, menor).

### §43.1. [ANÁLISIS HIPOTÉTICO] Comportamiento por escalones

| Escalón | Qué aguanta sin tocar | Primero en romperse | Mitigación |
|---|---|---|---|
| 10 grupos activos | todo | nada | — |
| 100 | todo | nada relevante | activar alertas métricas |
| 1.000 | Firestore/Functions holgados (~15-30 €/mes) | coste de lecturas del historial si hay usuarios muy intensivos; soporte manual | cache agresiva; App Check enforced obligatorio |
| 100.000 grupos / millones de tickets | motores (son O(n) puros) y modelo de datos | (1º) coste Firestore lecturas+recompute; (2º) fan-out de recompute por línea; (3º) OCR sigue on-device: escala gratis | recompute incremental + colas (Tasks) para agrupar triggers; presupuestos por grupo; sharding de agregados si hiciera falta (contador distribuido) |

Chat y timeline (visión §2): Firestore está especialmente bien para ambos
(subcolecciones append-only + listeners) — el modelo actual de `activity/` ya es
el embrión del timeline.

### §43.2. Registro de riesgos formal

| Riesgo | Prob. | Impacto | Mitigación |
|---|---|---|---|
| Un supermercado cambia el formato del ticket y rompe un perfil OCR | Alta (con el tiempo) | Medio | corpus de regresión + reglas aditivas: arreglar = añadir caso+regla; la confianza por campo degrada con aviso, no en silencio |
| Proveedor de IA cambia su API | Media | Bajo | 7 proveedores intercambiables + genérico OpenAI-compatible; errores tipificados; el producto funciona 100 % sin IA |
| Release desincronizada de FlutterFire (YA OCURRIÓ, §48.1-E5) | Media | Medio | pins exactos documentados en pubspec; despinear con verificación |
| Coste Firestore por bug de listeners | Baja | Medio | autoDispose + alertas métricas (pendiente activar) + presupuesto 3 € |
| Bucle de functions | Baja | Medio | escritura solo-si-cambia + maxInstances 3 + idempotencia por IDs deterministas |
| Abuso del enlace público | Media | Bajo | 128 bits + revocación + App Check (pendiente enforce) |
| Dependencia de una sola persona (bus factor) | Alta | Alto | esta Biblia + CLAUDE.md + spec + CI que no permite degradar |

## §44. Deuda técnica clasificada

**Crítica** (bloquea release pública, no el uso propio):
- **DT-1** `fcmTokens` nunca se registran → las notificaciones push no llegan
  aunque `notify` funciona. — *Pequeña, alto valor.*
- **DT-2** Crashlytics/Analytics sin integrar → ceguera ante crashes de terceros.
- **DT-3** App Check sin registrar/forzar (requiere Play Integrity con la app
  firmada) → API abierta a scripts con la config pública.

**Media**:
- **DT-4** El feed `activity/` se escribe pero no se muestra (timeline UI).
- **DT-5** Agregado te-deben/debes calculado sobre la página cargada del historial.
- **DT-6** Microinteracciones spec §3.6 sin implementar (escaneo, container
  transform, haptics).
- **DT-9** Flujo RGPD de borrado de cuenta + política de privacidad (RF-05).
- **DT-10** `aiPolicy` (sugerir/preguntar/nunca) definido en spec, sin ajuste en UI.

**Baja**: DT-7 pasada TalkBack/teclado; DT-8 cadenas de la web inline;
DT-11 recordatorios (RF-92/96); DT-12 import de PDF (RF-21; `parsePlainText` ya
existe); DT-13 web de invitados no muestra la foto del ticket; DT-14 pins de
FlutterFire por revisar cuando publiquen core 4.13.

## §45. Mejoras futuras y descartes

Ver spec §17-§18 (vigente). Descartado con motivo: gamificación/confeti (ruido),
chat propio EN v1 (WhatsApp ya existe; reevaluar con la visión grupos §2),
Flutter Web para invitados (peso), reconocimiento visual de logos (coste/valor),
multi-divisa v1 (complejidad sin caso real todavía).

## §46. Auditoría crítica honesta

- **Lo que cambiaría ya si costara gratis:** terminar la tríada
  DT-1/DT-2/DT-3 — es la diferencia entre "me funciona" y "producto".
- **Lo que envejecerá peor:** el fan-out de recompute (un trigger por línea).
  Correcto hoy (idempotente), derrochador a escala. La solución (agrupar por
  onWrite de ticket con debounce/cola) está clara y NO exige migrar datos.
- **Complejidad que vigilar:** `firestore_session_repository` crece hacia
  god-object; si supera ~600 líneas, trocearlo por agregado (sessions/tickets/
  settlements) manteniendo la interfaz.
- **UX**: la hoja "gente y reparto" concentra demasiadas decisiones para un
  usuario nuevo; con la visión grupos, separar "elegir grupo existente" de
  "crear grupo" será más natural.
- **Lo que rompería a gran escala:** nada estructural — el modelo de datos y los
  motores escalan; lo que dolería es COSTE, no corrección (§43.1).

## §47. Qué cambiaría si empezara de cero

Casi nada de fondo: mismas 8 decisiones capitales (§24). Haría distinto:
(1) IDs deterministas de liquidaciones DESDE EL DÍA UNO (el bug de concurrencia
era previsible); (2) rutas anidadas desde M0; (3) registrar fcmTokens en M3;
(4) `flutter run` con dispositivo desde M2 — probar en hardware ANTES de tener
6 fases encima habría cazado los bugs 1-4 mucho antes; (5) nombre interno
`Group` en lugar de `Session` (la visión ya apuntaba ahí).

## §48. Qué mantendría pase lo que pase

Los 8 principios técnicos de §4 — con especial énfasis en: vectores dorados
como contrato entre lenguajes, function autoritativa, deny-by-default con test
por celda, y dinero entero con una única primitiva de redondeo.

## §48.1. Errores históricos (postmortem permanente) [HECHO: verificable en git]

| # | Qué pasó | Causa raíz | Lección |
|---|---|---|---|
| E1 | Liquidaciones duplicadas y balances incoherentes en la primera prueba real (commit `d5e6d55`) | N líneas de un batch → N recomputes concurrentes creando docs con ID aleatorio | La idempotencia no es opcional en triggers: IDs deterministas y "escribir solo si cambia". Los logs estructurados de la function fueron la evidencia decisiva |
| E2 | Flujo atrapado sin "atrás" tras crear grupo (`d5e6d55`) | `go()` sobre rutas planas vacía la pila | Diseñar la jerarquía de rutas al principio; "ninguna pantalla sin salida" es un principio, no un deseo |
| E3 | Botón de IA muerto con proveedor válido (`d5e6d55`) | FutureProvider sin autoDispose cachea un `false` eterno | El ciclo de vida de providers derivados de estado externo debe invalidarse explícitamente |
| E4 | Web de invitados "Site Not Found" (`d5e6d55`) | M4 se validó solo contra emuladores; nunca se desplegó Hosting y el dominio era placeholder | "Verificado" significa verificado EN EL ENTORNO REAL; añadido al checklist de release |
| E5 | Stack FlutterFire roto aguas arriba (referencia a clase inexistente) | release desincronizada en pub.dev el 2026-07-13 | Pinear conjuntos alineados con el motivo escrito en el pubspec; no perseguir `latest` |
| E6 | Mojibake de acentos en CI yaml (commit `984c728`) | `-replace` de PowerShell 5.1 leyó UTF-8 como ANSI | Editar archivos con tildes SOLO con herramientas de edición, nunca con sustituciones de shell |
| E7 | Hora "18.32" convertida en importe por el canonicalizador | orden de fases del parser | El orden de normalizaciones es parte del contrato; test de regresión en corpus |
| E8 | `flutterfire configure` colgado en prompt oculto | CLI interactiva en entorno no interactivo | Preferir comandos deterministas (apps:create + sdkconfig) en automatización |

---

<a name="parte-viii"></a>
# PARTE VIII — VISIÓN DE FUTURO (sin implementar)

## §49–§50. Funcionalidades futuras y qué las habilita/bloquea

| Funcionalidad futura | Qué decisión actual la hace posible sin reescritura | Qué la bloquearía |
|---|---|---|
| **Grupos persistentes + chat + timeline** | el grupo YA es la raíz (`Session`), `activity/` append-only ya existe, listeners en tiempo real por diseño | haber hecho el ticket la raíz; agregados calculados en cliente |
| Pagos integrados / wallet | liquidaciones como docs con estado y auditoría; snapshot de métodos de pago | estados de pago acoplados al ticket (se evitó a propósito) |
| Cuentas compartidas / presupuestos | modelo cuenta→tickets ya multi | — |
| Estadísticas de gasto | categoría por ticket + fechas ISO + agregados por función | dinero en double (imposible por diseño) |
| IA más avanzada / OCR continuo | contrato `ReceiptExtraction` común a TODOS los orígenes; proveedores enchufables | prompt/parseo acoplado a un proveedor |
| Widgets / Wear / Watch / Auto | agregados desnormalizados (1 lectura = 1 widget) | — |
| Exportaciones avanzadas / API pública | backup JSON versionado como formato canónico de intercambio | — |
| Multi-idioma / multi-moneda | ARB + `currency` por grupo + Money agnóstico | strings en la web (DT-8, menor) |
| Push web a invitados / PWA | manifest ya presente; falta SW (decisión consciente) | — |

---

<a name="parte-ix"></a>
# PARTE IX — ROADMAP Y EJECUCIÓN

## §51–§53. Roadmap detallado hasta 1.0

Formato por tarea: objetivo · dependencias · dificultad (S/M/L) · riesgo ·
criterios de aceptación (CA) · tests · docs. La Definition of Done (§63) aplica
a TODAS.

### Fase R1 — "De MVP a producto propio fiable" (prioridad máxima)
1. **fcmTokens + permiso de notificaciones** (DT-1) · dep: dispositivo · S ·
   CA: pending→marked dispara push real en el móvil · test: unit del registro
   de token; manual E2E · docs: CLAUDE.md.
2. **Crashlytics + Analytics mínimos** (DT-2) · S · CA: crash forzado visible
   en consola · docs: §41.
3. **App Check** (DT-3) · dep: firma release + Play Integrity · M · riesgo:
   bloquear clientes legítimos → modo monitor 1 semana antes de enforce ·
   CA: métricas de verificación >99 % antes de enforce.
4. **Timeline de actividad en el detalle** (DT-4) · S · CA: eventos existentes
   listados en vivo; escritura de eventos faltantes (confirmaciones).
5. **Chip offline + cola visible** · S · CA: modo avión → chip + edición sigue
   funcionando → reconexión sincroniza.
6. **Pulido spec §3.6**: línea de escaneo, container transform, haptics (DT-6) · M.

### Fase R2 — "Listo para otros" (beta cerrada)
7. Borrado de cuenta + política de privacidad (DT-9) · M · CA: RF-05 completo.
8. aiPolicy en Ajustes (DT-10) + sugerencia por confianza (DC-13 completo) · S.
9. Recordatorios (DT-11): botón WhatsApp + programado local · M.
10. Import PDF (DT-12) · M · dep: pdfx render nativo verificado en dispositivo.
11. Foto del ticket en la web de invitados (DT-13) · S.
12. Corpus con ≥10 tickets reales del uso propio · continuo · CA: mustPass
    verdes tras cada adición.
13. Flavors dev/prod + firma release + `salda-prod` completo (replicar Auth/
    Storage/Functions/reglas; SHA-1 → Google Sign-In ON) · M.
14. Beta: Play internal testing + App Distribution · S.

### Fase R3 — "Visión grupos v1" (§54)
15. Renombrado de superficie: "Grupos" en UI (código sigue `Session`) · S.
16. Grupos persistentes: crear grupo sin gasto inicial; añadir gasto a grupo
    desde el FAB global (selector de grupo reciente) · M.
17. Timeline enriquecido (quién marcó, quién editó, quién entró) · M.
18. Perfil de usuario + avatar · S · **HECHO P2**. 19. Amistades canónicas por
    UID, independientes de personas frecuentes y de relaciones económicas · M ·
    **HECHO P3** (ADR-027).
20. [Evaluar tras uso real] chat ligero por grupo (Firestore está hecho para
    esto; decidir con el principio de simplicidad en la mano).

### Fase R4 — 1.0 pública
21. Página de producto + dominio definitivo + rebranding si procede (cambiar
    `brand.json` y regenerar) · 22. Play Store listing + revisión RGPD legal ·
23. iOS (Sign in with Apple, TestFlight) — la base ya compila para iOS
    [SUPOSICIÓN — VERIFICAR en un Mac].

**Dependencias entre fases:** R1 → R2 (sin fiabilidad no hay beta) → R4;
R3 puede solaparse con R2 salvo el punto 16 que conviene tras la beta inicial.

## §54. Estrategia de migración al modelo centrado en grupos

**Conclusión de la auditoría: NO hay migración de datos — hay evolución de
superficie.** El modelo actual YA es grupos:

| Concepto visión | Ya existe como | Trabajo real |
|---|---|---|
| Grupo | `sessions/{sid}` (kind multi) | renombrar UI + crear-sin-gasto (R3.15-16) |
| Miembros | `participants` + frequentPeople | perfiles/amigos (R3.18-19) |
| Movimientos | cuentas+tickets | ninguno |
| Balances/pagos | agregados + settlements | ninguno |
| Timeline | `activity/` (ya se escribe) | UI (R1.4, R3.17) |
| Chat | — | subcolección `messages/` NUEVA por extensión; reglas espejo de activity; CERO cambio en lo existente |

Regla de la migración: **prohibido renombrar colecciones o campos existentes**
(evolución por extensión). `kind: single` sigue siendo la "cuenta rápida" y la
UI decide cuánta "grupidad" mostrar.

## §55. Registro de decisiones de arquitectura (ADR)

> Fechas: verificables por commit donde se indica; el razonamiento completo
> vive en spec §0/§8-§9 y CLAUDE.md §8-§9. Formato completo aplicado; para
> mantener este documento manejable, Contexto/Problema se comprimen cuando la
> spec ya los desarrolla.

### ADR-001: Flutter como base única móvil
**Estado:** Aceptada · **Fecha:** 2026-07-09 (commit `e3804f3`)
**Contexto/Problema:** una base de código para Android e iOS con UI M3 de calidad y OCR on-device.
**Alternativas:** React Native (M3 de terceros, ML Kit comunitario) — descartada; KMP (UI iOS inmadura) — descartada.
**Decisión:** Flutter estable + Riverpod + go_router.
**Consecuencias:** + un solo equipo/base; − builds Android pesados en Windows.
**Revisión futura:** solo si Flutter dejara de soportar una plataforma objetivo.

### ADR-002: Web de invitados en Svelte (no Flutter Web)
**Estado:** Aceptada · **Fecha:** 2026-07-09 (spec v2.0, `e3804f3`)
**Problema:** el enlace se abre desde WhatsApp; 1,5–2 MB de Flutter Web = 3–6 s.
**Alternativas:** Flutter Web (peso) — rechazada; Preact/vanilla — equivalente, Svelte ganó por DX.
**Decisión:** Svelte 5 + Vite, SIN lógica de dinero, presupuesto de peso en CI (220 KB gz).
**Consecuencias:** + 183 KB gz reales; − dos stacks de UI (mitigado: tokens compartidos por codegen y cero dinero en web).
**Revisión:** si la web creciera a producto completo (no previsto).

### ADR-003: El grupo (Session) como raíz única; cuenta suelta = `single`
**Estado:** Aceptada · **Fecha:** 2026-07-09 (spec DC-6)
**Problema:** dos modelos (cuenta suelta vs sesión) duplicarían motor, reglas y UI.
**Decisión:** una sola raíz; la UI oculta la capa cuando kind=single.
**Consecuencias:** habilitó la visión "grupos" sin migración (§54).
**Revisión:** no prevista; es la base del producto.

### ADR-004: Function autoritativa + espejo TS + vectores dorados
**Estado:** Aceptada · **Fecha:** M1-M3 (`8ace6b4`, `84726bd`)
**Problema:** el invitado debe ver recalculos sin que el anfitrión abra la app; los clientes no pueden ser confiables para agregados; dos runtimes ⇒ riesgo de divergencia.
**Alternativas:** todo en cliente (frágil, sin tiempo real para invitados) — rechazada; solo servidor (offline roto) — rechazada.
**Decisión:** cálculo local optimista + recompute autoritativo; LOS MISMOS json dorados corren en Dart y TS en CI.
**Consecuencias:** + corrección verificable; − motores duplicados (el precio se paga UNA vez, la CI vigila para siempre).
**Revisión:** si Dart llegara a Cloud Functions de forma estable.

### ADR-005: `Money` extension type sobre céntimos int — **Fecha:** M1.
Nunca double; coste runtime cero. Revisión: nunca.

### ADR-006: Resto mayor como única primitiva de redondeo — **Fecha:** M1.
Σ==total como invariante con desempate determinista. Revisión: nunca.

### ADR-007: SplitEngine reparte el grandTotal por pesos de consumo — **Fecha:** M1.
Prorrateo de impuestos/descuentos/propina implícito; un solo redondeo. Alternativa (prorratear cada ajuste) acumulaba error. Revisión: si un caso legal exigiera desglose exacto por ajuste.

### ADR-008: pub workspace nativo (sin melos) — **Fecha:** M0. Menos herramienta; lockfile único en la raíz.

### ADR-009: Parser OCR = registry país + perfiles por cadena (detección por NIF) + reglas ordenadas — **Fecha:** M2 (`3aca453`).
Incremental por construcción; térmico ilegible ≠ marca perdida; corpus como contrato. Revisión: añadir país = nueva clase, no tocar esto.

### ADR-010: Confianza por campo + issues + alternativas por línea — **Fecha:** M2. La revisión manual resalta solo lo dudoso; corregir es 1 toque.

### ADR-011: IA último recurso, multi-proveedor, clave del usuario solo en dispositivo — **Fecha:** spec DC-5/DC-13; M6 (`f219105`,`1ae340b`). Presets del genérico OpenAI-compatible para cubrir 7 proveedores sin duplicar.

### ADR-012: Acceso de invitados por prueba de conocimiento (guestAccess)
**Estado:** Aceptada · **Fecha:** M3 (`84726bd`)
**Problema:** las reglas no pueden validar un secreto en LECTURAS.
**Alternativas:** custom claims vía function (más funciones, más latencia) — rechazada; sesión legible por cualquier autenticado (inaceptable) — rechazada.
**Decisión:** el invitado crea `guestAccess/{uid}` presentando el shareCode (la regla lo compara); las lecturas usan `exists()`. Revocación = rotar código + borrar guestAccess.
**Consecuencias:** + validable y testeable por reglas; − 1 get() extra por evaluación (dedupe del motor de reglas lo amortigua).

### ADR-013: IDs deterministas para liquidaciones (`pending_{from}_{to}`)
**Estado:** Aceptada (reemplaza el diseño de M3 con auto-IDs) · **Fecha:** 2026-07-14 (commit `d5e6d55`, bug E1)
**Contexto:** en producción, un ticket de N líneas dispara N recomputes concurrentes; con auto-IDs cada ejecución creaba su propia liquidación → duplicados reales observados en logs.
**Alternativas:** transacción global de recompute (cara y compleja) — rechazada; lock distribuido (complejidad sin garantías) — rechazada.
**Decisión:** un objetivo = un ID determinista; `set()` idempotente; lo no-confirmado que no coincide con un objetivo se purga; `marked` se preserva si el importe no cambió.
**Consecuencias:** + convergencia bajo cualquier concurrencia, auto-sanado de duplicados legacy; − máximo una liquidación pendiente por par ordenado (correcto por construcción del voraz).
**Revisión:** si el algoritmo generara >1 transferencia por par (no puede).

### ADR-014: Rutas anidadas bajo /home — **Fecha:** 2026-07-14 (`d5e6d55`, bug E2). `go()` construye la pila completa; nunca una pantalla sin atrás.

### ADR-015: recompute también escucha settlements — **Fecha:** 2026-07-14 (`d5e6d55`). Confirmar/marcar actualiza agregados; converge porque solo escribe si algo cambia.

### ADR-016: La config de cliente de Firebase se commitea
**Estado:** Aceptada (matiza la spec §7-secretos) · **Fecha:** 2026-07-13 (`5e28df4`)
**Problema:** la CI y cualquier clon necesitan compilar; las "keys" de cliente Firebase son identificadores públicos, no secretos (la seguridad la dan reglas + App Check).
**Decisión:** `firebase_options.dart` y `.env.production` de la web van al repo; los secretos reales (ninguno en cliente) siguen prohibidos.
**Consecuencias:** inconsistencia documental con spec §7 → registrada en [Inconsistencias](#inconsistencias).

### ADR-017: El owner puede crear/borrar liquidaciones — **Fecha:** M5-b (`87b7e74`). Necesario para importar backups (RF-91); no rompe invariantes: el owner ya podía forzar estados y recompute regenera lo que no cuadre.

### ADR-018: Pins exactos del stack FlutterFire — **Fecha:** 2026-07-14 (`d5e6d55`, bug E5). Conjunto alineado conocido-bueno con el motivo en el pubspec; despinear solo verificando (DT-14).

### ADR-019: Orden determinista de participantes por campo `order` — **Fecha:** M3. El desempate de los motores debe ser idéntico en app y function; `order` es el índice de inserción y NO debe reutilizarse ni reordenarse.

### ADR-020: Foto del ticket best-effort — **Fecha:** 2026-07-14 (`d5e6d55`). La subida jamás bloquea el flujo de creación; sin red = grupo creado sin foto.

### ADR-021: En "cada uno paga lo suyo", lo no reclamado recae en el pagador
**Estado:** Aceptada (reemplaza el uso de `splitAmongAll` en recompute) · **Fecha:** 2026-07-14
**Contexto/Problema:** en la primera prueba real, seleccionar productos daba importes tipo "1/N de lo que nadie ha cogido + lo tuyo" (una "media previa"). Causa raíz: `recompute` invocaba el motor con `unassignedPolicy: 'splitAmongAll'`, repartiendo las líneas AÚN no seleccionadas entre todos en cada recálculo continuo (la spec RF-46 solo preveía repartir huérfanas entre todos AL FINALIZAR y CON CONFIRMACIÓN, no en vivo).
**Alternativas:** (a) huérfanas → nadie (pending): rompe el invariante Σ consumo == grandTotal del BalanceEngine, más invasivo — rechazada; (b) mantener splitAmongAll: es el bug — rechazada.
**Decisión:** las líneas sin consumidores se atribuyen al **pagador del ticket** (neto cero para él en esa parte: la pagó y la "consume"); a medida que la gente reclama, la parte del pagador se reduce hasta quedar solo lo suyo. La conversión vive en `recompute.sanitizeLine` (que conoce al pagador); el motor puro NO cambia (paridad y vectores dorados intactos) y se le pasa `unassignedPolicy: 'error'` como red de seguridad. `splitAmongAll` sigue siendo una capacidad pura del motor (tested) reservada al futuro "finalizar y repartir sobrantes con confirmación" (RF-46), pero NUNCA se usa en el cálculo continuo.
**Consecuencias:** + fin de la media previa; Σ==grandTotal siempre; redondeo único preservado (ADR-007); + tests de regresión que blindan el caso exacto reportado y los límites (compartir 2/3/4, dejar de compartir, IVA/descuentos, tickets grandes, múltiples grupos). − el pagador ve una parte alta mientras el grupo no ha reclamado sus productos (correcto y transitorio; la UI puede indicarlo).
**Revisión futura:** si se implementa el "finalizar ticket" explícito (RF-46), decidir allí si los sobrantes se dejan al pagador o se reparten con confirmación.

### ADR-022: Progreso sobre obligaciones y separación histórico/actual
**Estado:** Aceptada · **Fecha:** 2026-07-15 (P0.3)
**Contexto/Problema:** la UI mostraba `net` incluso después de confirmar todos los
pagos y calculaba `settledConfirmed / grandTotal`. Las liquidaciones son transferencias
netas, por lo que su suma no coincide con el gasto y una cuenta saldada podía no llegar
al 100 %.
**Decisión:** `recompute` publica `settlementRequired = Σ confirmadas + Σ obligaciones
residuales actuales`. El progreso confirmado es `settledConfirmed /
settlementRequired`; si ambos son cero se define como 100 % porque no hacen falta
transferencias. `settledMarked` forma un tramo ámbar pero no cuenta como confirmado.
La vista principal usa `outstanding`; `paid/consumed/net` y las confirmadas permanecen
en un bloque histórico separado.
**Consecuencias:** confirmar mueve importe de residual a confirmado sin cambiar el
denominador; añadir gastos aumenta solo el residual nuevo; las congeladas permanecen;
varios pagadores y redondeos heredan la exactitud del motor. Se añade un campo opcional
al agregado raíz, sin migrar colecciones ni modificar los motores congelados.
**Revisión:** solo si cambia el modelo de estados de liquidación.

### ADR-023: Identidad por capacidades y conversión conservando UID
**Estado:** Aceptada · **Fecha:** 2026-07-16 (P1)
**Contexto:** `request.auth != null` trataba igual una cuenta verificada, una
cuenta de correo pendiente y un invitado anónimo. Crear otra cuenta al abandonar
el modo invitado también separaría sus sesiones del propietario original.
**Decisión:** invitado anónimo y cuenta verificada pueden usar el núcleo económico;
solo la cuenta verificada accede a `users/**`. Una cuenta email pendiente conserva
lectura de sesiones por UID, pero no escribe. La conversión usa
`linkWithCredential`, conserva UID y nunca fusiona ni cambia de cuenta de forma
silenciosa. Repositorios, borradores y secretos IA quedan aislados por UID.
**Consecuencias:** las cuentas email históricas no pierden sesiones, pero deben
verificar antes de editar; el invitado se puede proteger sin migración; perfiles,
amigos, grupos permanentes y chat podrán exigir `isFullAccount` sin usar el perfil
como fuente de autorización. App Check mantiene un rollout monitor-first para no
romper móvil o web antes de instrumentar ambos clientes.

### ADR-024: Identidad pública con claims de username y perfil separado del privado
**Estado:** Aceptada · **Fecha:** 2026-07-17 (P2)
**Contexto:** las funciones sociales futuras (búsqueda, amigos, espacios
compartidos) necesitan una identidad pública, pero `users/{uid}` es privado por
diseño (métodos de pago, política de IA) y Firestore no ofrece unicidad nativa
de campos.
**Decisión:** [HECHO] colección nueva `profiles/{uid}` pública (lectura para
cualquier autenticado, escritura solo del dueño verificado) con displayName,
displayNameLower, username, photoPath (preparado), createdAt/updatedAt y
schemaVersion; y `usernames/{username}` como claim de unicidad cuyo docId es el
username canónico en minúsculas (case-insensitive POR CONSTRUCCIÓN). Perfil y
claim se escriben en el mismo batch y las reglas exigen consistencia con
`getAfter()`: no puede existir perfil sin claim ni claim no referenciado.
Validación y propuestas naturales (edgar → edgar27 → edgar_cantera) viven en
`packages/domain/src/identity/` (puro, reutilizable por la web); la lista de
reservados se duplica conscientemente en las reglas. El avatar (iniciales +
color de `avatarPalette` por FNV-1a del uid) se DERIVA, nunca se almacena. La
búsqueda son dos queries de prefijo (`username`, `displayNameLower`) de campo
único: índices automáticos, cero composites. Las reglas rechazan campos aún sin
fase (`hasOnly`), de modo que bio/estadísticas llegarán como cambio de reglas
explícito, no silencioso.
**Consecuencias:** los invitados anónimos no tienen perfil (coherente con
ADR-023); el banner de Home cubre alta por email, Google y conversiones sin
acoplar el router a Firestore; el uid sigue siendo la clave de todo (espacios
compartidos y relaciones económicas futuras referenciarán uids, y la
trazabilidad balance→espacio→ticket→línea no depende del username, que es
editable). Renombrar el username no toca ningún dato económico.
**Revisión:** si la búsqueda por prefijo se queda corta (typos, contains),
evaluar un índice invertido propio antes que un servicio externo.

### ADR-025: Unidades reclamables, selección del creador y confirmación del receptor
**Estado:** Aceptada · **Fecha:** 2026-07-17 (P2.1)
**Contexto:** (1) seleccionar una línea "2 × flauta" cobraba las DOS unidades
al seleccionador; (2) el creador no podía declarar su propio consumo (todo lo
suyo era residual implícito); (3) confirmar la recepción de un pago era del
owner por ser creador, aunque el dinero lo recibiera otra persona.
**Decisión:** [HECHO]
- El peso de `assignment.participants` pasa a significar UNIDADES reclamadas.
  `SplitLine.units` deriva de `quantityMilli` (solo múltiplos enteros ≥ 2; los
  artículos a peso siguen siendo 1). Si Σ pesos < unidades, el motor añade el
  resto al PAGADOR (extensión natural de ADR-021); si Σ pesos ≥ unidades, el
  reparto es proporcional puro — compartir sigue funcionando EXACTAMENTE igual
  (pizza entre 3 = tercios). Sin `payerId` el motor conserva el comportamiento
  histórico (vector dorado "legacy"). 8 vectores dorados nuevos ejecutados por
  Dart y TS.
- El creador selecciona como cualquier invitado: líneas vivas en el detalle
  del ticket (toggle / stepper de unidades), misma forma de escritura que la
  web (`assignment` con `lastEditorPid`). El residual sigue calculándose tras
  las selecciones explícitas y recae en el pagador: explícito y residual no
  pueden duplicarse porque son pesos de la MISMA línea.
- Confirmar (o des-confirmar) una liquidación es EXCLUSIVO del receptor: regla
  `isReceiver` = dispositivo que reclamó el participante `to`; si nadie lo
  reclamó, el owner actúa como representante (un nombre sin dispositivo no
  tiene uid: sin ese proxy nadie podría confirmar jamás). Un nombre reclamado
  EXCLUYE al owner. El owner conserva la gestión organizativa pending↔marked
  y el alta/borrado por import de backup (ADR-017). La web muestra "He
  recibido el dinero" al receptor de una liquidación `marked`.
**Consecuencias:** los tickets antiguos no migran nada (mismo esquema; una
línea multi-unidad seleccionada entera ahora reparte el resto al pagador, que
es la semántica correcta que faltaba); la web de invitados sigue sin calcular
dinero; el caso Alba/Pedro (pago confirmado congelado + reasignación
posterior) queda blindado con test de regresión en recompute.
**Revisión:** la semántica de pesos para líneas multi-unidad queda
**superada por ADR-026** para documentos nuevos. Se conserva únicamente como
lector compatible de P2.1 para no cambiar balances históricos.

### ADR-026: Unidades físicas independientes con esquema aditivo
**Estado:** Aceptada · **Fecha:** 2026-07-17 (P2.2)
**Contexto:** P2.1 aplicaba una suma de pesos al total de línea. En 2 flautas,
Edgar con peso 2 y Alba con peso 1 producía 2/3 y 1/3, aunque el caso real era
una flauta exclusiva de Edgar y otra compartida. Los pesos no contienen la
identidad de la unidad y no permiten reconstruir ese hecho sin ambigüedad.
**Decisión:** [HECHO] extensión opcional por línea `assignment.type: units`,
`schemaVersion: 2`, `unitIds: [u0…]` y `units.{unitId}.{pid}: true`. Cada
unidad se divide solo entre sus consumidores; una unidad vacía es residual del
pagador real. Los clientes escriben la pertenencia por ruta punteada para que
ediciones concurrentes de pids distintos converjan sin sobrescritura. Rules
limita al invitado a su pid y a una unidad declarada. Solo cantidades enteras
discretas ≥2 se descomponen; peso/volumen/decimales siguen siendo una línea.
El dinero se reparte primero entre unidades y luego dentro de cada unidad con
`allocateProportionally`; los empates siguen `participant.order`, idéntico en
Dart y TypeScript. El caso 2 × 2,09 € queda 3,14 €/1,04 € por ese desempate.
**Compatibilidad:** la ausencia de la pareja exacta `type: units` +
`schemaVersion: 2` conserva el algoritmo histórico/P2.1. La conversión solo es
explícita al editar y parte vacía: nunca adivina unidades ni reinterpreta
balances confirmados. Es una ampliación de campos, sin migración destructiva.
**Consecuencias:** el modelo representa unidades exclusivas, compartidas por
grupos distintos, residuales y cantidades grandes con UX compacta; recompute
sigue siendo autoritativo y los vectores dorados compartidos garantizan suma
exacta y paridad. Contrato detallado en `docs/REPARTO_POR_UNIDADES.md`.
**Revisión:** si una futura importación ofrece identificadores de lote/unidad
reales, mapearlos a los ids estables existentes sin cambiar el motor.

### ADR-027: Una relación social canónica por pareja de UID
**Estado:** Aceptada · **Fecha:** 2026-07-18 (P3)
**Contexto:** solicitudes separadas de una amistad final o documentos duplicados
por usuario facilitan estados cruzados, requieren sincronización y permiten crear
dos relaciones A↔B. Username y displayName son mutables y no son identidad.
**Decisión:** [HECHO] una única fuente de verdad
`friendships/{canonicalFriendshipId(uidA, uidB)}` con `memberUids` ordenados,
roles requester/receiver, estado `pending|friends`, timestamps y
`schemaVersion: 1`. El ID es la codificación hexadecimal de una serialización
UTF-8 prefijada por longitudes; cliente y Rules la recalculan. Todas las
mutaciones usan transacciones idempotentes. Una solicitud inversa acepta la
pendiente existente; el receptor acepta/rechaza, el emisor cancela y cualquiera
de los miembros elimina una amistad. La única query usa `arrayContains` sobre
`memberUids`; perfiles y usernames se resuelven en tiempo real sin snapshots.
**Seguridad:** solo cuentas no anónimas, verificadas y con perfil público pueden
actuar. Rules valida ID, pareja, roles, campos, timestamps, transición e
inmutabilidad; terceros no leen ni escriben. No se confía en la UI.
**Consecuencias:** unicidad y simetría sin denormalización mutable ni índice
compuesto. Eliminar el vínculo no borra ni modifica sesiones, participantes,
tickets, balances o pagos. Grupos permanentes, chat, actividad y notificaciones
siguen fuera. Contrato detallado en `docs/AMISTADES.md`.
**Revisión:** cuando se implemente la eliminación definitiva de cuentas, añadir
limpieza autoritativa de relaciones canónicas sin tocar el historial económico.

### ADR-028: Espacios compartidos con propietario en un solo campo
**Estado:** Aceptada · **Fecha:** 2026-07-18 (P4)
**Contexto:** hace falta un contenedor social para organizar tickets entre
varias personas (pareja, piso, viaje, peña) con UN único modelo, sin duplicar
sistemas para relaciones de dos y sin acoplar membresía, amistad,
participación en tickets ni deuda.
**Decisión:** [HECHO] `spaces/{id}` (name, avatarEmoji?, ownerUid, status
active|archived, timestamps, schemaVersion) + `members/{uid}` ({uid,
joinedAt}) + `spaceInvites/{spaceId}_{toUid}` con ID determinista y estados
pending|accepted|rejected|cancelled. **El rol no se persiste**: el
propietario único es `ownerUid` y "miembro" es tener doc de membresía —
transferir es actualizar UN documento (atómico por definición, a miembro
activo validado por Rules); un rol persistido exigiría batches multi-doc
imposibles de validar (get() sobre docs del propio batch falla en Rules).
Aceptar invitación une y resuelve en el mismo batch (getAfter); cancelada no
se puede aceptar; reenvío reutiliza el doc. El owner no sale sin transferir
o archivar; archivar es la única baja (sin borrados destructivos). Tickets:
`spaceId` opcional en el doc del ticket (máx. un espacio, compatibilidad
total con tickets antiguos); los miembros leen el RESUMEN vía collection
group en tiempo real; líneas/foto/sesión siguen siendo privadas de quien ya
tiene acceso; vincula solo el dueño de la sesión si es miembro del espacio.
Dos fieldOverrides de collection group (members.uid, tickets.spaceId).
**Consecuencias:** todo por UID (renombrar username no toca nada); eliminar
amistad no expulsa de espacios ni viceversa; salir/expulsar borra solo la
membresía y jamás datos económicos; P4 no calcula dinero — los balances
consolidados por espacio serán un cambio de recompute en su propia fase.
Contrato en `docs/ESPACIOS.md`.
**Revisión:** al llegar los balances consolidados, decidir si el espacio
referencia sesiones completas además de tickets sueltos.

### ADR-029: Obligaciones derivadas y pagos bilaterales autoritativos
**Estado:** Aceptada · **Fecha:** 2026-07-19 (P5)
**Contexto:** los balances internos de una sesión usan participantes locales y
simplificación multilateral. Un usuario registrado necesita una vista global
por UID que sobreviva a cambios sociales y explique cada cifra sin crear otra
verdad económica ni reescribir tickets al pagar.
**Decisión:** [HECHO] `recompute` materializa `economicEntries` por ticket,
pareja de UID y moneda desde el resultado final de SplitEngine. Es una vista
reconstruible, con id determinista y escritura exclusiva Admin. `EconomicLedger`
(Dart + espejo TypeScript + golden común) conserva deuda bruta en ambos sentidos,
resta únicamente pagos confirmados y produce neteo bilateral, nunca multilateral.
Los pagos humanos viven en `economicPayments`: creación y resolución mediante
callables transaccionales, idempotencia, reserva de pendientes, pago parcial,
asignación determinista a tickets y confirmación exclusiva del receptor. Un
trigger congela el pago confirmado en las sesiones afectadas para que la UI
legacy y P5 no permitan doble pago. Rules deja ambos roots en solo lectura para
los UID participantes y exige cuenta completa; un owner de espacio no obtiene
privilegios económicos.
**Consecuencias:** amistad, username, membresía y deuda quedan desacoplados;
salir o ser expulsado conserva historial. Las monedas se muestran por separado.
Las proyecciones pueden repararse desde tickets y eventos, a costa de lecturas
adicionales en recompute y dos callables dentro del techo global existente.
Contrato detallado en `docs/RELACIONES_ECONOMICAS.md`.
**Revisión:** medir coste/latencia antes de añadir índices o materializar un
documento de saldo por usuario; P5 calcula esa vista en el cliente.

### ADR-030: Relaciones y grupos como raíz visible del producto
**Estado:** Aceptada · **Fecha:** 2026-07-22
**Contexto:** la navegación centrada en sesiones/tickets obligaba a crear el
gasto antes de declarar con quién se compartía. P4 ya aporta un contenedor por
UID y P5 deriva dinero por ticket, por lo que crear otro modelo duplicaría
estado social y económico.
**Decisión:** [HECHO] `spaces` se reutiliza como contexto único. `kind` distingue
`relationship` (pareja canónica e inmutable de UID) de `group`; los P4 sin campo
se leen como grupo. Inicio muestra ambos e invitaciones, y el escaneo solo nace
dentro de su detalle. Sesión y ticket nuevos comparten `spaceId` y
`contextModelVersion: 1`; sus miembros registrados reclaman los participantes
por UID. Las sesiones anteriores no se clasifican ni migran automáticamente:
quedan en «Histórico sin organizar» con vinculación manual explícita.
**Consecuencias:** una relación no admite tercer miembro; un grupo necesita tres
miembros para crear gastos; un ticket contextual no se desvincula. P5 conserva
fuente de verdad, neteo, liquidaciones, permisos y trazabilidad sin cambios. La
amistad continúa siendo independiente. P6/P7 no forman parte de esta decisión.
Contrato detallado en `docs/ESPACIOS.md`.
**Revisión:** antes de permitir invitados no registrados dentro de un grupo,
definir cómo se representa su identidad sin degradar el vínculo por UID.

### ADR-031: Actividad como proyección de auditoría con IDs deterministas
**Estado:** Aceptada · **Fecha:** 2026-07-20 (P6)
**Contexto:** el usuario necesita una cronología (quién hizo qué, cuándo, y
llegar al objeto) sin convertirla en chat, sin duplicar el modelo económico y
sin que un cliente pueda fabricar eventos a nombre de otro.
**Decisión:** [HECHO] colección `activityEvents/{id}` escrita SOLO por
triggers Admin (`activity.ts`): espacios (crear/editar/archivar/reactivar/
transferir con actor = owner, transferencia = owner anterior), membresías
(unirse; salida vs EXPULSIÓN distinguidas por el marcador `removedBy` que el
owner escribe antes del borrado y Rules valida), invitación enviada, tickets
(creado/borrado/vinculado/desvinculado y edición RELEVANTE: comercio, total,
fecha, pagador — una edición atómica = un evento; líneas y asignaciones son
ruido técnico sin evento), settlements humanos marked/confirmed (pending es
sugerencia del motor y jamás emite) y pagos P5 `source:user` (actor del
stateHistory; las proyecciones legacy no emiten: el mismo hecho nunca se
duplica entre sistemas). IDs deterministas por hecho + escritura
`create()`-only: reintentos de trigger, offline repetido y recompute
convergen en el mismo documento conservando su hora. Audiencia `memberUids`
CONGELADA al momento (máx. 30): un miembro nuevo no hereda actividad, un
expulsado conserva sus hechos, el owner no gana visibilidad económica.
Nombres de personas SIEMPRE en vivo por UID (sin snapshots); solo se congela
el rótulo del objeto. Queries con array-contains del propio uid (regla
demostrable) + dos índices compuestos; paginación por fecha con primera
página en stream. Sin retro-generación de P1–P5 (no se fabrican fechas ni
actores no demostrables). Contrato en `docs/ACTIVIDAD.md`.
**Consecuencias:** el feed es borrable y reconstruible parcialmente sin
tocar la verdad; P7 (chat) podrá convivir sin reusar esta colección; si los
espacios crecieran más allá de ~30 miembros habría que migrar a fan-out.
**Revisión:** al implementar notificaciones push completas, decidir si se
alimentan de estos mismos eventos.

### ADR-032: Chat contextual privado por membresía y fecha de alta
**Estado:** Aceptada · **Fecha:** 2026-07-23 (P7)
**Contexto:** Relaciones y Grupos necesitan coordinación dentro del contexto,
pero reutilizar actividad permitiría escrituras de cliente en una proyección
Admin y mezclaría conversación con auditoría. Congelar la audiencia de cada
mensaje exigiría una Function o confiar en listas aportadas por el cliente.
**Decisión:** [HECHO] subcolección aditiva
`spaces/{spaceId}/messages/{messageId}`, texto inmutable y autor por UID. Solo
cuentas completas que sigan siendo miembros leen, siempre con
`createdAt >= members/{uid}.joinedAt`: un miembro nuevo no hereda conversación
anterior y quien sale pierde acceso. Miembros de espacios activos envían y
borran únicamente mensajes propios; archivados quedan en solo lectura. Rules
valida forma, autor, longitud, versión y timestamp de servidor. Primera página
en vivo, historial bajo demanda, sin Function ni índice compuesto nuevo.
**Consecuencias:** el owner no modera mensajes ajenos; chat no genera
`activityEvents`, no altera P5 y no entra en `appcuentas-backup@1`. Sin
adjuntos, edición, reacciones, recibos, no leídos, push ni invitados web.
Contrato detallado en `docs/CHAT.md`.
**Revisión:** si se añaden adjuntos o notificaciones, diseñarlos como extensiones
independientes y revisar coste, retención y moderación antes de implementarlos.

### ADR-033: Participantes manuales como actores económicos de primera clase
**Estado:** Aceptada · **Fecha:** 2026-07-25
**Contexto:** solo podían participar personas con cuenta, pero la mayoría de
gastos reales incluye a alguien que no usa la app. Necesitábamos que pese
económicamente igual sin inventarle una cuenta, y sin cerrar la puerta a que
mañana reclame su identidad conservando el historial.
**Decisión:** [HECHO] `spaces/{id}/manualParticipants/{manualId}` con nombre
editable, `createdByUid` y `linkedUid: null` reservado; el participante de
sesión guarda `manualId` (identidad) además del `claimedByDevice` existente.
Toda obligación P5 pasa a expresarse entre ACTORES: el UID para una cuenta y
`manual:{manualId}` para quien no la tiene. Como los UID de Firebase nunca
contienen ':', el prefijo no colisiona y **no hace falta migrar ningún
documento**: un valor sin prefijo es una cuenta por definición. `memberUids`
sigue siendo solo UID reales (es lo que autorizan Rules y las queries
array-contains): cuenta↔manual tiene un lector, manual↔manual no se publica
en la economía global y se queda en el balance de su sesión. El id es opaco
y estable, nunca el nombre: renombrar no toca obligaciones y retirar a la
persona no borra su historial.
**Consecuencias:** el reparto, los balances y las liquidaciones de sesión
funcionan igual para ambos tipos; los pagos P5 siguen exigiendo dos cuentas
(saldar con un manual se hace por el flujo de sesión, que ya admite
participantes sin dispositivo). Invitados, enlaces y reclamación de identidad
siguen fuera.
**[DECISIÓN PENDIENTE] Vinculación con una cuenta — FUERA del alcance de
este sprint.** El actor `manual:{manualId}` debe permanecer ESTABLE: es la
clave con la que están escritas las obligaciones ya derivadas. La futura fase
deberá elegir explícitamente entre (a) **migración de referencias**,
reescribiendo el actor en cada documento histórico —homogéneo pero masivo, no
atómico entre colecciones, difícil de revertir e incompatible con los ids
deterministas ya calculados—, o (b) **resolución mediante alias**,
conservando el actor histórico y aplicando una equivalencia
`manual:{manualId} → uid` al leer y consolidar —sin tocar documentos,
reversible y demostrable—. **Opción preferente: alias**, salvo evidencia
técnica que justifique lo contrario (coste de lectura o complejidad de
consulta inasumibles). `linkedUid` **NO resuelve por sí solo** la
vinculación: es solo un marcador de intención; no reescribe obligaciones, no
las consolida al leer ni impide duplicidades.
**Duplicidad a evitar:** ningún contexto puede tener a la misma persona
activa a la vez como actor manual y como UID —sea el UID de una cuenta o el
de un INVITADO (ADR-034), que también tiene el suyo—. El mecanismo deberá
cubrir: vinculación e incorporación como miembro **atómicas**; la identidad
manual deja de ser seleccionable en repartos nuevos una vez vinculada; Rules
exige que un participante declare exactamente una identidad (invariante ya
vigente); consolidación de ambas vertientes en el balance bilateral al leer;
y decisión sobre qué hacer si la cuenta ya tenía obligaciones propias en ese
mismo contexto (fusión frente a coexistencia histórica).
**Revisión:** en el **Sprint 6 (vinculación de identidad)**, resolver la
decisión anterior —cubriendo manual↔cuenta y manual↔invitado con el mismo
mecanismo— y registrarla en un ADR propio antes de escribir código.

### ADR-034: Invitado como participante sin cuenta con identidad de dispositivo
**Estado:** Aceptada · **Fecha:** 2026-07-25
**Contexto:** entre la cuenta completa y el participante manual faltaba quien
USA la app pero no quiere registrarse. Necesitaba identidad propia y estable
—para que su historial económico sea suyo— sin abrirle la puerta a gobernar
contextos ni a tener presencia pública.
**Decisión:** [HECHO] el invitado es la sesión ANÓNIMA de Firebase Auth (que
el SDK persiste en el dispositivo y sobrevive a reinicios) más
`guestIdentities/{uid}` con el nombre visible que él elige. NO es un perfil
público: sin username, sin búsqueda y con `list` denegado en Rules; solo se
lee conociendo el UID, y su nombre viaja además como snapshot en la
membresía (`kind: guest`, `displayName`) porque no hay perfil del que leerlo
en vivo. Rules separa dos predicados: `canParticipate()` = cuenta **o**
invitado, para participar (leer el contexto y sus miembros, recibir y aceptar
invitaciones, ver balances y cronología propios); y `canUseSocial()` = solo
cuenta, para todo lo que crea o gobierna (crear contextos, invitar,
administrar, transferir, archivar, perfil y amistades). Los gastos del
invitado dependen de `spaces/{id}.guestsCanCreateExpenses`, que solo fija el
propietario y cuya ausencia equivale a `false`. El anfitrión puede invitar a
un invitado porque la regla acepta como destino un perfil público **o** una
identidad de invitado.
**Consecuencias:** el invitado **participa económicamente igual que una
cuenta porque dispone de UID propio** — para ADR-033 es un actor de cuenta
(sin prefijo `manual:`) y encaja en P5 sin cambios ni casos especiales. El
**nombre visible es solo un atributo de presentación**: cambiarlo NO afecta a
la identidad económica ni a obligaciones, balances o historial. Un anónimo
SIN identidad de invitado no participa en nada (sigue siendo el invitado web
de sesión de P1, mecanismo intacto).
**[FUERA DE ALCANCE] Incorporación mediante enlaces.** Hoy el anfitrión solo
invita a un invitado si conoce su UID, porque por diseño no es buscable. **El
flujo de invitación actual NO es el definitivo**: es el mínimo para validar
el modelo. **El Sprint 4 (Enlaces) resolverá la incorporación** y decidirá el
canal por el que el anfitrión alcanza a un invitado sin exponer identidades
ni hacerlo buscable.
**[DECISIÓN PENDIENTE — Sprint 6] Consolidación con MANUAL.** Nada impide
todavía que la misma persona esté en un contexto a la vez como participante
manual y como invitado con UID: serían dos actores y el saldo aparecería
partido. Se resolverá en el Sprint 6 (vinculación de identidad) con el MISMO
mecanismo que la vinculación manual↔cuenta de ADR-033, porque es el mismo
problema. Este ADR **no prejuzga** la elección entre migración de referencias
y resolución mediante alias, que sigue abierta en ADR-033.
**Revisión:** al cerrar el Sprint 4, comprobar que el canal de incorporación
elegido no convierte la identidad de invitado en buscable.

### ADR-035: Enlace de grupo como token opaco con prueba de conocimiento
**Estado:** Aceptada · **Fecha:** 2026-07-25 (Sprint 4)
**Contexto:** incorporar gente exigía conocer su UID y buscarla, y a un
INVITADO (ADR-034) sencillamente no se le podía alcanzar: por diseño no es
buscable. ADR-034 dejó abierto el canal y pidió que, al resolverlo, no
convirtiera la identidad de invitado en buscable ni expusiera identidades.
**Alternativas descartadas:** (a) **reutilizar `spaceInvites`** — imposible:
su ID determinista `{spaceId}_{toUid}` exige saber a quién invitas, que es
justo lo que falta. (b) **Solicitud de acceso con aprobación del propietario**
— convierte "unirse" en un trámite asíncrono que contradice el principio
rector y deja al que llega esperando. (c) **Cloud Function `redeemGroupLink`
callable** — resolvería el canje en servidor, pero añade una función nueva
contra el techo de coste (§62), rompe la norma de que las functions solo se
disparan por triggers de Firestore (CLAUDE.md §7) y no aporta nada que Rules
no pueda demostrar: la checklist §58 obliga a preguntarse antes si basta con
cliente + reglas. Aquí basta.
**Decisión:** [HECHO] colección `spaceLinks/{token}` en la que el
IDENTIFICADOR del documento ES el secreto (128 bits vía `ShareCode`, la misma
primitiva del enlace de invitados). Conocerlo es la autorización, igual que
ADR-012. `get` queda abierto a cualquier sesión que acierte el token —para
previsualizar el nombre del grupo sin ser miembro— y `list` reservado al
propietario ACTUAL: un enlace nunca es enumerable. El documento **no contiene
identidades**: solo a qué grupo abre y cómo se llama.
El canje escribe en UN batch la prueba de conocimiento
`spaces/{id}/joinGrants/{uid}` (con el token) y la membresía, y Rules valida
la segunda contra la primera con `existsAfter`, el mismo patrón que aceptar
una invitación. La prueba es de **solo escritura** —no la lee nadie, ni el
propietario— para que el token no se filtre a los demás miembros: si viviera
en la membresía, cualquier miembro podría reenviar el enlace y saltarse la
política de que solo el propietario incorpora gente. La membresía
**revalida el enlace en cada canje**, así que revocar cierra la puerta al
instante aunque quede una prueba antigua.
Solo GRUPOS activos (una relación reserva una pareja inmutable de UID y no
admite un tercero) y solo el propietario crea, rota o revoca; rotar emite un
token nuevo y deja el viejo demostrablemente muerto. Cuenta e invitado entran
por el mismo camino; MANUAL no aplica (no tiene dispositivo).
**Caducidad OPCIONAL** (`expiresAt`): un enlace es un secreto portador, así
que poder acotarle la vida limita el daño de una filtración. Ausente = sin
caducidad, que es el valor por defecto. No puede nacer caducado (enmascararía
un reloj mal puesto en cliente) y es INMUTABLE: alargarla resucitaría un
enlace que ya circula, así que para cambiarla se rota. Caducado ≠ revocado,
pero cierran igual porque ambas se comprueban en cada canje.
**A quien ya tiene identidad NO se le pregunta quién es.** Con cuenta —o con
identidad de invitado, que persiste en el dispositivo— el enlace entra solo y
aterriza en el grupo: sin pantalla intermedia ni botón de confirmar, porque
la identidad ya se conoce y preguntar sería fricción pura. El selector de
identidad queda reservado a los participantes MANUAL de los enlaces de TICKET
(Sprint 5), donde sí hay algo que elegir. Solo se pide algo a quien no tiene
identidad: continuar como invitado (que únicamente necesita un nombre
visible), entrar con su cuenta o crear una. El token pendiente vive en
`pendingGroupLinkProvider` y lo consume el router, de modo que identificarse
—incluido verificar el correo tras registrarse— **nunca pierde el enlace**;
por eso la pantalla del enlace se mantiene en pie para cualquier sesión, aun
sin verificar. Volver a pulsar un enlace del que ya se es miembro lleva al
grupo en vez de dar error.
**Consecuencias:** entrar por enlace es la vía natural del invitado, y por
eso este ADR **corrige un vacío de ADR-034**: la app pintaba
`_AccountRequiredHome` a todo el que no tuviera cuenta y la query de "mis
contextos" exigía `canUseSocial()`, de modo que un invitado podía ser miembro
en datos pero no tenía pantalla desde la que llegar al grupo. Ahora participa
de verdad: ve sus contextos y sus invitaciones, y también a los participantes
MANUAL con los que reparte. Crear contextos sigue siendo exclusivo de una
cuenta. Quien conserve un enlace vivo puede volver a entrar tras ser
expulsado —igual que en cualquier grupo de mensajería—: para cerrar de verdad
hay que rotar o revocar, y así está documentado en la UI.
`AndroidManifest.xml` declara el intent-filter `autoVerify` de
`https://{salda-dev|salda-prod}.web.app/g/` y el Hosting de `salda-dev` sirve
`/.well-known/assetlinks.json` con el paquete `dev.salda.salda_mobile` y el
SHA-256 del certificado (comprobado con la API de Digital Asset Links de
Google, que es lo que consulta Android). Dos ajustes de `firebase.json` lo
sostienen: `ignore` ya no excluye `**/.*` —ese patrón dejaba fuera del
despliegue la carpeta `.well-known` entera— y `appAssociation: "NONE"` impide
que Hosting genere el archivo por su cuenta. Mientras `buildTypes.release`
siga firmando con la config de debug, un único fingerprint cubre las tres
variantes; **al crear una clave de release habrá que añadir su SHA-256**.
**Pendiente (no es código de app):** servir `/g/{token}` como página de
aterrizaje para quien no tenga la app. Contrato en `docs/ESPACIOS.md`.
**Revisión:** al implementar los enlaces de TICKET (Sprint 5), reutilizar
este mecanismo en vez de inventar otro; y en el Sprint 6 tener presente que
un MANUAL y un INVITADO que sean la misma persona siguen siendo dos actores
distintos — entrar por enlace no lo empeora, pero tampoco lo resuelve.

---

<a name="parte-x"></a>
# PARTE X — REFERENCIA Y CONTINUIDAD

## §56. Glosario

**Relación/Grupo** contexto social raíz (código: `Space`) · **Sesión** contenedor
económico interno de uno o varios tickets · **Cuenta** agrupador
de tickets dentro del grupo · **Ticket** gasto escaneado o manual con pagador ·
**Línea** producto con asignación · **Asignación** unassigned|one|shared|all con
pesos · **quantityMilli** cantidad ×1000 (0,466 kg → 466) · **Balance** neto por
participante (derivado) · **Liquidación/Settlement** transferencia sugerida con
estado humano · **Congelada** liquidación confirmada que recompute no toca ·
**shareCode** secreto 128-bit del enlace (viaja en `#k=`) · **guestAccess**
prueba de conocimiento del invitado · **claim** vínculo participante↔dispositivo ·
**Vectores dorados** json de casos compartidos Dart/TS · **Corpus** tickets de
regresión del parser · **mustPass** contrato de un caso de corpus ·
**needsReview** issues≠∅ o confianza <0,75 · **recompute** función autoritativa ·
**computeVersion** contador de recálculos · **Draft** borrador persistente de
revisión · **ARB** archivos de i18n de Flutter.

## §57. Convenciones

Ver CLAUDE.md §4 (normativa). Esencia: código/identificadores en inglés, UI en
español vía ARB; comentarios explican el PORQUÉ; commits en español imperativo
con prefijo (`M5:`, `fix(mvp):`, `docs:`) y coautoría de Claude; feature-first
`features/<x>/{domain,data,application,presentation}`; análisis a cero avisos
(`--fatal-infos`); tests con nombres en español descriptivo.

## §57.1. Matriz de trazabilidad

| Requisito/Componente | Documento | ADR | Código | Tests |
|---|---|---|---|---|
| Motor de reparto | spec §8, Biblia §26, `docs/REPARTO_POR_UNIDADES.md` | 006, 007, 025, 026 | `packages/domain/.../split_engine.dart` + espejo `backend/functions/src/domain/splitEngine.ts` | golden `split_engine.json`, propiedades en `split_engine_test.dart`, recompute y Rules |
| BalanceEngine | spec §8, Biblia §27 | 004, 013, 019 | `.../balance_engine.dart` + `balanceEngine.ts` | golden `balance_engine.json` (10), `balance_engine_test.dart`, `recompute.test.ts` (regresión E1) |
| Relaciones económicas | `docs/RELACIONES_ECONOMICAS.md` | 029 | `economic_ledger.dart` + `economicLedger.ts`, `economicPayments.ts`, `features/economy/**` | golden `economic_ledger.json`, tests de dominio/Functions/Flutter/Rules |
| Relaciones y grupos | `docs/ESPACIOS.md` | 028, 030 | `features/spaces/**`, `features/home/**`, contexto en `features/sessions/**` | `spaces_repository_test.dart`, `session_repository_test.dart`, `app_smoke_test.dart`, Rules |
| Enlaces de grupo | `docs/ESPACIOS.md` | 035 (sobre 012, 033, 034) | `spaces_repository.dart`, `space_link_screen.dart`, `join_space_screen.dart`, `router.dart`, `AndroidManifest.xml`, `firestore.rules` (spaceLinks + joinGrants) | `space_links_test.dart` (18), `join_space_screen_test.dart` (5), `join_route_test.dart` (2), Rules «enlaces de grupo» (20) |
| recompute | spec §12.2, Biblia §31 | 004, 013, 015 | `backend/functions/src/recompute.ts` | `recompute.test.ts` (11) |
| OCR | spec §10, Biblia §28 | 009, 010 | `packages/ocr_parser/**` | corpus (13) + unit (9) |
| Contrato IA | spec §9, Biblia §29 | 011 | `packages/ai_providers/**` + `features/ai/**` | `ai_providers_test.dart` (10) + `ai_feature_test.dart` (6) |
| Autenticación | spec §12, Biblia §9, `docs/AUTENTICACION.md` | 023 | `features/auth/**` + claims en Rules | `auth_repository_test.dart`, `auth_screens_test.dart`, `app_smoke_test.dart`, reglas (54) |
| Grupos (sesiones) | spec §7, Biblia §7/§30 | 003, 012 | `features/sessions/**` + `firestore.rules` | `session_repository_test.dart` (7) + reglas (48) |
| Backup | spec §14 | 017 | `features/settings/data/backup_service.dart` | `backup_service_test.dart` (3) |
| Tokens de diseño | spec §3, Biblia §20 | — | `packages/design_tokens/**` | frescura en CI (diff) |

## §58. Checklists operativas

**Antes de un commit**
- [ ] `dart analyze --fatal-infos` a cero · [ ] tests del área tocada en verde
- [ ] si tocaste un motor: AMBOS lados (Dart y TS) + vectores dorados
- [ ] si tocaste brand/tokens o ARB: regenerados y commiteados
- [ ] mensaje con prefijo y coautoría; sin secretos en el diff

**Antes de un merge/push a main**
- [ ] suite COMPLETA local (§60 comandos) · [ ] CI verde esperada (no "ya veremos")
- [ ] docs actualizados si cambió comportamiento (spec/CLAUDE/Biblia)

**Antes de una release / beta / producción**
- [ ] verificado EN ENTORNO REAL (lección E4): hosting desplegado, functions
      desplegadas, app contra proyecto real en dispositivo físico
- [ ] reglas desplegadas y test manual de un invitado real
- [ ] presupuesto/alertas activos · [ ] App Check en monitor (release: enforce)
- [ ] rollback preparado (ver abajo) · [ ] CHANGELOG/etiqueta de versión
- [ ] beta: canal interno Play + App Distribution; producción además: RGPD (DT-9) hecho

**Antes de modificar la arquitectura**
- [ ] ¿extensión en vez de reescritura? (§4.7) · [ ] ¿la solución simple ya falla HOY? (§4.8)
- [ ] ADR escrito ANTES de implementar · [ ] contrato §63 revisado · [ ] lista negra §62 revisada

**Añadir proveedor de IA**
- [ ] implementa `AiReceiptProvider` o preset del genérico · [ ] errores mapeados a `AiErrorCode`
- [ ] test con Dio falso (forma de petición + parseo + 401) · [ ] registrado en `standard()` · [ ] probar conexión real manual

**Añadir país al OCR**
- [ ] nueva clase `XxReceiptParser` registrada en `ReceiptParser` (NO tocar `es`)
- [ ] ≥5 casos de corpus mustPass del país · [ ] patrones de importe/fecha propios · [ ] harness verde con métricas

**Añadir Cloud Function**
- [ ] ¿de verdad no puede ser cliente+reglas? (coste) · [ ] idempotente y "escribe solo si cambia"
- [ ] región/limits globales heredados · [ ] núcleo puro testeado sin Firestore · [ ] logs estructurados

**Añadir pantalla**
- [ ] ruta ANIDADA con atrás garantizado · [ ] estados vacío/carga/error/offline
- [ ] cadenas en ARB · [ ] tokens (nada hardcodeado) · [ ] test de widget del estado principal

**Añadir entidad de dominio**
- [ ] invariantes escritas (§25) · [ ] pura (sin Flutter/Firebase) · [ ] toJson/fromJson si cruza frontera
- [ ] si toca dinero: SOLO `Money` y `allocateProportionally` · [ ] espejo TS si la function la necesita + golden

**Rollback de una release**
- [ ] Hosting: `firebase hosting:rollback` (o redeploy del commit anterior)
- [ ] Functions: redeploy del commit etiquetado anterior (git checkout tag && deploy)
- [ ] App: subir build anterior al canal (Play conserva artefactos); los datos NO se migran hacia atrás (esquema aditivo: schemaVersion + campos nuevos siempre opcionales)
- [ ] postmortem en §48.1

## §59. Métricas de calidad (umbrales objetivo)

| Métrica | Umbral | Estado |
|---|---|---|
| Cobertura motores de dinero | ≥90 % (RNF-09) | [HECHO] exhaustiva por vectores+propiedades |
| Casos mustPass del corpus | 100 % | [HECHO] 12/12 |
| Bundle web (JS+CSS+HTML gz) | ≤220 KB (CI lo fuerza) | [HECHO] 183 KB |
| Web interactiva en 4G | <1 s | [SUPOSICIÓN — VERIFICAR con Lighthouse] |
| Arranque app (frío, gama media) | <2 s | [VERIFICAR en dispositivo] |
| OCR típico | <3 s | [HECHO en pruebas propias] |
| Sincronización invitado→anfitrión | <2 s (recompute incluido) | observado ~1 s |
| Coste mensual (uso personal) | ≤3 € presupuestado; esperado ~0 € | [HECHO] presupuesto activo |
| Accesibilidad | WCAG 2.1 AA en flujos principales | parcial (DT-7) |
| Rendimiento UI | 60 fps en listas; sin jank >32 ms | [VERIFICAR con DevTools] |
| Tasa de error producción | >1 % de sesiones con crash = incidente | requiere DT-2 |

## §60. Documento de continuidad (si el equipo desaparece mañana)

1. **Leer en orden:** CLAUDE.md → spec → esta Biblia. 2. **Entorno:** clonar;
   Flutter estable; `dart pub get` (raíz); `npm install` en `apps/guest_web` y
   `backend/functions` y `backend/firestore`; JDK 21 y Android SDK
   (CLAUDE.md §12 tiene las rutas de esta máquina). 3. **Verificación completa:**
   `dart analyze --fatal-infos` · `dart test` en domain y ocr_parser ·
   `flutter test` en apps/mobile · `npm test` en functions · `npm test` +
   `npm run check` + `build` + `check:size` en guest_web ·
   `firebase emulators:exec --only firestore --project demo-salda "npm --prefix backend/firestore test"`.
4. **Cuentas:** Firebase `salda-dev`/`salda-prod` y repo GitHub `DaoeZ/salda`
   pertenecen al usuario (Edgar); CLI autenticadas en su máquina.
5. **Deploy:** `firebase deploy --only firestore|storage|functions|hosting
   --project salda-dev` (functions en Windows: `FUNCTIONS_DISCOVERY_TIMEOUT=120`
   y `--force` por la política de retry de cleanup).
6. **Estado exacto y pendientes:** §44 (deuda) y §51 (roadmap R1).

## §60.1. Onboarding de un desarrollador humano

- **Día 1:** leer los tres documentos; levantar emuladores; correr TODA la
  suite; sembrar `tools/seed-emulator.mjs` y recorrer la web de invitados en
  local. NO tocar código.
- **Día 2:** app en un emulador/dispositivo contra emuladores
  (`--dart-define=USE_EMULATORS=true`); recorrer el flujo completo como
  anfitrión e invitado a la vez.
- **Semana 1:** primer PR pequeño y periférico sugerido: un caso nuevo de
  corpus con su regla, o una pantalla de estados vacíos. **Prohibido** tocar
  hasta dominar el modelo: `packages/domain` (motores), `recompute.ts`,
  `firestore.rules`, vectores dorados y corpus (son CONTRATOS).
- **Antes de tocar BalanceEngine u OCR:** reproducir a mano 3 vectores dorados
  en papel; leer §26–§28 y los tests de propiedades; entender E1 y E7 (§48.1).

## §61. Onboarding para un modelo de IA menos capaz

1. Lee CLAUDE.md → spec → Biblia. NO empieces a programar sin poder explicar el
   modelo mental (§7) y los 8 principios técnicos (§4).
2. Trabaja SOLO por extensión; ante la duda entre dos diseños, el más simple.
3. Nada de dinero fuera de `Money`+`allocateProportionally`. Nada de tocar UN
   motor: siempre los dos + vectores.
4. Cada cambio: checklist de commit (§58) + verificación completa (§60.3) +
   CI verde ANTES de darlo por hecho.
5. Si un test dorado/corpus falla: la implementación está mal, NO el dato.
   Si crees que el contrato cambió: ADR primero, ambos lados después.
6. No inventes estado del proyecto: verifica en el repo; si no puedes, dilo.
7. Consulta §62 (lista negra) y §63 (contrato) antes de cualquier decisión.

## §62. LISTA NEGRA — prohibido sin aprobación explícita del usuario

- Reescribir el dominio o un motor sin ADR aprobado.
- Cambiar Firestore por SQL (o cualquier migración de plataforma) "porque sí".
- Introducir estado global nuevo (singletons, providers raíz) sin justificación escrita.
- Modificar `BalanceEngine`/`SplitEngine` sin actualizar AMBOS lenguajes y sus vectores.
- Cambiar contratos públicos (`ReceiptExtraction`, `AiReceiptProvider`, formato de backup, esquema Firestore) sin versionarlos.
- Tocar el pipeline OCR sin pasar el corpus completo.
- "Arreglar" un vector dorado o un caso mustPass editando el JSON.
- Decisiones irreversibles (borrar datos, renombrar colecciones, publicar) sin ADR + aprobación.
- Subir `maxInstances`, cambiar región o quitar límites de coste.
- Debilitar una regla de seguridad o el principio deny-by-default.
- Añadir dependencias pesadas donde exista solución simple (§4.8).
- Ejecutar la IA sin acción explícita del usuario o sacar una API key del dispositivo.

## §63. CONTRATO DEL PROYECTO

**CONGELADO (cambiar exige ADR + aprobación explícita del usuario):**
la spec v2.0 como base funcional; los 8 principios técnicos (§4); el modelo de
datos raíz-grupo (§30) en cuanto a colecciones/campos EXISTENTES; los contratos:
vectores dorados, corpus mustPass, `ReceiptExtraction`, `AiReceiptProvider`,
formato de backup `appcuentas-backup@1`, códigos de `DomainException`; la matriz
de seguridad y su suite; los techos de coste.

**EVOLUCIONA LIBREMENTE (dentro de los principios):** UI/UX y navegación,
textos y ARB, perfiles y reglas del parser (aditivos), proveedores de IA
nuevos, campos NUEVOS opcionales en documentos, tooling y CI, todo el roadmap R1–R4.

**Cuándo SÍ está justificado modificar arquitectura:** un límite de §43 se
alcanza EN LA REALIDAD (no en teoría); un contrato externo cambia (Firebase,
FlutterFire); una exigencia legal; o el coste medido de mantener supera el de
migrar (cálculo explícito por escrito).

**Cuándo NO, aunque parezca mejora:** "quedaría más limpio", "es más moderno",
"por si acaso escala", "lo reescribo más elegante". Ninguna de esas frases
justifica tocar lo congelado.

**Checklist de decisión para CUALQUIER cambio futuro:**
- [ ] ¿Acerca el producto al principio rector (§1)?
- [ ] ¿Es extensión y no reescritura? Si es reescritura: ¿está el cálculo coste-mantener vs coste-migrar por escrito?
- [ ] ¿Es la opción más simple funcionalmente equivalente?
- [ ] ¿Respeta la lista negra (§62)?
- [ ] ¿Toca algo congelado? → ADR + aprobación ANTES.
- [ ] ¿Cumple la Definition of Done al cerrarse?

**Definition of Done (cierre de CUALQUIER tarea del roadmap):** implementado
según criterios de aceptación · tests en verde (unit/integración/golden si
aplica) · docs actualizados (Biblia/spec/CLAUDE según toque) · accesibilidad y
responsive verificados si hay UI · dentro de los umbrales §59 · cero warnings
nuevos · CI verde · ADR creado/actualizado si hubo decisión · matriz §57.1
actualizada si toca un componente trazado.

---

<a name="inconsistencias"></a>
# INCONSISTENCIAS DETECTADAS (documentación ↔ código)

| # | Inconsistencia | Resolución |
|---|---|---|
| I1 | spec §7-secretos dice `firebase_options.dart` gitignorado; el repo lo commitea | ADR-016 la matiza (config pública ≠ secreto). Al revisar la spec, actualizar esa línea |
| I2 | spec §12.2 "SOLO 3 functions"; hay 6 bindings desplegados | Son 3 funciones CONCEPTUALES (recompute con 4 triggers). Aclarado en §31 |
| I3 | spec §2.1 "FAB abre la cámara directamente"; la app muestra hoja cámara/galería/manual | Divergencia consciente de MVP (el gasto manual necesita entrada); revisar en R1.6 si se vuelve al diseño spec |
| I4 | spec RF-72 snapshot de pagos "al compartir"; el código lo congela al CREAR | Equivalente en la práctica (se comparte al crear). Documentado aquí |
| I5 | spec `pendingCount`; el código escribe `pendingSettlements` | Ganan los nombres del código (contrato §63); anotar al revisar spec |
| I6 | spec RF-95/96 y aiPolicy descritos como v1; no implementados | Deuda DT-1/DT-10/DT-11 con hueco en roadmap R1/R2 |
| I9 (RESUELTA) | recompute repartía las líneas huérfanas entre todos EN VIVO; la spec RF-46 solo lo preveía al finalizar y con confirmación | Corregido en ADR-021: huérfanas → pagador en el cálculo continuo. Ya no divergen |
| I7 | Formato de backup `appcuentas-backup` con marca provisional "Salda" | Valor CONGELADO de la spec §14 (compatibilidad); no renombrar |
| I10 (RESUELTA) | `brand.json` declaraba `androidApplicationId: dev.salda.app` mientras Gradle compilaba `dev.salda.salda_mobile`; la documentación citaba el primero como oficial. Detectada al publicar `assetlinks.json` en el cierre del Sprint 4 | El campo de `brand.json` era **código muerto** (no lo emitía el codegen ni lo leía nadie: regenerar los tokens tras quitarlo no cambia un byte). Oficial = **`dev.salda.salda_mobile`**, con fuente de verdad ÚNICA en `android/app/build.gradle.kts`; cambiarlo convertiría la app en otra distinta y los invitados perderían su identidad local (ADR-034). Campo eliminado, docs corregidas y `android_identity_test.dart` vigila que Gradle, manifest y `assetlinks.json` no vuelvan a separarse |
| I8 | CLAUDE.md §12 dice "smoke test usa Brand.tagline"; el test actual valida login/estado vacío | Detalle obsoleto de CLAUDE.md; corregir en su próxima edición |

*Fin de la Biblia. Cualquier modelo o ingeniero que llegue hasta aquí tiene todo
lo necesario; si algo no está en los tres documentos, la respuesta correcta es
preguntar, no asumir.*
