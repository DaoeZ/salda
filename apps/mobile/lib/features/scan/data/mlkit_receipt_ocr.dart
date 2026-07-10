import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:ocr_parser/ocr_parser.dart';

import '../domain/receipt_ocr.dart';

/// Adaptador de Google ML Kit Text Recognition v2 (on-device, gratis) al
/// modelo agnóstico del parser. Emite las TextLine de ML Kit como
/// OcrElement; la reconstrucción de filas la hace LineBuilder por geometría.
class MlKitReceiptOcr implements ReceiptOcr {
  @override
  Future<OcrDocument> recognize(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result =
          await recognizer.processImage(InputImage.fromFilePath(imagePath));
      return OcrDocument([
        for (final block in result.blocks)
          for (final line in block.lines)
            OcrElement(
              line.text,
              OcrRect(
                line.boundingBox.left.toDouble(),
                line.boundingBox.top.toDouble(),
                line.boundingBox.right.toDouble(),
                line.boundingBox.bottom.toDouble(),
              ),
            ),
      ]);
    } finally {
      await recognizer.close();
    }
  }
}
