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

## Requisitos de desarrollo

- Flutter estable (`C:\dev\flutter` en esta máquina) · Node 20+ · Firebase CLI
- Android Studio / SDK de Android para compilar y ejecutar el APK

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

El contrato de unidades físicas y compatibilidad está en
[docs/REPARTO_POR_UNIDADES.md](docs/REPARTO_POR_UNIDADES.md). La separación de
branding, URLs y builds dev/release está en [docs/ENTORNOS.md](docs/ENTORNOS.md).
