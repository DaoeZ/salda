import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../domain/space_models.dart';

enum ManualLinkRetryAction {
  claimed,
  active,
  inProgress,
  unclassifiable,
  cooldown,
}

class ManualLinkRetryResult {
  const ManualLinkRetryResult({
    required this.status,
    required this.action,
    this.sessions,
    this.reason,
  });

  final ManualLinkPropagationStatus status;
  final ManualLinkRetryAction action;
  final int? sessions;
  final String? reason;

  factory ManualLinkRetryResult.fromData(Map<String, dynamic> data) {
    return ManualLinkRetryResult(
      status: switch (data['status']) {
        'active' => ManualLinkPropagationStatus.active,
        'failed' => ManualLinkPropagationStatus.failed,
        _ => ManualLinkPropagationStatus.processing,
      },
      action: switch (data['action']) {
        'claimed' => ManualLinkRetryAction.claimed,
        'active' => ManualLinkRetryAction.active,
        'in-progress' => ManualLinkRetryAction.inProgress,
        'cooldown' => ManualLinkRetryAction.cooldown,
        _ => ManualLinkRetryAction.unclassifiable,
      },
      sessions: data['sessions'] as int?,
      reason: data['reason'] as String?,
    );
  }
}

abstract interface class ManualLinkFunctionsGateway {
  Future<void> request(
    String spaceId,
    String manualId, {
    required String displayName,
    String viaSessionId,
    String viaTicketId,
    String viaPid,
  });

  Future<ManualLinkRetryResult> retryPropagation(
    String spaceId,
    String manualId,
  );
}

class FirebaseManualLinkFunctionsGateway implements ManualLinkFunctionsGateway {
  FirebaseManualLinkFunctionsGateway(this.functions);

  final FirebaseFunctions functions;

  @override
  Future<void> request(
    String spaceId,
    String manualId, {
    required String displayName,
    String viaSessionId = '',
    String viaTicketId = '',
    String viaPid = '',
  }) async {
    await functions.httpsCallable('requestManualLink').call<void>({
      'spaceId': spaceId,
      'manualId': manualId,
      'displayName': displayName.trim(),
      if (viaSessionId.isNotEmpty) 'viaSessionId': viaSessionId,
      if (viaTicketId.isNotEmpty) 'viaTicketId': viaTicketId,
      if (viaPid.isNotEmpty) 'viaPid': viaPid,
    });
  }

