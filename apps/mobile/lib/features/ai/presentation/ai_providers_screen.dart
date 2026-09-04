import 'package:ai_providers/ai_providers.dart';
import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/surfaces.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/ai_analysis_controller.dart'
    show aiAvailableProvider, aiRegistryProvider;
import '../data/ai_config_store.dart';

/// Ajustes → Proveedores de IA (RF-30/31/32): configurar clave/URL/modelo,
/// "Probar conexión" OBLIGATORIO antes de poder guardar, y proveedor
/// por defecto. Las claves solo tocan el almacenamiento seguro.
class AiProvidersScreen extends ConsumerStatefulWidget {
  const AiProvidersScreen({super.key});

  @override
  ConsumerState<AiProvidersScreen> createState() => _AiProvidersScreenState();
}

class _AiProvidersScreenState extends ConsumerState<AiProvidersScreen> {
  Map<String, bool> _configured = {};
  String? _preferred;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    // El botón "Analizar con IA" de la revisión depende de este estado.
    ref.invalidate(aiAvailableProvider);
    final store = ref.read(aiConfigStoreProvider);
    final registry = ref.read(aiRegistryProvider);
    final configured = <String, bool>{};
    for (final provider in registry.all) {
      configured[provider.id] = await store.load(provider.id) != null;
    }
    final preferred = await store.preferredProviderId();
    if (mounted) {
      setState(() {
        _configured = configured;
        _preferred = preferred;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final registry = ref.watch(aiRegistryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiTitle)),
      body: ScreenBody(
        children: [
          Text(l10n.aiHint, style: Theme.of(context).textTheme.bodySmall),
          const SectionGap(height: TokenSpacing.lg),
          SectionHeader(title: l10n.aiProvidersSection),
          SaldaCardList(
            children: [
              for (final provider in registry.all)
                ListTile(
                  title: Text(provider.displayName),
                  subtitle: _configured[provider.id] == true
                      ? Text(l10n.aiConfigured)
                      : null,
                  leading: Icon(
                    _configured[provider.id] == true
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    color: _configured[provider.id] == true
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  trailing: _configured[provider.id] == true
                      ? IconButton(
                          tooltip: l10n.aiPreferred,
                          icon: Icon(
                            _preferred == provider.id
                                ? Icons.star
                                : Icons.star_border,
                          ),
                          onPressed: () async {
                            await ref
                                .read(aiConfigStoreProvider)
                                .setPreferred(provider.id);
                            await _refresh();
                          },
                        )
                      : null,
                  onTap: () async {
                    await _configure(provider);
                    await _refresh();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _configure(AiReceiptProvider provider) async {
    final l10n = AppLocalizations.of(context);
    final store = ref.read(aiConfigStoreProvider);
    final existing = await store.load(provider.id);
    if (!mounted) return;

    final key = TextEditingController(text: existing?.apiKey ?? '');
    final baseUrl = TextEditingController(text: existing?.baseUrl ?? '');
    final model = TextEditingController(
      text:
          existing?.model ??
          (provider.suggestedModels.isEmpty
              ? ''
              : provider.suggestedModels.first),
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            var tested = false;
            var testing = false;
            String? testError;
            return StatefulBuilder(
              builder: (sheetContext, setInner) {
                Future<void> test() async {
                  setInner(() {
                    testing = true;
                    testError = null;
                  });
                  try {
                    await provider.testConnection(
                      AiProviderConfig(
                        apiKey: key.text.trim(),
                        baseUrl: baseUrl.text.trim().isEmpty
                            ? null
                            : baseUrl.text.trim(),
                        model: model.text.trim(),
                      ),
                    );
                    setInner(() {
                      tested = true;
                      testing = false;
                    });
                  } on AiProviderException catch (error) {
                    setInner(() {
                      testing = false;
                      testError = _errorText(l10n, error.code);
                    });
                  }
                }

                return Padding(
                  padding: const EdgeInsets.all(TokenSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        provider.displayName,
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                      const SizedBox(height: TokenSpacing.md),
                      TextField(
                        controller: key,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: l10n.aiKey,
                          helperText: provider.requiresApiKey
                              ? null
                              : l10n.aiKeyOptional,
                        ),
                      ),
                      if (provider.requiresBaseUrl) ...[
                        const SizedBox(height: TokenSpacing.md),
                        TextField(
                          controller: baseUrl,
                          decoration: InputDecoration(
                            labelText: l10n.aiBaseUrl,
                            hintText: 'http://localhost:11434/v1',
                          ),
                        ),
                      ],
                      const SizedBox(height: TokenSpacing.md),
                      TextField(
                        controller: model,
                        decoration: InputDecoration(
                          labelText: l10n.aiModel,
                          helperText: provider.suggestedModels.isEmpty
                              ? null
                              : provider.suggestedModels.join(' · '),
                        ),
                      ),
                      if (testError != null) ...[
                        const SizedBox(height: TokenSpacing.sm),
                        Text(
                          testError!,
                          style: TextStyle(
                            color: Theme.of(sheetContext).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: TokenSpacing.lg),
                      Row(
                        children: [
                          if (existing != null)
                            TextButton(
                              onPressed: () async {
                                await store.remove(provider.id);
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                }
                              },
                              child: Text(l10n.lineDelete),
                            ),
                          const Spacer(),
                          FilledButton.tonal(
                            onPressed: testing ? null : test,
                            child: testing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(tested ? l10n.aiTestOk : l10n.aiTest),
                          ),
                          const SizedBox(width: TokenSpacing.sm),
                          FilledButton(
                            // RF-31: guardar SOLO tras probar la conexión.
                            onPressed: !tested
                                ? null
                                : () async {
                                    await store.save(
                                      provider.id,
                                      AiProviderConfig(
                                        apiKey: key.text.trim(),
                                        baseUrl: baseUrl.text.trim().isEmpty
                                            ? null
                                            : baseUrl.text.trim(),
                                        model: model.text.trim(),
                                      ),
                                    );
                                    if (await store.preferredProviderId() ==
                                        null) {
                                      await store.setPreferred(provider.id);
                                    }
                                    if (sheetContext.mounted) {
                                      Navigator.pop(sheetContext);
                                    }
                                  },
                            child: Text(l10n.commonSave),
                          ),
                        ],
                      ),
                      const SizedBox(height: TokenSpacing.sm),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

String _errorText(AppLocalizations l10n, AiErrorCode code) => switch (code) {
  AiErrorCode.invalidKey => l10n.aiErrInvalidKey,
  AiErrorCode.noCredit => l10n.aiErrNoCredit,
  AiErrorCode.rateLimited => l10n.aiErrRateLimited,
  AiErrorCode.modelNotAllowed => l10n.aiErrModel,
  AiErrorCode.badResponse => l10n.aiErrBadResponse,
  AiErrorCode.unsupportedInput => l10n.aiErrBadResponse,
  AiErrorCode.network => l10n.aiErrNetwork,
};

/// Texto de error compartido con la revisión.
String aiErrorText(AppLocalizations l10n, AiErrorCode code) =>
    _errorText(l10n, code);
