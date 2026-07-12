import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Persona frecuente del anfitrión (RF-40): chips de un toque al crear.
class FrequentPerson {
  const FrequentPerson({required this.id, required this.name, this.usageCount = 0});

  final String id;
  final String name;
  final int usageCount;
}

class FrequentPeopleRepository {
  FrequentPeopleRepository({required this.firestore, required this.uid});

  final FirebaseFirestore firestore;
  final String Function() uid;

  CollectionReference<Map<String, dynamic>> get _collection =>
      firestore.collection('users').doc(uid()).collection('frequentPeople');

  Stream<List<FrequentPerson>> watch() => _collection
      .orderBy('usageCount', descending: true)
      .limit(12)
      .snapshots()
      .map((snap) => [
            for (final d in snap.docs)
              FrequentPerson(
                id: d.id,
                name: (d.data()['name'] as String?) ?? '',
                usageCount: (d.data()['usageCount'] as int?) ?? 0,
              ),
          ]);

  /// Registra el uso de estos nombres (crea o incrementa). Id = nombre
  /// normalizado para no duplicar "Alba" y "alba ".
  Future<void> recordUsage(Iterable<String> names) async {
    final batch = firestore.batch();
    for (final name in names) {
      final normalized = name.trim();
      if (normalized.isEmpty) continue;
      batch.set(
        _collection.doc(normalized.toLowerCase()),
        {
          'name': normalized,
          'usageCount': FieldValue.increment(1),
          'lastUsedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> remove(String id) => _collection.doc(id).delete();
}

final frequentPeopleRepositoryProvider = Provider<FrequentPeopleRepository>(
  (ref) => FrequentPeopleRepository(
    firestore: FirebaseFirestore.instance,
    uid: () => FirebaseAuth.instance.currentUser!.uid,
  ),
);
