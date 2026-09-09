# Montar Salda en un ordenador nuevo

Guía completa para pasar de un ordenador vacío a un entorno de trabajo
idéntico al actual: mismo código, mismas versiones y **exactamente la misma
firma de desarrollo**.

> **Lo único que no viaja por Git es la clave de firma y las contraseñas.**
> Sin ellas el proyecto compila y los tests pasan, pero los APK salen con
> otro certificado y eso rompe tres cosas a la vez (§4). El repositorio
> contiene todo lo demás.

---

## 0. Lo que hay que llevar aparte

Cópialo a mano —USB, disco cifrado o gestor de contraseñas—, **nunca por
Git ni por correo**:

| Qué | Dónde está hoy | Dónde va en el ordenador nuevo |
|---|---|---|
| `salda-dev.jks` | `C:\Users\<usuario>\.salda\salda-dev.jks` | la ruta que decidas, **fuera del repo** |
| Contraseñas del keystore y de la clave | gestor de contraseñas | dentro de `dev-keystore.properties` |

El respaldo preparado para este traslado está en la carpeta
`salda-private-backup/`, **fuera del repositorio**, con su propio
`RESTAURAR.md` y los checksums. Verifica el SHA-256 del `.jks` al llegar:
si no coincide, el archivo se ha corrompido y **no** debes usarlo.

---

## 1. Clonar

```bash
git clone https://github.com/DaoeZ/salda.git
cd salda
git checkout codex/relations-groups-navigation
```

La rama de trabajo actual es `codex/relations-groups-navigation`, no `main`.

---

## 2. Herramientas y versiones

Las versiones están fijadas en archivos del repositorio para que no haya dos
fuentes de verdad. **El objetivo es reproducir el entorno actual, no
modernizarlo**: no subas ninguna versión «porque hay una más nueva».

| Herramienta | Versión | Fijada en | Por qué esa |
|---|---|---|---|
| Flutter | 3.44.8 (stable) | `.fvmrc` | La que compiló y verificó todo lo que hay |
| Dart | 3.12.2 | viene con Flutter | — |
| JDK | **17** (Temurin) | `.java-version` | Lo que exige el Android Gradle Plugin; es el que lee `JAVA_HOME` |
| Gradle | 9.1.0 | `apps/mobile/android/gradle/wrapper/gradle-wrapper.properties` | El wrapper lo descarga solo |
| Android Gradle Plugin | 9.0.1 | `apps/mobile/android/settings.gradle.kts` | — |
| Kotlin | 2.3.20 | `apps/mobile/android/settings.gradle.kts` | — |
| Android SDK | compileSdk 36 · targetSdk 36 · minSdk 24 | los fija Flutter | — |
| Node | serie 22 | `.nvmrc` | La que usa la CI. La 24 también funciona en local |
| npm | 11.x | — | El que traiga Node |
| Firebase CLI | 15.24.0 | — | `npm i -g firebase-tools` |
| JDK para el emulador de Firestore | 21 | `.github/workflows/ci.yml` | Solo lo necesita el emulador |

`.tool-versions` recoge las tres primeras en formato asdf/mise por si usas
un gestor de versiones.

> **Ojo con `JAVA_HOME`.** Gradle usa `JAVA_HOME`, no el `java` del `PATH`.
> Si `JAVA_HOME` apunta a un JDK 21 y el `PATH` a un 17 (o al revés) los
> síntomas son confusos. `scripts/bootstrap-windows.ps1` lo comprueba.

Qué instalar, en este orden:

1. **Git**
2. **Flutter 3.44.8** — descomprimir y añadir `<flutter>\bin` al `PATH`
3. **JDK 17 Temurin** — y definir `JAVA_HOME`
4. **Android Studio** (o solo el SDK) — instalar plataforma 36 y build-tools,
   aceptar licencias con `flutter doctor --android-licenses`, y definir
   `ANDROID_HOME`
5. **Node 22** y **npm**
6. **Firebase CLI**: `npm i -g firebase-tools`

FlutterFire CLI **no hace falta**: `apps/mobile/lib/firebase_options.dart`
está versionado y no se regenera en el día a día.

---

## 3. Restaurar lo privado

### 3.1 El keystore

Copia `salda-dev.jks` a su sitio, por ejemplo `C:\Users\<usuario>\.salda\`.
**Fuera del repositorio**, siempre.

### 3.2 `dev-keystore.properties`

```bash
cp apps/mobile/android/dev-keystore.properties.example \
   apps/mobile/android/dev-keystore.properties
