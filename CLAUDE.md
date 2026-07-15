# Salda (nombre provisional) — documento de traspaso y guía de desarrollo

> **Propósito:** que una sesión de Claude Code (u otra persona) en cualquier máquina
> retome el proyecto sin haber visto las conversaciones anteriores. Léelo entero antes
> de tocar código. La especificación `docs/ESPECIFICACION.md` v2.0 es **definitiva y
> congelada** y manda sobre este resumen.
>
> **Existe además `docs/BIBLIA_SALDA.md`** — la referencia estratégica y técnica
> definitiva: visión de producto vigente (centrada en GRUPOS), ADRs, Contrato del
> Proyecto, lista negra, checklists, métricas, roadmap R1–R4 y postmortems.
> **Orden de lectura obligatorio: este archivo → ESPECIFICACION.md → BIBLIA_SALDA.md.**

---

## 1. Resumen del proyecto: qué es y estado general

**Qué es:** app móvil (Android primero; iOS después desde la misma base Flutter) tipo
Tricount pero automatizada con OCR: el anfitrión fotografía un ticket, la app extrae
establecimiento/fecha/productos/total con ML Kit + parser propio (gratis, on-device),
añade participantes y reparte el gasto ("todo a medias" o "cada uno lo suyo" por línea).
Los invitados NO instalan nada: abren un enlace/QR (web ligera Svelte) donde eligen quién
son, se asignan productos, ven cuánto deben y marcan "ya he pagado". IA opcional
multi-proveedor (con la API key del propio usuario, guardada solo en su dispositivo) como
ÚLTIMO recurso cuando el OCR falla. Concepto superior **Sesión** ("Viaje a Madrid") que
agrupa cuentas (Hotel, Gasolina…) con balance global multi-pagador y simplificación de
deudas. Uso personal/amigos; coste objetivo 0–1 €/mes (techo 5 €).

**Estado general:** M0–M2 terminados y **M3 (Sesiones) COMPLETO A NIVEL DE CÓDIGO y
verificado** (~180 tests en verde: dominio, parser, reglas contra emulador, functions y
app). Pendiente de M3 solo lo que requiere al usuario: crear los proyectos Firebase
reales y probar en dispositivo (sin SDK de Android en esta máquina). Las reglas ya NO
son deny-all: implementan la matriz §13.2 con 48 tests. Las functions (recompute/notify/
cleanup) están implementadas y testeadas.

**Estabilización post-MVP (prueba en dispositivo real):** 6 bugs de la 1ª prueba
corregidos con causa raíz (commit `d5e6d55`); "cada uno paga lo suyo" blindado — las
líneas no reclamadas recaen en el pagador, sin media previa (ADR-021, `4c3ed98`); y
**foto del ticket P0.2 COMPLETA**: `ReceiptImageStore` (apps/mobile/.../scan/data/
receipt_storage.dart) con copia local DURABLE en app-documents ligada al ticket
(sobrevive al cierre de la app y a la limpieza del picker; vale para cámara y galería),
subida a Storage con reintento transparente (si falla, se reintenta al abrir el ticket),
y lectura LOCAL-PRIMERO memoizada (`ticketImageProvider`, instantánea/offline). El
detalle abre la foto a pantalla completa con zoom+pan. `imagePath` (referencia) viaja en
el backup JSON; los BYTES no (backup solo-JSON, spec §14) → tras restaurar en otro
dispositivo la referencia existe pero la imagen solo si el objeto de Storage sigue
(degrada a "sin foto"). Captura a q85 (< 2 MB, regla de Storage). Deuda menor: limpiar
las copias locales al borrar el grupo.

**P0.3 balance actual y progreso COMPLETA**: `recompute` publica
`totals.settlementRequired` = confirmadas históricas + obligaciones residuales;
el progreso compara confirmado/requerido (0/0 = saldado), nunca pagos/gasto total.
La app separa "Estado actual" (`outstanding`) de "Histórico económico"
(`paid/consumed/net` + transferencias confirmadas), con barra verde/ámbar/neutral y
actualización por streams. La web usa el mismo agregado autoritativo y ya no estima
importes "c/u" desde líneas. ADR-022 en la Biblia.

