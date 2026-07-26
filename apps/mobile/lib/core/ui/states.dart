import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import 'surfaces.dart';

/// Estado vacío: qué pasa, por qué, y qué hacer ahora.
///
/// Sin ilustración genérica y sin texto infantilizado — un icono discreto,
/// una frase que explica y, si existe, UNA acción. Alineado a la izquierda
/// como el resto del contenido: centrar todo hace que parezca un error.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.body,
    this.icon,
    this.action,
    this.onAction,
  });

  final String title;
  final String body;
  final IconData? icon;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.salda;
    final theme = Theme.of(context);
    return SaldaCard(
      color: c.surfaceMuted,
      borderColor: c.border,
      padding: const EdgeInsets.all(TokenSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 22, color: c.textMuted),
            const SizedBox(height: TokenSpacing.md),
          ],
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: TokenSpacing.xs),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(color: c.textSecondary),
          ),
          if (action != null && onAction != null) ...[
            const SizedBox(height: TokenSpacing.lg),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(onPressed: onAction, child: Text(action!)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Error de carga en lenguaje de producto. Nunca muestra la excepción, ni
/// UID, ni rutas, ni códigos: eso va a la consola, no a la pantalla.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.salda;
    final l10n = AppLocalizations.of(context);
    return SaldaCard(
      color: c.negativeMuted,
      borderColor: c.negative.withValues(alpha: 0.35),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: c.negative),
          const SizedBox(width: TokenSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: Theme.of(context).textTheme.bodyMedium),
                if (onRetry != null) ...[
                  const SizedBox(height: TokenSpacing.sm),
                  TextButton(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(l10n.commonRetry),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bloque gris del tamaño del contenido que va a ocupar. Da estabilidad de
/// layout: cuando llegan los datos nada salta de sitio.
class Skeleton extends StatelessWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = TokenRadius.thumbnail,
  });

  const Skeleton.line({super.key, this.width, this.height = 14})
    : radius = TokenRadius.thumbnail;

  const Skeleton.circle({super.key, double size = 40})
    : width = size,
      height = size,
      radius = TokenRadius.pill;

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: context.salda.skeleton,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// Esqueleto de una lista de filas. Se usa en vez de un spinner centrado
/// cuando ya se conoce la ESTRUCTURA de lo que va a llegar.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 3, this.leading = true});

  final int rows;
  final bool leading;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SaldaCardList(
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.all(TokenSpacing.lg),
            child: Row(
              children: [
                if (leading) ...[
                  const Skeleton.circle(size: 36),
                  const SizedBox(width: TokenSpacing.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton.line(width: i.isEven ? 140 : 110),
                      const SizedBox(height: TokenSpacing.sm),
                      const Skeleton.line(width: 76, height: 11),
                    ],
                  ),
                ),
                const Skeleton.line(width: 56, height: 16),
              ],
            ),
          ),
      ],
    ),
  );
}
