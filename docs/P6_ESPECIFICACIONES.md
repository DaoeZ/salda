/goal Cerrar P5 e implementar P6 --- Actividad

Trabaja sobre el repositorio actual de Salda.

Codex se quedó sin uso durante el cierre técnico de P5. La
implementación principal de P5 ya existe en el árbol de trabajo, pero
puede haber cambios sin commit, pruebas pendientes y documentación
incompleta.

Tu objetivo completo es:

1.  conservar y revisar el trabajo existente de Codex;
2.  terminar la validación y publicación de P5;
3.  implementar P6 --- Actividad;
4.  validar y publicar P6;
5.  detenerte antes de P7.

No reimplementes P5 desde cero. No hagas refactors amplios por
preferencias personales. No empieces chat, que corresponde a P7.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ REGLAS DE CONTINUIDAD
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Antes de tocar código:

-   ejecuta `git status`;
-   revisa la rama actual;
-   ejecuta `git diff --stat`;
-   revisa el diff completo pendiente;
-   revisa los últimos 15 commits;
-   identifica qué cambios ya están en commits y cuáles siguen sin
    guardar;
-   no descartes ni sobrescribas cambios existentes;
-   no uses `reset --hard`;
-   no reformatees archivos no relacionados.

Distingue las fases mediante Git:

-   P4 ya está validada y no debe modificarse salvo bug bloqueante
    demostrado;
-   el arreglo de amistades P3 quedó aislado en el commit `6f14551`;
-   P5 corresponde principalmente a los cambios económicos posteriores:
    -   relaciones económicas;
    -   balances;
    -   entradas económicas derivadas;
    -   pagos;
    -   recompute;
    -   pantallas económicas;
    -   Rules y Functions económicas;
    -   reconstrucción histórica;
    -   documentación económica.

Usa también como referencia:

-   `docs/RELACIONES_ECONOMICAS.md`;
-   ADR-029, si existe;
-   archivos modificados actualmente;
-   historial Git reciente.

No releas todo el repositorio. Revisa únicamente las piezas necesarias.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ PARTE 1 --- CERRAR P5
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Asume que P5 está implementada y actúa como revisor y cerrador.

Codex dejó indicios de haber completado:

-   balances derivados de tickets y pagos;
-   neteo bilateral por UID y moneda;
-   entradas económicas deterministas;
-   pagos parciales;
-   bloqueo de sobrepago;
-   confirmación o rechazo por el receptor;
-   cancelación por el pagador;
-   idempotencia;
-   protección contra suplantación de `userUid`;
-   bloqueo de escrituras directas de balances;
-   resumen económico global;
-   detalle bilateral;
-   resumen económico por espacio;
-   reconstrucción perezosa de tickets históricos;
-   conexión entre pagos P5 y recompute histórico;
-   adaptación de layouts;
-   documentación económica.

Resultados observados antes de interrumpirse:

-   Functions: 93/93;
-   Domain: 105/105;
-   bloque nuevo de Rules P5: 3/3 contra emulador;
-   P4 validada;
-   arreglo de amistades aislado.

No des estos resultados por definitivos: compruébalos en el estado
actual.

## Validación pendiente de P5

Comprueba especialmente:

1.  Que tickets y pagos sigan siendo la fuente de verdad.
2.  Que los balances no sean editables directamente.
3.  Que un pago confirmado no permita pagar dos veces la misma deuda
    mediante el sistema antiguo y el nuevo.
4.  Que el neteo sea bilateral y conserve trazabilidad.
5.  Que cada saldo pueda explicarse por:
    -   ticket;
    -   asignación;
    -   pago;
    -   moneda.
6.  Que solo los participantes lean relaciones económicas.
7.  Que no pueda falsificarse el `userUid` de un participante.
8.  Que el receptor económico confirme el pago.
9.  Que funcionen:
    -   pago completo;
    -   pago parcial;
    -   sobrepago bloqueado;
    -   doble pulsación;
    -   doble confirmación;
    -   cancelación;
    -   rechazo;
    -   reintentos.
10. Que tickets antiguos aparezcan sin tener que editarlos.
11. Que amistad eliminada o salida de un espacio no borren deudas.
12. Que no se mezclen monedas diferentes.

Ejecuta:

-   análisis estático;
-   tests Flutter relacionados y suite completa si es viable;
-   widget tests;
-   Domain;
-   Functions;
-   Firestore Rules contra emulador;
-   web tests y build;
-   Flutter build;
-   APK debug;
-   CI. 

Los problemas del entorno, caché o sandbox deben distinguirse de fallos
reales del código.

Si aparece un bug real:

-   crea el test mínimo que lo reproduzca;
-   corrige la causa;
-   vuelve a validar.

No añadas funcionalidades nuevas a P5.

## Cierre Git de P5

Cuando P5 esté verde:

-   termina `docs/RELACIONES_ECONOMICAS.md`;
-   actualiza solo la documentación afectada;
-   elimina ruido de formato no relacionado;
-   crea uno o varios commits claros;
-   sube la rama;
-   crea o actualiza la PR de P5;
-   no toques producción;
-   despliega únicamente en `salda-dev` cuando sea necesario.

No empieces P6 hasta que:

-   P5 compile;
-   las pruebas relevantes estén verdes;
-   sus cambios estén guardados en commits;
-   exista un punto Git limpio y recuperable.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ PARTE 2 --- P6: ACTIVIDAD
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Una vez cerrada P5, implementa P6 --- Actividad.

P6 debe ofrecer un historial comprensible de lo ocurrido en Salda, sin
convertirse en chat ni duplicar el modelo económico.

Objetivo:

> Que un usuario pueda ver qué ha cambiado, quién lo hizo, cuándo
> ocurrió y acceder al objeto original que explica el evento.

Ejemplos:

-   Edgar creó un ticket.
-   Alba modificó un ticket.
-   Pedro se unió a un espacio.
-   Alba salió del espacio.
-   Edgar archivó un espacio.
-   Pedro marcó un pago como realizado.
-   Alba confirmó un pago.
-   Se canceló una liquidación.
-   Se añadió o eliminó un participante.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ ALCANCE DE P6
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Implementa:

-   actividad global del usuario;
-   actividad dentro de cada espacio;
-   eventos económicos relevantes;
-   eventos de espacios y membresías;
-   eventos de tickets;
-   eventos de pagos;
-   actualización en tiempo real;
-   paginación;
-   acceso desde un evento al objeto original;
-   estados de carga, vacío y error;
-   conservación del historial cuando cambian usernames o membresías.

No implementes:

-   chat;
-   mensajes libres;
-   comentarios;
-   reacciones;
-   menciones;
-   indicadores de escritura;
-   adjuntos sociales;
-   notificaciones push completas;
-   correo de notificación;
-   rankings;
-   gamificación.

P7 será Chat.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ PRINCIPIOS DE ARQUITECTURA
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

La actividad es una proyección derivada o un registro de auditoría, no
la fuente de verdad.

Las fuentes de verdad siguen siendo:

-   tickets;
-   espacios;
-   membresías;
-   invitaciones;
-   pagos;
-   relaciones económicas.

Eliminar un evento de actividad nunca debe modificar el objeto original.

No utilices el feed para calcular:

-   balances;
-   permisos;
-   membresías;
-   estados de tickets;
-   estados de pagos.

Usa siempre UID para identidad.

Los usernames y nombres mostrados pueden ser snapshots visuales, pero
nunca claves relacionales.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ EVENTOS MÍNIMOS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Espacios

-   espacio creado;
-   nombre o avatar modificado;
-   espacio archivado;
-   espacio reactivado;
-   propiedad transferida.

## Miembros e invitaciones

-   invitación enviada;
-   invitación aceptada;
-   invitación rechazada o cancelada, solo si aporta valor al usuario;
-   miembro incorporado;
-   miembro salido;
-   miembro expulsado.

No expongas invitaciones privadas a usuarios que no participen.

## Tickets

-   ticket creado;
-   ticket vinculado o desvinculado de un espacio;
-   ticket modificado de forma relevante;
-   participantes modificados;
-   reparto o asignaciones confirmadas;
-   ticket archivado o eliminado, según el modelo existente.

Evita generar un evento por cada pequeño cambio técnico.

Una edición atómica de un ticket debe producir preferiblemente un único
evento comprensible.

## Economía y pagos

-   deuda generada o recalculada solo cuando sea útil y no cree ruido;
-   pago marcado como realizado;
-   pago confirmado;
-   pago rechazado;
-   pago cancelado.

