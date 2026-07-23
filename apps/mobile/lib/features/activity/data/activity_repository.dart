import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../domain/activity_models.dart';

/// Lectura de la actividad (P6). SOLO lectura: los eventos los generan los
/// triggers Admin. Todas las queries llevan `array-contains` sobre el propio
/// uid — es lo que las Rules exigen para ser demostrables — así que nunca se
/// descarga actividad ajena para filtrar en cliente.
class ActivityRepository {
  ActivityRepository({required this.firestore, required this.uid});

  final FirebaseFirestore firestore;
  final String Function() uid;

  static const int pageSize = 30;

  Query<Map<String, dynamic>> _base({String? spaceId}) {
    var query = firestore
        .collection('activityEvents')
        .where('memberUids', arrayContains: uid());
    if (spaceId != null) {
      query = query.where('spaceId', isEqualTo: spaceId);
    }
    return query.orderBy('at', descending: true);
  }

  /// Primera página EN VIVO (los eventos recientes aparecen solos).
  Stream<List<ActivityEvent>> watchFirstPage({String? spaceId}) =>
      _base(spaceId: spaceId)
          .limit(pageSize)
          .snapshots()
          .map((snap) => snap.docs.map(_fromDoc).toList());

  /// Historial anterior a [before] (paginación por fecha, bajo demanda).
  Future<List<ActivityEvent>> fetchOlder(
    DateTime before, {
    String? spaceId,
  }) async {
    var query = firestore
        .collection('activityEvents')
        .where('memberUids', arrayContains: uid())
        .where('at', isLessThan: Timestamp.fromDate(before));
    if (spaceId != null) {
      query = query.where('spaceId', isEqualTo: spaceId);
    }
    final snap = await query
        .orderBy('at', descending: true)
        .limit(pageSize)
        .get();
    return snap.docs.map(_fromDoc).toList();
  }

  ActivityEvent _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final summary = (data['summary'] as Map?) ?? const {};
    return ActivityEvent(
      id: doc.id,
      type: ActivityType.fromWire(data['type'] as String?),
      actorUid: (data['actorUid'] as String?) ?? '',
      spaceId: data['spaceId'] as String?,
      sessionId: data['sessionId'] as String?,
      ticketId: data['ticketId'] as String?,
      paymentId: data['paymentId'] as String?,
      spaceName: (summary['spaceName'] as String?) ?? '',
      ticketName: (summary['ticketName'] as String?) ?? '',
      sessionName: (summary['sessionName'] as String?) ?? '',
      amountCents: summary['amount'] as int?,
      currency: summary['currency'] as String?,
      at: (data['at'] as Timestamp?)?.toDate(),
    );
  }
}

final activityRepositoryProvider = Provider<ActivityRepository>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  return ActivityRepository(
    firestore: FirebaseFirestore.instance,
    uid: () => userId,
  );
});

/// Primera página global (o de un espacio con `family` abajo), en vivo.
final globalActivityProvider =
    StreamProvider.autoDispose<List<ActivityEvent>>(
  (ref) => ref.watch(activityRepositoryProvider).watchFirstPage(),
);

final spaceActivityProvider =
    StreamProvider.autoDispose.family<List<ActivityEvent>, String>(
  (ref, spaceId) =>
      ref.watch(activityRepositoryProvider).watchFirstPage(spaceId: spaceId),
);
