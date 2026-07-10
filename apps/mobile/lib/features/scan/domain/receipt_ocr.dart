import 'package:ocr_parser/ocr_parser.dart';

/// Puerto del motor OCR: la app depende de esta interfaz, no de ML Kit.
/// Permite testear el flujo con dobles y cambiar de motor sin tocar nada.
abstract interface class ReceiptOcr {
  Future<OcrDocument> recognize(String imagePath);
}
