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
    final theme = Theme.of(context);
    final messageStyle = theme.textTheme.bodySmall?.copyWith(
      color: c.textPrimary,
    );
    final boton = TextButton(
      onPressed: onAction,
      style: TextButton.styleFrom(
        foregroundColor: fg,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: TokenSpacing.md),
      ),
      child: Text(actionLabel),
    );

    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          TokenLayout.screenMargin,
          TokenSpacing.sm,
          TokenSpacing.sm,
          TokenSpacing.sm,
        ),
        // El aviso cabía en una fila con la escala normal y desbordaba con la
        // ampliada: el botón no se encoge y el mensaje ya iba en `Expanded`.
        // Se MIDE la acción en vez de adivinar un umbral de ancho, y cuando
        // el mensaje se quedaría sin sitio legible, la acción baja de línea.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final anchoIcono = icon == null ? 0.0 : 18 + TokenSpacing.md;
            final anchoAccion =
                _anchoDelTexto(
                  context,
                  actionLabel,
                  theme.textTheme.labelLarge,
                ) +
                TokenSpacing.md * 2;
            final sitioParaElMensaje =
                constraints.maxWidth - anchoIcono - anchoAccion;
            final enLinea = sitioParaElMensaje >= _mensajeMinimo;

            final texto = Text(message, style: messageStyle);
            if (enLinea) {
              return Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: fg),
                    const SizedBox(width: TokenSpacing.md),
                  ],
                  Expanded(child: texto),
                  const SizedBox(width: TokenSpacing.sm),
                  boton,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (icon != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(icon, size: 18, color: fg),
                      ),
                      const SizedBox(width: TokenSpacing.md),
                    ],
                    Expanded(child: texto),
                  ],
                ),
                Align(alignment: AlignmentDirectional.centerEnd, child: boton),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Ancho mínimo en el que el mensaje sigue siendo legible junto a la
  /// acción. Por debajo, apilar cuesta una línea y se lee entero.
  static const _mensajeMinimo = 120.0;

  static double _anchoDelTexto(
    BuildContext context,
    String text,
    TextStyle? style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

enum NoticeTone { info, warning }
