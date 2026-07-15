import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/session_models.dart';

/// Barra segmentada: verde = confirmado, ámbar = marcado, neutro = pendiente.
/// Los tres tramos proceden de agregados autoritativos, no del gasto total.
class SettlementProgressBar extends StatelessWidget {
  const SettlementProgressBar({
    super.key,
    required this.progress,
    required this.semanticLabel,
    this.height = 6,
  });

  final SettlementProgress progress;
  final String semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: semanticLabel,
      value: '${(progress.confirmedFraction * 100).round()} %',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: SizedBox(
            height: height,
            child: LayoutBuilder(builder: (context, constraints) {
              final confirmedWidth =
                  constraints.maxWidth * progress.confirmedFraction;
              final markedWidth =
                  constraints.maxWidth * progress.markedFraction;
              return Stack(children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: scheme.surfaceContainerHighest,
                  ),
                ),
                if (confirmedWidth > 0)
                  Positioned(
                    left: 0,
                    width: confirmedWidth,
                    top: 0,
                    bottom: 0,
                    child: ColoredBox(color: scheme.settlementConfirmed),
                  ),
                if (markedWidth > 0)
                  Positioned(
                    left: confirmedWidth,
                    width: markedWidth,
                    top: 0,
                    bottom: 0,
                    child: ColoredBox(color: scheme.settlementMarked),
                  ),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}
