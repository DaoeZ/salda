import 'dart:io';
import 'dart:typed_data';

import 'package:ai_providers/ai_providers.dart';
import 'package:dio/dio.dart';
import 'package:domain/domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../review/application/review_draft.dart';
import '../data/ai_config_store.dart';

final aiRegistryProvider = Provider<AiProviderRegistry>(
  (ref) => AiProviderRegistry.standard(Dio(BaseOptions(
    // Sin timeouts, una red caída dejaba el botón de IA colgado para siempre.
    connectTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 120),
  ))),
);

/// Ruta de la última imagen escaneada: la IA la necesita como entrada.
class LastScanImage extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? path) => state = path;
}

final lastScanImageProvider =
    NotifierProvider<LastScanImage, String?>(LastScanImage.new);

/// ¿Hay algún proveedor configurado? Habilita el botón de la revisión.
/// autoDispose + invalidación al guardar (bug del MVP: sin esto, un `false`
/// calculado antes de configurar el proveedor quedaba cacheado para siempre
/// y el botón de IA permanecía muerto).
final aiAvailableProvider = FutureProvider.autoDispose<bool>((ref) async {
  final registry = ref.watch(aiRegistryProvider);
  final preferred = await ref
      .watch(aiConfigStoreProvider)
      .preferred(registry.all.map((p) => p.id));
  return preferred != null;
});

/// Ejecuta el análisis con IA (SIEMPRE bajo acción explícita, DC-13):
/// imagen si el proveedor tiene visión; un único reintento si la
/// respuesta no valida (spec §9.1). El resultado sustituye el draft.
class AiAnalysisController extends Notifier<AsyncValue<String?>> {
  @override
  AsyncValue<String?> build() => const AsyncData(null);

  Future<({bool ok, AiErrorCode? error, String? provider})> analyze() async {
    final registry = ref.read(aiRegistryProvider);
    final stored = await ref
        .read(aiConfigStoreProvider)
        .preferred(registry.all.map((p) => p.id));
    final imagePath = ref.read(lastScanImageProvider);
    if (stored == null) {
      return (ok: false, error: AiErrorCode.unsupportedInput, provider: null);
    }
    final provider = registry.byId(stored.providerId)!;

    Uint8List? image;
    if (provider.supportsVision && imagePath != null) {
      try {
        image = await File(imagePath).readAsBytes();
      } on Object {
        image = null; // la foto ya no está: no bloquea, irá sin imagen
      }
    }
    // Sin imagen, el texto OCR reconstruible es el draft actual serializado.
    final draft = ref.read(reviewDraftProvider);
    final input = AiInput(
      imageJpeg: image,
      ocrText: image == null && draft != null
          ? draft.lines.map((l) => l.sourceText).join('\n')
          : null,
    );

    state = AsyncData(provider.displayName); // "analizando con X"
    try {
      ReceiptExtraction extraction;
      try {
        extraction = await provider.extractReceipt(input, stored.config);
      } on AiProviderException catch (first) {
        if (first.code != AiErrorCode.badResponse) rethrow;
        // Reintento único (spec §9.1).
        extraction = await provider.extractReceipt(input, stored.config);
      }
      ref.read(reviewDraftProvider.notifier).loadFrom(extraction);
      state = const AsyncData(null);
      return (ok: true, error: null, provider: provider.displayName);
    } on AiProviderException catch (error) {
      state = const AsyncData(null);
      return (ok: false, error: error.code, provider: provider.displayName);
    } on Object {
      state = const AsyncData(null);
      return (
        ok: false,
        error: AiErrorCode.network,
        provider: provider.displayName
      );
    }
  }
}

final aiAnalysisControllerProvider =
    NotifierProvider<AiAnalysisController, AsyncValue<String?>>(
        AiAnalysisController.new);
