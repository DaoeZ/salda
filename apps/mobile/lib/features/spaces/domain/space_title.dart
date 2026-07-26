/// Título visible de un espacio (BUG-5).
///
/// Un GRUPO tiene nombre propio: "Piso", "Viaje a Madrid". Una RELACIÓN no.
/// Es un contexto de exactamente dos identidades económicas y lo que cada
/// persona espera ver es *la otra*: Edgar ve «Pedro» y Pedro ve «Edgar».
/// Eso no es un dato que pueda persistirse —el mismo documento tiene que
/// leerse distinto según quién mire—, así que se resuelve al LEER.
///
/// Este archivo es Dart puro a propósito: la regla es la parte que hay que
/// poder probar exhaustivamente, y no depende de Firestore ni de Flutter.
library;

import 'space_models.dart';

/// De dónde sale el texto final. La superficie decide cómo pintar cada caso
/// —un título vacío no se pinta igual en una `AppBar` que dentro de una
/// frase de actividad—, pero la DECISIÓN es siempre esta.
enum SpaceTitleSource {
  /// Nombre de la otra identidad. Es el caso normal de una relación.
  person,

  /// La otra identidad existe pero no tiene un nombre legible (perfil
  /// borrado, manual heredado sin nombre). Se pinta un rótulo de producto,
  /// nunca un UID ni `manual:{id}`.
  unnamedPerson,

  /// El nombre persistido del espacio: grupos, y también las relaciones que
  /// no se pueden resolver para quien mira (alguien ajeno, datos
  /// incoherentes). Ahí inventar un título personalizado sería peor.
  storedName,

  /// Es una relación y todavía falta el dato de la otra persona. Se sabe que
  /// el nombre persistido NO sirve, así que no se pinta nada de momento: un
  /// parpadeo de «Edgar · Pedro» es exactamente lo que se está corrigiendo.
  pendingPerson,
}

class SpaceTitleResolution {
  const SpaceTitleResolution._(this.source, {this.person = '', this.diagnostic});

  const SpaceTitleResolution.person(String name)
    : this._(SpaceTitleSource.person, person: name);

  const SpaceTitleResolution.unnamedPerson()
    : this._(SpaceTitleSource.unnamedPerson);

  const SpaceTitleResolution.pendingPerson()
    : this._(SpaceTitleSource.pendingPerson);

  const SpaceTitleResolution.storedName({String? diagnostic})
    : this._(SpaceTitleSource.storedName, diagnostic: diagnostic);

  final SpaceTitleSource source;

  /// Solo con [SpaceTitleSource.person].
  final String person;

  /// Motivo por el que una RELACIÓN no se pudo resolver. Sirve para
  /// diagnóstico: nunca se enseña y nunca contiene identificadores.
  final String? diagnostic;
}

/// UID cuyo perfil público hay que leer para titular este espacio, o `null`
/// si no hace falta ninguno (grupo, relación con MANUAL vista por su
/// propietario, o alguien ajeno al contexto).
///
/// Va aparte de [resolveSpaceTitle] porque la lectura del perfil es
/// asíncrona: primero se decide A QUIÉN mirar y después se resuelve.
String? spaceTitleProfileUid({
  required Space space,
  required String currentUid,
  required List<ManualParticipant> manuals,
}) {
  if (!space.isRelationship || currentUid.isEmpty) return null;

  if (space.isManualRelationship) {
    // El propietario siempre ve al MANUAL, aunque después se vincule: para
    // él la otra identidad sigue siendo la misma persona.
    if (currentUid == space.ownerUid) return null;
    final manual = _manualOf(space, manuals);
    // Quien se vinculó a ese manual ES esa identidad (ADR-037), así que la
    // otra parte es el propietario. Contarlos por separado enseñaría su
    // propio nombre.
    if (manual != null && manual.linkedUid == currentUid) return space.ownerUid;
    return null;
  }

  final other = _otherUidOf(space, currentUid);
  return other;
}

/// Regla de resolución. El orden lexicográfico de `relationshipUids` NO
/// interviene: lo único que decide es excluir la identidad de quien mira.
SpaceTitleResolution resolveSpaceTitle({
  required Space space,
  required String currentUid,
  required List<ManualParticipant> manuals,
  required bool manualsLoading,
  required bool profileLoading,
  String? otherDisplayName,
  String? otherUsername,
}) {
  // Los grupos no se tocan: tienen nombre propio y elegido.
  if (!space.isRelationship) return const SpaceTitleResolution.storedName();
  if (currentUid.isEmpty) {
    return const SpaceTitleResolution.storedName(diagnostic: 'sin-sesion');
  }

  if (space.isManualRelationship) {
    final manual = _manualOf(space, manuals);
    if (currentUid == space.ownerUid) {
      if (manual == null) {
        // Rules crea el manual en el mismo batch que el espacio, así que
        // faltar solo puede ser "todavía no ha llegado" o un dato roto.
        return manualsLoading
            ? const SpaceTitleResolution.pendingPerson()
            : const SpaceTitleResolution.storedName(
                diagnostic: 'relacion-v3-sin-su-manual',
              );
      }
      final name = manual.displayName.trim();
      return name.isEmpty
          ? const SpaceTitleResolution.unnamedPerson()
          : SpaceTitleResolution.person(name);
    }
    if (manual != null && manual.linkedUid == currentUid) {
      // Vinculado: la otra identidad es el propietario.
      return _fromProfile(
        loading: profileLoading,
        displayName: otherDisplayName,
        username: otherUsername,
      );
    }
    if (manualsLoading) return const SpaceTitleResolution.pendingPerson();
    return const SpaceTitleResolution.storedName(diagnostic: 'ajeno-a-la-v3');
  }

  // v2: dos cuentas.
  final uids = space.relationshipUids;
  if (uids.length != 2) {
    return SpaceTitleResolution.storedName(
      diagnostic: 'relacion-con-${uids.length}-identidades',
    );
  }
  if (!uids.contains(currentUid)) {
    return const SpaceTitleResolution.storedName(diagnostic: 'ajeno-a-la-v2');
  }
  if (_otherUidOf(space, currentUid) == null) {
    // La pareja repite UID: no hay "la otra persona" que enseñar.
    return const SpaceTitleResolution.storedName(diagnostic: 'pareja-repetida');
  }
  return _fromProfile(
    loading: profileLoading,
    displayName: otherDisplayName,
    username: otherUsername,
  );
}

/// Mejor nombre disponible de una cuenta o un INVITADO. El `@` solo aparece
/// cuando hay username de verdad: un `@` huérfano no es un nombre.
SpaceTitleResolution _fromProfile({
  required bool loading,
  required String? displayName,
  required String? username,
}) {
  if (loading) return const SpaceTitleResolution.pendingPerson();
  final name = (displayName ?? '').trim();
  if (name.isNotEmpty) return SpaceTitleResolution.person(name);
  final handle = (username ?? '').trim();
  if (handle.isNotEmpty) return SpaceTitleResolution.person('@$handle');
  return const SpaceTitleResolution.unnamedPerson();
}

ManualParticipant? _manualOf(Space space, List<ManualParticipant> manuals) {
  for (final manual in manuals) {
    if (manual.id == space.relationshipManualId) return manual;
  }
  return null;
}

/// El UID de la pareja que NO es el de quien mira. `null` si no hay
/// exactamente uno (dato incoherente).
String? _otherUidOf(Space space, String currentUid) {
  String? found;
  for (final uid in space.relationshipUids) {
    if (uid == currentUid) continue;
    if (found != null) return null;
    found = uid;
  }
  return found;
}
