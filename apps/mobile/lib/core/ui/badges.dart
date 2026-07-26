import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart' show avatarColorIndex, avatarInitials;
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Intención de un estado. Cada una tiene color Y forma propias: el color
/// nunca es el único portador de significado.
enum BadgeTone { neutral, positive, negative, warning, pending, info }

/// Etiqueta de estado compacta: pendiente, aceptada, caducada, saldado…
///
/// Rectángulo de esquina suave, no cápsula: la app ya tiene bastantes
/// píldoras y a cierto tamaño todas se parecen.
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
      padding: const EdgeInsets.symmetric(
        horizontal: TokenSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              height: 1.2,
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
    // En oscuro el disco lleno vibra: se usa un fondo tenue con el color
    // como texto, que es lo mismo que hacen los badges.
    final bg = dark
        ? Color.alphaBlend(base.withValues(alpha: 0.22), context.salda.surface)
        : base;
    final fg = dark ? _lighten(base) : Colors.white;
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
          borderRadius: square ? BorderRadius.circular(radius * 0.55) : null,
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
