import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/painting.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/money_format.dart';
import '../domain/session_models.dart';

/// Exportaciones de sesión (RF-82/83), generadas 100 % on-device.

/// PDF con resumen, balance por persona, liquidaciones y desglose por cuenta.
Future<Uint8List> buildSessionPdf({
  required SessionDetail detail,
  required List<SessionParticipant> participants,
  required List<Settlement> settlements,
  required List<AccountExport> accounts,
}) async {
  final names = {for (final p in participants) p.id: p.name};
  final document = pw.Document(
    title: detail.summary.name,
    producer: Brand.appName,
  );
  final brand = PdfColor.fromInt(TokenColors.seed);

  pw.Widget row(String left, String right, {bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(child: pw.Text(left)),
            pw.Text(right,
                style: bold
                    ? pw.TextStyle(fontWeight: pw.FontWeight.bold)
                    : null),
          ],
        ),
      );

  document.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    build: (context) => [
      pw.Text(detail.summary.name,
          style: pw.TextStyle(
              fontSize: 22, fontWeight: pw.FontWeight.bold, color: brand)),
      pw.Text('Total: ${formatMoney(detail.summary.grandTotal)}',
          style: const pw.TextStyle(fontSize: 14)),
      pw.SizedBox(height: 16),
      pw.Text('Balance',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
      pw.Divider(color: brand),
      for (final p in participants)
        row(
          p.name,
          'pagó ${formatMoney(detail.balances[p.id]?.paid ?? Money.zero)} · '
          'consumió ${formatMoney(detail.balances[p.id]?.consumed ?? Money.zero)} · '
          'neto ${formatMoney(detail.balances[p.id]?.net ?? Money.zero)}',
        ),
      pw.SizedBox(height: 16),
      pw.Text('Pagos',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
      pw.Divider(color: brand),
      if (settlements.isEmpty) pw.Text('Todo saldado.'),
      for (final s in settlements)
        row(
          '${names[s.from] ?? s.from} → ${names[s.to] ?? s.to}'
          '  (${switch (s.state) {
            SettlementState.pending => 'pendiente',
            SettlementState.marked => 'dice que pagó',
            SettlementState.confirmed => 'confirmado',
          }})',
          formatMoney(s.amount),
        ),
      for (final account in accounts) ...[
        pw.SizedBox(height: 16),
        pw.Text(account.name,
            style:
                pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.Divider(color: brand),
        for (final ticket in account.tickets) ...[
          row(
            '${ticket.merchantName}'
            '${ticket.date == null ? '' : ' · ${ticket.date}'}'
            ' · pagó ${names[ticket.paidBy] ?? '—'}',
            formatMoney(ticket.grandTotal),
            bold: true,
          ),
          for (final line in ticket.lines)
            row(
              line.quantityMilli == 1000
                  ? line.name
                  : line.quantityMilli % 1000 == 0
                      ? '${line.quantityMilli ~/ 1000} × ${line.name}'
                      : '${(line.quantityMilli / 1000).toStringAsFixed(3)} kg ${line.name}',
              formatMoney(line.totalPrice),
            ),
        ],
      ],
      pw.SizedBox(height: 24),
      pw.Text('Generado con ${Brand.appName}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
    ],
  ));
  return document.save();
}

/// Tarjeta-resumen PNG para WhatsApp (RF-83), dibujada con Canvas:
/// determinista, sin árbol de widgets y testeable.
Future<Uint8List> buildSummaryImage({
  required SessionDetail detail,
  required List<SessionParticipant> participants,
}) async {
  const width = 1080.0;
  final rows = participants.length;
  final height = 420.0 + rows * 96.0;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final brand = ui.Color(TokenColors.seed);

  // Fondo y cabecera.
  canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width, height), ui.Paint()..color = const ui.Color(0xFFFAF9F7));
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(0, 0, width, 260), const ui.Radius.circular(0)),
    ui.Paint()..color = brand,
  );

  void text(String value, double x, double y,
      {double size = 36,
      ui.Color color = const ui.Color(0xFF1C1B1A),
      bool bold = false,
      double maxWidth = width - 128}) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, ui.Offset(x, y));
  }

  text(Brand.appName, 64, 48,
      size: 32, color: const ui.Color(0xB3FFFFFF));
  text(detail.summary.name, 64, 96,
      size: 56, color: const ui.Color(0xFFFFFFFF), bold: true);
  text('Total ${formatMoney(detail.summary.grandTotal)}', 64, 176,
      size: 44, color: const ui.Color(0xFFFFFFFF));

  var y = 300.0;
  for (final p in participants) {
    final net = detail.balances[p.id]?.net ?? Money.zero;
    text(p.name, 64, y, size: 40, bold: true, maxWidth: width - 420);
    final amount =
        '${net.cents > 0 ? '+' : ''}${formatMoney(net)}';
    final color = net.cents == 0
        ? const ui.Color(0xFF5F6368)
        : net.cents > 0
            ? ui.Color(TokenColors.balancePositiveLight)
            : ui.Color(TokenColors.balanceNegativeLight);
    // Importe alineado a la derecha (medida previa).
    final measure = TextPainter(
      text: TextSpan(
          text: amount,
          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w600)),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    text(amount, width - 64 - measure.width, y,
        size: 40, color: color, bold: true, maxWidth: 360);
    y += 96;
  }

  text('Abre el enlace para marcar lo tuyo', 64, height - 84,
      size: 30, color: const ui.Color(0xFF5F6368));

  final picture = recorder.endRecording();
  final image = await picture.toImage(width.toInt(), height.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}
