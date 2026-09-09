# Capturas de validación

Tomadas en el **emulador** `Medium_Phone_API_36.1` (Android 16, 1080×2400)
con el APK de **profile** `app-x86_64-profile.apk`. No se instaló nada en el
dispositivo físico conectado.

| Archivo | Qué muestra |
|---|---|
| `01-login-claro.png` | Autenticación en claro: wordmark textual, jerarquía de titulares, campos con relleno tenue, botón principal y alternativas |
| `02-invitado.png` | Inicio de un invitado sin nombre: barra con wordmark y dos acciones, aviso fino anclado |
| `03-inicio-oscuro.png` | Lo mismo en oscuro: carbón con matiz verde, verde claro para la marca, estado vacío del sistema |
| `04-menu-oscuro.png` | El menú que sustituye a los ocho iconos de la barra |
| `05-ajustes-oscuro.png` | Ajustes: encabezados de sección, una superficie por bloque con líneas de un pelo, selector de tema |

Por qué **profile** y no release: el guardián de entornos
(`AppEnvironment.resolveHostingDomain`) prohíbe que una build *release* use
los enlaces de `salda-dev`, así que una release solo arranca contra
`salda-prod` — que en esta máquina no está configurada y que no se toca.
Profile compila AOT igual que release y sí usa el entorno de desarrollo.