**Hoja de ruta:** M0 ✅ · M1 ✅ · M2 ✅ · M3 código ✅ · M4 código ✅ (E2E vs emulador) ·
M5 código ✅ (salvo lo intrínsecamente de dispositivo: recordatorios con notificaciones,
haptics reales, import de PDF con render nativo y captura guiada) · **M6 IA ✅ COMPLETO**:
paquete ai_providers (contrato, prompt canónico, parseAiResponse con validación de
cuadre, adaptadores Claude/Gemini/OpenAI-compatible + presets OpenAI/DeepSeek/GLM/
OpenRouter, registry, 10 tests con Dio falso) + lado app: SecretVault (interfaz sobre
flutter_secure_storage; keys SOLO dispositivo RF-32), AiConfigStore (config+preferido),
pantalla /settings/ai con "Probar conexión" OBLIGATORIO antes de guardar (RF-31),
AiAnalysisController (imagen si visión — ScanService ahora conserva imagePath en
lastScanImageProvider —, reintento único en badResponse, sustituye el draft) y botón
"Analizar con IA" de la revisión activo solo con proveedor configurado (DC-13).
**TODAS las fases de la hoja de ruta están completas a nivel de código.**
Entorno: SDK de Android instalado en C:\dev\android-sdk (cmdline-tools, licencias
aceptadas, ANDROID_HOME de usuario). ·
Pendiente de usuario: proyectos Firebase reales, Android Studio/dispositivo, App Check.

**M5 realizado:** Ajustes (tema persistido, métodos de pago en users/{uid} +
snapshot congelado al crear sesión RF-72, personas frecuentes, backup); gasto manual
(RF-13, extracción `manual` de 1 línea); añadir ticket a sesión existente (nueva cuenta
aN, sesión pasa a `multi`; entrada única de escaneo scan_flow + selector de pagador);
backup JSON completo spec §14 (export/import fusionar/restaurar, shareCodes regenerados,
ownerUid forzado → sirve para migrar de cuenta; reglas ampliadas: owner puede crear/
borrar settlements para el import, test actualizado); exportar PDF (paquete pdf) e
imagen-resumen PNG para WhatsApp (Canvas puro, testeable) desde el menú del detalle.

## 2. Por dónde vamos: punto exacto y última sesión paso a paso

**Punto exacto:** M2 cerrado y subido (commit `3aca453` + docs/CI posteriores). Lo
siguiente es preparar el entorno para M3 (ver §11).

**Qué se hizo en la última sesión de trabajo, en orden:**
1. Se congeló la especificación v2.0 (`docs/ESPECIFICACION.md`) tras incorporar:
   sesiones, multi-pagador, web ligera de invitados, functions autoritativas, proveedor
   IA genérico OpenAI-compatible, guía de diseño, backups JSON, presupuesto 5 €.
2. Naming: se propusieron ~30 nombres; elegido **Salda** como provisional. Todo el
   branding quedó centralizado en `packages/design_tokens/assets/brand.json`.
3. **M0**: instalación de Flutter 3.44.6 en `C:\dev\flutter` y Firebase CLI; monorepo
   pub workspace; paquete de tokens con codegen Dart+CSS; app Flutter con tema M3;
   web Svelte placeholder; functions esqueleto; reglas deny-all; emuladores; CI.
4. **M1**: Money/allocateProportionally/ShareCode/SplitEngine/BalanceEngine en Dart puro
   + espejo TS en functions + 29 vectores dorados compartidos + 54 tests Dart/29 TS.
5. **M2**: contrato `ReceiptExtraction` en domain; paquete `ocr_parser` completo
   (geometría, parser es-ES con 10 perfiles de cadena y 9 reglas, corpus de 13 casos con
   harness de métricas → 12/12 mustPass, 92 % casos completos); en la app: adaptador
   ML Kit, ScanService (cámara del sistema/galería), pantalla de revisión editable con
   cuadre en vivo y banner "repetir foto/editar/IA"; i18n ARB.
6. Se creó el repo GitHub privado **https://github.com/DaoeZ/salda** y se subió todo
   (hizo falta reautorizar gh con scope `workflow` por el archivo de CI).
7. Se escribió este documento de traspaso; se subieron las actions a checkout@v5/
   setup-node@v5 y se reparó un estropicio de encoding causado por PowerShell (ver §9).
8. CI verificada en verde en GitHub para el último commit.

**M3 realizado (código completo, ver commits M3):**
- Reglas §13.2 + 48 tests contra emulador (backend/firestore/test/rules.test.mjs);
  job `rules` en CI con setup-java y cache del jar del emulador.
