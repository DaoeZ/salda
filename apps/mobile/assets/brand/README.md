# Assets de marca

El símbolo definitivo de Salda **no está aprobado todavía**. Este directorio
es el único punto por el que entrará, para que sustituirlo no obligue a tocar
ni una pantalla.

## Qué hay ahora

Nada. La app usa el **wordmark textual** «Salda» (`Brand.appName`, generado
desde `packages/design_tokens/assets/brand.json`) en la barra de Inicio y en
las pantallas de autenticación, y el icono de lanzador **por defecto de
Flutter**. Es deliberado: no se redibuja un símbolo a partir de una captura
comprimida ni se inventa uno provisional que después haya que desaprender.

## Qué archivos hay que colocar aquí cuando el símbolo esté aprobado

| Archivo | Para qué | Requisitos |
|---|---|---|
| `salda_symbol.svg` | Símbolo a color, uso general | Vectorial, sin texto trazado |
| `salda_symbol_mono.svg` | Versión monocroma | Una sola forma, sin degradados; hereda `currentColor` |
| `salda_adaptive_foreground.svg` | Capa delantera del Adaptive Icon | Lienzo 108×108 dp con el símbolo dentro de los 66 dp centrales (zona segura) |
| `salda_wordmark.svg` | Wordmark, si llega a existir uno dibujado | Hasta entonces manda el texto |

El **fondo** del Adaptive Icon NO es un archivo: es el color
`@color/saldaLauncherBackground`, ya declarado en
`android/app/src/main/res/values/colors.xml` y tomado del token `primary`.
Así el fondo del icono no puede separarse de la paleta.

El **splash** ya usa `@color/saldaBackground` (token `background`, con su
variante de noche). Cuando exista el símbolo, se añade como capa `bitmap`
centrada en `drawable*/launch_background.xml`.

## Pasos exactos de sustitución

1. Copiar los SVG aquí.
2. Exportar el foreground a PNG por densidad (`mdpi` 108 px … `xxxhdpi` 432 px)
   en `android/app/src/main/res/mipmap-*/ic_launcher_foreground.png`.
3. Descomentar el `<foreground>` de
   `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`.
4. Regenerar los `ic_launcher.png` heredados para Android < 8.
5. Declarar `assets/brand/` en `pubspec.yaml` solo si alguna pantalla llega a
   pintar el SVG desde Dart (hoy ninguna lo hace, y añadir un renderizador de
   SVG es una dependencia que aún no hace falta).

Mientras tanto, `SaldaWordmark` (`core/ui/wordmark.dart`) es el ÚNICO sitio
donde se decide cómo se representa la marca en pantalla: cuando haya símbolo,
se cambia ahí y aparece en todas partes a la vez.
