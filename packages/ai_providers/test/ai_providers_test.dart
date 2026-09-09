import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_providers/ai_providers.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// Adapter falso: captura la petición y devuelve la respuesta enlatada.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_FakeAdapter adapter) => Dio()..httpClientAdapter = adapter;

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

const _receiptJson = {
  'merchantName': 'Mercadona',
  'date': '2026-07-10',
  'time': null,
  'category': 'supermercado',
  'lines': [
    {
      'name': 'GAZPACHO',
      'quantityMilli': 1000,
      'unitPrice': null,
      'totalPrice': 180,
    },
    {
      'name': 'LECHE',
      'quantityMilli': 2000,
      'unitPrice': 98,
      'totalPrice': 196,
    },
  ],
  'taxes': [
    {'label': 'IVA 4%', 'amount': 12},
  ],
  'discounts': <Object>[],
  'tip': null,
  'grandTotal': 376,
};

void main() {
  group('parseAiResponse', () {
    test('JSON limpio y con vallas markdown', () {
      for (final wrapper in [
        jsonEncode(_receiptJson),
        '```json\n${jsonEncode(_receiptJson)}\n```',
        'Aquí tienes:\n${jsonEncode(_receiptJson)}\nEspero que sirva.',
      ]) {
        final r = parseAiResponse(wrapper, engine: 'ai:test');
        expect(r.merchantName.value, 'Mercadona');
        expect(r.lines.length, 2);
        expect(r.grandTotal.value?.cents, 376);
        expect(r.issues, isEmpty);
        expect(r.engine, 'ai:test');
      }
    });

    test('descuadre → issue sumMismatch (revisión manual)', () {
      final bad = Map<String, Object?>.from(_receiptJson)..['grandTotal'] = 999;
      final r = parseAiResponse(jsonEncode(bad), engine: 'ai:test');
      expect(r.issues.single.code, 'sumMismatch');
      expect(r.needsReview, isTrue);
    });

    test('basura → badResponse', () {
      expect(
        () => parseAiResponse('no hay json aquí', engine: 'ai:test'),
        throwsA(
          isA<AiProviderException>().having(
            (e) => e.code,
            'code',
            AiErrorCode.badResponse,
          ),
        ),
      );
    });
  });

  group('ClaudeProvider', () {
    test('petición correcta (cabeceras, modelo, imagen) y parseo', () async {
      final adapter = _FakeAdapter(
        (options) => _json({
          'content': [
            {'type': 'text', 'text': jsonEncode(_receiptJson)},
          ],
        }),
      );
      final provider = ClaudeProvider(_dio(adapter));
      final result = await provider.extractReceipt(
        AiInput(imageJpeg: Uint8List.fromList([1, 2, 3])),
        const AiProviderConfig(apiKey: 'sk-test', model: 'claude-haiku-4-5'),
      );

      final request = adapter.lastRequest!;
      expect(request.path, 'https://api.anthropic.com/v1/messages');
      expect(request.headers['x-api-key'], 'sk-test');
      expect(request.headers['anthropic-version'], isNotNull);
      final body = request.data as Map;
      expect(body['model'], 'claude-haiku-4-5');
      final content =
          ((body['messages'] as List).first as Map)['content'] as List;
      expect((content.first as Map)['type'], 'image');
      expect(result.engine, 'ai:claude');
      expect(result.grandTotal.value?.cents, 376);
    });

    test('401 → invalidKey', () async {
      final provider = ClaudeProvider(
        _dio(_FakeAdapter((options) => _json({'error': 'no'}, 401))),
      );
      expect(
        () => provider.testConnection(
          const AiProviderConfig(apiKey: 'mala', model: 'x'),
        ),
        throwsA(
          isA<AiProviderException>().having(
            (e) => e.code,
            'code',
            AiErrorCode.invalidKey,
          ),
        ),
      );
    });
  });

  group('GeminiProvider', () {
    test(
      'clave en cabecera (nunca en la URL) y parseo de candidates',
      () async {
        final adapter = _FakeAdapter(
          (options) => _json({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': jsonEncode(_receiptJson)},
                  ],
                },
              },
            ],
          }),
        );
        final provider = GeminiProvider(_dio(adapter));
        final result = await provider.extractReceipt(
          const AiInput(ocrText: 'TOTAL 3,76'),
          const AiProviderConfig(apiKey: 'g-key', model: 'gemini-2.5-flash'),
        );
        final request = adapter.lastRequest!;
        expect(request.headers['x-goog-api-key'], 'g-key');
        expect(request.uri.query, isNot(contains('g-key')));
        expect(result.merchantName.value, 'Mercadona');
      },
    );
  });

  group('OpenAiCompatibleProvider', () {
    ResponseBody chatResponse(RequestOptions options) => _json({
      'choices': [
        {
          'message': {'content': jsonEncode(_receiptJson)},
        },
      ],
    });

    test(
      'genérico: base URL propia, sin clave (Ollama), barra final',
      () async {
        final adapter = _FakeAdapter(chatResponse);
        final provider = OpenAiCompatibleProvider(_dio(adapter));
        expect(provider.requiresBaseUrl, isTrue);
        await provider.extractReceipt(
          const AiInput(ocrText: 'TOTAL 3,76'),
          const AiProviderConfig(
            baseUrl: 'http://localhost:11434/v1/',
            model: 'llama3.2',
          ),
        );
        final request = adapter.lastRequest!;
        expect(request.path, 'http://localhost:11434/v1/chat/completions');
        expect(request.headers.containsKey('Authorization'), isFalse);
      },
    );

    test('preset (DeepSeek): base fija y Bearer', () async {
      final adapter = _FakeAdapter(chatResponse);
      final provider = AiProviderRegistry([
        OpenAiCompatibleProvider(
          _dio(adapter),
          id: 'deepseek',
          displayName: 'DeepSeek',
          fixedBaseUrl: 'https://api.deepseek.com/v1',
          requiresApiKey: true,
        ),
      ]).byId('deepseek')!;
      await provider.extractReceipt(
        const AiInput(ocrText: 'x'),
        const AiProviderConfig(apiKey: 'dk', model: 'deepseek-chat'),
      );
      final request = adapter.lastRequest!;
      expect(request.path, 'https://api.deepseek.com/v1/chat/completions');
      expect(request.headers['Authorization'], 'Bearer dk');
    });

    test('sin imagen ni texto → unsupportedInput', () {
      final provider = OpenAiCompatibleProvider(_dio(_FakeAdapter(_json)));
      expect(
        () => provider.extractReceipt(
          const AiInput(),
          const AiProviderConfig(baseUrl: 'http://x', model: 'm'),
        ),
        throwsA(
          isA<AiProviderException>().having(
            (e) => e.code,
            'code',
            AiErrorCode.unsupportedInput,
          ),
        ),
      );
    });
  });

  test('registry estándar: los 7 proveedores de la spec', () {
    final registry = AiProviderRegistry.standard(Dio());
    expect(
      registry.all.map((p) => p.id),
      containsAll([
        'claude',
        'gemini',
        'openai',
        'deepseek',
        'glm',
        'openrouter',
        'openai_compatible',
      ]),
    );
    expect(registry.byId('openai_compatible')!.requiresBaseUrl, isTrue);
    expect(registry.byId('claude')!.requiresBaseUrl, isFalse);
  });
}
