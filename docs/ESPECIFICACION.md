# AppCuentas — Especificación Definitiva del Proyecto

**Versión:** 2.0 — **DEFINITIVA Y CONGELADA** · **Fecha:** 2026-07-09
**Estado:** Referencia oficial del proyecto. Todo el desarrollo posterior respeta este documento. Cambios futuros requieren una revisión de versión explícita (2.1, 3.0…).

> Historial: v1.0 (2026-07-09) especificación inicial de Fase 1. v2.0 incorpora: filosofía de coste 1–5 €/mes, **Sesiones** como concepto superior a las cuentas, multi-pagador y simplificación de deudas, web de invitados ligera (sustituye a Flutter Web), Cloud Functions como calculadora autoritativa, proveedor de IA genérico OpenAI-compatible, guía de diseño completa, backups JSON, y revisiones de UX, rendimiento y seguridad.

---

## 0. Filosofía del proyecto

Aplicación para **uso personal y con amigos**, no para miles de usuarios. Las prioridades, en orden:

1. **Excelente experiencia de usuario** — calidad visual y de interacción comparable a productos de Google, Apple o Linear.
2. **Arquitectura limpia y escalable** — añadir funciones (especialmente proveedores de IA) sin tocar el resto.
3. **Muy poco mantenimiento** — sin servidores propios, sin dependencias frágiles, sin operaciones manuales.
4. **Coste prácticamente nulo** — objetivo 0–1 €/mes, con techo aceptado de **5 €/mes** cuando pagar simplifique claramente la arquitectura.

Regla de decisión aplicada en todo el documento: *ante dos opciones, gana la más simple de mantener aunque cueste céntimos, frente a la gratuita que complique el sistema.*

### Decisiones congeladas

| # | Decisión | Valor |
|---|---|---|
| DC-1 | Framework | **Flutter** — una base de código para APK Android e IPA iOS |
| DC-2 | Backend | **Firebase** (Auth, Firestore, Storage, FCM, App Check, Hosting, Cloud Functions mínimas, Emulator Suite) en plan **Blaze** con presupuesto 5 € |
| DC-3 | Web invitados | **SPA ligera (Svelte + Vite)** en Firebase Hosting — NO Flutter Web (justificación §6.2) |
| DC-4 | OCR | **Google ML Kit on-device**, gratis; fallback en orden: re-fotografiar → editar a mano → IA (la IA siempre última opción) |
| DC-5 | IA | Multi-proveedor modular + **proveedor genérico OpenAI-compatible** (base URL + key + modelo). Clave del usuario, solo en su dispositivo |
| DC-6 | Modelo de datos | **Sesión** como raíz; una "cuenta independiente" es una sesión de tipo `single` (la UI oculta la capa) |
| DC-7 | Cálculo de dinero | **Cloud Function autoritativa** recalcula totales, balances y liquidaciones en cada cambio; la app calcula en local solo para respuesta instantánea/offline |
| DC-8 | Alcance v1 | España: español + EUR (i18n y multi-moneda preparados) |
| DC-9 | Gastos manuales | Incluidos en v1 |
| DC-10 | Monetización | Ninguna |
| DC-11 | Prorrateo de impuestos/descuentos/propina | Proporcional al consumo (opción "a partes iguales" por sesión) |
| DC-12 | Cierre de sesión/cuenta | Reversible solo por el anfitrión, con registro en el feed de actividad |
| DC-13 | Política IA por defecto | "Sugerir cuando el OCR tenga confianza < 0,75" (calibrable) |

Única decisión abierta no bloqueante: **nombre comercial y dominio** (se desarrolla con el nombre de trabajo *AppCuentas* y `<proyecto>.web.app`; el dominio se conecta después sin cambios de código).

---

## 1. Análisis funcional completo

### 1.1 Conceptos del dominio

- **Sesión**: contenedor superior ("Viaje a Madrid", "Cena del sábado"). Tiene participantes, enlace/QR de invitados, balance global y liquidaciones. Tipos:
  - `multi`: agrupa varias cuentas (Hotel, Mercadona, Gasolina…).
  - `single`: una sola cuenta; la UI la presenta como "cuenta independiente" sin mostrar la capa de sesión. Internamente es idéntica → un solo modelo, un solo motor, unas solas reglas.
- **Cuenta**: un gasto o grupo de tickets dentro de una sesión ("Hotel"). Contiene 1..N tickets.
- **Ticket**: escaneado (imagen/PDF + OCR) o manual (concepto + importe). Cada ticket tiene **pagador** (quién lo pagó — por defecto el anfitrión, editable). Esto habilita el caso real de sesiones: Edgar paga el hotel, Alba la gasolina.
- **Participante**: persona de la sesión. El anfitrión siempre es participante (excluible de tickets concretos).
- **Balance**: por participante, `pagado − consumido = neto`. La sesión muestra el balance completo automáticamente.
- **Liquidación (settlement)**: transferencia sugerida "X debe pagar N € a Y" generada por simplificación de deudas (mínimo número de transferencias). En una sesión con un único pagador degenera exactamente en el modelo simple "cada uno paga al anfitrión".

### 1.2 Roles

**Anfitrión (registrado)** — Google, Email/contraseña, Apple (cuando exista iOS). Crea sesiones y cuentas, escanea, edita OCR, gestiona participantes y pagadores, comparte, confirma liquidaciones, cierra, exporta PDF/imagen/JSON, configura métodos de pago y proveedores de IA.

**Invitado (sin registro, sin app)** — abre enlace/QR → "Selecciona quién eres" → ve el ticket, elige sus productos (si aplica), ve cuánto debe y a quién, marca "Ya he pagado". Nada más; cero fricción.

### 1.3 Requisitos funcionales

**Autenticación**
- RF-01 Google Sign-In · RF-02 Email+contraseña (verificación, recuperación) · RF-03 preparado Sign in with Apple · RF-04 invitados con Auth anónimo transparente · RF-05 borrado de cuenta y datos (RGPD/Play).

**Sesiones y cuentas**
- RF-10 Crear sesión (nombre, emoji, moneda EUR) o "cuenta rápida" (sesión `single` en un paso).
- RF-11 Sesión `multi`: añadir/renombrar/mover/eliminar cuentas; balance global automático y en tiempo real.
- RF-12 Añadir ticket por cámara, galería, PDF; gasto manual en un formulario de una pantalla.
- RF-13 Pagador por ticket, por defecto el anfitrión; selector de un toque.
- RF-14 Cierre de sesión: bloquea toda escritura para todos; reversible solo por el anfitrión (queda en actividad). Cierre por cuenta individual no existe: se cierra la sesión (menos estados que mantener).
- RF-15 Duplicar sesión (misma gente, nuevo evento) · RF-16 archivar (oculta del listado principal sin borrar).

