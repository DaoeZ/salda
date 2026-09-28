import 'package:domain/domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ocr_parser/ocr_parser.dart';

import '../data/mlkit_receipt_ocr.dart';
import '../domain/receipt_ocr.dart';

final receiptOcrProvider = Provider<ReceiptOcr>((ref) => MlKitReceiptOcr());

final receiptParserProvider = Provider<ReceiptParser>(
  (ref) => ReceiptParser.standard(),
);

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

  Future<ScanResult?> scanFrom(ImageSource source) async {
    final image = await _picker.pickImage(
      source: source,
      maxWidth: 1600, // presupuesto de la spec §7: ≤1600px
      // q85: buena calidad de ticket y JPEG bien por debajo del límite de 2 MB
      // de la regla de Storage (a q92 una foto detallada podía rozarlo y ser
      // rechazada en silencio). image_picker recodifica a JPEG con esta opción.
      imageQuality: 85,
    );
    if (image == null) return null;
    final document = await ocr.recognize(image.path);
    return ScanResult(
      extraction: parser.parseDocument(document),
      imagePath: image.path,
    );
  }
}

/// La ruta de la imagen se conserva: la IA (M6) la usa como entrada y en
/// M3+ se sube a Storage como foto del ticket.
class ScanResult {
  const ScanResult({required this.extraction, required this.imagePath});

  final ReceiptExtraction extraction;
  final String imagePath;
}
