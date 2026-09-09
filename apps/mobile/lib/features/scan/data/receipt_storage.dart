import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../sessions/data/session_repository.dart';

/// Almacén de la foto original del ticket. Convierte cada ticket en un
/// registro COMPLETO y robusto (spec §7, P0.2):
///
///  1. **Copia local DURABLE** (app documents) ligada al ticket, hecha nada
///     más crearlo: sobrevive al cierre de la app y a que el SO limpie la
///     caché del picker. Vale igual para cámara y galería (es una copia de
///     archivo, agnóstica del origen).
///  2. **Subida a Firebase Storage** en `receipts/{sid}/{tid}/original.jpg`
///     con reintento transparente: si falla (red/tamaño), la copia local
///     permanece y la subida se reintenta al abrir el ticket.
///  3. **Lectura local-primero**: instantánea y offline; solo baja de Storage
///     si no hay copia local, y entonces la cachea.
///
/// La ruta de Storage es DETERMINISTA a partir del ticket, así que la copia
/// local y la remota coinciden siempre y no dependen de `imagePath`.
class ReceiptImageStore {
  ReceiptImageStore({
    required this.onUploaded,
    Future<Directory> Function()? baseDir,
    FirebaseStorage? storage,
  }) : _baseDir = baseDir ?? getApplicationDocumentsDirectory,
       _storageOverride = storage;

  /// Registra la ruta de Storage en Firestore al confirmar la subida.
  final Future<void> Function(String ticketPath, String storagePath) onUploaded;
  final Future<Directory> Function() _baseDir;
  final FirebaseStorage? _storageOverride;

  // Perezoso: no toca FirebaseStorage.instance hasta que hace falta (así el
  // store se puede construir y usar en local/tests sin inicializar Firebase).
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  /// `sessions/{sid}/accounts/{aid}/tickets/{tid}` → `receipts/{sid}/{tid}/original.jpg`.
  static String storagePathFor(String ticketPath) {
    final parts = ticketPath.split('/');
    final sid = parts.length > 1 ? parts[1] : 'unknown';
    final tid = parts.isNotEmpty ? parts.last : 'unknown';
    return 'receipts/$sid/$tid/original.jpg';
  }

  Future<File> _localFile(String storagePath) async {
    final dir = await _baseDir();
    final safe = storagePath.replaceAll('/', '_');
    return File('${dir.path}/receipt_images/$safe');
  }

  /// Copia durable de la foto recién capturada, ligada al ticket. Se llama
  /// justo tras crear el ticket con la ruta del picker (cámara o galería).
  Future<void> cacheLocalOriginal(String ticketPath, String sourcePath) async {
    final dest = await _localFile(storagePathFor(ticketPath));
    await dest.parent.create(recursive: true);
    await File(sourcePath).copy(dest.path);
  }

  /// Sube la copia local a Storage y marca `imagePath` al confirmar.
  /// Idempotente: se puede reintentar sin efectos. `true` si quedó subida.
  Future<bool> upload(String ticketPath) async {
    final storagePath = storagePathFor(ticketPath);
    final local = await _localFile(storagePath);
    if (!local.existsSync()) return false;
    try {
      await _storage
          .ref(storagePath)
          .putFile(local, SettableMetadata(contentType: 'image/jpeg'));
      await onUploaded(ticketPath, storagePath);
      return true;
    } on Object catch (error) {
      debugPrint('Subida de foto fallida (reintentable): $error');
      return false;
    }
  }

  /// Bytes para mostrar. Local-primero (instantáneo/offline); si no hay copia
  /// local y el ticket ya figura subido, baja de Storage y cachea. Si hay
  /// copia local pero aún NO figura subido (`imagePath` null: subida pendiente
  /// o fallida), muestra la local y dispara un reintento en segundo plano.
  Future<Uint8List?> load(String ticketPath, {required bool uploaded}) async {
    final storagePath = storagePathFor(ticketPath);
    final local = await _localFile(storagePath);
    if (local.existsSync()) {
      if (!uploaded) unawaited(upload(ticketPath));
      return local.readAsBytes();
    }
    if (!uploaded) return null; // ni copia local ni remota todavía
    try {
      final bytes = await _storage.ref(storagePath).getData(6 * 1024 * 1024);
      if (bytes != null) {
        await local.parent.create(recursive: true);
        await local.writeAsBytes(bytes);
      }
      return bytes;
    } on Object catch (error) {
      debugPrint('Descarga de foto fallida: $error');
      return null;
    }
  }
}

final receiptImageStoreProvider = Provider<ReceiptImageStore>(
  (ref) => ReceiptImageStore(
    onUploaded: (ticketPath, storagePath) => ref
        .read(sessionRepositoryProvider)
        .setTicketImage(ticketPath, storagePath),
  ),
);

/// Bytes de la foto de un ticket, memoizados por (ticketPath, uploaded) para
/// no re-descargar en cada rebuild de la pantalla de detalle.
final ticketImageProvider = FutureProvider.autoDispose
    .family<Uint8List?, ({String ticketPath, bool uploaded})>(
      (ref, key) => ref
          .watch(receiptImageStoreProvider)
          .load(key.ticketPath, uploaded: key.uploaded),
    );
