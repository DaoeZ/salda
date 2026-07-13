import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sessions/data/session_repository.dart';

/// Sube la foto original del ticket a Storage (spec §7:
/// receipts/{sessionId}/{ticketId}/original.jpg) y registra la ruta en el
/// documento. Best-effort: si falla (sin red), la sesión ya está creada y
/// la foto simplemente no aparece — nunca bloquea el flujo.
class ReceiptStorage {
  ReceiptStorage(this._ref);

  final Ref _ref;

  Future<void> uploadOriginal({
    required String sessionId,
    required String ticketPath,
    required String localImagePath,
  }) async {
    try {
      final ticketId = ticketPath.split('/').last;
      final storagePath = 'receipts/$sessionId/$ticketId/original.jpg';
      await FirebaseStorage.instance.ref(storagePath).putFile(
            File(localImagePath),
            SettableMetadata(contentType: 'image/jpeg'),
          );
      await _ref
          .read(sessionRepositoryProvider)
          .setTicketImage(ticketPath, storagePath);
    } on Object catch (error) {
      debugPrint('Subida de foto fallida (no bloqueante): $error');
    }
  }

  /// Bytes de una foto de ticket (el detalle la muestra).
  Future<Uint8List?> download(String storagePath) async {
    try {
      return await FirebaseStorage.instance
          .ref(storagePath)
          .getData(4 * 1024 * 1024);
    } on Object {
      return null;
    }
  }
}

final receiptStorageProvider =
    Provider<ReceiptStorage>((ref) => ReceiptStorage(ref));
