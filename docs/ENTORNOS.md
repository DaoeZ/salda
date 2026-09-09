# Entornos, branding y enlaces

## Branding visible

El nombre comercial mostrado es **Salda**. El proyecto Flutter y los package IDs
pueden conservar nombres técnicos como `salda_mobile`; no son branding visible.
Android usa `android:label="Salda"` y la app obtiene su título desde los tokens.

La fuente única es `packages/design_tokens/assets/brand.json`. El generador
produce las constantes Dart, CSS y TypeScript; no deben editarse a mano.

## Enlaces compartidos

| Build | Dominio |
|---|---|
| Flutter debug/desarrollo | `salda-dev.web.app` |
| Flutter release/producción | `salda-prod.web.app` |
| Web desplegable en dev | Firebase `salda-dev` |
| Web de producción | Firebase `salda-prod`, configuración aún no instalada ni desplegada en esta tarea |

Flutter selecciona el dominio en `AppEnvironment`. Se puede elegir con
`--dart-define=SALDA_ENV=development|production` y, para un dominio propio,
`--dart-define=SALDA_HOSTING_DOMAIN=dominio`. Una build release falla al arrancar
si el dominio resuelto es el de `salda-dev`.
Además, el arranque compara el proyecto de `FirebaseOptions` con el subdominio
de Hosting y aborta si no pertenecen al mismo entorno. La configuración móvil
commiteada sigue siendo `salda-dev`; por tanto una release de producción no será
operativa hasta generar e integrar las opciones de `salda-prod`, evitando una
release híbrida que comparta prod pero escriba en dev.

La web usa dos comandos separados:

```text
npm run build             # build salda-dev; usado por CI y deploy dev
npm run build:production  # exige configuración explícita de salda-prod
```

La configuración pública de dev vive en `.env.salda-dev`. Para producción se
copia `.env.production.example` a `.env.production.local` y se completan los
valores públicos de la app web de `salda-prod`. Vite aborta el build de
producción si detecta `salda-dev` o si no existe configuración explícita.

No se ha cambiado ni desplegado producción. El dominio por defecto
`salda-prod.web.app` es el destino configurado, pero debe considerarse no
validado hasta completar la configuración web, desplegar y ejecutar una prueba
real de invitado.

## Firma de desarrollo compartida (BUG-1)

**El problema.** Cada máquina genera su propio `~/.android/debug.keystore`, así
que el APK sale con un SHA-1 distinto en cada entorno. Google Sign-In autoriza
por **(package name + SHA-1)**, de modo que solo funcionaba donde esa huella
estuviera registrada en Firebase; en el resto fallaba con `DEVELOPER_ERROR`
(`ApiException: 10`). Lo mismo rompe los App Links, que Android verifica
contra el SHA-256 publicado en `assetlinks.json`.

**La regla.** Todos los entornos autorizados firman desarrollo con el **mismo**
certificado. Ni la keystore ni las contraseñas entran nunca en Git.

### Preparar un entorno

1. Consigue la keystore compartida del equipo. **No la generes tú**: si cada
   entorno crea la suya, vuelve exactamente el problema que esto arregla.
   Se transmite por un canal seguro (gestor de contraseñas o almacenamiento
   cifrado), nunca por chat ni por correo.

   **Certificado vigente** (creado el 2026-07-26, validez 30 años):

   | | |
   |---|---|
   | Alias | `salda-dev` |
   | SHA-1 | `AC:DA:85:11:0B:FF:BA:AC:20:0C:4B:CA:C4:D6:7F:40:CB:67:78:C5` |
   | SHA-256 | `A8:44:AB:39:C7:D5:F6:EC:E5:6A:BC:A8:70:EF:86:54:68:FC:E0:53:71:9A:86:0A:60:40:3D:FE:27:A9:A0:F4` |

   Ambas huellas están registradas en la app Android de `salda-dev`
   (`1:923355592259:android:024e3c6d1eab95bfbac6f6`) y el SHA-256 está
   publicado en `assetlinks.json`. Es el **certificado definitivo** de
   desarrollo.
