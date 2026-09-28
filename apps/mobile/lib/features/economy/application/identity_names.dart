import 'package:domain/domain.dart' show isManualActor, manualIdOf;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/data/profile_repository.dart';
import '../../auth/data/guest_identity_repository.dart';
import '../../sessions/application/session_providers.dart';
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
  final overview = ref.watch(participantEconomicOverviewProvider).value;
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

/// Nombres de MANUALES que solo alcanza el DERECHO HISTÓRICO (A11d).
///
/// Un ex-miembro pierde `manualParticipants` del grupo —y debe perderlo: es
/// el censo entero del contexto—, pero conserva `ticketEntitlements` de los
/// tickets en los que participó económicamente, y ahí viajan congelados los
/// nombres de ESE reparto. Sin este repliegue su propia deuda pasaba a
/// leerse «Persona sin nombre» en cuanto la contraparte era manual.
///
/// Solo se consulta lo que hace falta: un ticket por actor sin resolver, y
/// solo tickets que ya están en SUS obligaciones. No hay agenda histórica.
final historicManualNamesProvider =
    Provider.autoDispose<({Map<String, String> names, bool loading})>((ref) {
      final overview = ref.watch(participantEconomicOverviewProvider).value;
      if (overview == null) return (names: const {}, loading: false);
      final vivos = ref.watch(economicNamesProvider);

      final names = <String, String>{};
      var loading = false;
      for (final entry in overview.entries) {
        for (final actor in [entry.debtorUid, entry.creditorUid]) {
          if (!isManualActor(actor)) continue;
          if (vivos.containsKey(actor) || names.containsKey(actor)) continue;
          final historico = ref.watch(
            historicTicketProvider((sid: entry.sessionId, tid: entry.ticketId)),
          );
          if (historico.isLoading) loading = true;
          final nombre = historico.value?.participantNames[actor];
          if (nombre != null && nombre.isNotEmpty) names[actor] = nombre;
        }
      }
      return (names: names, loading: loading);
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
    // Segundo camino: el nombre congelado en el derecho histórico, para quien
    // ya no puede leer el espacio que custodia el manual.
    final historicos = ref.watch(historicManualNamesProvider);
    final historico = historicos.names[actor];
    if (historico != null) {
      return EconomicName(EconomicNameSource.person, historico);
    }
    // Sin nombre conocido todavía: puede estar cargando el espacio. Se
    // distingue de «no tiene nombre» para no parpadear un rótulo genérico.
    final overview = ref.watch(participantEconomicOverviewProvider);
    if (overview.isLoading || historicos.loading) {
      return const EconomicName(EconomicNameSource.loading);
    }
    // El participante ya no existe o se quedó sin nombre: rótulo controlado.
    // Que `manualIdOf` devuelva algo no autoriza a enseñarlo.
    return const EconomicName(EconomicNameSource.unnamed);
  }

  // Cuenta o invitado: un invitado no tiene perfil público, pero sí una
  // identidad de invitado autorizada para el resto de miembros del espacio.
  final profile = ref.watch(publicProfileProvider(actor));
  final value = profile.value;
  final displayName = (value?.displayName ?? '').trim();
  if (displayName.isNotEmpty) {
    return EconomicName(EconomicNameSource.person, displayName);
  }
  final username = (value?.username ?? '').trim();
  if (username.isNotEmpty) {
    return EconomicName(EconomicNameSource.person, '@$username');
  }
  final guest = ref.watch(guestIdentityProvider(actor));
  final guestName = (guest.value?.displayName ?? '').trim();
  if (guestName.isNotEmpty) {
    return EconomicName(EconomicNameSource.person, guestName);
  }
  if ((profile.isLoading && !profile.hasValue) ||
      (guest.isLoading && !guest.hasValue)) {
    return const EconomicName(EconomicNameSource.loading);
  }
  return const EconomicName(EconomicNameSource.unnamed);
});

/// Semilla estable para el avatar de un actor. Para un manual se usa su id
/// interno —nunca se enseña, solo elige color— de modo que renombrar no
/// cambie el color, igual que con las cuentas.
String economicAvatarSeed(String actor) => manualIdOf(actor) ?? actor;
