import 'dart:typed_data';

import 'package:domain/domain.dart';

/// Errores tipificados comunes a todos los proveedores (spec §9.1).
enum AiErrorCode {
  invalidKey,
  noCredit,
  rateLimited,
  modelNotAllowed,
  network,
  badResponse,
  unsupportedInput,
}

class AiProviderException implements Exception {
  const AiProviderException(this.code, this.message);

  final AiErrorCode code;
  final String message;

  @override
  String toString() => 'AiProviderException(${code.name}): $message';
}

/// Configuración que introduce el usuario. La API key vive SOLO en el
/// almacenamiento seguro del dispositivo y se inyecta por llamada.
class AiProviderConfig {
  const AiProviderConfig({this.apiKey = '', this.baseUrl, required this.model});

  final String apiKey;

  /// Solo para el proveedor genérico OpenAI-compatible (DC-5).
  final String? baseUrl;
  final String model;
}

/// Entrada de extracción: imagen si el modelo tiene visión; si no, el
/// texto crudo del OCR para que la IA lo estructure.
class AiInput {
  const AiInput({this.imageJpeg, this.ocrText});

  final Uint8List? imageJpeg;
  final String? ocrText;
}

/// Contrato de proveedor (puertos y adaptadores). Añadir un proveedor =
/// implementar esto y registrarlo; nada más cambia (spec §9.1).
abstract interface class AiReceiptProvider {
  String get id;
  String get displayName;
  bool get supportsVision;

  /// false en servidores locales (Ollama, LM Studio) donde la key es opcional.
  bool get requiresApiKey;

  /// true solo en el genérico: el usuario aporta la base URL.
  bool get requiresBaseUrl;

  List<String> get suggestedModels;

  /// Petición mínima real (RF-31): valida clave/URL/modelo sin gastar.
  Future<void> testConnection(AiProviderConfig config);

  Future<ReceiptExtraction> extractReceipt(
      AiInput input, AiProviderConfig config);
}
