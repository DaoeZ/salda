# Salda (nombre provisional) — documento de traspaso y guía de desarrollo

> **Propósito de este archivo:** que una sesión de Claude Code (u otra persona) en
> cualquier máquina pueda retomar el proyecto sin haber visto las conversaciones
> anteriores. Léelo entero antes de tocar código.

---

## 1. Resumen del proyecto y estado general

**Qué es:** app móvil (Android primero, iOS después, misma base Flutter) tipo Tricount
pero automatizada con OCR: el anfitrión fotografía un ticket, la app extrae
establecimiento/fecha/productos/total con ML Kit + parser propio, define participantes y
reparte el gasto. Los invitados NO instalan nada: abren un enlace/QR (web ligera) donde
eligen quién son, marcan sus productos y ven cuánto deben. Con IA opcional multi-proveedor
(la clave la pone el usuario) como ÚLTIMO recurso cuando el OCR falla.

**Referencia obligatoria:** `docs/ESPECIFICACION.md` v2.0 es la especificación
**definitiva y congelada**. No se rediseña arquitectura ni alcance; cualquier cambio
importante se propone al usuario y se registra como revisión del documento ANTES de
implementarlo. Este CLAUDE.md resume; la spec manda.

**Estado general:** M0 (cimientos), M1 (motores de dominio) y M2 (pipeline OCR completo)
terminados y verificados. Sin backend real todavía (reglas deny-all, functions vacías):
eso es M3. La app compila y los 112 tests pasan, pero NUNCA se ha ejecutado en un
dispositivo real (no hay SDK de Android en la máquina de desarrollo).

**Hoja de ruta:** M0 ✅ · M1 ✅ · M2 ✅ · M3 Sesiones ⬜ · M4 Invitados ⬜ · M5 Pulido ⬜ · M6 IA ⬜

## 2. Reglas de trabajo acordadas con el usuario (permanentes)

- Idioma del usuario: **español** (UI en español; código e identificadores en inglés).
- Tomar automáticamente las decisiones menores siguiendo mejores prácticas. Preguntar
  SOLO cuando afecte significativamente a funcionamiento, seguridad, coste o UX.
- Si se detecta una decisión de arquitectura claramente mejor que la spec, **consultar
  antes de cambiarla**. Si una librería deja de ser la mejor opción, proponer el cambio.
- No avanzar de fase hasta que la actual compile, pase todos los tests y quede estable.
- Cada fase termina con: verificación completa (analyze + tests + builds) + commit
  independiente + explicación de lo construido y decisiones tomadas.
- Cobertura alta en TODA la lógica de negocio, especialmente motores de dinero.
- Deuda técnica: se resuelve en la fase en que se detecta, no se pospone.
- No rehacer módulos terminados salvo motivo técnico importante.
- Coste: objetivo 0–1 €/mes, techo aceptado 5 €/mes (presupuesto con alertas).

## 3. Arquitectura

### Estructura del monorepo (pub workspace, pubspec.yaml raíz)

