/// Identidad económica canónica (participantes manuales, ADR-033).
///
/// Toda obligación de P5 se expresa entre dos ACTORES. Un actor es:
///
/// - una cuenta registrada: el UID tal cual (`aBc123…`);
/// - un participante MANUAL: `manual:{manualId}`.
///
/// Los UID de Firebase son alfanuméricos y nunca contienen ':', así que el
/// prefijo no puede colisionar y **los documentos económicos anteriores
/// siguen siendo válidos sin migración**: un valor sin prefijo es, por
/// definición, un actor de cuenta.
///
/// Un participante manual no tiene cuenta, ni UID, ni dispositivo: no lee
/// nada y no confirma nada. Su identidad la custodia el espacio que lo creó.
/// Cuando más adelante se vincule a una cuenta real bastará con reescribir
/// la referencia del actor (o mantener un alias) sin tocar los importes:
/// por eso el identificador es estable y opaco, y nunca es el nombre.
library;

/// Prefijo reservado para actores sin cuenta.
const String manualActorPrefix = 'manual:';

/// Actor económico de un participante manual.
String manualActor(String manualId) {
  if (manualId.isEmpty || manualId.contains(':')) {
    throw ArgumentError.value(manualId, 'manualId', 'Identificador inválido');
  }
  return '$manualActorPrefix$manualId';
}

/// Actor económico de una cuenta registrada (el propio UID).
String accountActor(String uid) {
  if (uid.isEmpty || uid.contains(':')) {
    throw ArgumentError.value(uid, 'uid', 'UID inválido');
  }
  return uid;
}

bool isManualActor(String actor) => actor.startsWith(manualActorPrefix);

/// Los actores de cuenta son los ÚNICOS que pueden leer y confirmar; de ahí
/// que `memberUids` (usado por Rules y por las queries array-contains) se
/// construya solo con ellos.
bool isAccountActor(String actor) =>
    actor.isNotEmpty && !isManualActor(actor);

/// Id del participante manual dentro de su actor, o null si es una cuenta.
String? manualIdOf(String actor) => isManualActor(actor)
    ? actor.substring(manualActorPrefix.length)
    : null;

/// UIDs reales de una pareja de actores, en orden y sin duplicados: la
/// audiencia que puede leer la obligación. Una obligación entre una cuenta y
/// un manual tiene UN solo lector; entre dos manuales, ninguno (nunca se
/// publica globalmente: vive en el balance de su sesión).
List<String> accountUidsOf(
  Iterable<String> actors, [
  Map<String, String> aliases = const {},
]) {
  final uids = <String>{};
  for (final actor in actors) {
    if (isAccountActor(actor)) {
      uids.add(actor);
      continue;
    }
    // VINCULACIÓN (ADR-037): un manual vinculado NO cambia de actor —sigue
    // siendo `manual:{id}`, la clave con la que están escritas todas sus
    // obligaciones— pero su persona pasa a ser LECTORA de lo suyo.
    final manualId = manualIdOf(actor);
    final linked = manualId == null ? null : aliases[manualId];
    if (linked != null) uids.add(linked);
  }
  return uids.toList()..sort();
}

/// Identidad con la que se PRESENTA un actor hoy. Solo para consolidar
/// saldos al leer: la misma persona no debe aparecer como dos deudas
/// partidas. Los documentos no se tocan.
String resolveActorIdentity(
  String actor, [
  Map<String, String> aliases = const {},
]) {
  final manualId = manualIdOf(actor);
  return (manualId == null ? null : aliases[manualId]) ?? actor;
}