- Functions: recompute (núcleo puro `computeAggregates` + 3 triggers), notify (FCM),
  cleanup (cascada). 37 tests TS. `order` en participantes fija el orden determinista
  de los motores — la app lo escribe al crear (p0..pN) y DEBE mantenerse.
- App: bootstrap Firebase (emuladores, opciones demo en
  `core/firebase/firebase_options_stub.dart`), Auth email+contraseña (Google oculto
  hasta proyecto real: `AuthRepository.googleSignInAvailable`), repositorio de sesiones
  (creación en DOS pasos: doc sesión y luego batch — las reglas de subdocs hacen get()
  de la sesión), providers autoDispose, LoginScreen, Home=historial con tarjeta
  te-deben/debes + skeletons, hoja Gente-y-reparto (chips frecuentes, modo, pagador),
  ShareScreen (QR + enlace #k=), detalle (Resumen balances+liquidaciones con
  confirmar/deshacer · Cuentas · Actividad placeholder), cerrar/reabrir/archivar/borrar,
  draft persistente con banner de recuperación (shared_preferences).

**M4 realizado (web de invitados completa):**
- `apps/guest_web` real: acceso por enlace `/s/{sid}#k=` (prueba de conocimiento →
  guestAccess), "¿Quién eres?" con nombres ocupados, resumen con "te toca pagar",
  botones de pago (PayPal/Revolut con importe; Bizum/IBAN copiar; solo los
  configurados), "Ya he pagado" (pending→marked con auditoría), elegir productos en
  vivo (toggle validado por reglas vía assignment.lastEditorPid), ticket completo,
  cuenta cerrada = solo lectura, identidad recordada en localStorage.
- La web NO calcula dinero: pinta `balances`/`totals` de la function; el pie de
  "llevas marcado" lee balances.consumed (se actualiza al recalcular).
- Estado con runas de Svelte 5 en `src/lib/session.svelte.ts` (clase GuestSession).
- Meta/OG/favicon SVG/manifest; SIN service worker a propósito (datos vivos +
  mantenimiento; decisión documentada). `robots: noindex`.
- Presupuesto de peso REAL en CI: `scripts/check-size.mjs` falla si JS+CSS+HTML
  gzip > 220 KB (hoy ~183 KB; el chunk `firebase` va separado y cachea entre deploys).
- 14 tests vitest de lógica pura (link, assignment, money, payments) + svelte-check
  a cero. **E2E manual completo contra emuladores** (flujo entero verificado, incluida
  la escritura quirúrgica de líneas contra las reglas reales y el estado en servidor).
- Herramienta dev: `backend/functions/tools/seed-emulator.mjs` siembra una sesión de
  prueba (`/s/e2e1#k=E2E-SECRET-CODE-16CH`) para probar la web en local.

**Qué quedó fuera de M3 a propósito:**
- Botón **"Analizar con IA"** deshabilitado hasta M6.
- **Captura guiada propia** y validación OCR real: pendientes de dispositivo.
- **Importar PDF** (RF-21) sin UI; gasto manual sin ticket: M5.
- Añadir ticket/cuenta a sesión EXISTENTE desde el detalle: pendiente (siguiente
  bloque natural; el modelo y las reglas ya lo soportan).
- Feed de actividad se escribe pero no se lista (M4).
- `/review` por deep link sin draft muestra spinner (el draft persistente cubre el
  caso real de recuperación).

## 3. Lógica seguida: el porqué de cada módulo

- **`domain` es Dart puro y las functions tienen un espejo TS** porque el cálculo de
  dinero vive en dos runtimes: la app (respuesta instantánea + offline) y la Cloud
  Function (autoritativa, para que un invitado vea recalculos sin que el anfitrión abra
  la app y para que ningún cliente pueda corromper agregados). La paridad no se confía a
  la disciplina: **los mismos JSON dorados se ejecutan contra ambas implementaciones en
  CI** y cualquier divergencia rompe el build.
- **`allocateProportionally` (resto mayor) es la única primitiva de redondeo**: si toda
  división de dinero pasa por ahí, "Σ partes == total exacto" es un invariante del
  sistema, no una esperanza. SplitEngine reparte el grandTotal proporcionalmente al
  consumo por líneas (en vez de prorratear impuestos/propina aparte) por esa misma razón:
  un solo redondeo, cero acumulación de error.
