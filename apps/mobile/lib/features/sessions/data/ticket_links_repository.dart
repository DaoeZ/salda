import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:domain/domain.dart' show ShareCode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../auth/data/guest_identity_repository.dart';
import '../../spaces/domain/space_models.dart' show JoinLinkLifetime;
import '../domain/ticket_link_models.dart';

/// Enlaces de TICKET (Sprint 5, ADR-036).
///
/// Reutiliza de ADR-035 lo que es igual —token opaco de 128 bits como id del
/// documento, revocación, caducidad opcional e inmutable— y NADA más: la
/// colección es propia porque el alcance es un ticket, no un grupo.
/// La proyección autoritativa del ticket todavía no está lista. Es
/// recuperable: reintentar cuando recompute termine.
class TicketLinkNotReady implements Exception {
  const TicketLinkNotReady();
}

class TicketLinksRepository {
  TicketLinksRepository({
    required this.firestore,
    required this.uid,
    this.guestDisplayName,
  });

  final FirebaseFirestore firestore;
  final String Function() uid;
  final String Function()? guestDisplayName;

  CollectionReference<Map<String, dynamic>> get _links =>
      firestore.collection('ticketLinks');

  // ── Vista del dueño ───────────────────────────────────────────────────

  /// Enlace vivo de un ticket PARA UN DESTINATARIO concreto. Rules restringe
  /// este `list` al dueño de la sesión, así que el token no es enumerable por
  /// nadie más.
  ///
  /// La consulta lleva `targetManualId` porque ahora hay un enlace por
  /// persona: reutilizar el de otro destinatario sería volver al enlace
  /// genérico que este bug corrige.
  Stream<TicketJoinLink?> watchActiveLink(
    String sessionId,
    String ticketId, {
    required String manualId,
  }) => _links
      .where('sessionId', isEqualTo: sessionId)
      .where('ticketId', isEqualTo: ticketId)
      .where('targetManualId', isEqualTo: manualId)
      .where('status', isEqualTo: 'active')
      .snapshots()
      .map((snap) {
        final now = DateTime.now().toUtc();
        final links = [
          for (final d in snap.docs)
            if (_linkFrom(d).usableAt(now)) _linkFrom(d),
        ];
        links.sort(
          (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
            a.createdAt ?? DateTime(0),
          ),
        );
        return links.isEmpty ? null : links.first;
      });

  /// ¿Está lista la proyección autoritativa de este ticket?
  ///
  /// Es la señal que escribe `recompute` en el MISMO batch que las entradas,
  /// así que su presencia demuestra que la proyección está COMPLETA.
  Future<bool> isProjectionReady(String sessionId, String ticketId) async {
    final doc = await firestore
        .doc('sessions/$sessionId/ticketParticipantProjections/$ticketId')
        .get();
    return doc.data()?['ready'] == true;
  }

  /// Espera a que la proyección esté lista, escuchando el documento.
  ///
  /// Es dirigido por EVENTOS, no por un temporizador: se resuelve en cuanto
  /// recompute escribe la señal. El plazo solo acota la espera para poder
  /// dar un error recuperable si la Function no termina; nunca se usa como
  /// garantía de consistencia.
  Future<bool> awaitProjectionReady(
    String sessionId,
    String ticketId, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (await isProjectionReady(sessionId, ticketId)) return true;
    try {
      await firestore
          .doc('sessions/$sessionId/ticketParticipantProjections/$ticketId')
          .snapshots()
          .firstWhere((doc) => doc.data()?['ready'] == true)
          .timeout(timeout);
      return true;
    } on Object {
      return false;
    }
  }

  /// Crea el enlace PARA [target], el participante MANUAL al que va dirigido.
  ///
  /// El destinatario viaja denormalizado porque quien recibe el enlace no
  /// puede leer los participantes de la sesión — y para leerlos necesitaría
  /// el acceso que intenta obtener. Pero no autoriza nada por sí mismo:
  /// Rules revalida `targetPid → targetManualId → activo` contra la sesión y
  /// contra la proyección autoritativa, y solo admite identificarse COMO ESE.
  ///
  /// Lanza [TicketLinkNotReady] si la proyección aún no está lista, en vez
  /// de crear un enlace que después fallaría por consistencia eventual.
  Future<TicketJoinLink> createLink({
    required String sessionId,
    required String accountId,
    required String ticketId,
    required String merchantName,
    required EligibleManual target,
    String spaceId = '',
    JoinLinkLifetime lifetime = JoinLinkLifetime.never,
  }) async {
    if (!await awaitProjectionReady(sessionId, ticketId)) {
      throw const TicketLinkNotReady();
    }
    final token = ShareCode.generate().value;
    final expiresAt = lifetime.duration == null
        ? null
        : DateTime.now().toUtc().add(lifetime.duration!);
    await _links.doc(token).set({
      'sessionId': sessionId,
      'accountId': accountId,
      'ticketId': ticketId,
      'merchantName': merchantName.trim(),
      if (spaceId.isNotEmpty) 'spaceId': spaceId,
      // El destino: inmutable una vez creado (Rules lo impone en el update).
      'targetPid': target.pid,
      'targetManualId': target.manualId,
      'targetName': target.displayName,
      'createdByUid': uid(),
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
      // 2 = enlace dirigido. El 1 (lista de manuales elegibles) ya no se
      // acepta al crear ni sirve para identificarse.
      'schemaVersion': 2,
    });
    return TicketJoinLink(
      token: token,
      sessionId: sessionId,
      accountId: accountId,
      ticketId: ticketId,
      merchantName: merchantName.trim(),
      createdByUid: uid(),
      revoked: false,
      spaceId: spaceId,
      target: target,
      expiresAt: expiresAt,
    );
  }

