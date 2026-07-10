import 'package:domain/domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ocr_parser/ocr_parser.dart';

import '../data/mlkit_receipt_ocr.dart';
import '../domain/receipt_ocr.dart';

final receiptOcrProvider = Provider<ReceiptOcr>((ref) => MlKitReceiptOcr());

final receiptParserProvider =
    Provider<ReceiptParser>((ref) => ReceiptParser.standard());

final scanServiceProvider = Provider<ScanService>(
  (ref) => ScanService(
    ocr: ref.watch(receiptOcrProvider),
    parser: ref.watch(receiptParserProvider),
  ),
);

/// Orquesta: elegir imagen (cámara del sistema o galería) → OCR on-device →
/// parser → ReceiptExtraction. Devuelve null si el usuario cancela.
///
/// La captura guiada propia (bordes, auto-disparo) llega con el trabajo en
/// dispositivo; la cámara del sistema ya cubre el flujo completo.
class ScanService {
  ScanService({required this.ocr, required this.parser, ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  final ReceiptOcr ocr;
  final ReceiptParser parser;
  final ImagePicker _picker;

  Future<ReceiptExtraction?> scanFrom(ImageSource source) async {
    final image = await _picker.pickImage(
      source: source,
      maxWidth: 1600, // presupuesto de la spec §7: ≤1600px
      imageQuality: 92,
    );
    if (image == null) return null;
    final document = await ocr.recognize(image.path);
    return parser.parseDocument(document);
  }
}
