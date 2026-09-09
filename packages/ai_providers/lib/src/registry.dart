import 'package:dio/dio.dart';

import 'contract.dart';
import 'providers.dart';

/// Registro de proveedores (spec §9.1): añadir uno = una entrada aquí.
/// OpenAI/DeepSeek/GLM/OpenRouter son PRESETS del genérico OpenAI-compatible
/// (misma API, base URL fija): cobertura completa sin duplicar adaptadores.
class AiProviderRegistry {
  AiProviderRegistry(List<AiReceiptProvider> providers)
    : _byId = {for (final p in providers) p.id: p};

  factory AiProviderRegistry.standard(Dio dio) => AiProviderRegistry([
    ClaudeProvider(dio),
    GeminiProvider(dio),
    OpenAiCompatibleProvider(
      dio,
      id: 'openai',
      displayName: 'OpenAI',
      fixedBaseUrl: 'https://api.openai.com/v1',
      requiresApiKey: true,
      suggestedModels: const ['gpt-4o-mini', 'gpt-4.1-mini'],
    ),
    OpenAiCompatibleProvider(
      dio,
      id: 'deepseek',
      displayName: 'DeepSeek',
      fixedBaseUrl: 'https://api.deepseek.com/v1',
      requiresApiKey: true,
      supportsVision: false,
      suggestedModels: const ['deepseek-chat'],
    ),
    OpenAiCompatibleProvider(
      dio,
      id: 'glm',
      displayName: 'GLM (Zhipu)',
      fixedBaseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      requiresApiKey: true,
      suggestedModels: const ['glm-4.6', 'glm-4.5-air'],
    ),
    OpenAiCompatibleProvider(
      dio,
      id: 'openrouter',
      displayName: 'OpenRouter',
      fixedBaseUrl: 'https://openrouter.ai/api/v1',
      requiresApiKey: true,
      suggestedModels: const ['anthropic/claude-haiku-4.5'],
    ),
    // El genérico SIEMPRE el último: URL propia (Ollama, LM Studio…).
    OpenAiCompatibleProvider(dio),
  ]);

  final Map<String, AiReceiptProvider> _byId;

  List<AiReceiptProvider> get all => _byId.values.toList(growable: false);

  AiReceiptProvider? byId(String id) => _byId[id];
}