- **BalanceEngine recibe consumos ya calculados** (no llama a SplitEngine): composición
  simple, testeo independiente, y la function puede recalcular solo lo que cambió.
  Las liquidaciones confirmadas se "congelan" y se descuentan antes de regenerar las
  pendientes (así confirmar un pago nunca "baila" por ediciones posteriores).
- **El parser OCR es un pipeline de fases** (geometría → normalización → perfiles →
  reglas → confianzas → issues) porque cada fuente de error tiene su capa: ML Kit parte
  las columnas (lo arregla la geometría), los térmicos confunden O/0 (normalización),
  cada cadena tiene su formato (perfiles, detectables por NIF cuando la cabecera es
  ilegible), y los formatos de línea son abiertos (lista ORDENADA de reglas: añadir una
  nueva no toca las demás). La confianza es POR CAMPO para que la revisión manual
  resalte solo lo dudoso, y las interpretaciones alternativas se conservan para que
  corregir sea un toque (chips) en vez de teclear.
- **`ReceiptExtraction` vive en domain, no en ocr_parser**, porque es el contrato común
  de TODOS los orígenes (parser hoy, proveedores IA en M6, edición manual): la pantalla
  de revisión es agnóstica del origen.
- **La pantalla de revisión trabaja sobre un draft** (`ReviewDraftState`, Riverpod)
  separado de la extracción inmutable: editar algo pone su confianza a 1.0 (el usuario
  es la verdad), borra alternativas y recalcula el cuadre en vivo.
- **Los tokens de diseño se generan desde JSON** para que app y web compartan identidad
  desde una única fuente; la CI vuelve a generar y hace `git diff --exit-code` para que
  nadie edite un `.g.` a mano.
- **La web de invitados no contiene lógica de dinero** por diseño: pinta agregados que
  escribe la function y hace escrituras quirúrgicas validadas por reglas. Así puede ser
  minúscula (11 KB gzip hoy) y duplicar "código" deja de ser un problema.

## 4. Normas y convenciones (a rajatabla)

**Reglas acordadas con el usuario (permanentes):**
- Idioma del usuario: **español** (UI en español vía ARB; código, identificadores y
  nombres de archivo en inglés).
- Decisiones menores: tomarlas automáticamente con mejores prácticas. Preguntar SOLO si
  afecta significativamente a funcionamiento, seguridad, coste o UX. Si hay una
  arquitectura claramente mejor que la spec, **consultar antes de cambiarla**; si una
  librería deja de ser la mejor opción, proponer el cambio antes de aplicarlo.
- No avanzar de fase hasta que la actual compile, pase todos los tests y quede estable.
  Cada fase termina con verificación completa + **commit propio** + explicación de lo
  construido y las decisiones tomadas.
- Cobertura alta en TODA la lógica de negocio (motores ≥90 %, RNF-09). Deuda técnica:
  se resuelve en la fase en que aparece. No rehacer módulos terminados sin motivo.

**Arquitectura y estilo:**
- **Clean Architecture ligera, feature-first** en la app: `features/<x>/{domain,data,
  application,presentation}`; transversal en `core/`. Dependencias SIEMPRE hacia dentro:
  `apps → packages`; `domain` y `ocr_parser` sin Flutter/Firebase/IO.
- Estado: **Riverpod v3** (Notifier/Provider); navegación: **go_router**.
- Puertos y adaptadores para todo lo externo (ej.: `ReceiptOcr` ↔ `MlKitReceiptOcr`);
  los motores son clases estáticas puras y deterministas.
- Análisis estricto (`analysis_options.yaml` raíz + flutter_lints): `dart analyze
  --fatal-infos` debe quedar a CERO avisos.
- Dinero: céntimos `int` envueltos en `Money` (extension type). JAMÁS `double`.
- Comentarios: en español, explican el PORQUÉ/restricciones, no el qué. Docs `///` en
  las APIs públicas de los paquetes.
