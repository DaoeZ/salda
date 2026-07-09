# Salda (nombre provisional) — guía para el desarrollo

## Referencia obligatoria

`docs/ESPECIFICACION.md` (v2.0) es la especificación **definitiva y congelada**. No se
rediseña arquitectura ni alcance; cualquier cambio importante se propone al usuario y se
registra como revisión del documento ANTES de implementarlo.

## Reglas de trabajo acordadas con el usuario (permanentes)

- Tomar automáticamente las decisiones menores (diseño, arquitectura, implementación)
  siguiendo mejores prácticas. Preguntar SOLO cuando afecte significativamente a
  funcionamiento, seguridad, coste o UX.
- Código limpio, modular, documentado; legibilidad > cleverness.
- No rehacer módulos terminados salvo motivo técnico importante.
- Al terminar cada fase (M0…M6), verificar que todo sigue funcionando antes de continuar
  (analyze + tests + builds).
- Si una librería deja de ser la mejor opción, proponer el cambio antes de aplicarlo.
- Idioma del usuario: español (UI en español; código e identificadores en inglés).

## Branding (provisional, intercambiable)

- Nombre de trabajo: **Salda** (de "saldar cuentas"). El usuario decidirá nombre/logo/dominio
  más adelante. TODO el branding vive en `packages/design_tokens/assets/brand.json` y se
  propaga por codegen — no hardcodear el nombre en UI, usar `Brand.appName`.
- `applicationId` Android provisional: `dev.salda.app` (cambiable sin coste hasta la
  primera publicación en Play; recordarlo al llegar a ese punto).

## Arquitectura (resumen operativo)

- Monorepo con **pub workspace** (pubspec raíz). Dependencias hacia dentro:
  `apps → packages`. `packages/domain` y `packages/ocr_parser` son Dart puro (prohibido
  importar Flutter/Firebase ahí).
- Dinero: SIEMPRE céntimos `int` (`Money`), jamás `double`.
- Motores (SplitEngine/BalanceEngine) existen en Dart y en TS (functions) y se validan
  contra los mismos **vectores dorados** (`packages/domain/test/golden/` ↔
  `backend/functions/test/golden` — mismos JSON). Si cambias un motor, cambia ambos.
- Web de invitados SIN lógica de dinero: solo pinta agregados calculados por la función.
- Firestore: agregados los escribe solo la Cloud Function; reglas = matriz §13.2 de la spec.
- API keys de IA: solo `flutter_secure_storage`; nunca en Firestore, logs ni backups.

## Estado del desarrollo (actualizar al cerrar cada fase)

- [x] Especificación v2.0 congelada
- [ ] M0 Cimientos (en curso)
- [ ] M1 Dominio · [ ] M2 OCR · [ ] M3 Sesiones · [ ] M4 Invitados · [ ] M5 Pulido · [ ] M6 IA

## Entorno de esta máquina (Windows 11)

- Flutter en `C:\dev\flutter` (añadido al PATH de usuario). Node 26. Firebase CLI global.
- SDK de Android: PENDIENTE de instalar (necesario para `flutter run`/APK; no bloquea
  analyze/tests). Sugerir Android Studio al usuario cuando toque probar en dispositivo.
- Emuladores Firebase: `firebase emulators:start` (proyecto `demo-salda`, sin credenciales).

## Comandos de verificación por fase

```
dart pub get                                    # raíz: resuelve workspace
dart analyze packages apps/mobile               # estático
dart test packages/domain packages/ocr_parser   # motores
cd apps/mobile && flutter test                  # app
cd apps/guest_web && npm run build              # web
cd backend/functions && npm run build           # functions
firebase emulators:exec --project demo-salda "npm --prefix backend/firestore test"  # reglas (desde M3)
```