**Captura y OCR** (detalle técnico en §10)
- RF-20 Captura guiada: detección de bordes, disparo automático al estabilizarse, corrección de perspectiva y contraste.
- RF-21 Importar imagen (JPG/PNG/HEIC) y PDF (con capa de texto → extracción directa; escaneado → rasterizar).
- RF-22 Extracción: establecimiento, logo (catálogo local de cadenas), fecha, hora, líneas (nombre, cantidad, precio ud., total), subtotal, IVA desglosado, descuentos, propina, total.
- RF-23 Confianza por campo; los dudosos se resaltan en revisión.
- RF-24 Revisión totalmente editable con validación de cuadre en vivo (añadir/borrar/fusionar/dividir líneas).
- RF-25 **Flujo ante baja confianza, en este orden**: (1) "Repetir foto" (2) "Editar a mano" (3) "Analizar con IA ✨" — la IA es siempre la última opción y nunca se lanza sola.
- RF-26 Categoría automática (supermercado, restaurante, gasolinera, ocio, viaje, otros), corregible.
- RF-27 Detección de duplicados: aviso si coinciden establecimiento+fecha+total con un ticket existente de la sesión.

**IA** (detalle en §9)
- RF-30 Proveedores: Claude, OpenAI, Gemini, DeepSeek, GLM, OpenRouter **+ "Compatible OpenAI" genérico** (base URL, API key, modelo) → cubre LM Studio, Ollama, LocalAI, vLLM, servidores privados y proveedores futuros.
- RF-31 "Probar conexión" obligatorio antes de poder guardar un proveedor; errores tipificados y claros.
- RF-32 Claves solo en Keystore/Keychain del dispositivo; jamás en Firestore, logs ni crash reports.
- RF-33 Orden de preferencia y fallback entre proveedores configurables.

**Reparto**
- RF-40 Participantes por nombre con **personas frecuentes**: chips de un toque con la gente usada antes (colección privada del anfitrión).
- RF-41 Modos por sesión (sobreescribible por ticket): **todo a medias** | **cada uno lo suyo** (asignación por línea).
- RF-42 Una línea: sin asignar / una persona / varias (partes iguales, por pesos, o por unidades si cantidad > 1) / todos.
- RF-43 Impuestos, descuentos y propina: prorrateo proporcional al subtotal asignado (DC-11).
- RF-44 Recalculo reactivo instantáneo (optimista local + autoritativo por función, §6.4).
- RF-45 Redondeo a céntimos por resto mayor: Σ partes = total exacto, determinista.
- RF-46 Líneas huérfanas: aviso; finalizar con huérfanas exige confirmación y las reparte entre todos.

**Balance y liquidaciones**
- RF-50 Balance por participante (pagado, consumido, neto) por cuenta y por sesión, en tiempo real.
- RF-51 Simplificación de deudas: mínimo número de transferencias (algoritmo voraz mayor-acreedor/mayor-deudor, determinista).
- RF-52 Estados por liquidación: `pendiente` → `marcada como pagada` (deudor) → `confirmada` (acreedor o anfitrión). El anfitrión puede forzar cualquier transición; todo queda auditado (quién, cuándo).
- RF-53 Liquidaciones confirmadas quedan **congeladas**: si después cambia el reparto, solo se regeneran las pendientes y se muestra el ajuste residual.

