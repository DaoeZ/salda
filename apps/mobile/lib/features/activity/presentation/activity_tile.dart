import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../sessions/presentation/ticket_navigation.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/money_text.dart';
import '../../profile/data/profile_repository.dart';
import '../../spaces/presentation/space_title_text.dart';
import '../domain/activity_models.dart';

/// Texto de la acción por tipo. El objeto va en el propio texto (rótulo
/// congelado) y el actor se resuelve en vivo por UID.
///
/// [spaceName] permite sustituir el nombre CONGELADO del espacio por el que
/// corresponde a quien lee (BUG-5): en una relación, el evento guarda
/// «Edgar · Pedro» y cada uno debe leer a la otra persona. El evento no se
/// reescribe — sigue siendo el rastro de auditoría de P6.
String activityText(
  AppLocalizations l10n,
  ActivityEvent event, {
  String? spaceName,
}) {
  final space = spaceName ?? event.spaceName;
  final ticket = event.ticketName.isEmpty
      ? event.sessionName
      : event.ticketName;
  return switch (event.type) {
    ActivityType.spaceCreated => l10n.activitySpaceCreated(space),
    ActivityType.spaceRenamed => l10n.activitySpaceRenamed(space),
    ActivityType.spaceArchived => l10n.activitySpaceArchived(space),
    ActivityType.spaceReactivated => l10n.activitySpaceReactivated(space),
    ActivityType.spaceTransferred => l10n.activitySpaceTransferred(space),
    ActivityType.inviteSent => l10n.activityInviteSent(space),
    ActivityType.memberJoined => l10n.activityMemberJoined(space),
    ActivityType.memberLeft => l10n.activityMemberLeft(space),
    ActivityType.memberRemoved => l10n.activityMemberRemoved(space),
    ActivityType.ticketCreated => l10n.activityTicketCreated(ticket),
    ActivityType.ticketUpdated => l10n.activityTicketUpdated(ticket),
    ActivityType.ticketLinked => l10n.activityTicketLinked(ticket, space),
    ActivityType.ticketUnlinked => l10n.activityTicketUnlinked(ticket),
    ActivityType.ticketDeleted => l10n.activityTicketDeleted(ticket),
    ActivityType.paymentMarked => l10n.activityPaymentMarked,
    ActivityType.paymentConfirmed => l10n.activityPaymentConfirmed,
    ActivityType.paymentCancelled => l10n.activityPaymentCancelled,
    ActivityType.unknown => l10n.activityUnknown,
  };
}

/// Tiempo relativo compacto ("ahora", "5 min", "3 h", "2 d", fecha).
String relativeTime(AppLocalizations l10n, DateTime? at, DateTime now) {
  if (at == null) return '';
  final delta = now.difference(at);
  if (delta.inMinutes < 1) return l10n.activityNow;
  if (delta.inHours < 1) return l10n.activityMinutesAgo(delta.inMinutes);
  if (delta.inDays < 1) return l10n.activityHoursAgo(delta.inHours);
  if (delta.inDays < 7) return l10n.activityDaysAgo(delta.inDays);
  return '${at.day.toString().padLeft(2, '0')}/'
      '${at.month.toString().padLeft(2, '0')}/${at.year}';
}

class ActivityTile extends ConsumerWidget {
  const ActivityTile({super.key, required this.event});

  final ActivityEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final actor = ref.watch(publicProfileProvider(event.actorUid)).value;
    final actorName = actor?.displayName ?? l10n.activityActorFallback;
    // El nombre congelado sirve de relleno: para un grupo ya es el bueno, y
    // para un espacio al que se perdió el acceso es lo único que queda.
    final spaceId = event.spaceId;
    final resolved = spaceId == null
        ? event.spaceName
        : spaceTitleLabel(
            ref.watch(spaceTitleProvider(spaceId)),
            l10n,
            event.spaceName,
          );
    // El resolver devuelve vacío mientras no sabe el nombre. Una frase con
    // un hueco («Has creado ») se lee peor que un sujeto neutro, así que
    // aquí se sustituye por un marcador y NUNCA por el nombre persistido,
    // que en una relación es justo el que no vale.
    final spaceName = resolved.isEmpty ? l10n.activityLoadingSubject : resolved;

    // Actor, acción, importe y fecha separados visualmente: la frase se
    // escanea en dos líneas fijas en vez de leerse entera.
    return InkWell(
      onTap: () => _open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TokenSpacing.lg,
          vertical: TokenSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SaldaAvatar(seed: event.actorUid, label: actorName, radius: 16),
            const SizedBox(width: TokenSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activityText(l10n, event, spaceName: spaceName),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$actorName · '
                    '${relativeTime(l10n, event.at, DateTime.now())}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.salda.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (event.hasAmount) ...[
              const SizedBox(width: TokenSpacing.md),
              MoneyText(Money(event.amountCents!), size: MoneySize.small),
            ],
          ],
        ),
      ),
    );
  }

  /// Navegación al objeto original. Si ya no existe o se perdió el acceso,
  /// las pantallas destino tienen su propio estado "no disponible": nunca
  /// se rompe la cronología.
  void _open(BuildContext context) {
    final spaceId = event.spaceId;
    final sessionId = event.sessionId;
    final ticketId = event.ticketId;
    if (event.paymentId != null) {
      context.push('/home/economy');
    } else if (sessionId != null &&
        sessionId.isNotEmpty &&
        ticketId != null &&
        ticketId.isNotEmpty) {
      // El evento SÍ identifica un ticket: se abre ese, no el espacio
      // entero. Los eventos antiguos sin `ticketId` caen a las ramas de
      // abajo — nunca se adivina un ticket por su nombre o su importe.
      openTicket(context, sessionId: sessionId, ticketId: ticketId);
    } else if (spaceId != null && spaceId.isNotEmpty) {
      context.push('/home/spaces/$spaceId');
    } else if (sessionId != null && sessionId.isNotEmpty) {
      context.push('/home/session/$sessionId');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).activityGone)),
      );
    }
  }
}

class ActivityEmptyState extends StatelessWidget {
  const ActivityEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TokenSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: TokenSpacing.md),
            Text(
              l10n.activityEmpty,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
