import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:domain/domain.dart' show ShareCode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/diagnostics/social_log.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/guest_identity_repository.dart';
import '../domain/space_models.dart';

enum SpaceFailureCode {
  accountRequired,
  notAllowed,
  alreadyMember,
  ownerCannotLeave,
  targetUnavailable,

  /// La otra persona ya creó la relación y te invitó: hay que ACEPTAR, no
  /// crear. Antes esto caía en `alreadyMember` y se mostraba como un error
  /// genérico, con la relación esperando en Inicio (BUG-3).
  invitedByOther,

  /// Documento canónico presente pero en un estado que no encaja con el
  /// modelo (datos antiguos o parciales). Recuperable avisando, nunca
  /// escribiendo encima a ciegas.
  incompatibleData,

  /// El servidor rechazó la escritura. En la práctica significa que la
  /// sesión NO cumple lo que exigen las Rules para escribir en el ámbito
  /// social: token todavía anónimo (conversión reciente sin refrescar),
  /// correo sin verificar, o perfil público sin crear. Se distingue del
  /// resto porque tiene arreglo por parte del usuario y merece decírselo.
  permissionDenied,
}

/// Traduce un fallo de Firestore a un [SpaceFailure] tipado y deja rastro
/// en consola para diagnóstico.
///
/// El rastro lleva la OPERACIÓN y el CÓDIGO, nunca el UID, el manualId ni la
/// ruta del documento: eso identificaría a personas en un log que puede
/// acabar en un informe de errores.
Never _rethrowAsSpaceFailure(String operation, Object error) {
  if (error is SpaceFailure) throw error;
  if (error is FirebaseException) {
    debugPrint('spaces.$operation falló: ${error.code}');
    throw SpaceFailure(
      error.code == 'permission-denied'
          ? SpaceFailureCode.permissionDenied
          : SpaceFailureCode.notAllowed,
    );
  }
  debugPrint('spaces.$operation falló: ${error.runtimeType}');
  throw const SpaceFailure(SpaceFailureCode.notAllowed);
}

/// Cómo terminó `createRelationship`. Distinguirlo es lo que permite a la UI
/// decir algo útil en vez de «no se pudo completar la acción».
enum RelationshipOutcome {
  /// Relación y primera invitación creadas.
  created,

  /// Ya existía con una invitación pendiente tuya: no se duplica nada.
  alreadyInvited,

  /// Había una invitación rechazada o cancelada y se ha vuelto a enviar.
  reinvited,

  /// Las dos personas ya son miembros: la relación está activa.
  alreadyActive,
}

