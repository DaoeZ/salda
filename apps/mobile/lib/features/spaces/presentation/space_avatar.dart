import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../domain/space_models.dart';
import 'space_title_text.dart';

/// Avatar básico de un espacio: emoji opcional o inicial del nombre, sobre
/// un color CONSISTENTE derivado del id (misma primitiva que las personas).
///
/// Las iniciales salen del MISMO título resuelto que la pantalla (BUG-5): en
/// una relación sacarlas de `space.name` daba «EP» de «Edgar · Pedro», las
/// dos personas mezcladas en un avatar que representa a una.
class SpaceAvatar extends ConsumerWidget {
  const SpaceAvatar({super.key, required this.space, this.radius = 20});

  final Space space;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = Color(
      TokenColors.avatarPalette[avatarColorIndex(
        space.id,
        TokenColors.avatarPalette.length,
      )],
    );
    final emoji = space.avatarEmoji;
    final title = spaceTitleLabel(
      ref.watch(spaceTitleProvider(space.id)),
      AppLocalizations.of(context),
      space.name,
    );
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        (emoji != null && emoji.isNotEmpty) ? emoji : avatarInitials(title),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}
