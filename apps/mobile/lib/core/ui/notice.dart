import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Aviso fino y anclado bajo la barra: perfil por completar, borrador
/// recuperable, nombre de invitado pendiente.
///
/// Sustituye a `MaterialBanner`, que ocupa el alto de una tarjeta y empuja el
/// contenido real hacia abajo. Aquí la altura es la de una fila, el color de
/// fondo lo distingue del contenido y la acción va a la derecha, sin
/// competir con la acción principal de la pantalla.
class Notice extends StatelessWidget {
  const Notice({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.icon,
    this.tone = NoticeTone.info,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final IconData? icon;
  final NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.salda;
    final (fg, bg) = switch (tone) {
      NoticeTone.info => (c.primary, c.primaryMuted),
      NoticeTone.warning => (c.warning, c.accentMuted),
    };
    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          TokenLayout.screenMargin,
          TokenSpacing.sm,
          TokenSpacing.sm,
          TokenSpacing.sm,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: TokenSpacing.md),
            ],
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: c.textPrimary),
              ),
            ),
            const SizedBox(width: TokenSpacing.sm),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: fg,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(
                  horizontal: TokenSpacing.md,
                ),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

enum NoticeTone { info, warning }
