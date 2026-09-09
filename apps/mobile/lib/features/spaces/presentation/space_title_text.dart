import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../profile/data/profile_repository.dart';
import '../data/spaces_repository.dart';
import '../domain/space_models.dart';
import '../domain/space_title.dart';

/// ÚNICO punto de entrada del título de un espacio (BUG-5).
///
/// Antes cada pantalla pintaba `space.name`, y para una relación ese nombre
/// era la concatenación «Edgar · Pedro»: correcta para nadie. Aquí se resuelve
/// en vivo para quien mira, y todas las superficies —Inicio, detalle, chat,
/// selector, tickets, actividad, avatar— leen de este mismo sitio para que no
/// puedan volver a divergir.
final spaceTitleProvider = Provider.autoDispose
    .family<SpaceTitleResolution, String>((ref, spaceId) {
      final currentUid = ref.watch(currentUserIdFromSpacesProvider);
      final spaceAsync = ref.watch(spaceProvider(spaceId));
      final space = spaceAsync.value;
      // Sin el espacio no se sabe ni si es una relación. El nombre que traiga
      // la superficie (el de la lista, el congelado de un evento) es lo mejor
      // disponible: para un grupo ya es el definitivo.
      if (space == null) return const SpaceTitleResolution.storedName();
      if (!space.isRelationship) return const SpaceTitleResolution.storedName();

      // Solo las relaciones con MANUAL necesitan la subcolección; un grupo o
      // una v2 salen sin abrir ese listener.
      final manualsAsync = space.isManualRelationship
          ? ref.watch(spaceManualParticipantsProvider(spaceId))
          : const AsyncValue<List<ManualParticipant>>.data([]);
      final manuals = manualsAsync.value ?? const <ManualParticipant>[];

      final otherUid = spaceTitleProfileUid(
        space: space,
        currentUid: currentUid,
        manuals: manuals,
      );
      final profileAsync = otherUid == null
          ? const AsyncValue<PublicProfile?>.data(null)
          : ref.watch(publicProfileProvider(otherUid));
      final profile = profileAsync.value;

      final resolution = resolveSpaceTitle(
        space: space,
        currentUid: currentUid,
        manuals: manuals,
        manualsLoading: manualsAsync.isLoading && !manualsAsync.hasValue,
        profileLoading:
            otherUid != null &&
            profileAsync.isLoading &&
            !profileAsync.hasValue,
        otherDisplayName: profile?.displayName,
        otherUsername: profile?.username,
      );
      // Una relación que cae al nombre persistido es un dato incoherente o
      // alguien ajeno mirando. Se registra el MOTIVO, nunca identificadores.
      if (resolution.diagnostic != null) {
        debugPrint('titulo de relacion sin resolver: ${resolution.diagnostic}');
      }
      return resolution;
    });

/// Texto final para las superficies que necesitan un `String` y no un widget
/// (frases de actividad, menús, iniciales del avatar).
///
/// [storedName] es el nombre que la superficie ya tenía a mano: el de la
/// lista, o el congelado en un evento de actividad.
String spaceTitleLabel(
  SpaceTitleResolution resolution,
  AppLocalizations l10n,
  String storedName,
) => switch (resolution.source) {
  SpaceTitleSource.person => resolution.person,
  SpaceTitleSource.unnamedPerson => l10n.personUnnamed,
  SpaceTitleSource.storedName => storedName,
  // Se sabe que el nombre persistido no vale, pero aún no se sabe cuál vale.
  SpaceTitleSource.pendingPerson => '',
};

/// Título de un espacio ya resuelto para quien mira.
class SpaceTitleText extends ConsumerWidget {
  const SpaceTitleText({
    super.key,
    required this.spaceId,
    required this.storedName,
    this.style,
    this.maxLines = 1,
    this.format,
  });

  final String spaceId;

  /// Nombre persistido del espacio, usado tal cual en los grupos.
  final String storedName;
  final TextStyle? style;
  final int maxLines;

  /// Envoltorio opcional para los sitios donde el título va dentro de una
  /// frase ("Vincular a X"). No se aplica mientras el título está en blanco:
  /// «Vincular a » sería peor que esperar un fotograma.
  final String Function(String)? format;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = spaceTitleLabel(
      ref.watch(spaceTitleProvider(spaceId)),
      AppLocalizations.of(context),
      storedName,
    );
    return Text(
      (format == null || title.isEmpty) ? title : format!(title),
      style: style,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Título de una INVITACIÓN a un espacio.
///
/// Quien la recibe todavía no puede leer el espacio, así que no hay nada que
/// resolver contra él: lo único disponible es el nombre denormalizado. Para
/// una relación ese nombre es justo el que no sirve, pero el `fromUid` sí
/// identifica a la otra parte — que en una relación es, por definición, la
/// única otra persona.
class SpaceInviteTitle extends ConsumerWidget {
  const SpaceInviteTitle({super.key, required this.invite, this.style});

  final SpaceInvite invite;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    var text = invite.spaceName;
    if (isRelationshipSpaceId(invite.spaceId)) {
      final profile = ref.watch(publicProfileProvider(invite.fromUid));
      text = switch (profile) {
        AsyncData(:final value?) when value.displayName.trim().isNotEmpty =>
          value.displayName.trim(),
        AsyncData(:final value?) when value.username.trim().isNotEmpty =>
          '@${value.username.trim()}',
        AsyncData() => l10n.personUnnamed,
        _ => '',
      };
    }
    return Text(
      text,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
