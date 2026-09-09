# Salda *(nombre provisional)*

Divide gastos con amigos escaneando tickets. OCR on-device + IA opcional multi-proveedor.
App Flutter (Android/iOS) + web ligera para invitados (Svelte) + Firebase.

> **Especificación oficial y congelada:** [docs/ESPECIFICACION.md](docs/ESPECIFICACION.md) (v2.0).
> El branding es provisional y está centralizado en `packages/design_tokens/assets/brand.json`.

## Estructura del monorepo

```
packages/design_tokens   Fuente única de diseño (JSON) → genera Dart + CSS
packages/domain          Entidades y motores de dinero (Dart puro, sin Flutter)
packages/ocr_parser      Parser de tickets españoles (Dart puro)
packages/ai_providers    Contrato + adaptadores de proveedores de IA
apps/mobile              App Flutter del anfitrión (Android + iOS)
apps/guest_web           Web de invitados (Svelte 5 + Vite + TS)
backend/functions        Cloud Functions v2 (TypeScript)
backend/firestore        Reglas de seguridad, índices y sus tests
docs/                    Especificación del proyecto
```

## Empezar en un ordenador nuevo

Guía completa: **[docs/SETUP_NUEVO_ORDENADOR.md](docs/SETUP_NUEVO_ORDENADOR.md)**.

```bash
git clone https://github.com/DaoeZ/salda.git && cd salda
pwsh scripts/bootstrap-windows.ps1     # Windows
./scripts/bootstrap.sh                 # Linux / macOS
```

> La **keystore de desarrollo y sus contraseñas no están en Git** y hay que
> copiarlas aparte. Sin ellas el proyecto compila y los tests pasan, pero los
> APK salen con otro certificado, y eso rompe Google Sign-In, los App Links y
> la actualización sobre la app instalada.
> `pwsh scripts/verify-signing-key.ps1` lo comprueba.

## Requisitos de desarrollo

Versiones fijadas en `.fvmrc`, `.nvmrc`, `.java-version` y `.tool-versions`:

- Flutter 3.44.8 · JDK 17 (Temurin, apuntado por `JAVA_HOME`) · Node 22 · Firebase CLI
- Android Studio / SDK de Android (compileSdk 36, minSdk 24) para compilar el APK

## Comandos habituales

```bash
dart pub get                         # resuelve el workspace completo (desde la raíz)
dart run design_tokens:generate      # regenera tokens Dart + CSS tras editar el JSON
cd apps/mobile && flutter run        # app móvil
cd apps/guest_web && npm run dev     # web de invitados
firebase emulators:start             # backend local completo (proyecto demo-salda)
```

## Firebase

Dos proyectos: `salda-dev` y `salda-prod` (ver `.firebaserc`). El desarrollo local usa
la Emulator Suite con el proyecto `demo-salda` (no requiere proyecto real ni credenciales).

La política de identidad, conversión de invitados, configuración de Google y rollout
de App Check se documentan en [docs/AUTENTICACION.md](docs/AUTENTICACION.md).

El contrato canónico de solicitudes y amistades está en
[docs/AMISTADES.md](docs/AMISTADES.md).

El contrato de unidades físicas y compatibilidad está en
[docs/REPARTO_POR_UNIDADES.md](docs/REPARTO_POR_UNIDADES.md). La separación de
branding, URLs y builds dev/release está en [docs/ENTORNOS.md](docs/ENTORNOS.md).