- **Commits:** en español, imperativos, con prefijo de fase o tipo (`M2: …`, `fix(ci): …`,
  `docs: …`), cuerpo con viñetas de lo relevante, y SIEMPRE la línea
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`. Un commit por fase como
  mínimo; commits pequeños extra para arreglos puntuales.
- Tests: unitarios por módulo + propiedades con aleatoriedad SEMBRADA (reproducible) +
  vectores dorados/corpus como contratos. Los nombres de test, en español descriptivo.

## 5. Arquitectura: estructura del monorepo

```
docs/ESPECIFICACION.md      Especificación v2.0 congelada (la biblia del proyecto)
pubspec.yaml                Raíz del pub workspace (lockfile único aquí, commiteado)
packages/design_tokens/     brand.json + design_tokens.json (fuente única de marca y
                            diseño) + bin/generate.dart → lib/src/tokens.g.dart (Dart)
                            y apps/guest_web/src/styles/tokens.g.css (CSS)
packages/domain/            Dart PURO: Money, allocateProportionally, ShareCode,
                            DomainException (códigos estables), SplitEngine,
                            BalanceEngine, ReceiptExtraction. test/golden/*.json =
                            VECTORES DORADOS compartidos con la implementación TS
packages/ocr_parser/        Dart puro: OcrDocument/OcrRect (agnóstico de motor) →
                            LineBuilder (geometría) → ReceiptParser (registry por país)
                            → EsReceiptParser (perfiles + reglas). test/corpus/ =
                            corpus de regresión con harness de métricas por campo
packages/ai_providers/      Esqueleto para M6 (contrato AiReceiptProvider + adaptadores)
apps/mobile/                Flutter Android+iOS (org dev.salda, proyecto salda_mobile):
                            core/{theme,routing,utils} · l10n/ (ARB es + generated/)
                            features/home · features/scan · features/review
apps/guest_web/             Svelte 5 + Vite + TS. Placeholder hasta M4. SIN dinero.
backend/functions/          Cloud Functions v2 TS (europe-west1, maxInstances 3):
                            src/domain/ = espejo TS de los motores; src/test/golden
backend/firestore/          firestore.rules + storage.rules (deny-all) + índices
firebase.json / .firebaserc Config + Emulator Suite (default: demo-salda)
.github/workflows/ci.yml    CI: dart+flutter · guest-web · functions (job rules en M3)
```

## 6. Firebase

**Servicios y para qué (spec §12):** Auth (Google+Email para anfitrión, **Anónimo** para
invitados, Apple cuando haya iOS) · Firestore (datos + tiempo real + offline, región
`europe-west1`) · Storage (fotos de tickets: original ≤1600px + thumb 300px generados
on-device) · Functions v2 (SOLO 3: `recompute` autoritativa, `notify` FCM, `cleanup`
borrado en cascada) · Hosting (web invitados + deep links) · App Check (enforced, M3/M4)
· FCM · Emulator Suite. **Los proyectos reales (`salda-dev`, `salda-prod`) NO existen
todavía**: crearlos en M3 con la cuenta del usuario, activar Blaze con presupuesto 5 €/mes
y alertas 50/90/100 % + alertas de métricas (spec §12.4). `.firebaserc` ya los referencia;
`default` es `demo-salda` (emuladores, sin credenciales).

**Modelo de datos (implantar en M3 EXACTAMENTE como spec §7):** raíz = **sesión**
(cuenta suelta = sesión `kind:"single"`, la UI oculta la capa):

```
users/{uid}                  perfil, paymentMethods, aiPolicy (JAMÁS API keys aquí)
users/{uid}/frequentPeople   personas frecuentes del anfitrión
sessions/{id}                ownerUid, kind, shareCode 128 bits, status, splitModeDefault,
                             paymentMethodsSnapshot, agregados desnormalizados (totals,
                             balances, computeVersion) ← SOLO los escribe la function
  participants/{pid}         name, isOwner, claimedByDevice, active
  accounts/{aid}             "Hotel", category, totals
    tickets/{tid}            kind, merchant{name,brandKey}, paidByParticipantId,
                             imagePath, ocr{engine,confidence}, subtotal/taxes[]/
                             discounts[]/tip/grandTotal, splitModeOverride
      lines/{lid}            name, quantity(×1000), unitPrice, totalPrice,
                             assignment{type, participants{pid:peso}}, order
  settlements/{sid}          from,to,amount,state pending|marked|confirmed, frozen,
                             stateHistory[], generation
  activity/{eid}             feed append-only
Storage: receipts/{sessionId}/{ticketId}/{original,thumb}.jpg
Índices (ya en firestore.indexes.json): sessions(ownerUid,updatedAt) y (ownerUid,status,updatedAt)
```

**Reglas de seguridad (IMPLEMENTADAS en M3, 48 tests por celda en CI):** matriz §13.2
con denegación por defecto. Mecanismo de invitados = **prueba de conocimiento**: el
invitado anónimo crea `sessions/{sid}/guestAccess/{su uid}` presentando el shareCode
(la regla lo compara con el de la sesión); las lecturas posteriores se autorizan con
`exists(guestAccess)`. Sus escrituras son quirúrgicas y validadas con `diff()`:
reclamar/liberar nombre (`claimedByDevice`), autoasignarse en líneas (solo SU entrada
del mapa, peso 1, modo byItem; el cliente declara `assignment.lastEditorPid` y la regla
verifica que ese pid está reclamado por su uid; no puede poner `all`), y `pending→marked`
solo donde él es `from`. Agregados solo-lectura; settlements solo los crea/borra la
function; cerrada = inmutable salvo reapertura del owner; activity append-only.
El shareCode viaja en el **fragment** (`#k=`). Revocación = regenerar código + borrar
guestAccess (lo hace `regenerateShareCode` del repositorio).

## 7. Servidores: comunicación, endpoints y secretos

**No hay servidores propios ni endpoints HTTP propios** (no aplica ese apartado tal
cual). Comunicación real: app Flutter ↔ Firestore por SDK (listeners tiempo real,
offline); web invitados ↔ Firestore por Firebase JS modular; las functions se disparan
por **triggers de Firestore** (no exponen HTTP); la IA (M6) irá directa dispositivo →
API del proveedor sin tocar Firebase.

**Ubicación de secretos (nunca valores):** API keys de IA → `flutter_secure_storage`
(Keystore/Keychain) del dispositivo del usuario, excluidas de logs/crashes/backup JSON ·
config Firebase de la app (`google-services.json`, `GoogleService-Info.plist`,
`firebase_options.dart`) → **gitignorados**, se generarán con `flutterfire configure` en
M3 (hoy NO existen) · **no hay `.env` en el repo ni secretos en CI todavía**; cuando
haya despliegue automático usar Workload Identity Federation · credenciales de gh y
firebase CLI → keyring del SO del desarrollador.

## 8. Decisiones de diseño tomadas y su motivo

(Las congeladas DC-1…DC-13 están en spec §0. Operativas añadidas durante el desarrollo:)

1. **Flutter** — un código APK+IPA, Material 3 de primera clase, ML Kit oficial.
2. **Web invitados Svelte, NO Flutter Web** — Flutter Web pesa 1,5–2 MB (3–6 s en 4G)
   para una página que se abre una vez desde WhatsApp; hoy el bundle son 11 KB gzip.
3. **Sesión raíz; cuenta suelta = sesión single** — un solo modelo, motor y reglas.
4. **Multi-pagador + simplificación de deudas** — sin esto las sesiones no funcionan;
   con un pagador degenera en el caso simple.
5. **Function autoritativa + cálculo local optimista + vectores dorados** — ver §3.
6. **Money extension type (céntimos int)** — coste cero, imposible mezclar con int/double.
7. **Resto mayor como única primitiva de redondeo** — exactitud como invariante.
8. **SplitEngine reparte el grandTotal por pesos de consumo** — un solo redondeo.
9. **pub workspace nativo (sin melos)** — menos herramienta, soporte de serie.
10. **Codegen de tokens JSON → Dart+CSS con verificación en CI** — una sola marca.
11. **Parser: registry país + perfiles cadena (detección por NIF) + reglas ordenadas** —
    incremental por construcción; térmico ilegible ≠ marca perdida.
12. **Confianza por campo + issues tipados + alternativas por línea** — revisión en 1 toque.
13. **IA último recurso SIEMPRE** — orden fijo: repetir foto → editar → IA; nunca sola.
14. **image_picker (cámara del sistema) por ahora** — flujo completo sin custom UI;
    captura guiada cuando haya dispositivo.
15. **l10n ARB desde M2** — deuda RNF-05 saldada antes de crecer la UI.
16. **applicationId provisional `dev.salda.app`** — cambiable gratis hasta publicar.
17. **Repo GitHub privado** (`DaoeZ/salda`) — branding y producto aún provisionales.

## 9. Enfoques probados y descartados (NO repetir)

- **Flutter Web para invitados** (spec v1.0) → descartado por peso/latencia.
- **v1 "sin Cloud Functions"** → descartado al aceptar el usuario coste 1–5 €: agregados
  escritos por clientes = transacciones frágiles y recalculos que no llegaban al invitado.
- **`node --test lib/test/` (directorio) en Windows** → el runner marca el directorio
  como test fallido. Se usa glob: `node --test "lib/test/**/*.test.js"` (package.json).
