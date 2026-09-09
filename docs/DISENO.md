# Sistema visual de Salda

> Fuente única: `packages/design_tokens/assets/design_tokens.json` →
> `dart run design_tokens:generate` → `tokens.g.dart` (app) y `tokens.g.css`
> (web de invitados). Ningún color, tamaño o radio se escribe a mano en una
> pantalla.

## Concepto

Salda reparte dinero entre gente que se conoce. La interfaz tiene que ser
**precisa y tranquila**: un importe se comprueba de un vistazo y una deuda no
debería dar ansiedad. De ahí las tres decisiones que gobiernan todo lo demás:

1. **La jerarquía la dan la superficie y el borde, nunca la sombra.** No hay
   elevación en ninguna parte: ni tarjetas, ni barra, ni hojas, ni el botón
   principal. Una herramienta de dinero con sombras profundas parece ruidosa.
2. **Una superficie por bloque.** Las filas se separan con líneas de un pelo
   dentro de UNA tarjeta (`SaldaCardList`), en vez de una tarjeta por fila.
   Anidar tarjetas está prohibido: si un bloque pide otra caja, lo que
   necesita es un encabezado de sección.
3. **El color nunca es el único portador de significado.** Cada estado lleva
   además rótulo, signo o forma: «A tu favor» junto al verde, «+» en el
   importe, círculo o cuadrado en el avatar según sea persona o contexto.

## Tema

`AppTheme` **no** usa `ColorScheme.fromSeed`. Una semilla reparte tonos por
algoritmo y produce justo lo que hay que evitar: Material sin personalizar.
Cada rol se declara en el JSON y se elige a mano, de modo que **claro y
oscuro están diseñados los dos**, no uno derivado del otro.

Los roles viven en la `ThemeExtension` `SaldaColors`, accesible como
`context.salda`. Que sean parte del tema —y no constantes sueltas— es lo que
impide que el modo oscuro se quede a medias por un color escrito a mano.

### Roles

`background · surface · surfaceElevated · surfaceMuted · border ·
borderStrong · textPrimary · textSecondary · textMuted · primary · onPrimary ·
primaryMuted · accent · accentMuted · positive · positiveMuted · negative ·
negativeMuted · warning · pending · disabled · overlay · skeleton · focus`

Verde bosque como principal; naranja cálido como acento **muy** controlado
(nunca dominante); fondos claros templados, no blanco azulado; oscuros carbón
con matiz verde, no negro absoluto; rojo solo para error, deuda en contra y
acciones destructivas; amarillo solo para pendiente o advertencia.

El contraste está **probado**, no supuesto: `design_system_test.dart` exige
≥7:1 para el texto principal sobre el fondo y ≥4,5:1 para el secundario sobre
la superficie, en los dos modos.

## Tipografía

`display · pageTitle · sectionTitle · cardTitle · body · bodyStrong · label ·
caption · moneyLarge · moneyMedium · moneySmall`, cada una con tamaño, peso,
tracking y altura de línea propios, mapeados sobre los slots de Material para
que cualquier widget herede ya la jerarquía correcta.

**No se empaqueta una fuente de terceros.** El token declaraba «Inter» sin que
ningún asset la cargara: la app caía en la fuente del sistema fingiendo que no
lo hacía. Ahora `fontFamily` es `null` a propósito y se usa la pila del
sistema (Roboto en Android), que además trae cifras tabulares. El carácter lo
dan el peso, el tamaño y el tracking, no una tipografía de novedad — y así no
entra ni una dependencia ni un binario al repositorio.

### Dinero

`MoneyText` es el único camino para pintar un importe: cifras tabulares
(`tnum`) para que las columnas se alineen entre filas, `softWrap: false` para
que «1.234,56 €» nunca parta, y tamaño elegido por el sistema. El neto se
muestra en valor absoluto con el sentido en el rótulo: un menos delante se
confunde con un guion.

## Espaciado y forma

