import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../auth/data/guest_identity_repository.dart';
import '../domain/space_models.dart';

enum SpaceFailureCode {
  accountRequired,
  notAllowed,
  alreadyMember,
  ownerCannotLeave,
  targetUnavailable,
}

class SpaceFailure implements Exception {
  const SpaceFailure(this.code);

  final SpaceFailureCode code;
}

/// Repositorio de espacios compartidos (P4, ADR-028).
///
/// Claves SIEMPRE por UID. Las operaciones sensibles son batches atómicos
/// validados por Rules con getAfter(): crear espacio (espacio + membresía
/// owner), aceptar invitación (invitación + membresía) y transferir la
/// propiedad (espacio + dos roles). Reintentar cualquiera es idempotente.
class SpacesRepository {
  SpacesRepository({
    required this.firestore,
    required this.uid,
    required this.isFullAccount,
    this.guestDisplayName,
  });

  final FirebaseFirestore firestore;
  final String Function() uid;
  final bool Function() isFullAccount;

  /// Nombre visible del INVITADO activo (ADR-034), o null si la identidad
  /// es una cuenta. Un invitado no tiene perfil público del que leerlo, así
  /// que viaja como snapshot al unirse a un contexto.
  final String Function()? guestDisplayName;

  CollectionReference<Map<String, dynamic>> get _spaces =>
      firestore.collection('spaces');

  CollectionReference<Map<String, dynamic>> get _invites =>
      firestore.collection('spaceInvites');

  void _requireAccount() {
    if (!isFullAccount()) {
      throw const SpaceFailure(SpaceFailureCode.accountRequired);
    }
  }

  // ── Lectura en tiempo real ────────────────────────────────────────────

  /// Mis espacios: collection group sobre MIS membresías; cada cambio de
  /// membresía relee los espacios. (Editar el nombre de un espacio se
  /// refleja al entrar en su detalle, que sí escucha el doc en vivo.)
  Stream<List<Space>> watchMySpaces() {
    _requireAccount();
    return firestore
        .collectionGroup('members')
        .where('uid', isEqualTo: uid())
        .snapshots()
        .asyncMap((snapshot) async {
          final refs = [
            for (final member in snapshot.docs) ?member.reference.parent.parent,
          ];
          final docs = await Future.wait(refs.map((ref) => ref.get()));
          final spaces = [for (final doc in docs) ?_spaceFrom(doc)];
          spaces.sort((a, b) => a.name.compareTo(b.name));
          return spaces;
        });
  }

  Stream<Space?> watchSpace(String spaceId) =>
      _spaces.doc(spaceId).snapshots().map(_spaceFrom);

  Stream<List<SpaceMember>> watchMembers(String spaceId) => _spaces
      .doc(spaceId)
      .collection('members')
      .orderBy('joinedAt')
      .snapshots()
      .map(
        (snap) => [
          for (final d in snap.docs)
            SpaceMember(
              uid: d.id,
              joinedAt: (d.data()['joinedAt'] as Timestamp?)?.toDate(),
              kind: d.data()['kind'] == 'guest'
                  ? SpaceMemberKind.guest
                  : SpaceMemberKind.account,
              displayName: d.data()['displayName'] as String?,
            ),
        ],
      );

  // ── Participantes manuales (ADR-033) ─────────────────────────────────

  /// Personas sin cuenta del espacio. Se leen igual que los miembros: son
  /// participantes del contexto común, solo que sin dispositivo.
  Stream<List<ManualParticipant>> watchManualParticipants(String spaceId) =>
      _spaces
          .doc(spaceId)
          .collection('manualParticipants')
          .orderBy('createdAt')
          .snapshots()
          .map((snap) => [for (final d in snap.docs) _manualFrom(d)]);

