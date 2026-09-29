import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart' show avatarColorIndex, avatarInitials;
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Intención de un estado. Cada una tiene color Y forma propias: el color
/// nunca es el único portador de significado.
enum BadgeTone { neutral, positive, negative, warning, pending, info }

/// Etiqueta de estado compacta: pendiente, aceptada, caducada, saldado…
///
/// Rectángulo de esquina casi recta, sin borde: una anotación al margen del
/// libro, no una píldora. Los hechos cerrados (cobrado, saldado) no usan
/// esto sino [Stamp].
class StatusBadge extends StatelessWidget {
  const StatusBadge(
    this.label, {
    super.key,
    this.tone = BadgeTone.neutral,
    this.icon,
  });

  final String label;
  final BadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.salda;
    final (fg, bg) = switch (tone) {
      BadgeTone.neutral => (c.textSecondary, c.surfaceMuted),
      BadgeTone.positive => (c.positive, c.positiveMuted),
      BadgeTone.negative => (c.negative, c.negativeMuted),
      BadgeTone.warning => (c.warning, c.accentMuted),
      BadgeTone.pending => (c.pending, c.surfaceMuted),
      BadgeTone.info => (c.primary, c.primaryMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(SaldaRadius.badge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          // Flexible porque hay rótulos largos ("Pendiente de confirmar") en
          // filas que además llevan un importe: sin esto la etiqueta empuja
          // y desborda.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar de persona o contexto: iniciales sobre un color derivado de una
/// semilla estable (el UID o el id del espacio), nunca del nombre — así
/// renombrar no cambia el color.
///
/// [square] distingue de un vistazo un CONTEXTO (esquina suave) de una
/// PERSONA (círculo), sin necesidad de leer nada.
class SaldaAvatar extends StatelessWidget {
  const SaldaAvatar({
    super.key,
    required this.seed,
    required this.label,
    this.radius = 20,
    this.square = false,
    this.emoji,
  });

  final String seed;
  final String label;
  final double radius;
  final bool square;
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    final base = Color(
      TokenColors.avatarPalette[avatarColorIndex(
        seed,
        TokenColors.avatarPalette.length,
      )],
    );
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Entintado, no disco lleno: sobre papel, ocho colores saturados
    // compitiendo en una lista eran lo más ruidoso de la pantalla. El color
    // sigue identificando (fondo tenue + iniciales en su tono), sin gritar.
    final bg = Color.alphaBlend(
      base.withValues(alpha: dark ? 0.24 : 0.16),
      context.salda.surface,
    );
    final fg = dark ? _lighten(base) : _darken(base);
    final text = (emoji != null && emoji!.isNotEmpty)
        ? emoji!
        : avatarInitials(label);

    return ExcludeSemantics(
      child: Container(
        width: radius * 2,
        height: radius * 2,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          shape: square ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: square
              ? BorderRadius.circular(SaldaRadius.control)
              : null,
        ),
        child: Text(
          text,
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w600,
            fontSize: radius * 0.72,
            height: 1.1,
          ),
        ),
      ),
    );
  }

  static Color _darken(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0)).toColor();
  }

  static Color _lighten(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness + 0.35).clamp(0.0, 1.0)).toColor();
  }
}

/// Punto de color con forma: acompaña siempre a un rótulo, nunca sustituye
/// al texto.
class ToneDot extends StatelessWidget {
  const ToneDot(this.color, {super.key, this.size = 7});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