Escala `4 · 8 · 12 · 16 · 20 · 24 · 32 · 40`. Radios con intención y pocos:
`control/field/button 10` para campos y controles, `card 14` para superficies,
`sheet 24` solo para hojas y diálogos, `pill` exclusivamente para avatares
circulares. Nada de un radio distinto por widget.

## Componentes

`core/ui/` — pequeños y sin abstracciones grandes:

| Fichero | Qué aporta |
|---|---|
| `surfaces.dart` | `SaldaCard`, `SaldaCardList`, `SectionHeader`, `ScreenBody`, `SectionGap` |
| `money_text.dart` | `MoneyText` con tamaño y signo semánticos |
| `badges.dart` | `StatusBadge`, `SaldaAvatar`, `ToneDot` |
| `states.dart` | `EmptyState`, `ErrorStateView`, `Skeleton`, `SkeletonList` |
| `notice.dart` | `Notice`, aviso fino anclado bajo la barra |

`SaldaCard` se apoya en `Material` y no en `DecoratedBox`: cualquier
`ListTile` o `InkWell` dentro necesita un Material ancestro para pintar su
fondo y su tinta, y con una caja decorada quedaban invisibles.

## Carga y errores

Nunca un aro girando en el centro cuando ya se conoce la estructura: se pinta
un `SkeletonList` del tamaño de lo que va a llegar, así nada salta de sitio.
Los errores se cuentan en lenguaje de producto y **jamás** enseñan la
excepción, un UID, una ruta ni un código; eso va a la consola.

Un caso concreto: mientras el título de una relación no está resuelto, la
frase de actividad usa un sujeto neutro. Antes se leía «Has creado » con un
hueco, y el relleno obvio —el nombre persistido— es justo el que no vale.

## Identidad

El símbolo definitivo **no está aprobado**, así que ninguna pantalla se apoya
en él: se usa el wordmark textual «Salda» leído de `brand.json`. Cuando haya
asset definitivo, entra por ahí sin tocar pantallas.

## Qué está prohibido

Glassmorphism · degradados decorativos · sombras profundas · tarjetas dentro
de tarjetas · esquinas redondeadas en todo · exceso de cápsulas · botones
flotantes gigantes · colores chillones · familias de iconos mezcladas
(solo Material Symbols outlined) · ilustraciones genéricas · emojis como
iconografía · texto centrado por defecto · animaciones largas.

## Compilación Android

### R8 y ML Kit

ML Kit reparte el reconocedor de texto en cinco artefactos. El plugin declara
el **latino** como `implementation` y chino, devanagari, japonés y coreano
como `compileOnly`: compila contra ellos pero no los distribuye, y cada app
añade solo las escrituras que use. Salda usa `TextRecognitionScript.latin` y
nada más, así que esas cuatro clases no están en el APK —son modelos de
varios MB por escritura— y R8 abortaba al no encontrarlas.

`android/app/proguard-rules.pro` declara esa ausencia **clase a clase**, no
con un comodín sobre `com.google.mlkit.**`: silenciar el paquete entero
ocultaría la falta de una clase del reconocedor latino, que sí sería un
fallo. El latino se conserva con `-keep` porque llega por reflexión.
Verificado sobre el APK resultante: los modelos `mlkit-google-ocr-models`
siguen dentro, `vision/text/latin/TextRecognizerOptions` sobrevive al
shrinker y no se empaqueta ninguna escritura sin usar.

### Qué artefacto sirve para validar

| Build | Entorno | Sirve para |
|---|---|---|
| `--debug` | desarrollo | Depurar; enorme (110 MB por ABI) |
| `--profile` | desarrollo | **Validación manual contra `salda-dev`** |
| `--release` | producción | Compila y está minificado, pero **no arranca** contra `salda-dev` |

No es un fallo: `AppEnvironment.resolveHostingDomain` prohíbe expresamente
que una release use los enlaces de desarrollo, para que una build de tienda
no comparta enlaces de `salda-dev` mientras escribe en producción. Una
release solo arranca con `salda-prod` configurado, que no se toca.

Usar siempre `--split-per-abi`: el APK universal mete los tres ABI y triplica
el tamaño (227 MB debug / 91 MB release) sin aportar nada en un móvil.
