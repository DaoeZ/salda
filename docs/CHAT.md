# Chat contextual (P7)

Estado: implementado (2026-07-23). Decisión: ADR-032.

## Objetivo

Cada Relación y Grupo ofrece una conversación privada en tiempo real dentro de
su propio contexto. El chat sirve para coordinar el gasto; nunca sustituye al
timeline de P6 ni participa en cálculos económicos.

## Alcance

P7 incluye:

- mensajes de texto dentro de Relaciones y Grupos;
- primera página en tiempo real y carga paginada del historial;
- envío optimista mediante Firestore;
- resolución en vivo del nombre y avatar del autor por UID;
- borrado de un mensaje propio con confirmación;
- estados de carga, vacío, error, archivo y envío;
- acceso desde el detalle del contexto.

P7 no incluye adjuntos, imágenes, audio, respuestas, edición, reacciones,
menciones, búsqueda, indicadores de escritura, presencia, recibos de lectura,
contador de no leídos, push, moderación del owner ni chat para invitados web.

## Modelo

```text
spaces/{spaceId}/messages/{messageId}
  authorUid: string
  text: string                  // 1..2000 caracteres
  createdAt: server timestamp
  schemaVersion: 1
```

Los IDs los genera el SDK de Firestore antes de escribir. No se almacena el
nombre del autor: `authorUid` es la identidad estable y el perfil se resuelve en
vivo. Los mensajes son inmutables; solo su autor puede borrarlos.

## Privacidad

La membresía actual y `members/{uid}.joinedAt` forman la frontera de acceso:

- solo una cuenta completa que siga siendo miembro puede leer;
- la query SIEMPRE incluye `createdAt >= joinedAt`;
- un miembro nuevo no hereda conversaciones anteriores a su entrada;
- al salir o ser expulsado se pierde todo acceso al chat;
- archivar conserva lectura para los miembros, pero deja el chat en solo
  lectura;
- el propietario no obtiene privilegios sobre mensajes ajenos.

Esta política evita congelar listas de audiencia dentro de cada mensaje, evita
una Cloud Function adicional y hace demostrable cada lectura en Rules. El
historial que un usuario ya leyó no puede retirarse de su memoria, pero el
backend no lo sigue sirviendo tras perder la membresía.

## Autorización

| Acción | Miembro actual | No miembro / invitado | Espacio archivado |
|---|---|---|---|
| Leer desde `joinedAt` | Sí | No | Sí |
| Leer mensajes anteriores a `joinedAt` | No | No | No |
| Crear como su propio UID | Sí | No | No |
| Editar | No | No | No |
| Borrar un mensaje propio | Sí | No | No |
| Borrar mensajes ajenos | No | No | No |

Rules valida forma exacta, autor autenticado, texto no vacío de hasta 2000
caracteres, `schemaVersion: 1` y `createdAt == request.time`. Ningún cliente
puede suplantar al autor ni añadir campos no versionados.

## Consultas y rendimiento

El repositorio obtiene primero la membresía propia y usa:

```text
messages
  where createdAt >= joinedAt
  orderBy createdAt desc
  limit 40
```

El historial usa además `createdAt < cursor`. Es una subcolección de un espacio
con rango y orden sobre el mismo campo, por lo que basta el índice automático.
Solo la primera página mantiene listener; las páginas antiguas son lecturas bajo
demanda. No se descarga todo para filtrar en cliente.

## Separación de P5 y P6

- P5 conserva tickets, asignaciones, entradas económicas, pagos y liquidaciones
  como únicas fuentes económicas. Ningún motor ni Function observa `messages`.
- P6 conserva `activityEvents` como proyección autoritativa de hechos. Enviar o
  borrar chat no genera actividad: un mensaje no es un evento económico ni se
  duplica entre colecciones.
- Eliminar amistad, renombrar username o transferir propiedad no modifica
  mensajes. Solo la membresía actual controla el acceso.

## Compatibilidad

Es una subcolección nueva y opcional: espacios P4, Relaciones/Grupos ADR-030,
actividad P6, sesiones históricas y pagos P5 no se migran ni reinterpretan. El
formato congelado `appcuentas-backup@1` no cambia; el chat no se exporta hasta
que exista una revisión versionada del backup.

## Pruebas obligatorias

- Repositorio: orden, tiempo real, límite por `joinedAt`, paginación, envío
  normalizado y borrado.
- Widget: vacío, mensajes propios/ajenos, envío, archivado y texto largo sin
  overflow.
- Rules: miembro actual, miembro nuevo, expulsado, anónimo/no verificado,
  suplantación, forma, límite, inmutabilidad, borrado propio/ajeno y archivo.
- Suite completa, análisis, web, Functions, Rules, CI y APK debug contra
  `salda-dev`.

La implementación añade 10 pruebas Dart/Flutter específicas y 7 escenarios de
Rules. La matriz completa de seguridad queda en 130/130 casos.