```

Y rellena los cuatro campos:

```properties
storeFile=C:/Users/<usuario>/.salda/salda-dev.jks
storePassword=<la del gestor de contraseñas>
keyAlias=salda-dev
keyPassword=<la del gestor de contraseñas>
```

Está en `.gitignore`. **Nunca** lo commitees.

En CI o entornos cloud puedes usar variables en su lugar:
`SALDA_DEV_KEYSTORE`, `SALDA_DEV_KEYSTORE_PASSWORD`, `SALDA_DEV_KEY_ALIAS`,
`SALDA_DEV_KEY_PASSWORD`. El archivo tiene prioridad sobre las variables.

### 3.3 Comprobarlo antes de nada

```bash
pwsh scripts/verify-signing-key.ps1
```

Debe terminar con **«La firma es la correcta»**. Si no, para y resuélvelo:
compilar con otra clave estropea más de lo que arregla (§4).

### 3.4 Firebase

```bash
firebase login
firebase use dev          # alias de salda-dev, definido en .firebaserc
firebase use              # confirma cuál está activo
```

Los alias son: `default` → `demo-salda` (emuladores), `dev` → `salda-dev`,
`prod` → `salda-prod`. **Nunca trabajes con `prod` activo.**

No hace falta ninguna credencial administrativa ni cuenta de servicio.

---

## 4. Por qué la firma es intocable

El certificado actual es:

```
titular   CN=Salda Development, OU=Desarrollo, O=Salda, L=Madrid, C=ES
alias     salda-dev
SHA-1     AC:DA:85:11:0B:FF:BA:AC:20:0C:4B:CA:C4:D6:7F:40:CB:67:78:C5
SHA-256   A8:44:AB:39:C7:D5:F6:EC:E5:6A:BC:A8:70:EF:86:54:68:FC:E0:53:71:9A:86:0A:60:40:3D:FE:27:A9:A0:F4
válido    26/07/2026 → 18/07/2056
```

Un certificado distinto rompe **tres cosas a la vez**, y ninguna avisa con
claridad:

1. **Google Sign-In** falla con `DEVELOPER_ERROR`. El cliente OAuth de
   Android se autoriza por (paquete + SHA-1); una huella nueva no está
   registrada en Firebase. El selector de cuentas aparece igual, pero al
   elegir una se vuelve al login sin explicación.
2. **Los App Links dejan de abrir la app.** Se verifican contra el SHA-256
   publicado en `apps/guest_web/public/.well-known/assetlinks.json`. Los
   enlaces de grupo (`/g/…`) y de ticket (`/t/…`) se quedarían en la web.
3. **Android trata el APK como otra aplicación.** No se instala encima de la
   que ya está: hay que desinstalar, y con ello se pierde la identidad local
   del invitado, que vive en el almacenamiento de la app.

Por eso `apps/mobile/android/app/build.gradle.kts` **detiene el ensamblado**
si no encuentra la firma compartida, en vez de caer en silencio al
`~/.android/debug.keystore` que Gradle genera en cada máquina.

**Prohibido**: generar una keystore nueva, cambiar el alias, cambiar el
`applicationId` (`dev.salda.salda_mobile`), subir el `.jks` a Git.

---

## 5. Instalar dependencias

Todo de una vez:

```bash
pwsh scripts/bootstrap-windows.ps1      # Windows
./scripts/bootstrap.sh                  # Linux / macOS
```

Comprueba herramientas, instala dependencias, verifica la firma y ejecuta el
análisis estático. No despliega nada.

A mano sería:

```bash
flutter pub get                         # workspace entero, desde la raíz
npm ci --prefix apps/guest_web
npm ci --prefix backend/functions
npm ci --prefix backend/firestore
```

`npm ci` y no `npm install`: respeta los lockfiles en vez de reescribirlos.

---

## 6. Validar

Ejecútalos **todos** antes de dar nada por bueno:

```bash
dart analyze --fatal-infos                                  # desde la raíz
cd packages/domain && dart test
cd packages/ocr_parser && dart test
cd apps/mobile && flutter test
npm --prefix backend/functions test
npm --prefix apps/guest_web run build
firebase emulators:exec --only firestore --project demo-salda "npm --prefix backend/firestore test"
```

Referencia actual (27/07/2026): dominio 121 · ocr_parser 22 · app 438 ·
functions 140 · Rules 286 · análisis sin avisos.

Si el emulador se queja de que el **puerto 8080 está ocupado**, ha quedado un
proceso `java` de una ejecución anterior. En Windows:

```powershell
Get-NetTCPConnection -LocalPort 8080 -State Listen | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }
```

---

## 7. Generar APKs

Exactamente esto:

```bash
flutter build apk --debug --split-per-abi
```

Produce tres, en `apps/mobile/build/app/outputs/flutter-apk/`:

- `app-arm64-v8a-debug.apk` — el de cualquier móvil moderno
- `app-armeabi-v7a-debug.apk`
- `app-x86_64-debug.apk`

Y verifica el arm64:

```bash
pwsh scripts/verify-signing-key.ps1 -Apk apps/mobile/build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk
```

o directamente:

```bash
apksigner verify --verbose --print-certs apps/mobile/build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk
```

El SHA-256 del certificado debe ser el de §4.

**No generes `app-release.apk` con `-PallowDebugSigning=true`.** Produce un
artefacto no publicable y confunde: parece una release y no lo es.

> **Si vienes de compilar en otro modo, `flutter clean` primero.** Un
> directorio `build/` que ya tuvo una compilación *release* deja artefactos
> que se cuelan en el APK de depuración: medido, 147,9 MB frente a los
> 115,8 MB de una compilación limpia, con el mismo código y la misma firma.
> No rompe nada, pero desconcierta al comparar tamaños o checksums.
>
> Los APK de depuración **no son reproducibles byte a byte**: incrustan rutas
> absolutas y marcas de tiempo, así que dos compilaciones del mismo commit
> difieren en unos cientos de bytes. Lo que sí debe coincidir siempre es el
> **certificado**, y eso es lo que verifica el script.

---

## 8. Firebase: el código local NO es lo que está activo

Esto ya costó una sesión entera de depuración: hubo una corrección cuyo
código local era correcto, pero **las Firestore Rules no estaban
desplegadas**, así que la app seguía fallando en el dispositivo. El
repositorio es la fuente de verdad *local*; el proyecto de Firebase tiene su
propia copia y **no se sincronizan solas**.

Antes de validar una APK, pregúntate si el cambio toca algún recurso remoto:

| Cambias… | ¿Hay que desplegar? | Comando |
|---|---|---|
| Firestore Rules | **Sí** | `firebase deploy --only firestore:rules --project salda-dev` |
| Firestore Indexes | **Sí** | `firebase deploy --only firestore:indexes --project salda-dev` |
| Storage Rules | **Sí** | `firebase deploy --only storage --project salda-dev` |
| Cloud Functions | **Sí** | `firebase deploy --only functions --project salda-dev` |
| Hosting / web de invitados / `assetlinks.json` | **Sí** | `firebase deploy --only hosting --project salda-dev` |
| Solo código Dart de la app | No | — |

Reglas de la casa:

- **Siempre `--project salda-dev`.** Nunca `salda-prod` sin una ventana de
  promoción explícita.
- **Verifica después de desplegar**, no te fíes del «Deploy complete!».
  Para las Rules basta con comparar el ruleset publicado con el archivo local
  (mismo número de líneas y mismo hash), o abrir la consola de Firebase.
- Los tests del emulador cargan el archivo **local**, así que pasar en verde
  no demuestra que lo desplegado sea eso mismo.

---

## 9. Qué NO está en Git, y por qué

| Archivo | Motivo |
|---|---|
| `apps/mobile/android/dev-keystore.properties` | contraseñas |
| `apps/mobile/android/key.properties` | contraseñas (clave de Play; hoy no existe) |
| `*.jks`, `*.keystore`, `*.p12`, `*.pfx`, `*.pem` | claves privadas |
| `apps/mobile/android/local.properties` | ruta del SDK, propia de cada máquina; la genera Flutter |
| `google-services.json`, `GoogleService-Info.plist` | no se usan: la config de cliente va en `firebase_options.dart` (ADR-016) |
| `serviceAccount*.json` | credenciales administrativas; el proyecto no las necesita |
| `node_modules/`, `build/`, `.dart_tool/`, `dist/` | artefactos regenerables |
| `salda-private-backup/` | el respaldo de traslado, que vive fuera del repo |

Sí están versionados, y **no son secretos**: `firebase_options.dart` y
`apps/guest_web/.env.salda-dev`. Contienen la API key *de cliente* de
Firebase, que es pública por diseño —viaja en cada APK y en cada página— y
cuya seguridad la dan las Rules y App Check, no el secreto (ADR-016).

---

## 10. Si algo falla

| Síntoma | Causa habitual |
|---|---|
| Gradle: «Firma de desarrollo COMPARTIDA no configurada» | falta `dev-keystore.properties` o la ruta del `.jks` es incorrecta |
| Google Sign-In → `DEVELOPER_ERROR` | estás firmando con otra clave: ejecuta `verify-signing-key.ps1` |
| Un enlace `/g/` o `/t/` abre la web en vez de la app | firma distinta, o `assetlinks.json` sin desplegar |
| «no se puede instalar»: hay que desinstalar antes | firma distinta |
| `permission-denied` en el dispositivo con código correcto | Rules no desplegadas en `salda-dev` (§8) |
| `flutter pub get` no encuentra `domain` | ejecútalo desde la **raíz**: es un pub workspace |
| Puerto 8080 ocupado | proceso `java` del emulador anterior (§6) |
