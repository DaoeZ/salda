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

/// PERSONAS distintas que hay hoy en un contexto (BUG-6).
///
/// Es la única respuesta autoritativa a "¿con cuánta gente puedo repartir un
/// gasto?". Contar documentos de membresía respondía a otra pregunta —cuántas
/// CUENTAS hay— y dejaba fuera a quien no tiene ninguna: una persona sin app
/// pesa económicamente igual que una con cuenta (ADR-033).
///
/// [accountUids] son las membresías (cuentas e INVITADOS, que sí tienen UID);
/// [manualLinks] va de `manualId` al UID con el que se vinculó, o null si
/// todavía no lo está.
///
/// Colapsa por [resolveActorIdentity], el mismo criterio con el que recompute
/// consolida saldos: un manual vinculado y su cuenta son UNA persona, no dos.
/// Descarta los identificadores vacíos o con ':' —documentos legacy o rotos—
/// en vez de contarlos como una persona más. No reescribe ningún actor: esto
/// solo cuenta, el histórico se queda como está.
List<String> effectiveEconomicIdentities({
  required Iterable<String> accountUids,
  required Map<String, String?> manualLinks,
}) {
  bool valid(String value) => value.isNotEmpty && !value.contains(':');

  final aliases = <String, String>{
    for (final entry in manualLinks.entries)
      if (valid(entry.key) && entry.value != null && valid(entry.value!))
        entry.key: entry.value!,
  };
  final identities = <String>{};
  for (final uid in accountUids) {
    if (valid(uid)) identities.add(uid);
  }
  for (final manualId in manualLinks.keys) {
    if (!valid(manualId)) continue;
    identities.add(resolveActorIdentity(manualActor(manualId), aliases));
  }
  return identities.toList()..sort();
}