- **`intl ^0.20.3`** → conflicto con flutter_localizations (fija 0.20.2). Queda `^0.20.2`.
- **`synthetic-package` en l10n.yaml** → opción retirada de Flutter; no reintroducir.
- **Canonicalizar importes ANTES de fecha/hora** → convertía la hora "18.32" en importe.
  El orden correcto (fecha/hora primero, sobre líneas originales) está comentado en
  `EsReceiptParser.parse`.
- **pubspec.lock por app** → con workspace el único lockfile es el de la RAÍZ.
- **Céntimos crudos en mapas const** (`{'b': 600}` donde se espera `Money`) → no compila;
  escribir `Money(600)`.
- **Tests de ReviewScreen con viewport por defecto** → ListView perezosa: el pie no se
  construye. Los tests fijan `tester.view.physicalSize` alto (2000 px).
- **Editar YAML con `-replace` de PowerShell 5.1** → leyó UTF-8 como ANSI y corrompió
  los acentos (mojibake `Ã¡`); hubo commit de reparación. Para editar archivos con
  tildes usar las herramientas de edición, no sustituciones de PowerShell.
- **`gh repo create --push` con workflows** → falla si el token no tiene scope
  `workflow`; se resolvió con `gh auth refresh -h github.com -s workflow` (device flow).

