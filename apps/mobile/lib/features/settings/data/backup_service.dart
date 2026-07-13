import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:domain/domain.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Copia de seguridad completa en JSON (spec §14, RF-90/91).
///
/// - Los Timestamp se envuelven como {'__t': iso} para un roundtrip sin
///   ambigüedad (JSON no tiene tipo fecha).
/// - Al importar, los shareCodes SIEMPRE se regeneran (los del backup se
///   consideran quemados) y el ownerUid se fuerza al usuario actual (así un
///   backup sirve para migrar de cuenta).
/// - Importar reemplaza el contenido de las sesiones incluidas (se purgan
///   sus subdocumentos antes de escribir). Con `replace: true` además se
///   borran las sesiones propias que NO estén en el backup.
class BackupService {
  BackupService({
    required this.firestore,
    required this.uid,
    required this.shareCodeFactory,
  });

  final FirebaseFirestore firestore;
  final String Function() uid;
  final String Function() shareCodeFactory;

  static const format = 'appcuentas-backup';

  // ── Exportar ───────────────────────────────────────────────────────────

  Future<Map<String, Object?>> exportAll() async {
    final owner = uid();
    final user = await firestore.doc('users/$owner').get();
    final frequentPeople =
        await firestore.collection('users/$owner/frequentPeople').get();
    final sessions = await firestore
        .collection('sessions')
        .where('ownerUid', isEqualTo: owner)
        .get();

    return {
      'format': format,
      'schemaVersion': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'user': {
        'profile': _encode(user.data() ?? {}),
        'frequentPeople': [
          for (final d in frequentPeople.docs)
            {'id': d.id, 'data': _encode(d.data())},
        ],
      },
      'sessions': [
        for (final session in sessions.docs) await _exportSession(session),
      ],
    };
  }

  Future<Map<String, Object?>> _exportSession(
      QueryDocumentSnapshot<Map<String, dynamic>> session) async {
    Future<List<Map<String, Object?>>> docsOf(String path) async => [
          for (final d
              in (await session.reference.collection(path).get()).docs)
            {'id': d.id, 'data': _encode(d.data())},
        ];

    final accounts = <Map<String, Object?>>[];
    for (final account
        in (await session.reference.collection('accounts').get()).docs) {
      final tickets = <Map<String, Object?>>[];
      for (final ticket
          in (await account.reference.collection('tickets').get()).docs) {
        tickets.add({
          'id': ticket.id,
          'data': _encode(ticket.data()),
          'lines': [
            for (final line
                in (await ticket.reference.collection('lines').get()).docs)
              {'id': line.id, 'data': _encode(line.data())},
          ],
        });
      }
      accounts.add(
          {'id': account.id, 'data': _encode(account.data()), 'tickets': tickets});
    }

    return {
      'id': session.id,
      'data': _encode(session.data()),
      'participants': await docsOf('participants'),
      'accounts': accounts,
      'settlements': await docsOf('settlements'),
      'activity': await docsOf('activity'),
    };
  }

  // ── Resumen previo al import (RF-91) ───────────────────────────────────

  ({int sessions, int tickets, int lines}) summarize(
      Map<String, Object?> backup) {
    var tickets = 0;
    var lines = 0;
    final sessions = (backup['sessions'] as List?) ?? const [];
    for (final s in sessions.cast<Map<String, Object?>>()) {
      for (final a
          in ((s['accounts'] as List?) ?? const []).cast<Map<String, Object?>>()) {
        final ts = ((a['tickets'] as List?) ?? const []);
        tickets += ts.length;
        for (final t in ts.cast<Map<String, Object?>>()) {
          lines += ((t['lines'] as List?) ?? const []).length;
        }
      }
    }
    return (sessions: sessions.length, tickets: tickets, lines: lines);
  }

  // ── Importar ───────────────────────────────────────────────────────────

