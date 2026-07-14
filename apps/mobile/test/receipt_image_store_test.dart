import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/scan/data/receipt_storage.dart';

void main() {
  group('ReceiptImageStore', () {
    late Directory tempDir;
    late ReceiptImageStore store;
    final uploads = <(String, String)>[];

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('salda_receipts_test');
      uploads.clear();
      store = ReceiptImageStore(
        onUploaded: (ticketPath, storagePath) async =>
            uploads.add((ticketPath, storagePath)),
        baseDir: () async => tempDir,
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    const ticketPath = 'sessions/S1/accounts/a0/tickets/T9';

    test('storagePathFor es determinista: receipts/{sid}/{tid}/original.jpg',
        () {
      expect(
        ReceiptImageStore.storagePathFor(ticketPath),
        'receipts/S1/T9/original.jpg',
      );
    });

    test('cacheLocalOriginal + load muestra la copia local al instante '
        '(vale para cámara y galería: es una copia de archivo)', () async {
      // Simula el archivo del picker (da igual el origen).
      final source = File('${tempDir.path}/picker_tmp.jpg');
      await source.writeAsBytes([1, 2, 3, 4, 5]);

      await store.cacheLocalOriginal(ticketPath, source.path);

      // Aunque la foto AÚN no figure subida (imagePath null), se ve local.
      final bytes = await store.load(ticketPath, uploaded: false);
      expect(bytes, [1, 2, 3, 4, 5]);
    });

    test('sin copia local y sin subir → null (no rompe, muestra "sin foto")',
        () async {
      final bytes = await store.load(ticketPath, uploaded: false);
      expect(bytes, isNull);
    });

    test('la copia local sobrevive a recrear el store (misma carpeta base)',
        () async {
      final source = File('${tempDir.path}/picker_tmp.jpg');
      await source.writeAsBytes([9, 9, 9]);
      await store.cacheLocalOriginal(ticketPath, source.path);

      // Nuevo store apuntando a la misma base (simula reinicio de la app).
      final store2 = ReceiptImageStore(
        onUploaded: (_, _) async {},
        baseDir: () async => tempDir,
      );
      final bytes = await store2.load(ticketPath, uploaded: true);
      expect(bytes, [9, 9, 9]);
    });

    test('cada ticket tiene su propia copia (no se pisan)', () async {
      final source = File('${tempDir.path}/picker_tmp.jpg');
      await source.writeAsBytes([1]);
      await store.cacheLocalOriginal(ticketPath, source.path);

      const other = 'sessions/S1/accounts/a1/tickets/T5';
      await source.writeAsBytes([2]);
      await store.cacheLocalOriginal(other, source.path);

      expect(await store.load(ticketPath, uploaded: true), [1]);
      expect(await store.load(other, uploaded: true), [2]);
    });
  });
}
