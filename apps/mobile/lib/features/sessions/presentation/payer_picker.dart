import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../application/session_providers.dart';

/// "¿Quién pagó este ticket?" al añadirlo a una sesión existente.
/// Devuelve el pid elegido o null si se cancela.
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
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(title: Text(l10n.payerQuestion)),
                for (final p in participants.where((p) => p.active))
                  ListTile(
                    leading: CircleAvatar(
                      radius: 16,
                      child: Text(p.name.isEmpty ? '?' : p.name[0]),
                    ),
                    title: Text(p.name),
                    onTap: () => Navigator.pop(sheetContext, p.id),
                  ),
              ],
            );
          },
        ),
      );
    },
  );
}