  Future<void> import(Map<String, Object?> backup,
      {required bool replace}) async {
    if (backup['format'] != format || backup['schemaVersion'] != 1) {
      throw const DomainException('invalidBackup', 'Formato no reconocido');
    }
    final owner = uid();
    final sessions =
        ((backup['sessions'] as List?) ?? const []).cast<Map<String, Object?>>();
    final importedIds = {for (final s in sessions) s['id'] as String};

    if (replace) {
      final existing = await firestore
          .collection('sessions')
          .where('ownerUid', isEqualTo: owner)
          .get();
      for (final doc in existing.docs) {
        if (!importedIds.contains(doc.id)) {
          await doc.reference.delete(); // cleanup cascada el resto
        }
      }
    }

    final user = (backup['user'] as Map?)?.cast<String, Object?>();
    if (user != null) {
      await firestore.doc('users/$owner').set(
            _decode((user['profile'] as Map?)?.cast<String, Object?>() ?? {}),
            SetOptions(merge: true),
          );
      for (final person in ((user['frequentPeople'] as List?) ?? const [])
          .cast<Map<String, Object?>>()) {
        await firestore
            .doc('users/$owner/frequentPeople/${person['id']}')
            .set(_decode((person['data'] as Map).cast<String, Object?>()));
      }
    }

    for (final session in sessions) {
      await _importSession(session, owner);
    }
  }

  Future<void> _importSession(
      Map<String, Object?> session, String owner) async {
    final ref = firestore.doc('sessions/${session['id']}');

    // Purga de subdocumentos existentes: el import REEMPLAZA la sesión.
    for (final path in [
      'participants',
      'settlements',
      'activity',
      'guestAccess',
    ]) {
      for (final doc in (await ref.collection(path).get()).docs) {
        await doc.reference.delete();
      }
    }
    for (final account in (await ref.collection('accounts').get()).docs) {
      for (final ticket
          in (await account.reference.collection('tickets').get()).docs) {
        for (final line
            in (await ticket.reference.collection('lines').get()).docs) {
          await line.reference.delete();
        }
        await ticket.reference.delete();
      }
      await account.reference.delete();
    }

    final data = _decode((session['data'] as Map).cast<String, Object?>());
    data['ownerUid'] = owner;
    data['shareCode'] = shareCodeFactory(); // los códigos del backup, quemados
    data['schemaVersion'] = 1;
    await ref.set(data);

    Future<void> writeDocs(String path, List<Object?> docs) async {
      for (final d in docs.cast<Map<String, Object?>>()) {
        await ref
            .collection(path)
            .doc(d['id'] as String)
            .set(_decode((d['data'] as Map).cast<String, Object?>()));
      }
    }

    await writeDocs('participants', (session['participants'] as List?) ?? []);
    await writeDocs('settlements', (session['settlements'] as List?) ?? []);
    await writeDocs('activity', (session['activity'] as List?) ?? []);

    for (final account in ((session['accounts'] as List?) ?? const [])
        .cast<Map<String, Object?>>()) {
      final accountRef = ref.collection('accounts').doc(account['id'] as String);
      await accountRef
          .set(_decode((account['data'] as Map).cast<String, Object?>()));
      for (final ticket in ((account['tickets'] as List?) ?? const [])
          .cast<Map<String, Object?>>()) {
        final ticketRef =
            accountRef.collection('tickets').doc(ticket['id'] as String);
        await ticketRef
            .set(_decode((ticket['data'] as Map).cast<String, Object?>()));
        for (final line in ((ticket['lines'] as List?) ?? const [])
            .cast<Map<String, Object?>>()) {
          await ticketRef
              .collection('lines')
              .doc(line['id'] as String)
              .set(_decode((line['data'] as Map).cast<String, Object?>()));
        }
      }
    }
  }

  // ── (De)serialización JSON-segura ──────────────────────────────────────

  Object? _encodeValue(Object? value) => switch (value) {
        Timestamp() => {'__t': value.toDate().toUtc().toIso8601String()},
        Map() => _encode(value.cast<String, Object?>()),
        List() => [for (final v in value) _encodeValue(v)],
        _ => value,
      };

  Map<String, Object?> _encode(Map<String, Object?> map) =>
      {for (final e in map.entries) e.key: _encodeValue(e.value)};

  Object? _decodeValue(Object? value) => switch (value) {
        Map() when value.length == 1 && value['__t'] is String =>
          Timestamp.fromDate(DateTime.parse(value['__t'] as String)),
        Map() => _decode(value.cast<String, Object?>()),
        List() => [for (final v in value) _decodeValue(v)],
        _ => value,
      };

  Map<String, Object?> _decode(Map<String, Object?> map) =>
      {for (final e in map.entries) e.key: _decodeValue(e.value)};
}

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    firestore: FirebaseFirestore.instance,
    uid: () => FirebaseAuth.instance.currentUser!.uid,
    shareCodeFactory: () => ShareCode.generate().value,
  ),
);
