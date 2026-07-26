import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../domain/space_models.dart';

/// Vinculación de identidad (Sprint 6, ADR-037).
///
/// Vincular es apropiarse de un historial económico, así que hacen falta DOS
/// partes: la persona lo PIDE y el anfitrión lo APRUEBA. Este repositorio es
/// el lado de cliente de ese trámite; Rules impone que no haya atajos.
///
/// Lo que se escribe al aprobar es únicamente `linkedUid`. El actor económico
/// sigue siendo `manual:{manualId}` y el `participantId` no cambia: vincular
/// AÑADE identidad, nunca reescribe historia.
class ManualLinkRepository {
  ManualLinkRepository({required this.firestore, required this.uid});

  final FirebaseFirestore firestore;
  final String Function() uid;

  CollectionReference<Map<String, dynamic>> _requests(String spaceId) =>
      firestore.collection('spaces/$spaceId/manualLinkRequests');

  static String requestId(String manualId, String uid) => '${manualId}_$uid';

  /// Solicitudes PENDIENTES del espacio. Solo las lista el anfitrión: Rules
  /// restringe el `list` al propietario.
  Stream<List<ManualLinkRequest>> watchPending(String spaceId) =>
      _requests(spaceId)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .map((snap) => [for (final d in snap.docs) _fromDoc(d)]);

  /// Mi solicitud sobre un manual concreto, si existe.
  Stream<ManualLinkRequest?> watchMine(String spaceId, String manualId) =>
      _requests(spaceId)
          .doc(requestId(manualId, uid()))
          .snapshots()
          .map((doc) => doc.data() == null ? null : _fromDoc(doc));

  /// La persona pide ser reconocida como ese participante manual.
  ///
  /// Se pide SIEMPRE para uno mismo: Rules exige `uid == auth.uid`, así que
  /// nadie puede solicitar en nombre de otro.
  Future<void> request(
    String spaceId,
    String manualId, {
    String displayName = '',
  }) => _requests(spaceId).doc(requestId(manualId, uid())).set({
    'manualId': manualId,
    'uid': uid(),
    if (displayName.trim().isNotEmpty) 'displayName': displayName.trim(),
    'status': 'pending',
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
    'schemaVersion': 1,
  });

  /// El anfitrión APRUEBA: la solicitud pasa a `accepted` y el `linkedUid`
  /// se escribe en el MISMO batch. Rules valida el emparejamiento con
  /// getAfter, así que no existe forma de escribir un vínculo sin aprobación.
  Future<void> approve(String spaceId, ManualLinkRequest req) async {
    final batch = firestore.batch();
    batch.update(_requests(spaceId).doc(req.id), {
      'status': 'accepted',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(
      firestore.doc('spaces/$spaceId/manualParticipants/${req.manualId}'),
      {'linkedUid': req.uid, 'updatedAt': FieldValue.serverTimestamp()},
    );
    await batch.commit();
  }

  /// Rechazar (o que el solicitante retire lo suyo). No escribe vínculo
  /// alguno; la solicitud se conserva como rastro de la decisión.
  Future<void> reject(String spaceId, String requestDocId) =>
      _requests(spaceId).doc(requestDocId).update({
        'status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      });

  ManualLinkRequest _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return ManualLinkRequest(
      id: doc.id,
      manualId: (data['manualId'] as String?) ?? '',
      uid: (data['uid'] as String?) ?? '',
      displayName: (data['displayName'] as String?) ?? '',
      status: switch (data['status']) {
        'accepted' => ManualLinkStatus.accepted,
        'rejected' => ManualLinkStatus.rejected,
        _ => ManualLinkStatus.pending,
      },
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

final manualLinkRepositoryProvider = Provider<ManualLinkRepository>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  return ManualLinkRepository(
    firestore: FirebaseFirestore.instance,
    uid: () => userId,
  );
});

/// Solicitudes pendientes de un espacio (bandeja del anfitrión).
final pendingManualLinksProvider = StreamProvider.autoDispose
    .family<List<ManualLinkRequest>, String>(
      (ref, spaceId) =>
          ref.watch(manualLinkRepositoryProvider).watchPending(spaceId),
    );

/// Mi solicitud sobre un manual concreto (vista de quien la pide).
final myManualLinkProvider = StreamProvider.autoDispose
    .family<ManualLinkRequest?, ({String spaceId, String manualId})>(
      (ref, key) => ref
          .watch(manualLinkRepositoryProvider)
          .watchMine(key.spaceId, key.manualId),
    );