  Future<void> revokeLink(String token) => _links.doc(token).update({
    'status': 'revoked',
    'updatedAt': FieldValue.serverTimestamp(),
  });

  // ── Vista de quien lo recibe ──────────────────────────────────────────

  /// Mira el enlace antes de entrar. Null si no existe, está revocado o ha
  /// caducado: los tres casos se presentan igual para no dar un oráculo.
  Future<TicketJoinLink?> preview(String token) async {
    final doc = await _links.doc(_normalizeToken(token)).get();
    if (!doc.exists) return null;
    final link = _linkFrom(doc);
    return link.usableAt(DateTime.now().toUtc()) ? link : null;
  }

  /// Identificación vigente de este UID para ESE ticket. La clave incluye
  /// el ticket, así que abrir un segundo enlace NO invalida el primero.
  Future<TicketAccess?> myAccess(String sessionId, String ticketId) async {
    final doc = await firestore
        .doc('sessions/$sessionId/ticketAccess/${ticketId}_${uid()}')
        .get();
    final data = doc.data();
    if (data == null) return null;
    return TicketAccess(
      uid: (data['uid'] as String?) ?? '',
      token: (data['token'] as String?) ?? '',
      ticketId: (data['ticketId'] as String?) ?? '',
      pid: (data['pid'] as String?) ?? '',
      manualId: (data['manualId'] as String?) ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Entrar como participante YA reclamado por este UID (cuenta o invitado
  /// conocido). No hay lectura anónima previa: poseer el enlace no basta,
  /// hay que representar a alguien que participa en el ticket.
  ///
  /// [pid] lo devuelve [knownParticipantPid]; Rules lo revalida contra la
  /// proyección autoritativa y contra `claimedByDevice`.
  Future<void> enterAsKnownParticipant(TicketJoinLink link, String pid) =>
      firestore
          .doc(
            'sessions/${link.sessionId}/ticketAccess/'
            '${link.ticketId}_${uid()}',
          )
          .set({
            'uid': uid(),
            'token': link.token,
            'ticketId': link.ticketId,
            'pid': pid,
            'createdAt': FieldValue.serverTimestamp(),
            'schemaVersion': 1,
          });

  /// Paso 2: confirmar que se es el DESTINATARIO del enlace.
  ///
  /// No admite un manual arbitrario: el que vale es el del token. Aunque un
  /// cliente modificado llamara con otro, Rules rechaza la escritura porque
  /// compara `manualId` y `pid` con `targetManualId`/`targetPid` del enlace.
  ///
  /// El cerrojo `ticketClaims/{ticketId}_{manualId}` va en el MISMO batch y
  /// su `create` solo prospera si no existe: eso es la exclusión mutua entre
  /// dispositivos, sin transacción extra. El segundo en llegar recibe
  /// permission-denied, que la app traduce a «ya no está disponible».
  Future<TicketLinkOutcome> identifyAsTarget(TicketJoinLink link) async {
    final manual = link.target;
    // Un enlace del esquema antiguo no dice a quién representa: no hay nada
    // que confirmar y no se concede identificación.
    if (manual == null) return TicketLinkOutcome.invalid;
    final claim = firestore.doc(
      'sessions/${link.sessionId}/ticketClaims/'
      '${link.ticketId}_${manual.manualId}',
    );
    final existing = await claim.get();
    if (existing.exists && existing.data()?['uid'] != uid()) {
      return TicketLinkOutcome.manualTaken;
    }
    final batch = firestore.batch();
    batch.set(claim, {
      'uid': uid(),
      'ticketId': link.ticketId,
      'manualId': manual.manualId,
      'createdAt': FieldValue.serverTimestamp(),
      'schemaVersion': 1,
    });
    batch.set(
      firestore.doc(
        'sessions/${link.sessionId}/ticketAccess/'
        '${link.ticketId}_${uid()}',
      ),
      {
        'uid': uid(),
        'token': link.token,
        'ticketId': link.ticketId,
        'pid': manual.pid,
        'manualId': manual.manualId,
        'createdAt': FieldValue.serverTimestamp(),
        'schemaVersion': 1,
      },
    );
    try {
      await batch.commit();
    } on FirebaseException catch (error) {
      // La carrera la resuelve Rules: quien llega segundo no escribe.
      if (error.code == 'permission-denied') {
        return TicketLinkOutcome.manualTaken;
      }
      rethrow;
    }
    return TicketLinkOutcome.opened;
  }

  /// Soltar la identificación. Es del dispositivo, así que la borra él.
  /// No toca ningún balance: el actor económico nunca fue este UID.
  Future<void> release(TicketJoinLink link, TicketAccess access) async {
    final batch = firestore.batch();
    if (access.identifiesAManual) {
      batch.delete(
        firestore.doc(
          'sessions/${link.sessionId}/ticketClaims/'
          '${link.ticketId}_${access.manualId}',
        ),
      );
    }
    batch.delete(
      firestore.doc(
        'sessions/${link.sessionId}/ticketAccess/'
        '${link.ticketId}_${uid()}',
      ),
    );
    await batch.commit();
  }

  /// ¿Este UID ya es un participante del ticket? Devuelve su `pid` o null.
  ///
  /// Se resuelve contra la proyección AUTORITATIVA `ticketParticipants`, que
  /// escribe recompute: es la misma fuente que valida Rules, así que la app
  /// nunca ofrece algo que después vaya a rechazarse.
  Future<String?> knownParticipantPid(TicketJoinLink link) async {
    final snap = await firestore
        .collection('sessions/${link.sessionId}/ticketParticipants')
        .where('ticketId', isEqualTo: link.ticketId)
        .where('claimedByDevice', isEqualTo: uid())
        .limit(1)
        .get();
    return snap.docs.isEmpty ? null : snap.docs.first.data()['pid'] as String?;
  }

  static String _normalizeToken(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return value;
    final marker = value.lastIndexOf('/t/');
    if (marker >= 0) value = value.substring(marker + 3);
    for (final separator in ['?', '#', '/']) {
      final index = value.indexOf(separator);
      if (index >= 0) value = value.substring(0, index);
    }
    return value.trim();
  }

  static String linkUrlFor(String hostingDomain, String token) =>
      'https://$hostingDomain/t/$token';

  TicketJoinLink _linkFrom(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return TicketJoinLink(
      token: doc.id,
      sessionId: (data['sessionId'] as String?) ?? '',
      accountId: (data['accountId'] as String?) ?? '',
      ticketId: (data['ticketId'] as String?) ?? '',
      merchantName: (data['merchantName'] as String?) ?? '',
      createdByUid: (data['createdByUid'] as String?) ?? '',
      revoked: data['status'] != 'active',
      spaceId: (data['spaceId'] as String?) ?? '',
      // Esquema 1 (lista `manuals`): se lee como enlace SIN destinatario. No
      // se degrada a «elige tú»: eso era justamente el agujero.
      target: ((data['targetManualId'] as String?) ?? '').isEmpty
          ? null
          : EligibleManual(
              pid: (data['targetPid'] as String?) ?? '',
              manualId: data['targetManualId'] as String,
              displayName: (data['targetName'] as String?) ?? '',
            ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate().toUtc(),
    );
  }
}

final ticketLinksRepositoryProvider = Provider<TicketLinksRepository>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  final user = ref.watch(currentAppUserProvider);
  final guestName = (user?.isAnonymous ?? false)
      ? ref.watch(myGuestIdentityProvider).value?.displayName
      : null;
  return TicketLinksRepository(
    firestore: FirebaseFirestore.instance,
    uid: () => userId,
    guestDisplayName: guestName == null ? null : () => guestName,
  );
});

/// Enlace de ticket pendiente mientras el usuario se identifica. Mismo
/// mecanismo que `pendingGroupLinkProvider` (ADR-035): identificarse no debe
/// perder el enlace.
final pendingTicketLinkProvider = NotifierProvider<PendingTicketLink, String?>(
  PendingTicketLink.new,
);

class PendingTicketLink extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String token) => state = token;

  void clear() => state = null;
}

/// Enlace vivo de un ticket para un destinatario concreto. La clave lleva el
/// `manualId` porque ahora hay uno por persona.
final ticketLinkProvider = StreamProvider.autoDispose
    .family<
      TicketJoinLink?,
      ({String sessionId, String ticketId, String manualId})
    >(
      (ref, key) => ref
          .watch(ticketLinksRepositoryProvider)
          .watchActiveLink(key.sessionId, key.ticketId, manualId: key.manualId),
    );