## 10. Archivos de referencia clave

| Archivo | Qué es / por qué consultarlo |
|---|---|
| `docs/ESPECIFICACION.md` | Spec v2.0 congelada: requisitos RF/RNF, matriz de seguridad §13.2, modelo de datos §7, guía de diseño §3, roadmap §19 |
| `packages/domain/lib/src/money.dart` | Money + allocateProportionally: LA primitiva de redondeo |
| `packages/domain/lib/src/engines/split_engine.dart` | Reparto por ticket (modos, pesos, política de líneas sin asignar) |
| `packages/domain/lib/src/engines/balance_engine.dart` | Balance multi-pagador, congeladas y simplificación de deudas |
| `packages/domain/lib/src/receipt/receipt_extraction.dart` | Contrato canónico OCR/IA/manual con confianzas e issues |
| `packages/domain/test/golden/*.json` | Vectores dorados Dart↔TS: contrato de paridad (¡no editarlos a la ligera!) |
| `backend/functions/src/domain/*.ts` | Espejo TS de los motores; si tocas uno, toca ambos |
| `packages/ocr_parser/lib/src/es/es_receipt_parser.dart` | Orquestador del parser: fases, reglas, issues (el archivo más denso del proyecto) |
| `packages/ocr_parser/lib/src/es/es_profiles.dart` | Perfiles por cadena; aquí se añade una cadena nueva |
| `packages/ocr_parser/test/corpus/` + su README | Corpus de regresión y protocolo para añadir tickets reales |
| `packages/design_tokens/assets/brand.json` | ÚNICO lugar del branding (nombre, tagline, applicationId) |
| `packages/design_tokens/bin/generate.dart` | Codegen tokens → Dart + CSS |
| `apps/mobile/lib/features/review/application/review_draft.dart` | Estado editable de la revisión y su lógica de cuadre |
| `apps/mobile/lib/features/scan/application/scan_service.dart` | Orquestación cámara/galería → OCR → parser |
| `apps/mobile/lib/core/theme/app_theme.dart` | Tema M3 desde tokens + colores semánticos de estados |
| `backend/firestore/firestore.rules` | Hoy deny-all; en M3, la matriz §13.2 |
| `firebase.json` / `.firebaserc` | Emuladores, hosting, rutas de reglas; proyectos dev/prod |
| `.github/workflows/ci.yml` | Qué verifica la CI (incluida la frescura de los `.g.`) |

## 11. Próximos pasos concretos (en orden)

