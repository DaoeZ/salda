import 'package:ai_providers/ai_providers.dart';
import 'package:domain/domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/ai/application/ai_analysis_controller.dart';
import 'package:salda_mobile/features/ai/data/ai_config_store.dart';
import 'package:salda_mobile/features/review/application/review_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InMemoryVault implements SecretVault {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}

class FakeAiProvider implements AiReceiptProvider {
  FakeAiProvider({this.failuresBeforeSuccess = 0});

  int failuresBeforeSuccess;
  int calls = 0;

  @override
  String get id => 'fake';
  @override
  String get displayName => 'Fake';
  @override
  bool get supportsVision => false;
  @override
  bool get requiresApiKey => false;
  @override
  bool get requiresBaseUrl => false;
  @override
  List<String> get suggestedModels => const ['fake-1'];

  @override
  Future<void> testConnection(AiProviderConfig config) async {}

  @override
  Future<ReceiptExtraction> extractReceipt(
      AiInput input, AiProviderConfig config) async {
    calls++;
    if (calls <= failuresBeforeSuccess) {
      throw const AiProviderException(AiErrorCode.badResponse, 'mala');
    }
    return ReceiptExtraction(
      engine: 'ai:$id',
      merchantName: const Extracted('IA Resuelto', 0.9),
      lines: [
        const ExtractedLine(
            name: 'Linea IA', totalPrice: Money(500), confidence: 0.9),
      ],
      grandTotal: const Extracted(Money(500), 0.9),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // El draft se persiste en cada loadFrom: el plugin necesita mock en tests.
  SharedPreferences.setMockInitialValues({});

  group('AiConfigStore', () {
    test('roundtrip, preferido con fallback y remove limpia preferido',
        () async {
      final store = AiConfigStore(InMemoryVault());
      expect(await store.load('claude'), isNull);

      await store.save('claude',
          const AiProviderConfig(apiKey: 'sk', model: 'claude-haiku-4-5'));
      final loaded = await store.load('claude');
      expect(loaded!.apiKey, 'sk');
      expect(loaded.model, 'claude-haiku-4-5');

      // Sin preferido explícito: cae al primero configurado.
      final preferred = await store.preferred(['gemini', 'claude']);
      expect(preferred!.providerId, 'claude');

      await store.setPreferred('claude');
      await store.remove('claude');
      expect(await store.preferredProviderId(), isNull);
    });
  });

  group('AiAnalysisController', () {
    ProviderContainer container(FakeAiProvider provider, InMemoryVault vault) {
      final c = ProviderContainer(overrides: [
        secretVaultProvider.overrideWithValue(vault),
        aiRegistryProvider
            .overrideWithValue(AiProviderRegistry([provider])),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<InMemoryVault> vaultWithFake() async {
      final vault = InMemoryVault();
      await AiConfigStore(vault)
          .save('fake', const AiProviderConfig(model: 'fake-1'));
      return vault;
    }

    ReceiptExtraction draft() => ReceiptExtraction(
          engine: 'mlkit',
          lines: [
            const ExtractedLine(
                name: 'X',
                totalPrice: Money(100),
                confidence: 0.4,
                sourceText: 'X 1,00'),
          ],
          grandTotal: const Extracted(Money(999), 0.4),
        );

    test('sustituye el draft por la extracción de la IA', () async {
      final c = container(FakeAiProvider(), await vaultWithFake());
      c.read(reviewDraftProvider.notifier).loadFrom(draft());

      final result =
          await c.read(aiAnalysisControllerProvider.notifier).analyze();

      expect(result.ok, isTrue);
      final newDraft = c.read(reviewDraftProvider)!;
      expect(newDraft.engine, 'ai:fake');
      expect(newDraft.merchantName, 'IA Resuelto');
      expect(newDraft.grandTotal, const Money(500));
    });

    test('badResponse reintenta UNA vez y luego informa', () async {
      final retryOk = FakeAiProvider(failuresBeforeSuccess: 1);
      var c = container(retryOk, await vaultWithFake());
      c.read(reviewDraftProvider.notifier).loadFrom(draft());
      expect((await c.read(aiAnalysisControllerProvider.notifier).analyze()).ok,
          isTrue);
      expect(retryOk.calls, 2);

      final alwaysBad = FakeAiProvider(failuresBeforeSuccess: 99);
      c = container(alwaysBad, await vaultWithFake());
      c.read(reviewDraftProvider.notifier).loadFrom(draft());
      final result =
          await c.read(aiAnalysisControllerProvider.notifier).analyze();
      expect(result.ok, isFalse);
      expect(result.error, AiErrorCode.badResponse);
      expect(alwaysBad.calls, 2); // no bucles
    });

    test('sin proveedor configurado: no hace nada y lo dice', () async {
      final c = container(FakeAiProvider(), InMemoryVault());
      final result =
          await c.read(aiAnalysisControllerProvider.notifier).analyze();
      expect(result.ok, isFalse);
    });
  });
}