2. Guárdala **fuera del repositorio**:
   - Windows: `C:\Users\<usuario>\.salda\salda-dev.jks`
   - Linux/macOS: `~/.salda/salda-dev.jks`
3. Configúrala, de una de estas dos formas:

   **Archivo** (recomendado en portátiles). Copia
   `apps/mobile/android/dev-keystore.properties.example` a
   `dev-keystore.properties` —gitignorado— y rellena `storeFile`,
   `storePassword`, `keyAlias` y `keyPassword`.

   **Variables de entorno** (CI, Codex y entornos cloud, donde no conviene
   dejar el archivo escrito):

   ```bash
   export SALDA_DEV_KEYSTORE=/ruta/salda-dev.jks
   export SALDA_DEV_KEYSTORE_PASSWORD=...
   export SALDA_DEV_KEY_ALIAS=salda-dev
   export SALDA_DEV_KEY_PASSWORD=...
   ```

   En CI, la keystore se materializa desde un secreto codificado en base64 y
   se borra al terminar el job. El archivo tiene prioridad sobre las
   variables.

### Qué pasa si falta

`assemble*`, `bundle*`, `install*` y `package*` **fallan con un mensaje
explícito**. No hay caída silenciosa a la keystore local: un APK firmado con
otro certificado es justamente el bug.

Lo que **no** necesita firma y sigue funcionando en un clon recién hecho:
`flutter test`, `dart analyze`, `gradlew signingReport` y cualquier tarea que
no produzca artefacto. Si necesitas un APK local a sabiendas de que Google
Sign-In no funcionará, existe una salida explícita:
`flutter build apk --debug -PallowLocalDebugKeystore=true`.

### Comprobar que tu entorno firma bien

```bash
cd apps/mobile/android && ./gradlew signingReport
```

Debe decir **`Config: dev`** y apuntar a la keystore compartida. Si dice
`Config: debug` con `Store: ~/.android/debug.keystore`, tu entorno **no** está
configurado y Google Sign-In fallará.

Para verificar el APK ya compilado:

```bash
apksigner verify --print-certs build/app/outputs/flutter-apk/app-debug.apk
```

El SHA-256 debe coincidir con el de `signingReport` y con el publicado en
`assetlinks.json`.

### Registrar las huellas en salda-dev

Una sola vez, con las huellas de la keystore compartida:

```bash
firebase apps:android:sha:create <appId> <sha1> --project salda-dev
```

La app Android de `salda-dev` para `dev.salda.salda_mobile` es
`1:923355592259:android:024e3c6d1eab95bfbac6f6`. Consulta lo registrado con
`firebase apps:android:sha:list <appId> --project salda-dev`. **No borres las
huellas antiguas** hasta confirmar que ningún APK instalado depende de ellas.

`assetlinks.json` publica hoy **tres** SHA-256:

- `A8:44:AB:39:…` — el del certificado compartido. **Es el definitivo.**
- `FD:13:54:A4:…` y `AC:1A:4A:6A:…` — certificados anteriores, ya registrados
  en `salda-dev`, que se conservan **temporalmente** para que los APK
  instalados antes de la unificación sigan verificando sus App Links.

Retira esos dos cuando confirmes que no queda ninguna instalación con ellos.
Un APK firmado con un certificado distinto **no se puede actualizar sobre
otro**: hay que desinstalar antes.

### Rotar el certificado de desarrollo

1. Generar la nueva keystore y distribuirla.
2. Añadir sus SHA-1 y SHA-256 en `salda-dev` **sin quitar los antiguos**.
3. Añadir el nuevo SHA-256 a `assetlinks.json` y desplegar Hosting.
4. Que todos los entornos actualicen su configuración y reinstalen.
5. Solo entonces, retirar las huellas viejas.

### Nunca en Git

`dev-keystore.properties`, `key.properties`, `*.jks`, `*.keystore`,
`google-services.json` y cualquier contraseña. Todos están en `.gitignore`;
el repositorio solo contiene las **plantillas** `.example`.
