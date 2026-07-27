import 'package:domain/domain.dart' show isManualActor, manualIdOf;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/data/profile_repository.dart';
import '../../spaces/data/spaces_repository.dart';
import '../data/economic_repository.dart';

/// De dónde sale el nombre visible de una identidad económica.
enum EconomicNameSource {
  /// Nombre real de la persona.
  person,

  /// La identidad existe pero no se le conoce nombre (participante borrado,
  /// perfil ausente, dato heredado en blanco). La pantalla pone un rótulo de
  /// producto: NUNCA el identificador interno.
  unnamed,

  /// Todavía se está resolviendo.
  loading,
}

class EconomicName {
  const EconomicName(this.source, [this.text = '']);

  final EconomicNameSource source;
  final String text;
}

/// Nombres visibles de TODAS las identidades económicas, por actor.
///
/// Existe porque el nombre se resolvía en tres pantallas distintas y las tres
/// caían al mismo sitio cuando no había perfil público: mostrar el actor tal
/// cual. Para una cuenta eso es un UID; para un participante MANUAL es
/// `manual:{id}`, que es lo que se veía en balances, deudas y resúmenes.
///
/// Un MANUAL no tiene perfil público —no tiene cuenta— y su nombre lo
/// custodia el ESPACIO que lo creó (ADR-033). Aquí se reúnen los espacios
/// implicados en las obligaciones y se construye el mapa completo, de modo
/// que ninguna pantalla tenga que interpretar un identificador.
final economicNamesProvider = Provider.autoDispose<Map<String, String>>((ref) {
  final overview = ref.watch(economicOverviewProvider).value;
  if (overview == null) return const {};

  // Espacios que aparecen en alguna obligación: son los únicos que pueden
  // custodiar el nombre de un manual implicado.
  final spaceIds = <String>{
    for (final entry in overview.entries)
      if ((entry.spaceId ?? '').isNotEmpty) entry.spaceId!,
  };

  final names = <String, String>{};
  for (final spaceId in spaceIds) {
    final manuals = ref.watch(spaceManualParticipantsProvider(spaceId)).value;
    for (final manual in manuals ?? const []) {
      final nombre = manual.displayName.trim();
      if (nombre.isNotEmpty) names[manual.actor] = nombre;
    }
  }
  return names;
});

/// Nombre visible de UN actor económico.
///
/// Es el único camino: ninguna pantalla debe deducir un nombre a partir del
/// identificador, ni recortarlo, ni enseñarlo como último recurso.
final economicNameProvider = Provider.autoDispose.family<EconomicName, String>((
  ref,
  actor,
) {
  if (actor.isEmpty) return const EconomicName(EconomicNameSource.unnamed);

  // MANUAL: su nombre vive en el espacio, no en un perfil público.
  if (isManualActor(actor)) {
    final names = ref.watch(economicNamesProvider);
    final nombre = names[actor];
    if (nombre != null) return EconomicName(EconomicNameSource.person, nombre);
    // Sin nombre conocido todavía: puede estar cargando el espacio. Se
    // distingue de «no tiene nombre» para no parpadear un rótulo genérico.
    final overview = ref.watch(economicOverviewProvider);
    if (overview.isLoading) {
      return const EconomicName(EconomicNameSource.loading);
    }
    // El participante ya no existe o se quedó sin nombre: rótulo controlado.
    // Que `manualIdOf` devuelva algo no autoriza a enseñarlo.
    return const EconomicName(EconomicNameSource.unnamed);
  }

  // CUENTA o INVITADO: perfil público.
  final profile = ref.watch(publicProfileProvider(actor));
  if (profile.isLoading && !profile.hasValue) {
    return const EconomicName(EconomicNameSource.loading);
  }
  final value = profile.value;
  final displayName = (value?.displayName ?? '').trim();
  if (displayName.isNotEmpty) {
    return EconomicName(EconomicNameSource.person, displayName);
  }
  final username = (value?.username ?? '').trim();
  if (username.isNotEmpty) {
    return EconomicName(EconomicNameSource.person, '@$username');
  }
  return const EconomicName(EconomicNameSource.unnamed);
});

/// Semilla estable para el avatar de un actor. Para un manual se usa su id
/// interno —nunca se enseña, solo elige color— de modo que renombrar no
/// cambie el color, igual que con las cuentas.
String economicAvatarSeed(String actor) => manualIdOf(actor) ?? actor;