No dupliques el mismo hecho mediante un evento del sistema antiguo y
otro de P5.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ MODELO DE EVENTO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Diseña el modelo mínimo después de revisar el repositorio.

Conceptualmente, un evento debería poder incluir:

-   `activityId`;
-   tipo;
-   actor UID;
-   UIDs afectados;
-   `spaceId` opcional;
-   `ticketId` opcional;
-   `paymentId` opcional;
-   fecha del servidor;
-   resumen visual o datos mínimos para construirlo;
-   versión del esquema;
-   clave de idempotencia o identificador determinista;
-   visibilidad.

No guardes información económica completa innecesariamente.

El evento debe enlazar al objeto original siempre que siga accesible.

Si el objeto ya no existe, muestra un estado histórico válido en lugar
de romper la pantalla.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ GENERACIÓN E IDEMPOTENCIA
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Prefiere generación autoritativa mediante:

-   Functions;
-   transacciones;
-   o el mecanismo servidor ya utilizado.

No permitas que un cliente cree arbitrariamente eventos que parezcan
realizados por otra persona.

Los reintentos no deben duplicar eventos.

Usa:

-   IDs deterministas;
-   claves de idempotencia;
-   o una estrategia equivalente.

Comprueba especialmente:

-   triggers repetidos;
-   escritura offline;
-   doble pulsación;
-   actualización repetida;
-   recompute económico;
-   reconstrucción histórica.

Un recompute no debe llenar el feed con eventos falsos o duplicados.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ VISIBILIDAD Y PRIVACIDAD
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Cada usuario solo puede leer actividad que legítimamente le corresponde.

Actividad global:

-   eventos donde participa;
-   eventos de espacios de los que es miembro, según la política
    definida;
-   pagos donde es pagador o receptor;
-   tickets a los que tiene acceso.

Actividad del espacio:

-   solo miembros con acceso;
-   miembros históricos únicamente cuando necesiten conservar acceso a
    hechos económicos propios;
-   no conceder al propietario acceso económico adicional.

Un miembro nuevo no debe recibir automáticamente detalles privados de
tickets antiguos si la política de tickets de P4 no se lo permite.

Las Rules deben respetar los permisos reales del objeto original.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ HISTORIAL Y SNAPSHOTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

El historial debe seguir siendo comprensible si:

-   cambia el username;
-   cambia el nombre del espacio;
-   un usuario sale;
-   se elimina una amistad;
-   se archiva el espacio;
-   se elimina o anonimiza una cuenta.

Decide qué datos visuales se resuelven en tiempo real y cuáles se
guardan como snapshot.

No almacenes correos, tokens ni datos privados innecesarios en eventos.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ UX FLUTTER
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Implementa como mínimo:

## Actividad global

Una pantalla o sección accesible que muestre eventos ordenados del más
reciente al más antiguo.

Cada fila debe mostrar:

-   actor;
-   acción;
-   objeto;
-   fecha o tiempo relativo;
-   importe y moneda cuando corresponda;
-   espacio cuando aporte contexto.

## Actividad del espacio

Dentro del detalle del espacio:

-   lista de eventos de ese espacio;
-   acceso al ticket, pago o miembro relacionado;
-   paginación.

## Comportamiento

-   tiempo real para eventos recientes;
-   paginación para historial;
-   estado vacío;
-   loading;
-   errores;
-   reintento;
-   nombres largos;
-   importes largos;
-   pantalla pequeña;
-   sin overflows;
-   navegación segura si el objeto fue eliminado o el usuario perdió
    acceso.

No construyas un diseño de red social. Debe ser una cronología funcional
y clara.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ CONSULTAS E ÍNDICES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

No descargues toda la actividad para filtrarla en cliente.

Diseña consultas eficientes para:

-   actividad global del usuario;
-   actividad de un espacio;
-   paginación por fecha;
-   filtro opcional por tipo, solo si resulta sencillo y útil.

Añade los índices necesarios.

Evita modelos que requieran una lista ilimitada de UIDs en
`arrayContainsAny`.

Documenta límites y estrategia de escalabilidad.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ FIRESTORE RULES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Protege:

-   lectura según participantes y membresía;
-   prohibición de escritura directa del cliente, salvo justificación
    fuerte;
-   actor inmutable;
-   referencias inmutables;
-   tipo válido;
-   timestamps del servidor;
-   esquema cerrado;
-   acceso de miembros expulsados;
-   acceso de miembros nuevos;
-   actividad económica privada;
-   usuarios anónimos o no verificados;
-   eventos fraudulentos.

