import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Aviso con acciones: invitación pendiente, solicitud de identidad,
/// borrador recuperable.
///
/// Existe porque el patrón anterior se repetía copiado en cinco pantallas y
/// era el mismo error en todas: texto y botones en la MISMA fila rígida. Con
/// 320 px, escala de texto grande o un nombre largo, los botones no caben y
/// `RenderFlex` desborda. En un `ListTile.trailing` es peor todavía: las
/// restricciones son laxas, así que no hay franja amarilla — el botón
/// simplemente se va fuera de la pantalla y deja de poder pulsarse.
///
/// La estructura fija la jerarquía que el aviso necesita:
///  1. QUÉ hay pendiente ([title]);
///  2. a QUIÉN o a qué grupo corresponde ([subtitle]);
///  3. acción principal y 4. secundaria ([actions], la última a la derecha).
///
/// Las acciones van SIEMPRE en su propia línea, dentro de un [Wrap]: es lo
/// único que no puede desbordar pase lo que pase con el idioma, la escala o
/// la longitud del nombre. El icono se alinea arriba para no bailar cuando
/// el texto ocupa varias líneas.
class ActionBanner extends StatelessWidget {
  const ActionBanner({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.badge,
    this.actions = const <Widget>[],
    this.padding = const EdgeInsets.all(TokenSpacing.lg),
  });

  /// Qué hay pendiente. Se pasa como widget para que quien lo use pueda
  /// componer (un título de espacio en vivo, por ejemplo) sin recortarlo.
  final Widget title;
  final Widget? subtitle;
  final IconData? icon;

  /// Etiqueta de estado bajo el texto (pendiente, caducada…).
  final Widget? badge;

  /// De secundaria a principal: la última queda a la derecha del renglón y
  /// abajo cuando el ancho obliga a apilarlas.
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.salda;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                // Alineado con la primera línea de texto, no centrado en un
                // bloque cuya altura no se conoce de antemano.
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, size: 20, color: c.textSecondary),
                ),
                const SizedBox(width: TokenSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sin maxLines: cortar el texto de una invitación deja al
                    // usuario sin saber a qué le invitan.
                    DefaultTextStyle.merge(
                      style: Theme.of(context).textTheme.bodyMedium,
                      child: title,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      DefaultTextStyle.merge(
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: c.textSecondary),
                        child: subtitle!,
                      ),
                    ],
                    if (badge != null) ...[
                      const SizedBox(height: TokenSpacing.xs),
                      Align(alignment: Alignment.centerLeft, child: badge!),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: TokenSpacing.sm),
            // `Wrap` y no `Row`: cuando dos botones no caben en el ancho
            // disponible pasan a la línea siguiente en vez de desbordar.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: TokenSpacing.sm,
              runSpacing: TokenSpacing.xs,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}
