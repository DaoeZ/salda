import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// El ticket como objeto: una tira de papel más clara que el fondo, con el
/// borde inferior dentado de un corte de impresora.
///
/// Es el ÚNICO recurso físico del sistema y vive solo en el detalle del
/// ticket. Un dentado, sin sombra, sin textura, sin rotación: lo justo para
/// que se lea como comprobante y no como disfraz.
class ReceiptPaper extends StatelessWidget {
  const ReceiptPaper({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      TokenSpacing.xl,
      TokenSpacing.xl,
      TokenSpacing.xl,
      TokenSpacing.lg,
    ),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Alto de cada diente del corte.
  static const double toothDepth = 6;
  static const double _toothWidth = 12;

  @override
  Widget build(BuildContext context) {
    final c = context.salda;
    return CustomPaint(
      painter: _ReceiptEdgePainter(
        fill: c.paper,
        stroke: c.border,
        toothDepth: toothDepth,
        toothWidth: _toothWidth,
      ),
      child: Padding(
        padding: padding.add(const EdgeInsets.only(bottom: toothDepth)),
        // Material transparente: las filas del recibo son pulsables y su
        // tinta necesita un Material ancestro por encima del papel pintado.
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }
}

class _ReceiptEdgePainter extends CustomPainter {
  _ReceiptEdgePainter({
    required this.fill,
    required this.stroke,
    required this.toothDepth,
    required this.toothWidth,
  });

  final Color fill;
  final Color stroke;
  final double toothDepth;
  final double toothWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final bottom = size.height - toothDepth;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, bottom);
    // Dientes repartidos para que el corte cierre exacto en ambos bordes,
    // sea cual sea el ancho.
    final teeth = (size.width / toothWidth).floor().clamp(1, 1000);
    final step = size.width / teeth;
    for (var i = teeth; i > 0; i--) {
      final x = i * step;
      path
        ..lineTo(x - step / 2, size.height)
        ..lineTo(x - step, bottom);
    }
    path.close();
    canvas
      ..drawPath(path, Paint()..color = fill)
      ..drawPath(
        path,
        Paint()
          ..color = stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
  }

  @override
  bool shouldRepaint(_ReceiptEdgePainter old) =>
      old.fill != fill || old.stroke != stroke;
}

/// Filete discontinuo del recibo: separa cabecera, líneas y totales como
/// los guiones de una impresora térmica.
class ReceiptRule extends StatelessWidget {
  const ReceiptRule({super.key, this.vertical = TokenSpacing.md});

  final double vertical;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: vertical),
    child: CustomPaint(
      size: const Size(double.infinity, 1),
      painter: _DashPainter(context.salda.paperRule),
    ),
  );
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 4.0;
    const gap = 3.0;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, 0.5), Offset(x + dash, 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// Renglón de totales del recibo: concepto a la izquierda, importe a la
/// derecha, ambos en la voz mono del comprobante.
class ReceiptTotalRow extends StatelessWidget {
  const ReceiptTotalRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasis = false,
    this.valueColor,
  });

  final String label;
  final String value;

  /// El TOTAL: más cuerpo y peso, como en el papel.
  final bool emphasis;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final c = context.salda;
    final size = emphasis ? 17.0 : 13.5;
    final weight = emphasis ? FontWeight.w700 : FontWeight.w400;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              emphasis ? label.toUpperCase() : label,
              style: SaldaType.mono(
                size: size,
                weight: weight,
                color: emphasis ? c.textPrimary : c.textSecondary,
                tracking: emphasis ? 0.6 : 0,
              ),
            ),
          ),
          const SizedBox(width: TokenSpacing.md),
          Text(
            value,
            maxLines: 1,
            softWrap: false,
            style: SaldaType.mono(
              size: size,
              weight: weight,
              color: valueColor ?? c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