```
docs/ESPECIFICACION.md      Especificación v2.0 congelada (la biblia del proyecto)
packages/design_tokens/     Fuente única de diseño y branding:
                            assets/brand.json + assets/design_tokens.json
                            bin/generate.dart → genera lib/src/tokens.g.dart (Dart)
                            y apps/guest_web/src/styles/tokens.g.css (CSS)
packages/domain/            Dart PURO (prohibido Flutter/Firebase/IO):
                            Money, allocateProportionally, ShareCode, DomainException,
                            SplitEngine, BalanceEngine, ReceiptExtraction (contrato OCR/IA)
                            test/golden/*.json ← VECTORES DORADOS compartidos con TS
packages/ocr_parser/        Dart puro. Pipeline OCR: OcrDocument (agnóstico de motor) →
                            LineBuilder (geometría) → ReceiptParser (registry por país) →
                            EsReceiptParser (perfiles por cadena + reglas incrementales)
                            test/corpus/ ← corpus de regresión con harness de métricas
packages/ai_providers/      Esqueleto (se implementa en M6): contrato AiReceiptProvider
apps/mobile/                Flutter (Android+iOS). Riverpod v3 + go_router + M3 theme
                            desde tokens + l10n ARB (lib/l10n/app_es.arb → generated/)
                            features/: home, scan (ML Kit adapter + ScanService),
                            review (draft editable + pantalla con cuadre en vivo)
apps/guest_web/             Svelte 5 + Vite + TS. Placeholder hasta M4. SIN lógica de
                            dinero JAMÁS (solo pinta agregados de la function)
backend/functions/          Cloud Functions v2 TS (europe-west1, maxInstances 3).
                            src/domain/ = ESPEJO TS de los motores Dart (misma semántica)
                            src/test/golden.test.ts consume los MISMOS JSON dorados
backend/firestore/          firestore.rules + storage.rules (hoy deny-all) + índices
firebase.json / .firebaserc Config Firebase + Emulator Suite (default: demo-salda)
.github/workflows/ci.yml    CI: dart (analyze+tests+frescura de tokens) · web · functions
```

### Reglas de dependencia (violarlas = revisar el diseño)

- `apps → packages`; nunca al revés. `domain` y `ocr_parser` sin Flutter/Firebase.
- Dinero: SIEMPRE céntimos `int` envueltos en `Money` (extension type). JAMÁS `double`.
- `allocateProportionally` (resto mayor) es LA ÚNICA primitiva de redondeo del sistema.
- Los motores existen en Dart Y en TS. **Si cambias un motor, cambia ambos y ejecuta los
  vectores dorados en los dos lados.** Nunca edites un vector para "arreglar" un test.
- La web de invitados no calcula dinero: lee agregados que escribirá la Cloud Function.
- Branding: TODO sale de `packages/design_tokens/assets/brand.json` vía codegen.
  No hardcodear "Salda" en UI: usar `Brand.appName`. Cambiar branding = editar JSON +
  `dart run design_tokens:generate` (la CI comprueba que lo generado está al día).

## 4. Firebase

### Servicios y para qué (spec §12)

| Servicio | Uso | Estado |
|---|---|---|
| Auth | Google + Email (anfitrión), **Anónimo** (invitados), Apple (futuro iOS) | Sin configurar (M3) |
| Firestore | Todos los datos + tiempo real + offline. Región `europe-west1` | Reglas deny-all |
| Storage | Fotos de tickets (original ≤1600px + thumb 300px, generados on-device) | Reglas deny-all |
| Functions v2 | SOLO 3: `recompute` (calculadora autoritativa), `notify` (FCM), `cleanup` (borrado en cascada). TS, Node 22, `minInstances 0`, `maxInstances 3` | Esqueleto compila, sin funciones |
| Hosting | Web de invitados + dominio de deep links | Config lista, sin desplegar |
| App Check | Se activará **enforced** en Firestore/Storage/Functions | Pendiente M3/M4 |
| FCM | Push al anfitrión ("X ha pagado") | Pendiente M3 |
| Emulator Suite | Desarrollo local completo, proyecto `demo-salda` (sin credenciales) | Configurado en firebase.json |

**Proyectos:** `.firebaserc` define `default: demo-salda` (emuladores), `dev: salda-dev`,
`prod: salda-prod`. **Los proyectos reales NO existen todavía** — crearlos en M3 con la
cuenta Google del usuario (`firebase login`), activar Blaze con presupuesto de 5 €/mes y
alertas al 50/90/100 % + alertas de métricas (lecturas >25k/día etc., spec §12.4).

### Modelo de datos (implementarlo en M3 EXACTAMENTE como spec §7)

Raíz = **sesión** (una "cuenta independiente" es una sesión `kind: "single"`; la UI oculta
la capa). Resumen del árbol:

```
users/{uid}                      perfil, paymentMethods, aiPolicy (NUNCA API keys aquí)
users/{uid}/frequentPeople/{id}  personas frecuentes
sessions/{id}                    ownerUid, kind single|multi, shareCode (128 bits),
                                 status open|closed|archived, splitModeDefault,
                                 paymentMethodsSnapshot, agregados desnormalizados
                                 (totals, balances, computeVersion ← SOLO los escribe
                                 la function; los clientes solo leen)
  /participants/{pid}            name, isOwner, claimedByDevice
  /accounts/{aid}                "Hotel", category, totals (agregado)
    /tickets/{tid}               kind scanned|manual, merchant, paidByParticipantId,
                                 imagePath, ocr{engine,confidence}, totales, taxes[]
      /lines/{lid}               name, quantity(×1000), precios, assignment
                                 {type: unassigned|one|shared|all, participants{pid:peso}}
  /settlements/{sid}             from, to, amount, state pending|marked|confirmed,
                                 frozen (confirmada = congelada), stateHistory[]
  /activity/{eid}                feed append-only
Storage: receipts/{sessionId}/{ticketId}/original.jpg + thumb.jpg
Índices: sessions(ownerUid, updatedAt desc) y sessions(ownerUid, status, updatedAt desc)
```

### Reglas de seguridad: por qué están como están

Hoy `firestore.rules` y `storage.rules` son **deny-all a propósito**: no hay backend en
uso y la regla del proyecto es denegación por defecto con `allow` explícitos únicamente.
En M3 se implementa la **matriz de autorización de spec §13.2** (owner R/W si open;
invitado anónimo con shareCode: lectura + escrituras quirúrgicas con `diff()` — solo
autoasignarse líneas, solo marcar `pending→marked` en SUS liquidaciones, solo
`claimedByDevice`) **con un test por celda de la matriz (positivo y negativo) contra el
Emulator Suite en CI**. Es la pieza de seguridad más crítica del sistema. El shareCode
viaja en el fragment de la URL (`#k=`) para que no llegue a logs de servidor.

## 5. Servidores y comunicación

**No hay servidores propios.** Todo es serverless:

- **App Flutter ↔ Firestore**: SDK oficial, listeners en tiempo real, persistencia
  offline activada. Sin endpoints HTTP propios.
- **Web invitados ↔ Firestore**: Firebase JS modular (Auth anónimo + shareCode).
- **Cloud Functions**: SOLO triggers de Firestore (onWrite en lines/tickets/participants/
  settlements) y de borrado. **No exponen endpoints HTTP.** La app calcula en local
  (optimista, offline) y la function escribe el resultado autoritativo; convergen porque
  ambas implementaciones pasan los mismos vectores dorados.
- **IA (M6)**: llamadas directas dispositivo → API del proveedor (Claude/OpenAI/Gemini/
  DeepSeek/GLM/OpenRouter + genérico OpenAI-compatible con base URL para Ollama/LM Studio).
  Ninguna clave ni petición pasa por Firebase.

**Secretos y variables de entorno (ubicaciones, nunca valores):**
- API keys de IA de cada usuario → SOLO `flutter_secure_storage` (Keystore/Keychain) en el
  dispositivo. Nunca en Firestore, logs, crash reports ni en el backup JSON exportable.
- Config Firebase de la app (`google-services.json`, `GoogleService-Info.plist`,
  `firebase_options.dart`) → **gitignorados**; se generan con `flutterfire configure`
  en M3. No existen todavía.
- No hay `.env` en el repo. CI (GitHub Actions) no tiene secretos aún; cuando toque
  desplegar, usar Workload Identity Federation (no service account JSON en el repo).
- Credenciales gh/firebase CLI → keyring del sistema operativo del desarrollador.

## 6. Decisiones de diseño ya tomadas y su motivo

(Las 13 decisiones congeladas DC-1…DC-13 están en spec §0; aquí las operativas + motivo.)

