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
