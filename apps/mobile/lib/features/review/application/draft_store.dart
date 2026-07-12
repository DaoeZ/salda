import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistencia del borrador de revisión (spec §4.3): si la app muere a
/// mitad de un escaneo, el ticket se recupera al volver a abrir.
/// Se serializa como ReceiptExtraction (el contrato canónico ya tiene JSON).
class DraftStore {
  static const _key = 'review_draft_v1';

  Future<void> save(ReceiptExtraction extraction) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(extraction.toJson()));
  }

  Future<ReceiptExtraction?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return ReceiptExtraction.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      await prefs.remove(_key); // corrupto: mejor perderlo que romper
      return null;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

final draftStoreProvider = Provider<DraftStore>((ref) => DraftStore());

/// Borrador guardado de una sesión anterior (null si no hay).
final savedDraftProvider = FutureProvider<ReceiptExtraction?>(
    (ref) => ref.watch(draftStoreProvider).load());