  @override
  Future<ManualLinkRetryResult> retryPropagation(
    String spaceId,
    String manualId,
  ) async {
    final response = await functions
        .httpsCallable('retryManualLinkPropagation')
        .call<Map<String, dynamic>>({'spaceId': spaceId, 'manualId': manualId});
    return ManualLinkRetryResult.fromData(response.data);
  }
}

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
  ManualLinkRepository({
    required this.firestore,
    required this.uid,
    required this.functions,
  });

  final FirebaseFirestore firestore;
  final String Function() uid;
  final ManualLinkFunctionsGateway functions;

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
  /// La Function deriva el UID y el propietario actuales. Los punteros de
  /// ticket solo explican la legitimidad y se revalidan en Admin SDK.
  Future<void> request(
    String spaceId,
    String manualId, {
    required String displayName,
    String viaSessionId = '',
    String viaTicketId = '',
    String viaPid = '',
  }) => functions.request(
    spaceId,
    manualId,
    displayName: displayName,
    // La Function deriva el propietario actual; el cliente no lo aporta.
    viaSessionId: viaSessionId,
    viaTicketId: viaTicketId,
    viaPid: viaPid,
  );

  /// El anfitrión APRUEBA: la solicitud pasa a `accepted` y el `linkedUid`
  /// se escribe en el MISMO batch. Rules valida el emparejamiento con
  /// getAfter, así que no existe forma de escribir un vínculo sin aprobación.
  /// Tres documentos en UN batch: la solicitud pasa a `accepted`, se reserva
  /// la identidad y se escribe el `linkedUid`. Rules exige los tres con
  /// getAfter, así que no existen estados a medias — ni aceptada sin
  /// vínculo, ni vínculo sin reserva, ni reserva sin vínculo.
  Future<void> approve(String spaceId, ManualLinkRequest req) async {
    final batch = firestore.batch();
    batch.update(_requests(spaceId).doc(req.id), {
      'status': 'accepted',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // Reserva determinista uid → manual: impide que la misma persona quede
    // vinculada a dos manuales del espacio, lo que producía obligaciones
    // consigo misma.
    batch.set(firestore.doc('spaces/$spaceId/linkedIdentities/${req.uid}'), {
      'uid': req.uid,
      'manualId': req.manualId,
      'createdAt': FieldValue.serverTimestamp(),
      'schemaVersion': 1,
    });
    batch.update(
      firestore.doc('spaces/$spaceId/manualParticipants/${req.manualId}'),
      {'linkedUid': req.uid, 'updatedAt': FieldValue.serverTimestamp()},
    );
    await batch.commit();
  }

  /// Rechazar (o que el solicitante retire lo suyo). No escribe vínculo
  /// alguno; la solicitud se conserva como rastro de la decisión.
  /// Nuevo intento tras un rechazo. No reescribe un terminal en silencio:
  /// sube el contador, que queda como rastro de cuántas veces se pidió.
  /// Desde `accepted` es imposible — ese sí es terminal de verdad.
  Future<void> retry(String spaceId, ManualLinkRequest req) =>
      _requests(spaceId).doc(req.id).update({
        'status': 'pending',
        'attempt': req.attempt + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> reject(String spaceId, String requestDocId) =>
      _requests(spaceId).doc(requestDocId).update({
        'status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Solicita la propagación autoritativa del vínculo ya aprobado. La Function
  /// deriva el propietario y el UID vinculado: el cliente solo aporta la ruta.
  Future<ManualLinkRetryResult> retryPropagation(
    String spaceId,
    String manualId,
  ) => functions.retryPropagation(spaceId, manualId);

  ManualLinkRequest _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return ManualLinkRequest(
      id: doc.id,
      manualId: (data['manualId'] as String?) ?? '',
      uid: (data['uid'] as String?) ?? '',
      displayName: (data['displayName'] as String?) ?? '',
      attempt: (data['attempt'] as int?) ?? 1,
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
    functions: ref.watch(manualLinkFunctionsGatewayProvider),
  );
});

final manualLinkFunctionsGatewayProvider = Provider<ManualLinkFunctionsGateway>(
  (ref) => FirebaseManualLinkFunctionsGateway(
    FirebaseFunctions.instanceFor(region: 'europe-west1'),
  ),
);

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

/// M4: bandeja GLOBAL del anfitrión — todas sus solicitudes pendientes, de
/// todos sus espacios, en una sola consulta.
///
/// Sin esto había que entrar grupo por grupo para descubrir si alguien había
/// pedido algo, y las solicitudes legítimas se quedaban meses sin respuesta.
/// El collection group va acotado por `spaceOwnerUid`, que Rules valida
/// contra el propietario real: nadie enumera lo ajeno.
final myPendingManualLinksProvider =
    StreamProvider.autoDispose<List<ManualLinkRequest>>((ref) {
      final uid = ref.watch(currentUserIdProvider);
      if (uid.isEmpty) return Stream.value(const []);
      return FirebaseFirestore.instance
          .collectionGroup('manualLinkRequests')
          .where('spaceOwnerUid', isEqualTo: uid)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .map(
            (snap) => [
              for (final d in snap.docs)
                ManualLinkRequest(
                  id: d.id,
                  manualId: (d.data()['manualId'] as String?) ?? '',
                  uid: (d.data()['uid'] as String?) ?? '',
                  displayName: (d.data()['displayName'] as String?) ?? '',
                  status: ManualLinkStatus.pending,
                  // Ruta del espacio, para poder navegar hasta él.
                  spaceId: d.reference.parent.parent?.id ?? '',
                ),
            ],
          );
    });