**Invitados (web)**
- RF-60 Enlace `https://<dominio>/s/{sessionId}#k={shareCode}` y QR. El código va en el *fragment* (#), que **no llega al servidor ni a logs de Hosting** (mejora de seguridad respecto a v1).
- RF-61 Web responsive, estética idéntica a la app (mismos tokens de diseño), claro/oscuro automático, carga < 1 s en 4G.
- RF-62 "Selecciona quién eres" (recordado en el dispositivo); aviso si el nombre ya fue reclamado; el anfitrión puede liberar nombres.
- RF-63 El invitado puede: ver tickets y desglose, asignarse/quitarse líneas (modo "lo suyo", sesión abierta), ver su balance y sus liquidaciones, marcar "Ya he pagado", usar los botones de pago. Nada más (reglas §13).
- RF-64 Tiempo real: cualquier cambio se refleja sin recargar.

**Métodos de pago**
- RF-70 Perfil del anfitrión: Bizum (teléfono), PayPal (paypal.me), Revolut (revtag), IBAN, otros. Aparecen solo si están configurados.
- RF-71 Botones en web/app: PayPal y Revolut abren enlace con importe; Bizum e IBAN muestran dato + copiar con **concepto sugerido** ("Viaje Madrid — AppCuentas").
- RF-72 Snapshot de métodos en la sesión al compartir (cambios futuros del perfil no alteran sesiones ya compartidas).

**Historial**
- RF-80 Listado de sesiones: nombre/establecimiento, fecha, total, avatares, % liquidado (barra), chip Abierta/Cerrada/Archivada, miniatura.
- RF-81 Búsqueda y filtros (texto, fecha, categoría, estado) · RF-82 tarjeta "me deben / debo" agregada arriba del historial.
- RF-83 Exportar PDF por sesión (resumen, desglose por persona, líneas, estados, imágenes) y **compartir como imagen** (tarjeta-resumen para WhatsApp) — generados on-device.

**Backups (nuevo)**
- RF-90 **Exportar todos los datos** a JSON (esquema en §14): perfil (sin API keys), personas frecuentes, todas las sesiones con cuentas/tickets/líneas/participantes/liquidaciones/actividad. Opcional: ZIP con el JSON + imágenes de tickets.
- RF-91 **Importar**: validación de esquema + resumen previo ("se importarán 12 sesiones, 340 líneas…") + modos *fusionar* (por id, gana el más reciente) o *restaurar* (reemplaza). Ids regenerables para importar en otra cuenta.
- RF-92 Exportación accesible desde Ajustes y compartible por el share sheet (Drive, email…).

**Notificaciones y recordatorios**
- RF-95 Push FCM al anfitrión: "Alba ha marcado que ha pagado", "Todos han pagado 🎉" (enviadas por Cloud Function).
- RF-96 Recordatorio a invitados: botón "Recordar" que abre WhatsApp/SMS con texto+importe+enlace prellenados; y recordatorio automático programable por sesión (notificación al anfitrión para reenviar, generada localmente).

### 1.4 Requisitos no funcionales

- RNF-01 Material 3 expresivo con identidad propia (§3); Dynamic Color opcional en Android 12+ (por defecto **off**: la marca manda).
- RNF-02 Claro/oscuro/sistema · RNF-03 arranque < 2 s, OCR < 3 s, web invitado interactiva < 1 s en 4G.
- RNF-04 Offline-first en la app: todo lo del anfitrión funciona sin red y sincroniza al volver.
- RNF-05 Español base, cadenas en ARB desde el día 1 · RNF-06 accesibilidad AA, targets ≥ 48dp, escalado de fuente.
- RNF-07 RGPD: minimización, borrado en cascada, exportación de datos (RF-90 la cumple).
- RNF-08 Coste ≤ 5 €/mes con presupuesto y alertas (§12.4); objetivo real 0–1 €.
- RNF-09 Cobertura ≥ 90 % en motores de dominio (reparto, balance, parser) y **tests de paridad Dart↔TS** con vectores dorados (§6.4).

---

## 2. Experiencia de usuario: flujos optimizados

Principio: **el camino feliz nunca supera 3 pantallas** y cada pantalla tiene una sola acción principal.

### 2.1 Camino feliz "cena con amigos" (de abrir la app a compartir: ~6 toques)

```
1. FAB "＋ Escanear"  → la CÁMARA se abre directamente (sin menú previo;
   galería/PDF/manual son iconos secundarios dentro de la propia cámara)
2. Auto-captura al estabilizar el encuadre (0 toques) → OCR procesa con
   animación de escaneo (< 3 s)
3. [Revisión] — una sola pantalla: cabecera + líneas + totales editables inline.
   Si todo cuadra y la confianza es alta, el usuario solo pulsa "Continuar".
   Si la confianza es baja: banner con las 3 opciones en orden
   (Repetir foto · Editar · Analizar con IA)
4. [Gente y reparto] — hoja inferior sobre la misma pantalla:
   chips de personas frecuentes (1 toque cada una) + campo para nuevas;
   "Todo a medias" preseleccionado (recordado del último uso);
   "¿Quién pagó?" = Yo (por defecto)
5. "Crear y compartir" → hoja de compartir del sistema con enlace + QR visible
```

- Modo "cada uno lo suyo": tras el paso 4 se abre la pantalla de asignación; también puede dejarse que **cada invitado se asigne lo suyo desde la web** (es el flujo recomendado: el anfitrión no asigna nada).
- Gasto manual: FAB → icono "manual" → formulario de una pantalla (concepto, importe, quién pagó, gente) → compartir. 4 toques + teclado.
- Añadir ticket a sesión existente: desde el detalle, mismo flujo sin el paso 4 (participantes heredados).

### 2.2 Camino del invitado (0 instalación, ~3 toques)

```
Abre enlace → [¿Quién eres?] (1 toque, recordado para siempre)
→ [Mi resumen]: "Debes 12,45 € a Edgar" + botones de pago
→ (opcional) "Elegir mis productos" con checkboxes y total en vivo
→ [Ya he pagado] (1 toque) → confirmación con animación ✓
```

### 2.3 Reducciones aplicadas respecto a v1

| Antes (v1) | Ahora (v2) |
|---|---|
| Wizard de 5 pasos | Cámara directa + revisión + hoja de gente (3 vistas) |
| Menú "Cámara/Galería/PDF/Manual" como paso | Iconos secundarios dentro de la cámara |
| Escribir cada participante | Chips de personas frecuentes (1 toque) |
| Elegir tipo de reparto siempre | Preseleccionado con el último usado |
| Pantalla de compartir separada | Share sheet inmediato al crear |
| El anfitrión asigna productos de todos | Cada invitado se asigna lo suyo desde la web |

---

## 3. Guía de diseño

La identidad debe leerse como producto profesional (referencias: Google Wallet, Linear, Things). Base Material 3, ejecutada con criterio propio — no M3 "de fábrica".

### 3.1 Identidad visual

- **Personalidad**: precisa, ligera, cercana. El dinero se muestra grande, claro y sin dramatismo.
- **Color semilla**: verde-azulado profundo `#0B6E5D` (dinero/confianza, poco quemado en apps españolas). Generación tonal M3 a partir de la semilla; Dynamic Color desactivado por defecto (activable en Ajustes).
- **Roles (claro / oscuro)** — generados por M3, valores orientativos que fija el `ColorScheme.fromSeed`:
  - `primary` ≈ `#0B6E5D` / `#7FDAC4` · `secondary` verde-gris · `tertiary` ámbar suave (acentos de propina/avisos)
  - `surface` con 5 niveles tonales (surface, surfaceContainerLow/·/High/Highest) — la jerarquía se hace con **tono, no con sombras**.
- **Semánticos fijos (idénticos en claro/oscuro salvo tono)**:
  - Pendiente `⚪ neutral` · Marcado como pagado `🟡 ámbar #B58500/#FFD166` · Confirmado `🟢 #1B7A43/#6CD597` · Error `M3 error` · Positivo/negativo en balances: verde/rojo **acompañados siempre de signo y texto** (no solo color — accesibilidad).
- **Avatares de participantes**: iniciales sobre 8 colores de una paleta armonizada con la semilla, asignación estable por hash del nombre.

### 3.2 Tipografía

- **Inter** (variable) para todo, con `tabular-nums` activado en cualquier cifra de dinero (columnas que alinean).
- Escala (sp): Display 45 (importe grande del invitado) · Headline 28 (totales) · Title 20 (tarjetas) · Body 16/14 · Label 12.
- Los importes usan peso 600 y el símbolo € en peso 400 ligeramente menor: `12,45 €`.

### 3.3 Iconografía

- **Material Symbols Rounded**, peso 400, `fill` en estado activo. Un solo estilo en toda la app y la web. Sin emojis en UI estructural (sí permitidos en nombres de sesión elegidos por el usuario).

### 3.4 Espaciado, forma y elevación

- Retícula de **4dp**; espaciados estándar 4/8/12/16/24/32; márgenes de pantalla 16dp (compact).
- Radios: tarjetas 16 · hojas inferiores 28 (solo arriba) · botones 24 (pill) · campos 12 · miniaturas de ticket 8.
- Elevación: tonal (contenedores M3), sombra solo en FAB y hojas. Nada "flota" sin motivo.

### 3.5 Componentes clave

- **Tarjeta de sesión** (historial): miniatura ticket 56dp · nombre + fecha · total tabular a la derecha · fila de avatares solapados · barra de progreso de liquidación con los 3 colores de estado.
- **Fila de línea de ticket**: nombre (1 línea, ellipsis) · cantidad × precio en Label gris · total tabular · avatares asignados (máx 3 + "+2").
- **Hoja de asignación**: segmentos [Una persona | Varias | Todos] + chips de participantes.
- **Botones**: Filled solo para la acción principal de la pantalla (uno como máximo); Tonal para secundarias; Text para terciarias. Destructivas siempre en diálogo de confirmación.
- **Chips de personas frecuentes** con avatar; seleccionado = filled + check.
- **Banner de estado de cuenta** (cerrada/offline/sincronizando) fino bajo la app bar, no intrusivo.

### 3.6 Movimiento y microinteracciones

- Curvas y duraciones M3: *emphasized* `cubic-bezier(0.2, 0, 0, 1)`; entradas 300–400 ms, salidas 200 ms, toggles 150 ms. Nada > 500 ms.
- **Transición contenedor** (container transform) de tarjeta de sesión → detalle, y de miniatura → ticket completo.
- Listas con *stagger* sutil (25 ms/elemento, solo primera carga).
- **Escaneo**: línea de barrido sobre la foto durante el OCR + las líneas detectadas aparecen "cayendo" ya parseadas — es EL momento mágico del producto, se cuida al máximo.
- Asignar producto: el avatar "salta" a la línea con spring suave; total de la persona hace *count-up*.
- "Ya he pagado": check dibujado (path animation) + transición del chip a ámbar.
- Confirmación del último pago de la sesión: barra de progreso completa con un pulso — celebración sobria, sin confeti.
- Respeto de `reduce motion` del sistema: se sustituyen por fundidos.

### 3.7 Feedback háptico (Android/iOS)

| Evento | Haptic |
|---|---|
| Auto-captura del ticket | medio (impact) |
| Toggle de asignación / selección de chip | ligero (selection) |
| "Ya he pagado" / confirmación de liquidación | éxito (notification success) |
| Error de validación (no cuadra el total) | error suave |
| Pull-to-refresh completado | ligero |

### 3.8 Estados del sistema

- **Skeleton loaders** (shimmer suave 1,2 s): tarjetas de historial, detalle de sesión, web del invitado. Nunca spinner a pantalla completa salvo el arranque.
- **Estados vacíos**: ilustración ligera (línea, 2 colores del tema) + 1 frase + 1 CTA. Historial vacío: "Escanea tu primer ticket". Sesión sin tickets, sin participantes, búsqueda sin resultados: mismos patrones.
- **Errores**: inline junto al elemento afectado + acción de recuperación ("Reintentar", "Editar a mano"). Toast/snackbar solo para confirmaciones, nunca para errores que exigen decisión.
- **Offline**: chip "Sin conexión" en la app bar; todo sigue funcionando; los elementos no sincronizados llevan un punto discreto. Al volver la red: "Sincronizado ✓" 2 s.
- **Sincronización**: indicador de progreso lineal de 2dp bajo la app bar solo si dura > 400 ms (evita parpadeos). Escrituras siempre optimistas: la UI nunca espera al servidor.
- **Cargas de IA**: hoja con el proveedor usado, animación de "pensando", cancelable, y coste orientativo ("~0,002 €").

### 3.9 Web del invitado

Misma guía al 100 %: los tokens (colores, tipografía, radios, espaciados) se exportan a **CSS custom properties desde una única fuente de verdad** (`design_tokens.json` en el monorepo → generación para Dart y CSS). La web no es "una página aparte": es la misma marca.

---

## 4. Flujo completo de pantallas

### 4.1 App del anfitrión

```
[Splash] → sesión activa ? [Home] : [Login]
[Login] Google · Email · (Apple) · crear cuenta · recuperar contraseña

[Home] — bottom bar: Sesiones · (FAB ＋ Escanear) · Ajustes
│
├─ SESIONES (historial)
│   · Tarjeta agregada "Te deben X € · Debes Y €" (tap → desglose)
│   · Lista de tarjetas de sesión · buscador + filtros · archivadas al final
│   · Tap → [Detalle de sesión]
│
├─ FAB ＋ → CÁMARA directa (§2.1)  [iconos: galería · PDF · manual · linterna]
│   → [Revisión de ticket] → hoja [Gente y reparto] → share sheet
│   → (si "lo suyo" y el anfitrión quiere asignar él) [Asignación]
│
├─ [Detalle de sesión]
│   · Cabecera: nombre, total, barra de liquidación, botón Compartir
│   · Pestañas: Resumen · Cuentas · Actividad
│     Resumen: balance por persona (pagó/consumió/neto) + liquidaciones
│              con sus estados y acciones (confirmar, forzar, recordar)
│     Cuentas: lista (Hotel, Mercadona…) → [Detalle de cuenta] → tickets
│              → [Revisión de ticket] / [Asignación]
│     Actividad: feed en tiempo real (quién hizo qué)
│   · Menú: añadir cuenta/ticket, editar gente, duplicar, exportar PDF,
│     compartir imagen-resumen, cerrar sesión de gasto, archivar, eliminar
│
├─ [Asignación] (por ticket)
│   · Persona activa arriba (carrusel) → tap en líneas para asignar en cadena
│   · Tap largo en línea → hoja [Una | Varias | Todos]
│   · Totales por persona en vivo abajo · aviso de huérfanas
│
└─ AJUSTES
    · Perfil · métodos de pago · personas frecuentes
    · Apariencia (claro/oscuro/sistema · dynamic color)
    · Proveedores de IA (lista, añadir, probar conexión, orden, política)
    · Recordatorios por defecto · idioma
    · Copia de seguridad: Exportar JSON/ZIP · Importar
    · Privacidad · borrar cuenta · acerca de
```

### 4.2 Web del invitado

```
/s/{id}#k=CODE → validar → [¿Quién eres?] (si no recordado)
→ [Mi resumen]  "Debes 12,45 € a Edgar" · estado propio · botones de pago
                · [Ya he pagado] · [Elegir mis productos] (si "lo suyo")
                · [Ver tickets] · progreso del grupo (lectura)
→ [Mis productos]  líneas con checkbox, quién comparte cada una, total vivo
→ [Ticket completo]  imagen con zoom + desglose
Estados: sesión cerrada (banner solo lectura) · enlace inválido · offline
```

### 4.3 Navegación (rutas)

```
App (go_router):
/            /login  /register  /forgot
/home        /session/new (cámara)        /session/:id
/session/:id/account/:aid                 /session/:id/account/:aid/ticket/:tid
/session/:id/account/:aid/ticket/:tid/assign
/session/:id/share                        /settings/...  /settings/ai/:provider
/settings/backup

Web: /s/:id (fragment #k=)   /s/:id/pick   /s/:id/ticket/:tid

Deep/App/Universal Links sobre el dominio de Hosting: si el invitado tiene la
app, el mismo enlace la abre en la sesión.
```

- El wizard de creación mantiene **draft persistente**: si la app muere a mitad, se recupera.

---

## 5. Arquitectura técnica

### 5.1 Visión general

```
┌────────────── Monorepo (melos) ──────────────────────────────────────┐
│                                                                      │
│  packages/domain          Dart puro: entidades, Money, SplitEngine,  │
│                           BalanceEngine, validadores. Sin Flutter.   │
│  packages/ocr_parser      Dart puro: parser de tickets españoles.    │
│  packages/ai_providers    contrato + adaptadores IA (Dart+dio).      │
│  packages/design_tokens   design_tokens.json → genera Dart y CSS.    │
│                                                                      │
│  apps/mobile              Flutter (Android + iOS). Riverpod,         │
│                           go_router, ML Kit, Firebase SDKs.          │
│  apps/guest_web           Svelte 5 + Vite + TS. Firebase JS (Auth    │
│                           anónimo + Firestore). Solo lectura +       │
│                           escrituras acotadas. SIN lógica de dinero. │
│  backend/functions        Cloud Functions v2 (TS): recompute,        │
│                           notify, cleanup. Comparte vectores de test │
│                           con packages/domain.                       │
│  backend/firestore        reglas + índices + tests (Emulator Suite). │
└──────────────────────────────────────────────────────────────────────┘
```

Principios: dependencias hacia dentro (`apps → packages`), dominio sin frameworks, `Money` = céntimos enteros siempre, motores deterministas y puros.

### 5.2 Web de invitados: por qué NO Flutter Web

Decisión revisada como pedía el producto. Flutter Web descarga ~1,5–2 MB (motor CanvasKit/wasm) antes del primer render: 3–6 s en 4G para una página que un invitado abre una vez desde WhatsApp. Es la primera impresión del producto para cada invitado y debe ser instantánea.

**Elección: Svelte 5 + Vite, SPA estática en Firebase Hosting.** Svelte compila a JS mínimo sin runtime de framework; con Firebase Auth+Firestore modular el bundle queda en ~120–150 KB gzip → interactiva < 1 s en 4G. Sencilla de mantener (4 vistas), TypeScript, y los tokens de diseño se comparten desde `design_tokens.json`.

La objeción de "duplicar código" se desactiva por diseño: la web **no contiene lógica de dinero** (§5.3); solo pinta datos ya calculados y hace escrituras acotadas que valida Firestore Rules y recalcula la función. Lo único compartido conceptualmente son los tokens de diseño (generados) y el esquema de datos (documentado en §7).

### 5.3 Dónde vive cada cálculo (DC-7)

| Cálculo | App Flutter | Web invitado | Cloud Function |
|---|---|---|---|
| Reparto, balance, liquidaciones | ✅ local (optimista, offline) | ❌ nunca | ✅ **autoritativa** |
| Parser OCR | ✅ | ❌ | ❌ |
| PDF / imagen-resumen / miniaturas | ✅ on-device | ❌ | ❌ |
| Notificaciones push | ❌ | ❌ | ✅ |
| Borrado en cascada (Storage + subcolecciones) | ❌ | ❌ | ✅ |

- La función `recompute` se dispara al escribir tickets/líneas/participantes; recalcula totales de cuenta, balances de sesión y liquidaciones pendientes, y los escribe en los documentos agregados. La app pinta su cálculo local al instante y converge con el autoritativo (idénticos por los **vectores dorados**: un corpus JSON de casos entrada→salida que se ejecuta contra la implementación Dart y la TS en CI; cualquier divergencia rompe el build).
- Ventaja: el invitado que se asigna líneas ve los importes actualizados en ~1 s sin que la web sepa calcular nada, y sin depender de que el anfitrión abra la app.

### 5.4 Estado y datos en la app

- **Riverpod**: streams de Firestore → providers; recalculo reactivo gratis.
- Persistencia offline de Firestore activada; drafts del wizard en almacenamiento local.
- API keys en `flutter_secure_storage`; preferencias en `shared_preferences`.

---

## 6. Tecnologías (resumen y justificación)

| Área | Elección | Por qué |
|---|---|---|
| App | Flutter stable + Riverpod + go_router + freezed | M3 de primera clase, un código Android+iOS, reactividad para tiempo real |
| OCR | google_mlkit_text_recognition (+ document scanner en Android, recorte manual como fallback iOS) | Gratis, on-device, offline |
| PDF in/out | pdfx (rasterizar) · pdf + printing (generar) | Todo on-device |
| IA HTTP | dio con interceptores (scrubbing de cabeceras) | Timeouts, cancelación, seguridad de logs |
| Web invitado | **Svelte 5 + Vite + TS** + Firebase JS modular | §5.2: carga instantánea, mantenimiento mínimo |
| Backend | Firebase: Auth, Firestore, Storage, Hosting, FCM, App Check, **Functions v2 (TS, europe-west1)**, Emulator Suite | §12 |
| Tokens diseño | design_tokens.json → codegen Dart + CSS | Una sola fuente de verdad app+web |
| QR | qr_flutter | Generación local |
| Notificaciones | FCM (push) + flutter_local_notifications (recordatorios) | |
| CI/CD | GitHub Actions + Fastlane; deploy de Hosting/Functions/Rules por CLI | Tests de reglas y vectores dorados en cada PR |
| Crash/analytics | Crashlytics + Analytics (eventos mínimos) | Mantenimiento casi nulo |

---

## 7. Modelo de datos (Cloud Firestore)

`Money` = céntimos (int). Timestamps de servidor. `schemaVersion` en cada raíz desde el día 1.

```
users/{uid}                                   ← privado del anfitrión
  schemaVersion, displayName, email, photoUrl, locale, themeMode
  paymentMethods { bizumPhone?, paypalLink?, revolutTag?, iban?, other? }
  aiPolicy: "suggest" | "ask" | "never"       ← (las API keys NUNCA están aquí)
  fcmTokens: [ … ], reminderDefaults, createdAt

users/{uid}/frequentPeople/{personId}         ← personas frecuentes
  name, colorSeed, usageCount, lastUsedAt

sessions/{sessionId}
  schemaVersion, ownerUid, kind: "single" | "multi"
  name, emoji, currency: "EUR", category
  status: "open" | "closed" | "archived", closedAt?
  shareCode                                   ← 128 bits URL-safe (CSPRNG)
  splitModeDefault: "equal" | "byItem"
  paymentMethodsSnapshot { … }
  — agregados (escritos SOLO por la Cloud Function; clientes solo leen):
  totals { grandTotal, settledConfirmed, settledMarked }
  balances { pid: { paid, consumed, net } }
  participantsCount, pendingSettlements
  computeVersion                              ← nº de recálculo (la UI detecta convergencia)
  createdAt, updatedAt

sessions/{sessionId}/participants/{pid}
  name, colorSeed, isOwner, claimedByDevice?, active: bool

sessions/{sessionId}/accounts/{accountId}
  name ("Hotel"), category, order
  totals { grandTotal }                       ← agregado (función)
  createdAt, updatedAt

sessions/{sessionId}/accounts/{accountId}/tickets/{ticketId}
  kind: "scanned" | "manual"
  merchant { name, brandKey? }, date, time
  paidByParticipantId                         ← multi-pagador (RF-13)
  imagePath?, ocr { engine: "mlkit"|"ai:<provider>", confidence, processedAt }
  subtotal, taxes[{label,amount}], discounts[{label,amount}], tip, grandTotal
  splitModeOverride?
  createdAt, updatedAt

…/tickets/{ticketId}/lines/{lineId}
  name, quantity(×1000), unitPrice, totalPrice, ocrConfidence, order
  assignment { type: "unassigned"|"one"|"shared"|"all",
               participants { pid: weight } }

sessions/{sessionId}/settlements/{settlementId}
  fromPid, toPid, amount
  state: "pending" | "marked" | "confirmed"
  stateHistory [ { state, at, by: "host"|"guest" } ]
  frozen: bool                                ← confirmada = congelada (RF-53)
  generation                                  ← nº de regeneración

sessions/{sessionId}/activity/{eventId}       ← append-only
  type, actorPid | "host", payload, at
```

**Índices compuestos:** `sessions(ownerUid, status, updatedAt desc)` · `sessions(ownerUid, updatedAt desc)`.

**Storage:** `receipts/{sessionId}/{ticketId}/original.jpg` (≤1600px, JPEG q80, ~200–400 KB) + `thumb.jpg` (300px), ambos generados on-device antes de subir.

**Reglas de diseño del modelo:**
- El **historial se pinta con 1 lectura por sesión** (todo lo del listado está desnormalizado en el doc raíz).
- Los agregados los escribe solo la función → los clientes no pueden corromperlos y no hay transacciones complejas en cliente.
- `kind: "single"` permite a la UI presentar "cuenta independiente" sin modelo aparte.

---

## 8. Modelo de entidades y motores de dominio

| Entidad | Claves | Invariantes |
|---|---|---|
| Session | id, kind, estado, shareCode, splitModeDefault | cerrada ⇒ inmutable (salvo reapertura del owner) |
| Account | id, nombre, orden | pertenece a 1 sesión |
| Ticket | tipo, merchant, fecha, pagador, totales, confianza | Σlíneas − descuentos + impuestos + propina = grandTotal (tolerancia con aviso) |
| TicketLine | nombre, cantidad, precios, asignación | asignación ∈ {unassigned, one, shared(pesos), all} |
| Participant | nombre, esAnfitrión, activo | nombres únicos por sesión |
| Settlement | from, to, importe, estado, frozen | pending→marked→confirmed; confirmada ⇒ congelada |
| Money (VO) | céntimos int + moneda | aritmética solo en enteros |
| ShareCode (VO) | 128 bits URL-safe | CSPRNG |
| ReceiptExtraction (VO) | resultado normalizado OCR/IA con confianzas | contrato único parser ↔ todos los proveedores IA |

**SplitEngine** (puro, determinista): por ticket → consumo por participante. `equal`: total/N con resto mayor. `byItem`: líneas asignadas + "all" entre activos + compartidas por pesos; prorrateo proporcional de impuestos/descuentos/propina; redondeo por resto mayor con orden estable.

**BalanceEngine** (puro, determinista): agrega consumos y pagos (pagador de cada ticket) → neto por participante → **simplificación de deudas** voraz (empareja mayor deudor con mayor acreedor) → lista mínima de liquidaciones. Respeta las congeladas: las descuenta del neto antes de regenerar pendientes. Empates resueltos por orden estable de pid → salida reproducible.

Ambos motores existen en Dart (`packages/domain`) y TS (`backend/functions`), verificados contra los **mismos vectores dorados** en CI (RNF-09).

---

## 9. Arquitectura de la IA

### 9.1 Contrato y registro (puertos y adaptadores)

```
ai/contract
  AiReceiptProvider:
    id, displayName, capabilities { vision, jsonMode }
    configSchema  ← qué campos pide al usuario (key; y baseURL+modelo en el genérico)
    testConnection(config) → ok | error tipificado
    extractReceipt(input, config) → ReceiptExtraction
  Errores comunes: invalidKey · noCredit · rateLimited · modelNotAllowed
                   · network · badResponse · unsupportedInput

ai/providers      claude/ openai/ gemini/ deepseek/ glm/ openrouter/
                  openai_compatible/   ← EL GENÉRICO (DC-5)
ai/registry       lista, orden de preferencia, fallback
```

- **Añadir proveedor = nuevo directorio + 1 línea en el registro.** Nada más cambia.
- **`openai_compatible`**: base URL personalizada + API key (opcional — servidores locales como Ollama no la exigen) + nombre de modelo libre. Usa `/v1/chat/completions` con `response_format` JSON si el servidor lo soporta y degradación a "JSON en el prompt + validación" si no. Cubre LM Studio, Ollama, LocalAI, vLLM, servidores privados y futuros proveedores. Los adaptadores dedicados existen igualmente porque aprovechan lo mejor de cada API (visión de Gemini/Claude, tool-use, límites) y dan mensajes de error precisos.
- **Prompt canónico único** en el contrato (JSON Schema del ticket + 2 ejemplos de tickets españoles); cada adaptador solo lo envuelve en su formato.
- Entrada: imagen re-comprimida (~1024px) si el modelo tiene visión; si no, el texto crudo del OCR. Salida validada contra el esquema + cuadre; 1 reintento citando el error; luego error amable + edición manual.
- La IA **nunca se ejecuta sin acción explícita del usuario** (DC-4/RF-25) y muestra proveedor + coste orientativo.

### 9.2 Claves y seguridad de la IA

- Almacenamiento exclusivo en `flutter_secure_storage` (Android Keystore / iOS Keychain). Excluidas de backups del sistema **y del backup JSON de la app** (RF-90).
- Llamadas directas dispositivo→proveedor. Ninguna clave transita por Firebase ni por logs (interceptor con scrubbing de `Authorization`/`x-api-key`; Crashlytics sin breadcrumbs de red de IA).
- "Probar conexión" obligatorio antes de guardar: petición mínima real (listado de modelos o completion de 1 token), timeout 10 s, resultado tipificado. El genérico valida además que la base URL responde al formato OpenAI.
- Nota honesta al usuario en Ajustes: recomendación de crear claves con límite de gasto en el panel del proveedor.

---

## 10. Arquitectura del OCR

Pipeline on-device (gratis, offline):

```
Imagen → 1. Pre-proceso: bordes + perspectiva + gris + contraste adaptativo + deskew
       → 2. ML Kit Text Recognition v2 (latin): bloques + bounding boxes
       → 3. Reconstrucción de líneas por geometría (texto izq. + importe dcha.)
       → 4. Parser heurístico es-ES (packages/ocr_parser, Dart puro):
            establecimiento (diccionario de cadenas: Mercadona, Carrefour, Lidl,
            DIA, Alcampo…) · fecha/hora multi-formato · líneas [cant] desc … importe
            · "2 x 1,50" · pesables "0,456 kg x 9,99 €/kg" · IVA "BASE/CUOTA"
            · descuentos negativos · propina · TOTAL (palabra clave + posición)
       → 5. Confianza por campo + global (¿cuadra? ¿fecha válida? ¿hay líneas?)
       → 6. Decisión (DC-4):
            ≥ 0,75 → revisión directa
            < 0,75 → banner con TRES opciones en orden:
                     ① Repetir foto  ② Editar a mano  ③ Analizar con IA ✨
            (la IA es siempre la última opción; deshabilitada si no hay proveedor,
             con enlace a configurarlo)
```

- El parser emite el mismo `ReceiptExtraction` que la IA: la pantalla de revisión es agnóstica del origen.
- **Corpus de regresión**: textos OCR reales anonimizados + JSON esperado, en CI. Crece con cada ticket problemático encontrado en uso real (mejor inversión de calidad del proyecto).
- PDFs con capa de texto: extracción directa sin OCR. Escaneados: rasterizar → mismo pipeline.
- La palanca nº 1 de precisión es la **captura guiada** (paso 1), no el parser: se prioriza en diseño y en esfuerzo.

---

## 11. Rendimiento

Revisión completa de cuellos de botella y su tratamiento:

**Firestore (coste y latencia)**
- Historial: **1 lectura por sesión** (agregados desnormalizados). 100 sesiones = 100 lecturas, paginadas de 20 en 20 (`limit` + `startAfter`).
- Listeners **solo en la pantalla visible**; se cancelan al salir (autoDispose de Riverpod). Nunca listeners app-wide a subcolecciones.
- Detalle de sesión: listener al doc raíz + a la subcolección visible en la pestaña activa.
- Escrituras por lotes (`WriteBatch`) al guardar un ticket (ticket + N líneas = 1 round-trip).
- La función recompute escribe agregados **solo si cambian** (comparación previa) → evita cascadas de invalidación y lecturas de listeners.
- Persistencia offline = caché: reabrir la app no relee lo no cambiado.

**Red**
- Imágenes: original ≤1600px q80 (~300 KB) + thumb 300px (~15 KB). Las listas cargan solo thumbs; el original solo al abrir el ticket (lazy + caché de disco).
- Subidas en segundo plano con reintento; la UI nunca espera a Storage.
- Web invitado: bundle ~150 KB gzip, cache-control agresivo en Hosting, imágenes lazy.

**Batería**
- Cero polling: todo es push (streams de Firestore / FCM).
- Cámara y ML Kit se liberan al salir de la pantalla de captura; OCR en isolate para no bloquear UI.
- Recordatorios: alarmas locales del sistema, no tareas periódicas propias.

**Percepción**
- Escrituras optimistas siempre; skeletons > 400 ms; container transforms para continuidad; motores locales para importes instantáneos aunque la función autoritativa tarde ~1 s.

---

## 12. Backend Firebase: arquitectura y configuración

### 12.1 Servicios

| Servicio | Uso |
|---|---|
| Auth | Google + Email (anfitrión), **Anónimo** (invitados), Apple (futuro iOS) |
| Firestore | Datos + tiempo real + offline. Región `europe-west1` (RGPD, latencia) |
| Storage | Imágenes de tickets (misma región) |
| Hosting | Web de invitados + dominio de deep links |
| FCM | Push al anfitrión |
| App Check | **Enforced** en Firestore, Storage y Functions (Play Integrity / App Attest / reCAPTCHA Enterprise en web) |
| Functions v2 (TS) | Solo 3, mínimas (§12.2) |
| Emulator Suite | Desarrollo local completo (auth+firestore+storage+functions) y tests de reglas en CI |

### 12.2 Cloud Functions (deliberadamente pocas)

1. **`recompute`** — trigger Firestore en `tickets/**`, `lines/**`, `participants/**`: recalcula agregados de cuenta, balances de sesión y liquidaciones pendientes (motor TS = vectores dorados). Idempotente y con debounce lógico (marca `computeVersion`).
2. **`notify`** — trigger en `settlements/**`: FCM al anfitrión en `pending→marked` y "todos pagados". Trigger en `participants` para "X ha elegido sus productos" (silenciosa, agrupada).
3. **`cleanup`** — trigger al borrar sesión/usuario: borrado en cascada de subcolecciones e imágenes de Storage.

Node 22, región `europe-west1`, memoria 256 MB, `minInstances: 0` (el arranque en frío de ~1 s es aceptable y mantiene el coste en ~0 €), reintentos activados solo en `cleanup`.

### 12.3 Reglas de seguridad (matriz completa en §13)

### 12.4 Presupuesto, alertas y límites (configuración recomendada)

- **Plan Blaze** con cuenta de facturación dedicada al proyecto.
- **Budget de Google Cloud Billing: 5 €/mes**, alertas por email al **50 % (2,50 €), 90 % (4,50 €) y 100 %**, incluyendo previsión (*forecasted spend*).
- Importante: un budget **no corta el gasto**; por eso, además:
  - **Alertas de métricas** (Cloud Monitoring, gratis): lecturas Firestore > 25k/día, escrituras > 10k/día, invocaciones de functions > 5k/día, egress Storage > 1 GB/día → email. Detectan un bug de listeners o un abuso mucho antes que la factura.
  - **App Check enforced** (la mayor protección real contra consumo abusivo por terceros).
  - Límite de concurrencia y `maxInstances: 3` en cada function (techo físico al gasto por bucle accidental).
  - *Kill-switch* de facturación (function que desvincula billing al superar un umbral): **documentado pero NO instalado en v1** — a esta escala es más riesgo operativo (apagón accidental del proyecto) que protección. Revisar si algún mes se superan 2 €.
- Revisión mensual de 5 minutos: panel Usage de Firebase (única "operación" del proyecto).

### 12.5 Buenas prácticas adoptadas

- Dos proyectos Firebase: **`appcuentas-dev`** (con emuladores; datos falsos) y **`appcuentas-prod`**. Nunca se desarrolla contra prod.
- Reglas, índices y functions versionados en el repo y desplegados por CI (`firebase deploy` en merge a main tras pasar tests de emulador).
- `schemaVersion` en documentos raíz + estrategia de migración perezosa (el cliente migra al leer, la función al escribir).
- Claves de servicio: ninguna en el repo; CI con Workload Identity Federation.
- Backups: export JSON en la app (RF-90) + *point-in-time recovery* de Firestore activado (7 días, coste ~0 a esta escala).

---

## 13. Seguridad (revisión completa)

### 13.1 Modelo de amenazas asumido

Grupos de amigos (confianza social alta). Las barreras protegen contra: terceros con el enlace filtrado, manipulación de importes/estados, abuso de la infraestructura, y extracción de claves de IA. No se pretende proteger contra un participante malicioso decidido dentro del grupo (mismo modelo que Tricount) — el anfitrión siempre puede corregir y todo queda auditado.

### 13.2 Matriz de autorización (base de las Firestore Rules)

| Recurso | Anfitrión (owner) | Invitado (anónimo con shareCode) | Cualquier otro |
|---|---|---|---|
| `users/{uid}` | R/W propio | — | — |
| `sessions/{id}` doc raíz | R/W (si open; closed: solo reabrir/archivar) | R | — |
| `participants` | R/W | R; W solo `claimedByDevice` propio | — |
| `accounts`, `tickets` | R/W (open) | R | — |
| `lines` | R/W (open) | R; W solo añadirse/quitarse a sí mismo en `assignment.participants` (open + byItem), validado con `diff()` campo a campo | — |
| `settlements` | R/W (todas las transiciones) | R; W solo `state: pending→marked` en liquidaciones donde `fromPid` = su identidad reclamada | — |
| Agregados (`totals`, `balances`) | solo lectura | solo lectura | — |
| `activity` | R + append | R + append (solo tipos de invitado) | — |
| Storage `receipts/**` | R/W de sus sesiones | R con shareCode (regla espejo) | — |

Mecanismo invitado: Auth anónimo + el cliente presenta el `shareCode`; las reglas lo comparan con el del documento de sesión. El código viaja en el *fragment* de la URL (#) → no aparece en logs de servidor ni en Referer.

### 13.3 Controles aplicados

- **shareCode**: 128 bits CSPRNG, regenerable por el anfitrión (invalida enlaces antiguos), rotación sugerida al cerrar sesión de gasto.
- **Estados de pago**: transiciones válidas codificadas en reglas (un invitado no puede confirmarse a sí mismo ni tocar liquidaciones ajenas); `stateHistory` append-only.
- **Manipulación de importes**: imposible desde la web (no puede escribir campos de dinero); en la app, los agregados los escribe solo la función; los datos base (líneas/tickets) solo el owner.
- **App Check enforced** en Firestore/Storage/Functions: bloquea scripts contra la API con el config público del proyecto.
- **API keys de IA**: Keystore/Keychain, sin backup, scrubbing en logs/crashes, nunca en el export JSON.
- **Accesos no autorizados**: sin shareCode no hay lectura posible; enumeración de sessionIds inútil sin código; reglas denegación-por-defecto (`allow` explícitos únicamente).
- **Tests de reglas**: suite completa contra Emulator Suite en CI (caso por celda de la matriz, incluidos los negativos). Es la pieza de seguridad más crítica del sistema y se trata como tal (R-5).
- Cuenta cerrada = solo lectura para todos, también para el owner salvo reapertura explícita.

---

## 14. Backups (exportar / importar)

**Formato**: un único JSON versionado; opcionalmente ZIP = JSON + `/images/{sessionId}/{ticketId}.jpg`.

```
{
  "format": "appcuentas-backup",
  "schemaVersion": 1,
  "exportedAt": "2026-07-09T18:00:00Z",
  "user": { profile, paymentMethods, frequentPeople[] },     // SIN API keys
  "sessions": [ { …doc raíz, participants[], accounts[ { …, tickets[ { …, lines[] } ] } ],
                  settlements[], activity[] } ]
}
```

- **Exportar**: desde Ajustes; se genera on-device leyendo Firestore (o la caché offline) y se comparte por el share sheet. También sirve como exportación RGPD.
- **Importar**: validación de esquema → resumen previo (nº sesiones/tickets/líneas, colisiones) → modo **fusionar** (por id; en conflicto gana `updatedAt` más reciente) o **restaurar** (borra e importa; doble confirmación). Opción "regenerar ids" para importar el backup de otra persona sin colisiones. Los shareCodes **se regeneran siempre** al importar (los del backup se consideran quemados).
- Las imágenes del ZIP se re-suben a Storage en segundo plano tras importar.

---

## 15. Riesgos técnicos

| # | Riesgo | Prob. | Imp. | Mitigación |
|---|---|---|---|---|
| R-1 | Precisión OCR en tickets térmicos arrugados (riesgo nº 1 del producto) | Alta | Alto | Captura guiada; confianza por campo; edición manual rapidísima; IA a un toque; corpus de regresión creciente |
| R-2 | Divergencia entre motores Dart y TS (reparto/balance) | Media | Alto | **Vectores dorados compartidos en CI**; motores puros y deterministas; cualquier divergencia rompe el build |
| R-3 | Reglas de Firestore mal escritas (escrituras finas de invitados) | Media | Alto | Suite de tests de reglas por celda de la matriz §13.2 en CI; denegación por defecto |
| R-4 | Suplantación de invitado (cualquiera con el enlace elige un nombre) | Media | Bajo | Modelo de confianza social; `claimedByDevice` + aviso; anfitrión confirma pagos y libera nombres; auditoría |
| R-5 | Enlace filtrado → terceros leen la sesión | Media | Bajo/Medio | shareCode 128 bits en fragment, regenerable; cierre de sesión; sin datos sensibles más allá del consumo |
| R-6 | Conflictos de edición colaborativa | Media | Medio | Granularidad por línea + transacciones; tiempo real reduce la ventana; última escritura gana por línea |
| R-7 | Latencia/frío de la función recompute (~1 s) | Cierta | Bajo | UI optimista con motor local; `computeVersion` para convergencia; aceptable a esta escala |
| R-8 | Cambios en APIs de proveedores IA | Media | Medio | Aislado en adaptadores; errores tipificados; fallback; el genérico OpenAI-compatible como red de seguridad |
| R-9 | Extracción de claves IA del dispositivo | Baja | Medio | Keystore/Keychain hardware; sin backups; scrubbing; recomendar claves con límite de gasto |
| R-10 | Bug de listeners dispara lecturas (coste) | Baja | Medio | autoDispose, paginación, agregados; **alertas de métricas** §12.4 avisan el mismo día |
| R-11 | Bucle accidental en functions | Baja | Medio | Escritura de agregados solo-si-cambia; `maxInstances: 3`; alertas de invocaciones |
| R-12 | Apple: iOS exige Sign in with Apple + 99 $/año | Cierta (si iOS) | Bajo | Contemplado en Auth; gasto pospuesto hasta decidir iOS |
| R-13 | RGPD (fotos, nombres de terceros no registrados) | Media | Medio | Región EU, minimización (sin emails de invitados), borrado en cascada, export RF-90, política de privacidad |
| R-14 | Lock-in Firebase | Baja | Medio | Dominio puro sin Firebase; repositorios como interfaces; export JSON completo = datos siempre recuperables |

---

## 16. Estimación de costes

**Mensual esperado: 0–1 € · techo presupuestado: 5 € (alertas 2,50/4,50/5).**

| Concepto | Franja gratuita | Uso estimado (decenas de usuarios) | Coste |
|---|---|---|---|
| Firestore | 50k lect / 20k escr / día | ~5k / ~1k | 0 € |
| Functions | 2M invocaciones/mes | < 10k/mes | 0 € |
| Storage | ~5 GB + egress | ~1–2 GB/año | 0–0,10 € |
| Hosting | 10 GB/mes | < 1 GB | 0 € |
| Auth / FCM / App Check / Crashlytics | — | — | 0 € |
| PITR Firestore (backup 7 días) | — | GB-mes mínimos | ~0–0,20 € |

Costes fijos reales: Google Play Console **25 $ una vez** · dominio opcional ~12 €/año · Apple Developer **99 $/año solo cuando llegue iOS**.

IA (la paga cada usuario con su clave; transparencia mostrada en Ajustes): por ticket con imagen ≈ 0,001–0,005 € según proveedor (Gemini Flash / GPT-4o-mini / Claude Haiku / DeepSeek); con servidores locales (Ollama/LM Studio) = 0 €.

---

## 17. Funciones incluidas en v1 (revisión de fundador)

Añadidas a esta versión por valor real (todas ya especificadas arriba): sesiones con balance global y **simplificación de deudas** (RF-50/51) · **multi-pagador** por ticket (RF-13) · **personas frecuentes** (RF-40) · tarjeta "me deben / debo" (RF-82) · **compartir resumen como imagen** para WhatsApp (RF-83) · concepto de pago prellenado al copiar (RF-71) · detección de duplicados (RF-27) · draft persistente del wizard (§4.3) · asignación por el propio invitado como flujo principal (§2.1) · **backup JSON/ZIP completo** (RF-90/91) · aprendizaje local de correcciones de nombres de producto por establecimiento (diccionario local, sin nube).

Descartadas conscientemente (llamativas sin utilidad a esta escala): gamificación, confeti, social feed, chat interno (WhatsApp ya existe), múltiples divisas por sesión en v1, reconocimiento visual de logos.

## 18. Funciones futuras (v2+, no bloquean nada del diseño actual)

Grupos persistentes (misma gente, muchas sesiones) · multi-moneda con conversión (viajes) · estadísticas de gasto por categoría/mes · PWA instalable + push web a invitados · e-tickets por email (requiere backend adicional) · widget de pantalla de inicio · versión iOS + Sign in with Apple · reconocimiento visual de logos · integración de pagos con confirmación automática.

---

## 19. Hoja de ruta de desarrollo

1. **M0 — Cimientos**: monorepo, tokens de diseño + tema M3, proyectos dev/prod, emuladores, CI.
2. **M1 — Dominio**: entidades, Money, SplitEngine, BalanceEngine + vectores dorados (Dart y TS) — sin UI.
3. **M2 — OCR**: captura guiada, ML Kit, parser + corpus, pantalla de revisión.
4. **M3 — Sesiones**: modelo Firestore, reglas + tests de reglas, functions (recompute/notify/cleanup), flujos de creación y detalle.
5. **M4 — Invitados**: web Svelte, shareCode, QR, asignación por invitado, liquidaciones y estados, tiempo real, métodos de pago.
6. **M5 — Pulido**: PDF e imagen-resumen, recordatorios, cierre/archivado, backup JSON, estados vacíos/error/offline, accesibilidad, microinteracciones y haptics, beta (Play internal + App Distribution).
7. **M6 — IA**: contrato + adaptadores Claude, Gemini y **openai_compatible** (cubre el resto de facto); OpenAI/DeepSeek/GLM/OpenRouter dedicados después.

*La IA va al final a propósito: el producto es 100 % usable sin ella y su contrato (`ReceiptExtraction`) queda fijado desde M2.*

---

**Documento congelado.** A partir de aquí comienza el desarrollo (M0). Cualquier cambio de alcance o arquitectura se registra como revisión de este documento antes de implementarse.