1. **Flutter** — una base para APK+IPA, Material 3 de primera clase, ML Kit oficial.
2. **Web invitados = Svelte 5, NO Flutter Web** — Flutter Web pesa 1,5–2 MB (3–6 s en 4G)
   para una página que un invitado abre una vez desde WhatsApp; el bundle Svelte actual
   son 11 KB gzip. La duplicación de lógica se evita porque la web no calcula dinero.
3. **Sesión como raíz; cuenta suelta = sesión `single`** — un solo modelo/motor/reglas.
4. **Multi-pagador por ticket + BalanceEngine con simplificación de deudas** — sin esto,
   las sesiones (Edgar paga hotel, Alba gasolina) no funcionan. Con un solo pagador
   degenera exactamente en el modelo simple "todos pagan al anfitrión".
5. **Cloud Function autoritativa + cálculo local optimista + vectores dorados** — el
   invitado ve importes actualizarse sin que el anfitrión abra la app; el cliente no
   puede corromper agregados; la paridad Dart↔TS la garantiza la CI, no la disciplina.
6. **`Money` como extension type sobre int (céntimos)** — coste cero en runtime,
   imposible mezclar con int crudo, imposible `double` en dinero.
7. **Resto mayor (largest remainder) como única primitiva de redondeo** — Σ partes ==
   total EXACTO siempre, determinista (empates → índice menor).
8. **El SplitEngine reparte el grandTotal proporcionalmente al consumo en líneas** en vez
   de prorratear impuestos/descuentos/propina por separado — matemáticamente equivalente
   (DC-11) y elimina el error de redondeo acumulado.
9. **pub workspace nativo, sin melos** — Dart lo soporta de serie; menos herramientas.
10. **Tokens de diseño con codegen JSON → Dart + CSS** — app y web comparten identidad
    desde una sola fuente; la CI vigila que lo generado esté al día.
11. **Parser OCR: registry por país + perfiles por cadena + reglas ordenadas** — añadir
    país = clase nueva; añadir cadena = perfil; añadir formato = regla + caso de corpus.
    Detección de cadena también **por NIF** (sobrevive a cabeceras térmicas ilegibles).
12. **Confianza POR CAMPO + issues tipados + alternativas por línea** — la revisión
    manual resalta solo lo dudoso y corregir es 1 toque (chips de alternativas).
13. **IA como último recurso SIEMPRE** — orden fijo: ① repetir foto ② editar ③ IA.
    Nunca se lanza sola; botón deshabilitado hasta que haya proveedor configurado (M6).
14. **Cámara del sistema (image_picker) por ahora** — cubre el flujo completo sin custom
    UI; la captura guiada propia (bordes/auto-disparo) se hará con dispositivo real.
15. **l10n ARB desde M2** — deuda de RNF-05 saldada antes de que la UI creciera.
16. **`applicationId` Android provisional: `dev.salda.app`** — cambiable gratis hasta la
    primera publicación en Play. Recordarlo al llegar a ese punto.

## 7. Enfoques probados y descartados (NO repetir)

