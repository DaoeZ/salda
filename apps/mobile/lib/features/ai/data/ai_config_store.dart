import 'dart:convert';

import 'package:ai_providers/ai_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Bóveda clave-valor tras interfaz: la real es Keystore/Keychain
/// (flutter_secure_storage); los tests usan una en memoria.
abstract interface class SecretVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureStorageVault implements SecretVault {
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Configuración guardada de un proveedor. La API key SOLO vive aquí
/// (RF-32): jamás en Firestore, logs, crashes ni en el backup JSON.
class AiConfigStore {
  AiConfigStore(this._vault);

  final SecretVault _vault;

  static String _key(String providerId) => 'ai.$providerId.config';
  static const _preferredKey = 'ai.preferred';

  Future<AiProviderConfig?> load(String providerId) async {
    final raw = await _vault.read(_key(providerId));
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return AiProviderConfig(
      apiKey: (json['apiKey'] as String?) ?? '',
      baseUrl: json['baseUrl'] as String?,
      model: (json['model'] as String?) ?? '',
    );
  }

  Future<void> save(String providerId, AiProviderConfig config) =>
      _vault.write(
        _key(providerId),
        jsonEncode({
          'apiKey': config.apiKey,
          'baseUrl': config.baseUrl,
          'model': config.model,
        }),
      );

  Future<void> remove(String providerId) async {
    await _vault.delete(_key(providerId));
    if (await preferredProviderId() == providerId) {
      await _vault.delete(_preferredKey);
    }
  }

  Future<String?> preferredProviderId() => _vault.read(_preferredKey);

  Future<void> setPreferred(String providerId) =>
      _vault.write(_preferredKey, providerId);

  /// Config del proveedor preferido (o el primero configurado).
  Future<({String providerId, AiProviderConfig config})?> preferred(
      Iterable<String> providerIds) async {
    final preferredId = await preferredProviderId();
    if (preferredId != null) {
      final config = await load(preferredId);
      if (config != null) return (providerId: preferredId, config: config);
    }
    for (final id in providerIds) {
      final config = await load(id);
      if (config != null) return (providerId: id, config: config);
    }
    return null;
  }
}

final secretVaultProvider =
    Provider<SecretVault>((ref) => SecureStorageVault());

final aiConfigStoreProvider =
    Provider<AiConfigStore>((ref) => AiConfigStore(ref.watch(secretVaultProvider)));