/// Resultado de crear una relación: su id y qué ocurrió realmente.
typedef RelationshipResult = ({String id, RelationshipOutcome outcome});

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

  CollectionReference<Map<String, dynamic>> get _links =>
      firestore.collection('spaceLinks');

  void _requireAccount() {
    if (!isFullAccount()) {
      throw const SpaceFailure(SpaceFailureCode.accountRequired);
    }
  }

  /// Cuenta o INVITADO: lo que basta para PARTICIPAR (ADR-034). Espejo en
  /// cliente de `canParticipate()` de Rules.
  void _requireParticipant() {
    if (!isFullAccount() && guestDisplayName?.call() == null) {
      throw const SpaceFailure(SpaceFailureCode.accountRequired);
    }
  }

  // ── Lectura en tiempo real ────────────────────────────────────────────

  /// Mis espacios: collection group sobre MIS membresías; cada cambio de
  /// membresía relee los espacios. (Editar el nombre de un espacio se
  /// refleja al entrar en su detalle, que sí escucha el doc en vivo.)
  ///
  /// También para INVITADOS: participar incluye poder llegar a los grupos
  /// de los que ya se es miembro. Sin esto, entrar por enlace dejaba al
  /// invitado dentro del grupo pero sin ninguna pantalla desde la que verlo.
  Stream<List<Space>> watchMySpaces() {
    _requireParticipant();
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
    // BUG-4: solo los GRUPOS admiten personas añadidas a mano. Una relación
    // tiene sus dos identidades decididas —la invitación reserva la segunda
    // en v2, y el manual la ocupa en v3—, así que añadir otra la rompería.
    // Rules ya lo deniega; aquí se corta antes para dar un error con sentido
    // y para que un cliente modificado no dependa solo del servidor.
    final space = await _spaces.doc(spaceId).get();
    if (space.data()?['kind'] == SpaceKind.relationship.name) {
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
  ) => ManualParticipant(
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
  ///
  /// BUG-3: antes, CUALQUIER documento canónico preexistente abortaba con
  /// `alreadyMember`, que la pantalla mostraba como un error genérico. Como
  /// el id se deriva del par de UID, eso ocurría exactamente en los casos en
  /// que la relación ya tenía historia con ESA cuenta —la otra persona te
  /// había invitado antes, o hubo un rechazo previo— y dejaba un callejón
  /// sin salida permanente con ella. Ahora cada situación se distingue y la
  /// que tiene arreglo se resuelve sola.
  Future<RelationshipResult> createRelationship({
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

    final existing = await space.get();
    if (existing.exists) {
      return _resumeRelationship(space, invite, existing, fromUid, toUid);
    }

    await firestore
        .runTransaction((transaction) async {
          // Se relee DENTRO de la transacción: entre la comprobación anterior y
          // este punto la otra persona puede haber creado la misma relación
          // canónica. Si ocurre, converge en el camino de reanudación.
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
        })
        .catchError((Object error) async {
          // Carrera: la creó la otra persona mientras tanto. No es un fallo.
          if (error is SpaceFailure &&
              error.code == SpaceFailureCode.alreadyMember) {
            return;
          }
          throw error;
        });

    final after = await space.get();
    if (!after.exists) throw const SpaceFailure(SpaceFailureCode.notAllowed);
    // Si la ganó la otra persona, el resultado converge al mismo estado.
    if ((after.data()?['ownerUid'] as String?) != fromUid) {
      return _resumeRelationship(space, invite, after, fromUid, toUid);
    }
    return (id: space.id, outcome: RelationshipOutcome.created);
  }

  /// Relación con una persona SIN cuenta (BUG-2).
  ///
  /// Sigue siendo un contexto de exactamente DOS identidades económicas: la
  /// mía y el actor `manual:{manualId}`. La diferencia con una relación entre
  /// cuentas es el identificador: como la segunda parte no tiene UID, no
  /// puede derivarse del par canónico, así que se genera. Las de dos cuentas
  /// siguen usando su id canónico —es lo que impide duplicados— y no cambian.
  ///
  /// El espacio, mi membresía y el participante manual se escriben en UN
  /// batch: Rules exige el manual con `getAfter`, de modo que no puede
  /// quedar una relación a medias con una sola identidad.
  Future<RelationshipResult> createRelationshipWithManual({
    required String name,
    required String manualName,
    String flow = '-',
  }) async {
    _requireAccount();
    final personName = manualName.trim();
    if (personName.isEmpty || personName.length > 40) {
      throw const SpaceFailure(SpaceFailureCode.notAllowed);
    }
    final space = _spaces.doc();
    final manual = space.collection('manualParticipants').doc();

    final batch = firestore.batch();
    batch.set(space, {
      'name': name.trim(),
      'ownerUid': uid(),
      'kind': SpaceKind.relationship.name,
      // Una sola cuenta; la segunda plaza la ocupa el manual.
      'relationshipUids': [uid()],
      'relationshipManualId': manual.id,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'schemaVersion': 3,
    });
    batch.set(space.collection('members').doc(uid()), {
      'uid': uid(),
      'joinedAt': FieldValue.serverTimestamp(),
    });
    batch.set(manual, {
      'manualId': manual.id,
      'displayName': personName,
      // Reservado a la vinculación del Sprint 6: cuando Pablo se registre,
      // su UID se añade aquí sin tocar el actor `manual:{id}` ni el
      // histórico económico.
      'linkedUid': null,
      'createdByUid': uid(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'schemaVersion': 1,
    });
    // Un batch es todo-o-nada: si Rules deniega cualquiera de los tres
    // documentos no se escribe ninguno, así que no puede quedar un manual
    // huérfano ni un espacio sin membresía. Lo que faltaba era TRADUCIR el
    // fallo: `permission-denied` llegaba a la UI como un error genérico.
    SocialLog.log(flow, 'batchRelacionManual', {
      'fase': 'commit',
      'docs': 'space,members,manualParticipants',
      'schemaVersion': 3,
      'espacio': SocialLog.fingerprint(space.id),
    });
    try {
      await batch.commit();
      SocialLog.log(flow, 'batchRelacionManual', {'fase': 'ok'});
    } on Object catch (error) {
      SocialLog.log(flow, 'batchRelacionManual', {
        'fase': 'error',
        ...SocialLog.errorFields(error),
      });
      _rethrowAsSpaceFailure('createRelationshipWithManual', error);
    }
    return (id: space.id, outcome: RelationshipOutcome.created);
  }

  /// Qué hacer cuando la relación canónica YA existe. Cada rama corresponde
  /// a una situación real distinta, y solo una es un error de verdad.
  Future<RelationshipResult> _resumeRelationship(
    DocumentReference<Map<String, dynamic>> space,
    DocumentReference<Map<String, dynamic>> invite,
    DocumentSnapshot<Map<String, dynamic>> existing,
    String fromUid,
    String toUid,
  ) async {
    final ownerUid = (existing.data()?['ownerUid'] as String?) ?? '';
    final members = space.collection('members');
    final soyMiembro = (await members.doc(fromUid).get()).exists;
    final esMiembro = (await members.doc(toUid).get()).exists;

    // Las dos plazas ocupadas: la relación ya está viva.
    if (soyMiembro && esMiembro) {
      return (id: space.id, outcome: RelationshipOutcome.alreadyActive);
    }

    // La creó la OTRA persona: lo correcto es aceptar su invitación, no
    // crear nada. La pantalla lo dirá con esas palabras.
    if (ownerUid == toUid) {
      throw const SpaceFailure(SpaceFailureCode.invitedByOther);
    }

    if (ownerUid != fromUid) {
      // Ni mía ni suya: dato antiguo o incoherente. No se escribe encima.
      throw const SpaceFailure(SpaceFailureCode.incompatibleData);
    }

    final inviteSnap = await invite.get();
    final status = inviteSnap.data()?['status'] as String?;
    if (status == 'pending') {
      return (id: space.id, outcome: RelationshipOutcome.alreadyInvited);
    }
    if (status == 'accepted') {
      return (id: space.id, outcome: RelationshipOutcome.alreadyActive);
    }

    // Rechazada, cancelada o perdida: se REENVÍA sobre el mismo documento
    // determinista, que es justo lo que Rules permite al propietario. Antes
    // no había forma de volver a invitar a esa persona nunca más.
    await invite.set({
      'spaceId': space.id,
      'spaceName': (existing.data()?['name'] as String?) ?? '',
      'fromUid': fromUid,
      'toUid': toUid,
      'status': 'pending',
      'createdAt':
          inviteSnap.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return (id: space.id, outcome: RelationshipOutcome.reinvited);
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

  // ── Enlaces de grupo (Sprint 4, ADR-035) ──────────────────────────────

  /// Enlace vivo del grupo (vista del propietario). Rules restringe este
  /// `list` al propietario ACTUAL, así que el token no es enumerable por
  /// nadie más — ni siquiera por los demás miembros.
  Stream<SpaceJoinLink?> watchActiveJoinLink(String spaceId) => _links
      .where('spaceId', isEqualTo: spaceId)
      .where('status', isEqualTo: 'active')
      .snapshots()
      .map((snap) {
        final now = DateTime.now().toUtc();
        // La query filtra por `status`; la caducidad se descarta aquí para
        // no necesitar un índice compuesto por una comprobación trivial.
        final links = [
          for (final d in snap.docs)
            if (_linkFrom(d).usableAt(now)) _linkFrom(d),
        ];
        // Rotar deja el anterior revocado, así que en la práctica hay 0 o 1;
        // ante un empate por carrera gana el más reciente, nunca dos vivos
        // compitiendo en la UI.
        links.sort(
          (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
            a.createdAt ?? DateTime(0),
          ),
        );
        return links.isEmpty ? null : links.first;
      });

  /// Crea el enlace del grupo. El token es un secreto de 128 bits
  /// (`ShareCode`, la misma primitiva del enlace de invitados) y ES el id
  /// del documento: así Rules puede validar el conocimiento sin que el
  /// secreto tenga que copiarse a ningún documento legible.
  Future<SpaceJoinLink> createJoinLink(
    String spaceId,
    String spaceName, {
    JoinLinkLifetime lifetime = JoinLinkLifetime.never,
  }) async {
    _requireAccount();
    final token = ShareCode.generate().value;
    final name = spaceName.trim();
    // La caducidad se calcula en cliente porque Firestore no sabe sumar a
    // serverTimestamp; Rules solo comprueba que no nazca ya caducada, así
    // que un reloj adelantado no puede alargar la vida de nadie más.
    final expiresAt = lifetime.duration == null
        ? null
        : DateTime.now().toUtc().add(lifetime.duration!);
    await _links.doc(token).set({
      'spaceId': spaceId,
      'spaceName': name,
      'createdByUid': uid(),
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
      'schemaVersion': 1,
    });
    return SpaceJoinLink(
      token: token,
      spaceId: spaceId,
      spaceName: name,
      createdByUid: uid(),
      revoked: false,
      expiresAt: expiresAt,
    );
  }

  /// Revocar corta el acceso de inmediato: la membresía revalida el enlace
  /// en cada canje, así que un token ya repartido deja de servir aunque
  /// alguien lo hubiera guardado.
  Future<void> revokeJoinLink(String token) => _links.doc(token).update({
    'status': 'revoked',
    'updatedAt': FieldValue.serverTimestamp(),
  });

  /// Rotar = revocar el anterior y crear uno nuevo. Son dos documentos
  /// distintos a propósito: el token viejo queda demostrablemente muerto en
  /// lugar de reciclarse.
  Future<SpaceJoinLink> rotateJoinLink(
    String spaceId,
    String spaceName, {
    String? previousToken,
    JoinLinkLifetime lifetime = JoinLinkLifetime.never,
  }) async {
    _requireAccount();
    if (previousToken != null) await revokeJoinLink(previousToken);
    return createJoinLink(spaceId, spaceName, lifetime: lifetime);
  }

  /// Mantiene el rótulo del enlace al día tras renombrar el grupo (solo es
  /// presentación: el enlace nunca cambia de grupo).
  Future<void> syncJoinLinkName(String token, String spaceName) =>
      _links.doc(token).update({
        'spaceName': spaceName.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Mira el enlace ANTES de entrar: quien lo recibe ve a qué grupo va sin
  /// ser todavía miembro. Devuelve null si el token no existe o fue
  /// revocado — la app no distingue ambos casos para no dar un oráculo.
  Future<SpaceJoinLink?> previewJoinLink(String token) async {
    final doc = await _links.doc(_normalizeToken(token)).get();
    if (!doc.exists) return null;
    final link = _linkFrom(doc);
    // Revocado, caducado e inexistente se tratan igual: la app no distingue
    // los casos para no convertirse en un oráculo de qué grupos existen.
    return link.usableAt(DateTime.now().toUtc()) ? link : null;
  }

  /// Canjea el enlace: escribe la prueba de conocimiento y la membresía en
  /// UN SOLO batch, que es lo que Rules valida (`existsAfter`). Cuenta e
  /// invitado entran por el mismo camino; solo cambia lo que se guarda en
  /// la membresía, porque el invitado no tiene perfil del que leer su
  /// nombre en vivo.
  Future<JoinLinkOutcome> joinWithLink(String token) async {
    final normalized = _normalizeToken(token);
    final link = await previewJoinLink(normalized);
    if (link == null) return JoinLinkOutcome.invalid;

    final guestName = guestDisplayName?.call();
    if (guestName == null) {
      // Ni cuenta ni invitado con nombre: la app le pide antes su nombre
      // visible en vez de fallar con un permiso denegado.
      if (!isFullAccount()) return JoinLinkOutcome.needsGuestName;
    }

    final member = _spaces.doc(link.spaceId).collection('members').doc(uid());
    if ((await member.get()).exists) return JoinLinkOutcome.alreadyMember;

    final batch = firestore.batch();
    batch.set(_spaces.doc(link.spaceId).collection('joinGrants').doc(uid()), {
      'uid': uid(),
      'token': normalized,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(member, {
      'uid': uid(),
      'joinedAt': FieldValue.serverTimestamp(),
      if (guestName != null) ...{'kind': 'guest', 'displayName': guestName},
    });
    await batch.commit();
    return JoinLinkOutcome.joined;
  }

  /// Acepta tanto el enlace completo como el token pelado: pegar la URL
  /// entera desde WhatsApp es el caso normal.
  static String _normalizeToken(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return value;
    final marker = value.lastIndexOf('/g/');
    if (marker >= 0) value = value.substring(marker + 3);
    // Restos de la URL que no forman parte del token base64url.
    for (final separator in ['?', '#', '/']) {
      final index = value.indexOf(separator);
      if (index >= 0) value = value.substring(0, index);
    }
    return value.trim();
  }

  /// Enlace de grupo canónico. El token va en la RUTA, no en el fragment:
  /// a diferencia del `#k=` de una sesión, aquí el servidor necesitará
  /// resolverlo para pintar la página de aterrizaje.
  static String joinUrlFor(String hostingDomain, String token) =>
      'https://$hostingDomain/g/$token';

  SpaceJoinLink _linkFrom(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return SpaceJoinLink(
      token: doc.id,
      spaceId: (data['spaceId'] as String?) ?? '',
      spaceName: (data['spaceName'] as String?) ?? '',
      createdByUid: (data['createdByUid'] as String?) ?? '',
      revoked: data['status'] != 'active',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate().toUtc(),
    );
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
      if (guestName != null) ...{'kind': 'guest', 'displayName': guestName},
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
      relationshipManualId: (data['relationshipManualId'] as String?) ?? '',
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
      (ref, spaceId) =>
          ref.watch(spacesRepositoryProvider).watchManualParticipants(spaceId),
    );

final spaceInvitesProvider = StreamProvider.autoDispose
    .family<List<SpaceInvite>, String>(
      (ref, spaceId) =>
          ref.watch(spacesRepositoryProvider).watchSpaceInvites(spaceId),
    );

/// Enlace de grupo pendiente de canjear mientras el usuario se identifica.
///
/// Sin esto, tocar "iniciar sesión" o "crear cuenta" perdía el enlace: al
/// autenticarse, el router manda a `/home` y el token se quedaba por el
/// camino, obligando a volver a pulsar el enlace del chat. El router lo
/// consume para devolver a la persona exactamente donde estaba.
final pendingGroupLinkProvider = NotifierProvider<PendingGroupLink, String?>(
  PendingGroupLink.new,
);

class PendingGroupLink extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String token) => state = token;

  void clear() => state = null;
}

/// Enlace vivo del grupo. Solo devuelve algo al propietario: Rules restringe
/// el `list` de `spaceLinks` al dueño del grupo.
final spaceJoinLinkProvider = StreamProvider.autoDispose
    .family<SpaceJoinLink?, String>(
      (ref, spaceId) =>
          ref.watch(spacesRepositoryProvider).watchActiveJoinLink(spaceId),
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