- **Flutter Web para invitados** (spec v1.0) → descartado por peso/latencia (ver #2).
- **v1 "sin Cloud Functions, todo en cliente"** → descartada al relajar el usuario el
  presupuesto a 1–5 €/mes: los agregados escritos por clientes exigían transacciones
  complejas y reglas frágiles, y el invitado no veía recalculos hasta que el anfitrión
  abría la app.
- **`node --test lib/test/` (directorio) en Windows** → el runner marca el directorio
  como test fallido. Usar glob: `node --test "lib/test/**/*.test.js"` (así está en
  backend/functions/package.json). No "simplificarlo".
- **`intl ^0.20.3`** → conflicto: flutter_localizations fija 0.20.2. Queda `^0.20.2`.
- **`synthetic-package` en l10n.yaml** → opción eliminada en Flutter actual; no añadirla.
- **Canonicalizar importes ANTES de extraer fecha/hora** → bug real: convierte la hora
  degradada "18.32" en el importe "18,32". El orden correcto (fecha/hora primero sobre
  líneas originales) está implementado en `EsReceiptParser.parse` con comentario.
- **pubspec.lock por app** → con pub workspace el único lockfile es el de la RAÍZ
  (los demás los borra pub). El .gitignore ya lo refleja.
- **Mapas const con céntimos crudos** (`{'b': 600}`) → no compila donde se espera
  `Map<String, Money>`; escribir `{'b': Money(600)}`.
- **Tests de widget de ReviewScreen con viewport por defecto (600px)** → la ListView es
  perezosa y el pie no se construye: los tests fijan `physicalSize` alto (2000px).

## 8. Estado actual exacto

### Terminado y verificado (112 tests en verde, analyze limpio)

- **M0**: monorepo completo, tema M3 desde tokens, CI, emuladores config, web placeholder.
- **M1**: `packages/domain` (Money/allocate, ShareCode, SplitEngine, BalanceEngine,
  DomainException) + espejo TS en `backend/functions/src/domain/` + 29 vectores dorados
  compartidos. 57 tests Dart (incluye propiedades sembradas) + 29 TS.
- **M2**: contrato `ReceiptExtraction` en domain (JSON roundtrip probado);
  `packages/ocr_parser` completo (geometría, normalización OCR, parser es con 10 perfiles
  de cadena y 7+2 reglas); corpus 13 casos → **12/12 mustPass verdes; métricas: casos
  completos 92 %, establecimiento/fecha/total/issues 100 %, líneas 92 %**; en la app:
  adaptador ML Kit, ScanService, pantalla de revisión editable con cuadre en vivo,
  hoja de edición con alternativas, banner DC-4, l10n ARB.

### A medias / pendiente de entorno

- **Botón "Continuar" de ReviewScreen es un no-op** — se conecta en M3 con la creación
  de sesión. `/review` sin draft cargado muestra spinner (deep link sin estado).
- **Botón "Analizar con IA" deshabilitado** hasta M6.
- **NUNCA probado en dispositivo real** (sin Android SDK): el OCR con fotos reales, la
  cámara y los permisos están sin verificar. El corpus actual son recreaciones realistas;
  debe crecer con tickets reales anonimizados (protocolo en test/corpus/README.md).
- **Captura guiada propia** (detección de bordes, auto-disparo) sin hacer — decidido
  hacerla cuando haya dispositivo.
- **Importar PDF** (RF-21) no implementado aún (la vía `parsePlainText` para PDFs con
  capa de texto ya existe en el parser). Hacerlo en M3-M5.
- **Firebase real inexistente**: sin proyectos, sin `flutterfire configure`, functions
  sin lógica, reglas deny-all.

### Últimos commits (main)

```
3aca453 M2: pipeline OCR completo con parser extensible y corpus de regresion
8ace6b4 M1: nucleo de dominio con motores validados por vectores dorados
eebeca0 M0 completado: app Flutter + verificacion en verde
e3804f3 M0: especificacion v2.0 congelada + cimientos del monorepo
```

La última sesión de trabajo (M2) tocó: `packages/domain` (receipt_extraction.dart nuevo +
export + test), `packages/ocr_parser` entero (nuevo), `apps/mobile` (pubspec deps ML Kit/
image_picker/intl/flutter_localizations, l10n.yaml + ARB + generated/, core/utils/
money_format.dart, features/scan/** y features/review/** nuevos, router y home
actualizados, review_screen_test.dart), y este CLAUDE.md.

## 9. Próximos pasos concretos (en orden)

1. **Preparar entorno para M3** (bloqueante): instalar Android Studio (trae JDK, que
   necesita el emulador de Firestore y el build Android) y el SDK de Android. Verificar
   `flutter doctor`. Probar la app en un dispositivo/emulador y el OCR con 3-4 tickets
   reales; añadir al corpus lo que falle.
2. **Crear proyectos Firebase** `salda-dev` y `salda-prod` (cuenta del usuario,
   `firebase login`): región europe-west1, Blaze + presupuesto 5 € + alertas (spec §12.4),
   `flutterfire configure` para la app (los json van gitignorados).
3. **M3 — Sesiones** (spec §7, §12.2, §13.2):
   a. Modelo Firestore (colecciones de spec §7) con `schemaVersion` desde el día 1.
   b. Reglas de seguridad = matriz §13.2 + **tests por celda** con Emulator Suite
      (`firebase emulators:exec`); añadir job `rules` a la CI.
   c. Functions: `recompute` (usa los motores TS ya existentes en src/domain/),
      `notify` (FCM), `cleanup`. Idempotentes, con `computeVersion`.
   d. App: Auth (Google+Email), repositorios Firestore en `apps/mobile/lib/data/`,
      flujo crear sesión (conectar el "Continuar" de la revisión), detalle de sesión
      (resumen/cuentas/actividad), personas frecuentes, compartir enlace+QR.
   e. Draft persistente del wizard (recuperar si la app muere a mitad).
4. **M4 — Invitados**: web Svelte real (¿quién eres? → resumen → elegir productos →
   ya he pagado), Auth anónimo + shareCode, tiempo real, botones de pago, App Check.
5. **M5 — Pulido**: PDF import/export, imagen-resumen WhatsApp, recordatorios, cierre/
   archivado, backup JSON (RF-90/91), estados vacíos/offline, haptics, beta.
6. **M6 — IA**: contrato + adaptadores (Claude, Gemini, openai_compatible primero),
   "Probar conexión", política de sugerencia por confianza < 0,75.

## 10. Cosas "raras" o no obvias (leer antes de romper algo)

- **Vectores dorados**: `packages/domain/test/golden/*.json` los ejecutan Dart Y TS.
  El ORDEN de las liquidaciones esperadas es parte del contrato (determinismo). Si un
  motor cambia, actualiza ambos lados; jamás "arregles" el JSON para que pase un test.
- **Corpus**: si un caso `mustPass: false` empieza a pasar, el harness FALLA a propósito
  (te obliga a promocionarlo a `true`). No es un bug.
- **`dart run design_tokens:generate`** tras tocar brand.json/design_tokens.json; los
  `.g.` van commiteados y la CI falla si no están al día (`git diff --exit-code`).
- **Los archivos generados de l10n** (`apps/mobile/lib/l10n/generated/`) van commiteados.
  Tras tocar el ARB: `flutter gen-l10n` en apps/mobile.
- **`Extracted<T>`**: `confidence` 0..1 por campo; `Extracted.missing()` para ausentes.
  `needsReview` = issues no vacíos O confianza global < 0,75 (umbral DC-13, calibrable).
- **quantityMilli**: cantidades ×1000 (pesables: 0,466 kg → 466). 1000 = una unidad.
- **ShareCode.toString() es opaco** a propósito (no filtrar secretos a logs). El código
  va en el **fragment** de la URL (`#k=`), no en query string.
- **Windows**: Flutter vive en `C:\dev\flutter` (PATH de usuario); primera ejecución
  compila la herramienta (minutos). PowerShell 5.1: sin `&&`; los timeouts largos de
  `flutter pub get`/`create` la primera vez son normales (descarga artefactos).
- **La web de invitados tiene presupuesto de peso**: `chunkSizeWarningLimit: 300` en
  vite.config.ts. Si un cambio lo dispara, replantear (lazy import de Firebase, etc.).
- **Functions**: `maxInstances: 3` y región europe-west1 están en setGlobalOptions como
  techo de coste (spec §12.4) — no subirlos sin consultar al usuario.
- **El smoke test de la app** compara contra `Brand.appName`/`Brand.tagline`: si se
  cambia el branding, el ARB `homeTagline` debe seguir en sincronía con brand.json.
- **GitHub**: repo privado `DaoeZ/salda` (creado al cierre de la sesión M2). El token de
  gh necesitó el scope `workflow` para poder subir `.github/workflows/ci.yml`.