  /// Crea la identidad manual. El id es opaco y estable (nunca el nombre):
  /// renombrar después no afecta a ninguna obligación ya derivada.
  Future<ManualParticipant> addManualParticipant(
    String spaceId,
    String displayName,
  ) async {
    _requireAccount();
    final name = displayName.trim();
    if (name.isEmpty || name.length > 40) {
      throw const SpaceFailure(SpaceFailureCode.notAllowed);
    }
    final doc = _spaces.doc(spaceId).collection('manualParticipants').doc();
    await doc.set({
      'manualId': doc.id,
      'displayName': name,
      'linkedUid': null, // reservado a la futura vinculación
      'createdByUid': uid(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'schemaVersion': 1,
    });
    return ManualParticipant(
      id: doc.id,
      displayName: name,
      createdByUid: uid(),
    );
  }

  /// Solo cambia el nombre visible: la identidad económica no se toca.
  Future<void> renameManualParticipant(
    String spaceId,
    String manualId,
    String displayName,
  ) {
    final name = displayName.trim();
    if (name.isEmpty || name.length > 40) {
      throw const SpaceFailure(SpaceFailureCode.notAllowed);
    }
    return _spaces
        .doc(spaceId)
        .collection('manualParticipants')
        .doc(manualId)
        .update({
          'displayName': name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  /// Retira a la persona del contexto. NO borra su historial: las
  /// obligaciones ya derivadas conservan el actor `manual:{id}`, igual que
  /// expulsar a un miembro no borra sus deudas.
  Future<void> removeManualParticipant(String spaceId, String manualId) =>
      _spaces
          .doc(spaceId)
          .collection('manualParticipants')
          .doc(manualId)
          .delete();

  ManualParticipant _manualFrom(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) =>
      ManualParticipant(
        id: doc.id,
        displayName: (doc.data()['displayName'] as String?) ?? '',
        linkedUid: doc.data()['linkedUid'] as String?,
        createdByUid: (doc.data()['createdByUid'] as String?) ?? '',
        createdAt: (doc.data()['createdAt'] as Timestamp?)?.toDate(),
      );

  /// Invitaciones que YO he recibido y siguen pendientes. Recibirlas y
  /// responderlas es PARTICIPAR: también las ve un invitado (ADR-034).
  Stream<List<SpaceInvite>> watchMyInvites() {
    if (guestDisplayName?.call() == null) _requireAccount();
    return _invites
        .where('toUid', isEqualTo: uid())
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.map(_inviteFrom).toList());
  }

  /// Invitaciones pendientes de un espacio (vista del owner).
  Stream<List<SpaceInvite>> watchSpaceInvites(String spaceId) => _invites
      .where('spaceId', isEqualTo: spaceId)
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((snap) => snap.docs.map(_inviteFrom).toList());

  /// Tickets vinculados, EN VIVO desde los propios documentos de ticket
  /// (collection group por spaceId): sin copias que desincronizar.
  Stream<List<SpaceTicket>> watchSpaceTickets(String spaceId) => firestore
      .collectionGroup('tickets')
      .where('spaceId', isEqualTo: spaceId)
      .snapshots()
      .map((snap) {
        final tickets = [
          for (final d in snap.docs)
            SpaceTicket(
              path: d.reference.path,
              sessionId: d.reference.path.split('/')[1],
              merchantName:
                  ((d.data()['merchant'] as Map?)?['name'] as String?) ?? '',
              grandTotalCents: (d.data()['grandTotal'] as int?) ?? 0,
              date: d.data()['date'] as String?,
            ),
        ];
        tickets.sort((a, b) => b.path.compareTo(a.path));
        return tickets;
      });

  // ── Ciclo de vida del espacio ─────────────────────────────────────────

  Future<String> createSpace(String name, {String? avatarEmoji}) async {
    _requireAccount();
    final space = _spaces.doc();
    final batch = firestore.batch();
    batch.set(space, {
      'name': name.trim(),
      if (avatarEmoji != null && avatarEmoji.isNotEmpty)
        'avatarEmoji': avatarEmoji,
      'ownerUid': uid(),
      'kind': SpaceKind.group.name,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'schemaVersion': 2,
    });
    batch.set(space.collection('members').doc(uid()), {
      'uid': uid(),
      'joinedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return space.id;
  }

  /// Crea la relación y su invitación inicial de forma atómica. El ID y los
  /// UID reservados hacen que A→B y B→A sean el mismo contexto económico.
  Future<String> createRelationship({
    required String toUid,
    required String name,
  }) async {
    _requireAccount();
    final fromUid = uid();
    if (toUid == fromUid) {
      throw const SpaceFailure(SpaceFailureCode.notAllowed);
    }
    final pair = [fromUid, toUid]..sort();
    final space = _spaces.doc(relationshipSpaceId(fromUid, toUid));
    final invite = _invites.doc(SpaceInvite.idFor(space.id, toUid));
    await firestore.runTransaction((transaction) async {
      if ((await transaction.get(space)).exists) {
        throw const SpaceFailure(SpaceFailureCode.alreadyMember);
      }
      transaction.set(space, {
        'name': name.trim(),
        'ownerUid': fromUid,
        'kind': SpaceKind.relationship.name,
        'relationshipUids': pair,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'schemaVersion': 2,
      });
      transaction.set(space.collection('members').doc(fromUid), {
        'uid': fromUid,
        'joinedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(invite, {
        'spaceId': space.id,
        'spaceName': name.trim(),
        'fromUid': fromUid,
        'toUid': toUid,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    return space.id;
  }

  Future<void> rename(String spaceId, String name, {String? avatarEmoji}) =>
      _spaces.doc(spaceId).update({
        'name': name.trim(),
        'avatarEmoji': (avatarEmoji == null || avatarEmoji.isEmpty)
            ? FieldValue.delete()
            : avatarEmoji,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> setStatus(String spaceId, SpaceStatus status) =>
      _spaces.doc(spaceId).update({
        'status': status.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Transferencia ATÓMICA por diseño: el propietario único vive en
  /// `ownerUid`, así que transferir es actualizar UN documento. Solo a un
  /// miembro activo (Rules lo exige con exists()).
  Future<void> transferOwnership(String spaceId, String toUid) async {
    _requireAccount();
    if (toUid == uid()) return; // ya es suyo: idempotente
    final member = await _spaces
        .doc(spaceId)
        .collection('members')
        .doc(toUid)
        .get();
    if (!member.exists) {
      throw const SpaceFailure(SpaceFailureCode.targetUnavailable);
    }
    await _spaces.doc(spaceId).update({
      'ownerUid': toUid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Invitaciones ──────────────────────────────────────────────────────

  /// Invita (o REENVÍA tras rechazo/cancelación: mismo doc determinista).
  Future<void> invite(String spaceId, String spaceName, String toUid) async {
    _requireAccount();
    if (toUid == uid()) throw const SpaceFailure(SpaceFailureCode.notAllowed);
    final member = await _spaces
        .doc(spaceId)
        .collection('members')
        .doc(toUid)
        .get();
    if (member.exists) {
      throw const SpaceFailure(SpaceFailureCode.alreadyMember);
    }
    final doc = _invites.doc(SpaceInvite.idFor(spaceId, toUid));
    await firestore.runTransaction((transaction) async {
      final existing = await transaction.get(doc);
      if (existing.exists) {
        final status = existing.data()?['status'] as String?;
        if (status == 'pending') return; // ya invitado: idempotente
        if (status == 'accepted') {
          throw const SpaceFailure(SpaceFailureCode.alreadyMember);
        }
        transaction.update(doc, {
          'status': 'pending',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }
      transaction.set(doc, {
        'spaceId': spaceId,
        'spaceName': spaceName,
        'fromUid': uid(),
        'toUid': toUid,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> cancelInvite(String inviteId) => _invites.doc(inviteId).update({
    'status': 'cancelled',
    'updatedAt': FieldValue.serverTimestamp(),
  });

  /// Aceptar crea la membresía y resuelve la invitación EN EL MISMO batch:
  /// una invitación cancelada ya no puede aceptarse (la regla exige
  /// pending → accepted).
  Future<void> acceptInvite(SpaceInvite invite) async {
    // Aceptar es PARTICIPAR, no administrar: también lo hace un invitado.
    final guestName = guestDisplayName?.call();
    if (guestName == null) _requireAccount();
    final batch = firestore.batch();
    batch.update(_invites.doc(invite.id), {
      'status': 'accepted',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(_spaces.doc(invite.spaceId).collection('members').doc(uid()), {
      'uid': uid(),
      'joinedAt': FieldValue.serverTimestamp(),
      // Un invitado congela su nombre aquí porque no tiene perfil público.
      if (guestName != null) ...{
        'kind': 'guest',
        'displayName': guestName,
      },
    });
    await batch.commit();
  }

  Future<void> rejectInvite(String inviteId) => _invites.doc(inviteId).update({
    'status': 'rejected',
    'updatedAt': FieldValue.serverTimestamp(),
  });

  // ── Membresía ─────────────────────────────────────────────────────────

  /// Salir del espacio. El OWNER no puede salir: antes debe transferir la
  /// propiedad (o archivar el espacio). Solo borra la membresía: tickets,
  /// asignaciones, pagos y balances históricos quedan intactos.
  Future<void> leave(String spaceId) async {
    _requireAccount();
    final space = await _spaces.doc(spaceId).get();
    if (space.data()?['ownerUid'] == uid()) {
      throw const SpaceFailure(SpaceFailureCode.ownerCannotLeave);
    }
    await _spaces.doc(spaceId).collection('members').doc(uid()).delete();
  }

  /// Expulsión por el owner. Mismo contrato: solo la membresía. El marcador
  /// `removedBy` (validado por Rules: solo el owner y nunca sobre sí mismo)
  /// precede al borrado para que la actividad (P6) distinga expulsión de
  /// salida voluntaria. Si la app muriera entre ambas escrituras, el
  /// marcador huérfano es inocuo y el reintento converge.
  Future<void> removeMember(String spaceId, String memberUid) async {
    final member = _spaces.doc(spaceId).collection('members').doc(memberUid);
    await member.update({'removedBy': uid()});
    await member.delete();
  }

  // ── Tickets ───────────────────────────────────────────────────────────

  /// Vincula un ticket a un espacio (máximo uno: el campo sobrescribe).
  /// No cambia participantes, asignaciones, balances ni pagos.
  Future<void> linkTicket(String ticketPath, String spaceId) =>
      firestore.doc(ticketPath).update({'spaceId': spaceId});

  Future<void> unlinkTicket(String ticketPath) =>
      firestore.doc(ticketPath).update({'spaceId': ''});

  // ── Mapeo ─────────────────────────────────────────────────────────────

  Space? _spaceFrom(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    return Space(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      ownerUid: (data['ownerUid'] as String?) ?? '',
      status: data['status'] == 'archived'
          ? SpaceStatus.archived
          : SpaceStatus.active,
      kind: data['kind'] == SpaceKind.relationship.name
          ? SpaceKind.relationship
          : SpaceKind.group,
      relationshipUids: [
        for (final value in (data['relationshipUids'] as List?) ?? const [])
          if (value is String) value,
      ],
      guestsCanCreateExpenses:
          (data['guestsCanCreateExpenses'] as bool?) ?? false,
      avatarEmoji: data['avatarEmoji'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Política de invitados del contexto (ADR-034). Solo el owner.
  Future<void> setGuestsCanCreateExpenses(String spaceId, bool allowed) {
    _requireAccount();
    return _spaces.doc(spaceId).update({
      'guestsCanCreateExpenses': allowed,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  SpaceInvite _inviteFrom(QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
      SpaceInvite(
        id: doc.id,
        spaceId: (doc.data()['spaceId'] as String?) ?? '',
        spaceName: (doc.data()['spaceName'] as String?) ?? '',
        fromUid: (doc.data()['fromUid'] as String?) ?? '',
        toUid: (doc.data()['toUid'] as String?) ?? '',
        status: switch (doc.data()['status']) {
          'accepted' => SpaceInviteStatus.accepted,
          'rejected' => SpaceInviteStatus.rejected,
          'cancelled' => SpaceInviteStatus.cancelled,
          _ => SpaceInviteStatus.pending,
        },
        createdAt: (doc.data()['createdAt'] as Timestamp?)?.toDate(),
        updatedAt: (doc.data()['updatedAt'] as Timestamp?)?.toDate(),
      );
}

final spacesRepositoryProvider = Provider<SpacesRepository>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  final user = ref.watch(currentAppUserProvider);
  // Nombre del invitado activo (null para cuentas): lo necesita el alta de
  // membresía, que para un invitado congela su nombre visible (ADR-034).
  final guestName = (user?.isAnonymous ?? false)
      ? ref.watch(myGuestIdentityProvider).value?.displayName
      : null;
  return SpacesRepository(
    firestore: FirebaseFirestore.instance,
    uid: () => userId,
    isFullAccount: () => user?.isFullAccount ?? false,
    guestDisplayName: guestName == null ? null : () => guestName,
  );
});

final mySpacesProvider = StreamProvider.autoDispose<List<Space>>(
  (ref) => ref.watch(spacesRepositoryProvider).watchMySpaces(),
);

/// uid activo para los widgets de espacios (sin acoplarlos a auth).
final currentUserIdFromSpacesProvider = Provider<String>(
  (ref) => ref.watch(spacesRepositoryProvider).uid(),
);

final mySpaceInvitesProvider = StreamProvider.autoDispose<List<SpaceInvite>>(
  (ref) => ref.watch(spacesRepositoryProvider).watchMyInvites(),
);

final spaceProvider = StreamProvider.autoDispose.family<Space?, String>(
  (ref, spaceId) => ref.watch(spacesRepositoryProvider).watchSpace(spaceId),
);

final spaceMembersProvider = StreamProvider.autoDispose
    .family<List<SpaceMember>, String>(
      (ref, spaceId) =>
          ref.watch(spacesRepositoryProvider).watchMembers(spaceId),
    );

/// Participantes manuales del espacio (ADR-033), en vivo.
final spaceManualParticipantsProvider = StreamProvider.autoDispose
    .family<List<ManualParticipant>, String>(
      (ref, spaceId) => ref
          .watch(spacesRepositoryProvider)
          .watchManualParticipants(spaceId),
    );

final spaceInvitesProvider = StreamProvider.autoDispose
    .family<List<SpaceInvite>, String>(
      (ref, spaceId) =>
          ref.watch(spacesRepositoryProvider).watchSpaceInvites(spaceId),
    );

final spaceTicketsProvider = StreamProvider.autoDispose
    .family<List<SpaceTicket>, String>(
      (ref, spaceId) =>
          ref.watch(spacesRepositoryProvider).watchSpaceTickets(spaceId),
    );

/// Espacio pendiente de vincular al PRÓXIMO ticket creado ("crear ticket
/// desde el espacio"): lo consume el controlador de creación al guardar.
final pendingSpaceLinkProvider =
    NotifierProvider<
      PendingSpaceLink,
      ({String id, String name, SpaceKind kind})?
    >(PendingSpaceLink.new);

class PendingSpaceLink
    extends Notifier<({String id, String name, SpaceKind kind})?> {
  @override
  ({String id, String name, SpaceKind kind})? build() => null;

  void set(String id, String name, SpaceKind kind) =>
      state = (id: id, name: name, kind: kind);

  void clear() => state = null;

  ({String id, String name, SpaceKind kind})? consume() {
    final value = state;
    state = null;
    return value;
  }
}
