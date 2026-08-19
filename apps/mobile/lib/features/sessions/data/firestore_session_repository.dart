import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:domain/domain.dart';

import '../domain/session_models.dart';
import 'session_repository.dart';

/// Implementación Firestore del repositorio de sesiones (modelo spec §7).
///
/// La creación se hace en DOS pasos (doc de sesión y luego batch con el
/// resto) porque las reglas de las subcolecciones validan con get() sobre
/// la sesión, que dentro de un mismo batch aún no existiría.
class FirestoreSessionRepository implements SessionRepository {
  FirestoreSessionRepository({
    required this.firestore,
    required this.uid,
    required this.shareCodeFactory,
  });

  final FirebaseFirestore firestore;
  final String Function() uid;
  final String Function() shareCodeFactory;

  CollectionReference<Map<String, dynamic>> get _sessions =>
      firestore.collection('sessions');

  @override
  Stream<List<SessionSummary>> watchSessions() => _sessions
      .where('ownerUid', isEqualTo: uid())
      .orderBy('updatedAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map((d) => _summary(d.id, d.data())).toList());

  @override
  Stream<SessionDetail?> watchSession(String sessionId) =>
      _sessions.doc(sessionId).snapshots().map((doc) {
        final data = doc.data();
        if (data == null) return null;
        return SessionDetail(
          summary: _summary(doc.id, data),
          shareCode: (data['shareCode'] as String?) ?? '',
          splitModeDefault: SplitMode.values.byName(
            (data['splitModeDefault'] as String?) ?? 'equal',
          ),
          balances: {
            for (final entry
                in ((data['balances'] as Map?) ?? const {}).entries)
              entry.key as String: _balance(entry.value as Map),
          },
        );
      });

  @override
  Stream<List<SessionParticipant>> watchParticipants(String sessionId) =>
      _sessions
          .doc(sessionId)
          .collection('participants')
          .orderBy('order')
          .snapshots()
          .map(
            (snap) => [
              for (final d in snap.docs)
                SessionParticipant(
                  id: d.id,
                  name: (d.data()['name'] as String?) ?? '',
                  isOwner: (d.data()['isOwner'] as bool?) ?? false,
                  order: (d.data()['order'] as int?) ?? 0,
                  claimedByDevice:
                      (d.data()['claimedByDevice'] as String?) ?? '',
                  active: (d.data()['active'] as bool?) ?? true,
                ),
            ],
          );

  @override
  Stream<List<SessionAccount>> watchAccounts(String sessionId) => _sessions
      .doc(sessionId)
      .collection('accounts')
      .orderBy('order')
      .snapshots()
      .map(
        (snap) => [
          for (final d in snap.docs)
            SessionAccount(
              id: d.id,
              name: (d.data()['name'] as String?) ?? '',
              order: (d.data()['order'] as int?) ?? 0,
              grandTotal: Money(
                ((d.data()['totals'] as Map?)?['grandTotal'] as int?) ?? 0,
              ),
            ),
        ],
      );

  @override
  Stream<List<Settlement>> watchSettlements(String sessionId) => _sessions
      .doc(sessionId)
      .collection('settlements')
      .snapshots()
      .map(
        (snap) => [
          for (final d in snap.docs)
            Settlement(
              id: d.id,
              from: (d.data()['from'] as String?) ?? '',
              to: (d.data()['to'] as String?) ?? '',
              amount: Money((d.data()['amount'] as int?) ?? 0),
              state: SettlementState.values.byName(
                (d.data()['state'] as String?) ?? 'pending',
              ),
            ),
        ]..sort((a, b) => b.amount.cents.compareTo(a.amount.cents)),
      );

  @override
  Future<({String sessionId, String ticketPath})> createSession(
    NewSessionInput input,
  ) async {
    final owner = uid();
    final sessionRef = _sessions.doc();

    // Paso 1: el documento de sesión (las reglas de subdocs hacen get()).
    await sessionRef.set({
      'schemaVersion': 1,
      if (input.spaceId != null) 'contextModelVersion': 1,
      if (input.spaceId != null) 'spaceId': input.spaceId,
      if (input.spaceName != null) 'spaceName': input.spaceName,
      'ownerUid': owner,
      'kind': input.kind,
      'name': input.name,
      'currency': 'EUR',
      'category': input.ticket.category,
      'status': 'open',
      'splitModeDefault': input.splitModeDefault.name,
      'shareCode': shareCodeFactory(),
      'ownerParticipantId': 'p0',
      'paymentMethodsSnapshot': input.paymentMethodsSnapshot,
      'computeVersion': 0,
      'totals': {
        'grandTotal': 0,
        'settlementRequired': 0,
        'settledConfirmed': 0,
        'settledMarked': 0,
      },
      'balances': const <String, Object?>{},
      'participantsCount': input.participantNames.length,
      'pendingSettlements': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Paso 2: participantes, cuenta, ticket, líneas y actividad.
    final batch = firestore.batch();
    for (var i = 0; i < input.participantNames.length; i++) {
      // Un participante es de CUENTA (claimedByDevice) o MANUAL (manualId),
      // nunca ambos: el actor económico se deriva de esa identidad estable
      // y no del nombre, que puede cambiar (ADR-033).
      final manualId = i < input.participantManualIds.length
          ? input.participantManualIds[i]
          : '';
      batch.set(sessionRef.collection('participants').doc('p$i'), {
        'name': input.participantNames[i],
        'isOwner': i == 0,
        'order': i,
        'claimedByDevice': manualId.isNotEmpty
            ? ''
            : (i < input.participantUids.length
                  ? input.participantUids[i]
                  : ''),
        if (manualId.isNotEmpty) 'manualId': manualId,
        'active': true,
      });
    }

    final ticketPath = _writeAccountWithTicket(
      batch,
      sessionRef: sessionRef,
      accountIndex: 0,
      accountName: input.accountName ?? input.ticket.merchantName,
      ticket: input.ticket,
      payerPid: 'p${input.payerIndex}',
      spaceId: input.spaceId,
      splitMode: input.splitModeDefault,
    );

    batch.set(sessionRef.collection('activity').doc(), {
      'type': 'sessionCreated',
      'actor': 'host',
      'at': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    return (sessionId: sessionRef.id, ticketPath: ticketPath);
  }

  @override
  Future<String> addTicket(
    String sessionId,
    NewTicketInput ticket, {
    required String payerPid,
    required String spaceId,
  }) async {
    final sessionRef = _sessions.doc(sessionId);
    final accounts = await sessionRef.collection('accounts').get();
    final session = await sessionRef.get();
    final batch = firestore.batch();
    final ticketPath = _writeAccountWithTicket(
      batch,
      sessionRef: sessionRef,
      accountIndex: accounts.size,
      accountName: ticket.merchantName,
      ticket: ticket,
      payerPid: payerPid,
      spaceId: spaceId,
      splitMode: SplitMode.values.byName(
        (session.data()?['splitModeDefault'] as String?) ?? 'equal',
      ),
    );
    batch.update(sessionRef, {
      // Con más de una cuenta la sesión es conceptualmente multi (DC-6).
      if (accounts.size >= 1) 'kind': 'multi',
      'contextModelVersion': 1,
      'spaceId': spaceId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(sessionRef.collection('activity').doc(), {
      'type': 'ticketAdded',
      'actor': 'host',
      'at': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return ticketPath;
  }

  /// Devuelve la ruta del ticket creado.
  String _writeAccountWithTicket(
    WriteBatch batch, {
    required DocumentReference<Map<String, dynamic>> sessionRef,
    required int accountIndex,
    required String accountName,
    required NewTicketInput ticket,
    required String payerPid,
    String? spaceId,
    SplitMode? splitMode,
  }) {
    final accountRef = sessionRef.collection('accounts').doc('a$accountIndex');
    batch.set(accountRef, {
      'name': accountName,
      'order': accountIndex,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final ticketRef = accountRef.collection('tickets').doc();
    batch.set(ticketRef, {
      'kind': ticket.kind,
      'merchant': {'name': ticket.merchantName, 'brandKey': ticket.brandKey},
      'date': ticket.date,
      'time': ticket.time,
      'paidByParticipantId': payerPid,
      'ocr': {'engine': ticket.engine, 'confidence': ticket.confidence},
      'taxes': [
        for (final t in ticket.taxes)
          {'label': t.label, 'amount': t.amount.cents},
      ],
      'discounts': [
        for (final d in ticket.discounts)
          {'label': d.label, 'amount': d.amount.cents},
      ],
      'tip': ticket.tip?.cents,
      'grandTotal': ticket.grandTotal.cents,
      ...?spaceId == null
          ? null
          : <String, Object?>{
              'spaceId': spaceId,
              'contextModelVersion': 1,
              // Modo efectivo EN EL TICKET (A11b). Un miembro del grupo
              // audita el ticket pero NO puede leer `sessions/{sid}` —ahí
              // vive el shareCode—, así que sin esto no sabría si el gasto
              // se reparte por líneas y no podría elegir su consumo. El
              // campo ya existía y recompute ya le da precedencia sobre el
              // valor de la sesión: escribir el mismo valor no cambia un
              // solo céntimo, solo lo hace visible a quien participa.
              if (splitMode != null) 'splitModeOverride': splitMode.name,
            },
      'createdAt': FieldValue.serverTimestamp(),
    });

    for (var i = 0; i < ticket.lines.length; i++) {
      final line = ticket.lines[i];
      batch.set(ticketRef.collection('lines').doc('l$i'), {
        'name': line.name,
        'quantityMilli': line.quantityMilli,
        'unitPrice': line.unitPrice?.cents,
        'totalPrice': line.totalPrice.cents,
        'order': i,
        'unitIds': [
          for (
            var unit = 0;
            unit < SplitLine.unitsFromQuantityMilli(line.quantityMilli);
            unit++
          )
            'u$unit',
        ],
        'assignment': {
          'type': 'units',
          'schemaVersion': 2,
          'units': const <String, Object?>{},
        },
      });
    }
    return ticketRef.path;
  }

  @override
  Stream<List<SessionTicket>> watchTickets(
    String sessionId,
    String accountId,
  ) => _sessions
      .doc(sessionId)
      .collection('accounts')
      .doc(accountId)
      .collection('tickets')
      .snapshots()
      .map(
        (snap) => [
          for (final d in snap.docs)
            SessionTicket(
              id: d.id,
              path: d.reference.path,
              merchantName:
                  ((d.data()['merchant'] as Map?)?['name'] as String?) ?? '',
              date: d.data()['date'] as String?,
              grandTotal: Money((d.data()['grandTotal'] as int?) ?? 0),
              paidBy: (d.data()['paidByParticipantId'] as String?) ?? '',
              kind: (d.data()['kind'] as String?) ?? 'scanned',
              imagePath: d.data()['imagePath'] as String?,
              splitModeOverride: switch (d.data()['splitModeOverride']
                  as String?) {
                'equal' => SplitMode.equal,
                'byItem' => SplitMode.byItem,
                _ => null,
              },
              spaceId: d.data()['spaceId'] as String?,
              contextModelVersion:
                  (d.data()['contextModelVersion'] as int?) ?? 0,
            ),
        ],
      );

  @override
  Future<List<LineExport>> fetchTicketLines(String ticketPath) async {
    final lines = await firestore
        .collection('$ticketPath/lines')
        .orderBy('order')
        .get();
    return [
      for (final line in lines.docs)
        LineExport(
          name: (line.data()['name'] as String?) ?? '',
          quantityMilli: (line.data()['quantityMilli'] as int?) ?? 1000,
          totalPrice: Money((line.data()['totalPrice'] as int?) ?? 0),
        ),
    ];
  }

  @override
  Stream<List<TicketLine>> watchTicketLines(String ticketPath) => firestore
      .collection('$ticketPath/lines')
      .orderBy('order')
      .snapshots()
      .map(
        (snap) => [
          for (final line in snap.docs)
            TicketLine(
              id: line.id,
              path: line.reference.path,
              name: (line.data()['name'] as String?) ?? '',
              quantityMilli: (line.data()['quantityMilli'] as int?) ?? 1000,
              totalPrice: Money((line.data()['totalPrice'] as int?) ?? 0),
              assignmentType:
                  ((line.data()['assignment'] as Map?)?['type'] as String?) ??
                  'unassigned',
              weights: {
                for (final entry
                    in (((line.data()['assignment'] as Map?)?['participants']
                                as Map?) ??
                            const {})
                        .entries)
                  if (entry.value is int && (entry.value as int) > 0)
                    entry.key as String: entry.value as int,
              },
              assignmentSchemaVersion:
                  ((line.data()['assignment'] as Map?)?['schemaVersion']
                      as int?),
              unitConsumers: {
                for (final unitEntry
                    in (((line.data()['assignment'] as Map?)?['units']
                                as Map?) ??
                            const {})
                        .entries)
                  if ((unitEntry.key as String).startsWith('u') &&
                      int.tryParse((unitEntry.key as String).substring(1)) !=
                          null)
                    int.parse((unitEntry.key as String).substring(1)): {
                      for (final member
                          in ((unitEntry.value as Map?) ?? const {}).entries)
                        if (member.value == true || member.value == 1)
                          member.key as String,
                    },
              },
            ),
        ],
      );

  @override
  Future<void> setLineAssignment(
    String linePath,
    Map<String, int> weights, {
    required String editorPid,
  }) {
    // [weights] es el mapa COMPLETO deseado: 0 = quitar a esa persona.
    // Cada entrada se escribe con su ruta punteada (peso o delete): misma
    // semántica en producción y en fake_cloud_firestore, que fusionaría un
    // mapa pasado como valor y dejaría entradas fantasma.
    final positive = weights.values.where((w) => w > 0).length;
    final updates = <String, Object?>{
      'assignment.type': positive == 0
          ? 'unassigned'
          : positive == 1
          ? 'one'
          : 'shared',
      'assignment.lastEditorPid': editorPid,
      for (final entry in weights.entries)
        'assignment.participants.${entry.key}': entry.value > 0
            ? entry.value
            : FieldValue.delete(),
    };
    return firestore.doc(linePath).update(updates);
  }

  @override
  Future<void> convertLineToUnitAssignment(
    String linePath, {
    required String editorPid,
    required int unitCount,
  }) => firestore.doc(linePath).update({
    'unitIds': [for (var unit = 0; unit < unitCount; unit++) 'u$unit'],
    'assignment.type': 'units',
    'assignment.schemaVersion': 2,
    'assignment.units': const <String, Object?>{},
    'assignment.lastEditorPid': editorPid,
    'assignment.lastEditedUnit': '',
    'assignment.participants': FieldValue.delete(),
  });

  @override
  Future<void> setUnitConsumer(
    String linePath, {
    required int unit,
    required String participantId,
    required bool selected,
  }) => firestore.doc(linePath).update({
    'assignment.type': 'units',
    'assignment.schemaVersion': 2,
    'assignment.lastEditorPid': participantId,
    'assignment.lastEditedUnit': 'u$unit',
    'assignment.units.u$unit.$participantId': selected
        ? true
        : FieldValue.delete(),
  });

  @override
  Future<void> setTicketImage(String ticketPath, String storagePath) =>
      firestore.doc(ticketPath).update({'imagePath': storagePath});

  /// Firma de la corrección (A11c). El actor lo pone quien escribe y la
  /// fecha el servidor: las Rules comprueban ambas cosas, así que no se
  /// puede corregir un gasto ajeno de forma anónima.
  Map<String, Object?> get _correctionSignature => {
    'lastEditedByUid': uid(),
    'lastEditedAt': FieldValue.serverTimestamp(),
  };

  @override
  Future<void> correctTicketHeader(
    String ticketPath, {
    required String merchantName,
    String? date,
    required Money grandTotal,
  }) => firestore.doc(ticketPath).update({
    'merchant.name': merchantName,
    ...?date == null ? null : <String, Object?>{'date': date},
    'grandTotal': grandTotal.cents,
    ..._correctionSignature,
  });

  @override
  Future<void> correctLine(
    String linePath, {
    required String name,
    required int quantityMilli,
    required Money totalPrice,
    List<String> removedUnitIds = const [],
    List<String>? unitIds,
  }) async {
    final lineRef = firestore.doc(linePath);
    final ticketRef = lineRef.parent.parent!;

    final batch = firestore.batch();
    batch.update(lineRef, {
      'name': name,
      'quantityMilli': quantityMilli,
      'totalPrice': totalPrice.cents,
      // El precio unitario deja de ser cierto en cuanto se corrige el
      // importe o la cantidad, y nadie lo recalcula: se retira antes que
      // conservar un dato falso (solo lo lee el backup).
      'unitPrice': FieldValue.delete(),
      ...?unitIds == null ? null : <String, Object?>{'unitIds': unitIds},
      // Poda quirúrgica: se borra la entrada de la unidad que desaparece y
      // NADA más. Reescribir el mapa entero habría sido más corto y habría
      // permitido colar a alguien en una unidad ajena de paso.
      for (final unit in removedUnitIds)
        'assignment.units.$unit': FieldValue.delete(),
    });
    // El total NO se toca. `grandTotal` es el dinero REALMENTE pagado (tras
    // impuestos, descuentos y propina) y las líneas son los PESOS con los
    // que ese dinero se reparte (DC-11): por eso los vectores dorados tienen
    // tickets donde la suma de líneas y el total difieren a propósito.
    // Corregir un producto mal leído cambia el reparto —que es lo que debe
    // cambiar— sin inventar que se pagó más. Si el total también está mal,
    // se corrige aparte y a conciencia.
    batch.update(ticketRef, _correctionSignature);
    await batch.commit();
  }

  @override
  Future<void> removeLine(String linePath) async {
    final lineRef = firestore.doc(linePath);
    final ticketRef = lineRef.parent.parent!;

    final batch = firestore.batch();
    batch.delete(lineRef);
    // Retirar un producto que el OCR se inventó no devuelve dinero: lo
    // pagado sigue siendo lo que pone el ticket. Lo que cambia es que ese
    // importe pasa a repartirse entre los productos que sí existen.
    batch.update(ticketRef, _correctionSignature);
    await batch.commit();
  }

  @override
  Future<void> updateSettlementState(
    String sessionId,
    String settlementId,
    SettlementState state,
  ) => _sessions
      .doc(sessionId)
      .collection('settlements')
      .doc(settlementId)
      .update({
        'state': state.name,
        'stateHistory': FieldValue.arrayUnion([
          {'state': state.name, 'at': Timestamp.now(), 'by': 'host'},
        ]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> setStatus(String sessionId, SessionStatus status) =>
      _sessions.doc(sessionId).update({
        'status': status.name,
        'closedAt': status == SessionStatus.closed
            ? FieldValue.serverTimestamp()
            : null,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> deleteSession(String sessionId) =>
      _sessions.doc(sessionId).delete(); // cleanup purga el resto

  @override
  Future<String> regenerateShareCode(String sessionId) async {
    final code = shareCodeFactory();
    await _sessions.doc(sessionId).update({
      'shareCode': code,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final guests = await _sessions
        .doc(sessionId)
        .collection('guestAccess')
        .get();
    final batch = firestore.batch();
    for (final doc in guests.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    return code;
  }

  @override
  Future<List<AccountExport>> fetchFullTree(String sessionId) async {
    final accounts = await _sessions
        .doc(sessionId)
        .collection('accounts')
        .orderBy('order')
        .get();
    final result = <AccountExport>[];
    for (final account in accounts.docs) {
      final tickets = await account.reference.collection('tickets').get();
      final exports = <TicketExport>[];
      for (final ticket in tickets.docs) {
        final lines = await ticket.reference
            .collection('lines')
            .orderBy('order')
            .get();
        exports.add(
          TicketExport(
            merchantName:
                ((ticket.data()['merchant'] as Map?)?['name'] as String?) ??
                (account.data()['name'] as String? ?? ''),
            date: ticket.data()['date'] as String?,
            grandTotal: Money((ticket.data()['grandTotal'] as int?) ?? 0),
            paidBy: (ticket.data()['paidByParticipantId'] as String?) ?? '',
            lines: [
              for (final line in lines.docs)
                LineExport(
                  name: (line.data()['name'] as String?) ?? '',
                  quantityMilli: (line.data()['quantityMilli'] as int?) ?? 1000,
                  totalPrice: Money((line.data()['totalPrice'] as int?) ?? 0),
                ),
            ],
          ),
        );
      }
      result.add(
        AccountExport(
          name: (account.data()['name'] as String?) ?? '',
          tickets: exports,
        ),
      );
    }
    return result;
  }

  // ── Mappers ────────────────────────────────────────────────────────────

  SessionSummary _summary(String id, Map<String, dynamic> data) {
    final totals = (data['totals'] as Map?) ?? const {};
    final ownerPid = (data['ownerParticipantId'] as String?) ?? 'p0';
    final balances = (data['balances'] as Map?) ?? const {};
    final mine = balances[ownerPid] as Map?;
    return SessionSummary(
      id: id,
      name: (data['name'] as String?) ?? '',
      kind: (data['kind'] as String?) ?? 'single',
      status: SessionStatus.values.byName(
        (data['status'] as String?) ?? 'open',
      ),
      grandTotal: Money((totals['grandTotal'] as int?) ?? 0),
      settlementRequired: Money(
        (totals['settlementRequired'] as int?) ??
            (totals['settledConfirmed'] as int?) ??
            0,
      ),
      settledConfirmed: Money((totals['settledConfirmed'] as int?) ?? 0),
      settledMarked: Money((totals['settledMarked'] as int?) ?? 0),
      participantsCount: (data['participantsCount'] as int?) ?? 0,
      pendingSettlements: (data['pendingSettlements'] as int?) ?? 0,
      ownerParticipantId: ownerPid,
      myOutstanding: Money((mine?['outstanding'] as int?) ?? 0),
      category: data['category'] as String?,
      updatedAtMillis:
          (data['updatedAt'] as Timestamp?)?.millisecondsSinceEpoch,
    );
  }

  ParticipantBalanceView _balance(Map raw) => ParticipantBalanceView(
    paid: Money((raw['paid'] as int?) ?? 0),
    consumed: Money((raw['consumed'] as int?) ?? 0),
    net: Money((raw['net'] as int?) ?? 0),
    outstanding: Money((raw['outstanding'] as int?) ?? 0),
  );
}
