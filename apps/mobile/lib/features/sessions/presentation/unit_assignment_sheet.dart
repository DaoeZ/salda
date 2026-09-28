import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../application/session_providers.dart';
import '../data/session_repository.dart';
import '../domain/session_models.dart';

/// Quién consume UNA unidad (A10).
///
/// La abre quien tiene autoridad sobre el gasto —quien lo subió, y quien
/// administra el grupo del que nació— para repartir directamente lo que ya
/// sabe: esto es de Alba, esto de Jorge, esto lo compartieron los dos. La
/// persona beneficiaria no tiene que entrar a reclamar nada para que el
/// reparto sea válido.
///
/// Escribe con la MISMA operación por unidad que la autoselección de
/// siempre: una casilla = un par (unidad, persona). Ni mapa completo, ni
/// segundo modelo de asignaciones.
Future<void> showUnitAssignmentSheet(
  BuildContext context,
  WidgetRef ref, {
  required TicketLine line,
  required int unit,
  required String sessionId,
  required String payerName,
  String? myPid,
  bool usesPicking = false,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (sheetContext) => _UnitAssignmentSheet(
    linePath: line.path,
    unit: unit,
    sessionId: sessionId,
    payerName: payerName,
    myPid: myPid,
    usesPicking: usesPicking,
  ),
);

class _UnitAssignmentSheet extends ConsumerWidget {
  const _UnitAssignmentSheet({
    required this.linePath,
    required this.unit,
    required this.sessionId,
    required this.payerName,
    this.myPid,
    this.usesPicking = false,
  });

  final String linePath;
  final int unit;
  final String sessionId;
  final String payerName;

  /// Mi participante en este gasto (null si no lo soy). Solo decide si la
  /// escritura firma la procedencia: marcarme a mí mismo desde aquí es una
  /// autoselección igual que tocar la unidad en el detalle.
  final String? myPid;

  /// A19: tocar una unidad devuelve a esa persona a «eligiendo».
  final bool usesPicking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // En vivo: si otra persona toca la misma unidad mientras esta hoja está
    // abierta, se ve. El feedback de concurrencia fino es A19.
    final lines = ref.watch(
      ticketLinesProvider(linePath.split('/lines/').first),
    );
    final line = lines.value
        ?.where((l) => l.path == linePath)
        .cast<TicketLine?>()
        .firstWhere((l) => true, orElse: () => null);
    final participants =
        ref.watch(participantsProvider(sessionId)).value ??
        const <SessionParticipant>[];
    // Solo quien sigue en el reparto recibe consumo NUEVO. Lo que ya
    // estuviera asignado no se toca por dejar de estar activo.
    final elegibles = [
      for (final p in participants)
        if (p.active) p,
    ]..sort((a, b) => a.order.compareTo(b.order));
    final consumers = line?.consumersOf(unit) ?? const <String>[];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(TokenSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.unitAssignTitle(unit + 1),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: TokenSpacing.xs),
            Text(
              consumers.isEmpty
                  ? l10n.unitAssignResidual(payerName)
                  : l10n.unitAssignShareHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: TokenSpacing.md),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final participant in elegibles)
                    CheckboxListTile(
                      value: consumers.contains(participant.id),
                      title: Text(participant.name),
                      onChanged: line == null
                          ? null
                          : (value) => _set(
                              context,
                              ref,
                              l10n,
                              participantId: participant.id,
                              selected: value ?? false,
                            ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: TokenSpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.commonDone),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _set(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n, {
    required String participantId,
    required bool selected,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(sessionRepositoryProvider)
          .setUnitConsumer(
            linePath,
            unit: unit,
            participantId: participantId,
            selected: selected,
            myPid: myPid,
            usesPicking: usesPicking,
          );
    } on Object {
      // La autoridad real la aplican las Rules; si rechazan, se dice.
      messenger.showSnackBar(SnackBar(content: Text(l10n.ticketPickError)));
    }
  }
}