1. **Entorno para M3** (bloqueante): instalar Android Studio (trae el JDK que necesitan
   el emulador de Firestore y el build Android) + SDK Android; `flutter doctor` limpio.
   Probar la app en dispositivo/emulador; validar OCR con 3-4 tickets reales y
   **alimentar el corpus** con lo que falle (protocolo en test/corpus/README.md).
2. **Crear proyectos Firebase** `salda-dev`/`salda-prod` (cuenta del usuario,
   `firebase login`): europe-west1, Blaze + presupuesto 5 € + alertas (spec §12.4);
   `flutterfire configure` (los archivos generados van gitignorados).
3. **M3 — Sesiones**: (a) modelo Firestore de spec §7 con `schemaVersion`; (b) reglas =
   matriz §13.2 con test por celda vía `firebase emulators:exec` + job `rules` en CI;
   (c) functions `recompute` (reutiliza `src/domain/` TS), `notify`, `cleanup`,
   idempotentes con `computeVersion`; (d) app: Auth Google+Email, repositorios Firestore,
   crear sesión (conectar el "Continuar" de la revisión), detalle de sesión, personas
   frecuentes, compartir enlace+QR; (e) draft persistente del wizard.
4. **M4 — Invitados**: web Svelte real (¿quién eres? → resumen → elegir productos →
   ya he pagado), Auth anónimo + shareCode, tiempo real, App Check enforced.
5. **M5 — Pulido**: PDF import/export, imagen-resumen para WhatsApp, recordatorios,
   cierre/archivado, backup JSON (RF-90/91), estados vacíos/offline, haptics, beta.
6. **M6 — IA**: contrato + adaptadores (Claude, Gemini y openai_compatible primero),
   "Probar conexión" obligatorio, sugerencia por confianza < 0,75 (DC-13).

## 12. Cosas "raras" o no obvias (leer antes de romper algo)

- **Vectores dorados**: los ejecutan Dart Y TS; el ORDEN de las liquidaciones esperadas
  es parte del contrato. Nunca edites un JSON para "arreglar" un test: corrige la
  implementación, o revisa conscientemente AMBOS lados si el contrato cambia.
- **Corpus**: si un caso `mustPass:false` empieza a pasar, el harness FALLA a propósito
  para obligarte a promocionarlo a `true`. No es un bug.
- **Archivos generados commiteados**: `tokens.g.dart`/`tokens.g.css` (regenerar con
  `dart run design_tokens:generate`; la CI hace diff) y `apps/mobile/lib/l10n/generated/`
  (regenerar con `flutter gen-l10n` tras tocar el ARB).
- **`quantityMilli`**: cantidades ×1000 (0,466 kg → 466; una unidad → 1000).
- **`ShareCode.toString()` es opaco** a propósito (no filtrar secretos a logs).
- **Umbral de revisión**: `needsReview` = issues no vacíos O confianza global < 0,75
  (DC-13; calibrable con el corpus real).
- **Functions**: `maxInstances: 3` y europe-west1 en `setGlobalOptions` son el techo de
  coste (spec §12.4) — no subirlos sin consultar al usuario.
- **Presupuesto de peso de la web**: `chunkSizeWarningLimit: 300` en vite.config.ts;
  si un cambio lo dispara, replantear (lazy import de Firebase, etc.).
- **El smoke test de la app** usa `Brand.appName`/`Brand.tagline`: si cambias el branding,
  sincroniza también el ARB (`homeTagline`).
- **Entorno Windows de esta máquina**: Flutter en `C:\dev\flutter` y JDK Temurin 21 en
  `C:\dev\jdk-21.0.11+10` (ambos en PATH de usuario; JAVA_HOME persistido — lo necesita
  el emulador de Firestore). Node 26, Firebase CLI y gh (cuenta DaoeZ) globales.
  PowerShell 5.1: sin `&&`; primeras ejecuciones de flutter lentas (compila su tool).
  En otra máquina: clonar, instalar Flutter estable, `dart pub get` en la raíz,
  `npm install` en apps/guest_web y backend/functions, y listo.
- **Comandos de verificación por fase** (ejecutarlos TODOS antes de dar una fase por
  cerrada): `dart analyze --fatal-infos` (raíz) · `dart test` en packages/domain y
  packages/ocr_parser · `flutter test` en apps/mobile · `npm run build` en
  apps/guest_web · `npm test` en backend/functions · (desde M3) tests de reglas con
  `firebase emulators:exec`.