Añade tests positivos y negativos para los tipos principales.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ COMPATIBILIDAD E HISTÓRICO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

No es obligatorio generar retrospectivamente toda la actividad de
P1--P5.

Define explícitamente desde qué momento comienza P6.

Preferencia:

-   eventos nuevos a partir del despliegue;
-   reconstrucción histórica solo para elementos donde aporte valor y
    pueda hacerse de forma idempotente.

No fabriques fechas o actores históricos que no puedan demostrarse.

Los tickets y pagos antiguos deben seguir siendo accesibles desde sus
pantallas aunque no tengan eventos P6.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ TESTS DE P6
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Añade pruebas para:

-   evento de creación de espacio;
-   incorporación y salida de miembro;
-   ticket creado;
-   ticket modificado;
-   pago creado;
-   pago confirmado;
-   pago rechazado o cancelado;
-   idempotencia;
-   reintento de trigger;
-   actor correcto;
-   intento de suplantación;
-   privacidad;
-   miembro nuevo;
-   miembro expulsado;
-   cambio de username;
-   objeto eliminado;
-   paginación;
-   orden cronológico;
-   actualización en tiempo real;
-   navegación;
-   estados vacíos y error;
-   nombres e importes largos;
-   ausencia de duplicados por recompute.

No rompas las suites anteriores.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ DOCUMENTACIÓN
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Crea:

`docs/ACTIVIDAD.md`

Incluye:

-   objetivo;
-   eventos soportados;
-   fuente de verdad;
-   modelo de datos;
-   generación;
-   idempotencia;
-   privacidad;
-   snapshots;
-   consultas;
-   índices;
-   compatibilidad histórica;
-   límites de P6.

Actualiza únicamente la documentación general necesaria:

-   `CLAUDE.md`;
-   `AGENTS.md`;
-   `docs/BIBLIA_SALDA.md`;
-   esquema de Firestore;
-   documentación de espacios, tickets y economía si procede.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ VALIDACIÓN Y PUBLICACIÓN DE P6
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Antes de declarar P6 terminada:

-   análisis estático limpio;
-   tests Flutter verdes;
-   Domain verdes;
-   Functions verdes;
-   Rules contra emulador verdes;
-   web tests verdes;
-   build Flutter;
-   build web;
-   APK debug;
-   CI verde;
-   índices verificados;
-   despliegue solo en `salda-dev`;
-   producción sin tocar;
-   árbol Git limpio;
-   commits claros;
-   rama publicada;
-   PR creada o actualizada.

No mezcles P5 y P6 en un único commit gigante.

Como mínimo conserva hitos recuperables:

1.  cierre y correcciones de P5;
2.  implementación base de P6;
3.  tests, documentación y cierre de P6.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ PROTOCOLO PARA NO QUEDARSE A MEDIAS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Mantén este `/goal` como objetivo principal.

Después de cada hito importante:

-   guarda el trabajo en un commit;
-   registra qué se ha completado;
-   registra qué queda pendiente;
-   evita mantener una gran cantidad de cambios sin commit.

Si se acerca un límite de uso, contexto o tiempo:

1.  detén nuevas implementaciones;
2.  deja el árbol en estado compilable cuando sea posible;
3.  crea un commit de checkpoint claramente nombrado si el código es
    coherente;
4.  entrega un informe de relevo con:
    -   rama;
    -   último commit;
    -   archivos pendientes;
    -   tests ejecutados;
    -   tests pendientes;
    -   fallos reales;
    -   problemas de entorno;
    -   siguiente comando exacto recomendado.

No declares terminada una fase sin resultados verificables.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ INFORME FINAL
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Entrega un informe claro pero no excesivamente largo con:

1.  estado encontrado al tomar el relevo;
2.  qué faltaba realmente de P5;
3.  bugs corregidos en P5;
4.  resultados completos de P5;
5.  commits y PR de P5;
6.  arquitectura de P6;
7.  tipos de actividad implementados;
8.  generación e idempotencia;
9.  privacidad;
10. UX;
11. índices;
12. tests de P6;
13. resultados completos de validación;
14. despliegues;
15. commits y PR de P6;
16. pasos manuales para probar P5 y P6 con tres cuentas.

Detente al terminar P6.

No empieces P7.
