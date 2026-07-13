import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import 'contract.dart';
import 'prompt.dart';

/// Mapeo común de errores HTTP a códigos tipificados (spec §9.1).
AiProviderException mapHttpError(Object error) {
  if (error is AiProviderException) return error;
  if (error is DioException) {
    final status = error.response?.statusCode;
    return switch (status) {
      401 || 403 => const AiProviderException(
          AiErrorCode.invalidKey, 'Clave inválida o sin permisos'),
      402 => const AiProviderException(
          AiErrorCode.noCredit, 'Sin crédito en el proveedor'),
      404 => const AiProviderException(
          AiErrorCode.modelNotAllowed, 'Modelo no disponible'),
      429 => const AiProviderException(
          AiErrorCode.rateLimited, 'Límite de peticiones alcanzado'),
      _ => AiProviderException(
          AiErrorCode.network, 'Error de red (${status ?? error.type.name})'),
    };
  }
  return AiProviderException(AiErrorCode.network, '$error');
}

String _userContent(AiInput input) {
  if (input.imageJpeg == null && (input.ocrText ?? '').isEmpty) {
    throw const AiProviderException(
        AiErrorCode.unsupportedInput, 'Sin imagen ni texto OCR');
  }
  return input.ocrText == null || input.ocrText!.isEmpty
      ? extractionPrompt
      : '$extractionPrompt\nTexto OCR del ticket:\n${input.ocrText}';
}

/// ── Claude (Anthropic) ────────────────────────────────────────────────────
class ClaudeProvider implements AiReceiptProvider {
  ClaudeProvider(this._dio);

  final Dio _dio;
  static const _base = 'https://api.anthropic.com/v1';
  static const _version = '2023-06-01';

  @override
  String get id => 'claude';
  @override
  String get displayName => 'Claude (Anthropic)';
  @override
  bool get supportsVision => true;
  @override
  bool get requiresApiKey => true;
  @override
  bool get requiresBaseUrl => false;
  @override
  List<String> get suggestedModels =>
      const ['claude-haiku-4-5', 'claude-sonnet-5'];

  Map<String, String> _headers(AiProviderConfig config) => {
        'x-api-key': config.apiKey,
        'anthropic-version': _version,
      };

  @override
  Future<void> testConnection(AiProviderConfig config) async {
    try {
      await _dio.get<Object>('$_base/models',
          options: Options(headers: _headers(config)));
    } on Object catch (error) {
      throw mapHttpError(error);
    }
  }

  @override
  Future<ReceiptExtraction> extractReceipt(
      AiInput input, AiProviderConfig config) async {
    final text = _userContent(input);
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$_base/messages',
        options: Options(headers: _headers(config)),
        data: {
          'model': config.model,
          'max_tokens': 2000,
          'messages': [
            {
              'role': 'user',
              'content': [
                if (input.imageJpeg != null)
                  {
                    'type': 'image',
                    'source': {
                      'type': 'base64',
                      'media_type': 'image/jpeg',
                      'data': base64Encode(input.imageJpeg!),
                    },
                  },
                {'type': 'text', 'text': text},
              ],
            },
          ],
        },
      );
      final content =
          ((response.data!['content'] as List).first as Map)['text'] as String;
      return parseAiResponse(content, engine: 'ai:$id');
    } on Object catch (error) {
      throw mapHttpError(error);
    }
  }
}

/// ── Gemini (Google) ───────────────────────────────────────────────────────
class GeminiProvider implements AiReceiptProvider {
  GeminiProvider(this._dio);

  final Dio _dio;
  static const _base = 'https://generativelanguage.googleapis.com/v1beta';

  @override
  String get id => 'gemini';
  @override
  String get displayName => 'Gemini (Google)';
  @override
  bool get supportsVision => true;
  @override
  bool get requiresApiKey => true;
  @override
  bool get requiresBaseUrl => false;
  @override
  List<String> get suggestedModels =>
      const ['gemini-2.5-flash', 'gemini-2.5-pro'];

