import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/surfaces.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/session_providers.dart';

/// "¿Quién pagó este ticket?" al añadirlo a una sesión existente.
/// Devuelve el pid elegido o null si se cancela.
///
/// Todas las identidades aparecen igual: una persona sin cuenta puede haber
/// pagado, y el modelo económico ya lo admite (el pagador es un `pid`, no un
/// UID). Distinguirla con un avatar más pobre sería sugerir lo contrario.
Future<String?> showPayerPicker(
  BuildContext context,
  WidgetRef ref,
  String sessionId,
) {
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Consumer(
          builder: (context, ref, _) {
            final participants =
                ref.watch(participantsProvider(sessionId)).value ?? const [];
            final active = participants.where((p) => p.active).toList();
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                TokenLayout.screenMargin,
                0,
                TokenLayout.screenMargin,
                TokenSpacing.xxl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.payerQuestion,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: TokenSpacing.xl),
                  SaldaCardList(
                    children: [
                      for (final p in active)
                        ListTile(
                          leading: SaldaAvatar(
                            // El pid es estable y no cambia al renombrar,
                            // así que el color del avatar tampoco.
                            seed: p.id,
                            label: p.name,
                            radius: 17,
                          ),
                          title: Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: context.salda.textMuted,
                          ),
                          onTap: () => Navigator.pop(sheetContext, p.id),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}