  // La clave va en cabecera, NUNCA en la query (no acabar en logs/URLs).
  Map<String, String> _headers(AiProviderConfig config) =>
      {'x-goog-api-key': config.apiKey};

  @override
  Future<void> testConnection(AiProviderConfig config) async {
    try {
      await _dio.get<Object>('$_base/models',
          options: Options(headers: _headers(config)));
    } on Object catch (error) {
      throw mapHttpError(error);
    }
  }

  @override
  Future<ReceiptExtraction> extractReceipt(
      AiInput input, AiProviderConfig config) async {
    final text = _userContent(input);
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$_base/models/${config.model}:generateContent',
        options: Options(headers: _headers(config)),
        data: {
          'contents': [
            {
              'parts': [
                if (input.imageJpeg != null)
                  {
                    'inline_data': {
                      'mime_type': 'image/jpeg',
                      'data': base64Encode(input.imageJpeg!),
                    },
                  },
                {'text': text},
              ],
            },
          ],
        },
      );
      final content = ((((response.data!['candidates'] as List).first
                  as Map)['content'] as Map)['parts'] as List)
          .map((p) => (p as Map)['text'] as String? ?? '')
          .join();
      return parseAiResponse(content, engine: 'ai:$id');
    } on Object catch (error) {
      throw mapHttpError(error);
    }
  }
}

/// ── Compatible OpenAI ─────────────────────────────────────────────────────
/// El genérico (base URL del usuario: Ollama, LM Studio, vLLM, servidores
/// propios) y, con [fixedBaseUrl], los presets de OpenAI/DeepSeek/GLM/
/// OpenRouter — misma implementación, cero duplicación (DC-5).
class OpenAiCompatibleProvider implements AiReceiptProvider {
  OpenAiCompatibleProvider(
    this._dio, {
    this.id = 'openai_compatible',
    this.displayName = 'Compatible OpenAI (URL propia)',
    this.fixedBaseUrl,
    this.requiresApiKey = false,
    this.supportsVision = true,
    this.suggestedModels = const [],
  });

  final Dio _dio;
  @override
  final String id;
  @override
  final String displayName;
  final String? fixedBaseUrl;
  @override
  final bool requiresApiKey;
  @override
  final bool supportsVision;
  @override
  final List<String> suggestedModels;

  @override
  bool get requiresBaseUrl => fixedBaseUrl == null;

  String _base(AiProviderConfig config) {
    final base = fixedBaseUrl ?? config.baseUrl ?? '';
    if (base.isEmpty) {
      throw const AiProviderException(
          AiErrorCode.network, 'Falta la base URL');
    }
    return base.replaceAll(RegExp(r'/+$'), '');
  }

  Map<String, String> _headers(AiProviderConfig config) => {
        if (config.apiKey.isNotEmpty)
          'Authorization': 'Bearer ${config.apiKey}',
      };

  @override
  Future<void> testConnection(AiProviderConfig config) async {
    try {
      await _dio.get<Object>('${_base(config)}/models',
          options: Options(headers: _headers(config)));
    } on Object catch (error) {
      throw mapHttpError(error);
    }
  }

  @override
  Future<ReceiptExtraction> extractReceipt(
      AiInput input, AiProviderConfig config) async {
    final text = _userContent(input);
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${_base(config)}/chat/completions',
        options: Options(headers: _headers(config)),
        data: {
          'model': config.model,
          'max_tokens': 2000,
          'messages': [
            {
              'role': 'user',
              'content': input.imageJpeg == null
                  ? text
                  : [
                      {'type': 'text', 'text': text},
                      {
                        'type': 'image_url',
                        'image_url': {
                          'url': 'data:image/jpeg;base64,'
                              '${base64Encode(input.imageJpeg!)}',
                        },
                      },
                    ],
            },
          ],
        },
      );
      final content = (((response.data!['choices'] as List).first
              as Map)['message'] as Map)['content'] as String;
      return parseAiResponse(content, engine: 'ai:$id');
    } on Object catch (error) {
      throw mapHttpError(error);
    }
  }
}
