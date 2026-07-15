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
      .map((snap) =>
          snap.docs.map((d) => _summary(d.id, d.data())).toList());

  @override
  Stream<SessionDetail?> watchSession(String sessionId) =>
      _sessions.doc(sessionId).snapshots().map((doc) {
        final data = doc.data();
        if (data == null) return null;
        return SessionDetail(
          summary: _summary(doc.id, data),
          shareCode: (data['shareCode'] as String?) ?? '',
          splitModeDefault: SplitMode.values
              .byName((data['splitModeDefault'] as String?) ?? 'equal'),
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
          .map((snap) => [
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
              ]);

  @override
  Stream<List<SessionAccount>> watchAccounts(String sessionId) => _sessions
      .doc(sessionId)
      .collection('accounts')
      .orderBy('order')
      .snapshots()
      .map((snap) => [
            for (final d in snap.docs)
              SessionAccount(
                id: d.id,
                name: (d.data()['name'] as String?) ?? '',
                order: (d.data()['order'] as int?) ?? 0,
                grandTotal: Money(
                    ((d.data()['totals'] as Map?)?['grandTotal'] as int?) ??
                        0),
              ),
          ]);

  @override
  Stream<List<Settlement>> watchSettlements(String sessionId) => _sessions
      .doc(sessionId)
      .collection('settlements')
      .snapshots()
      .map((snap) => [
            for (final d in snap.docs)
              Settlement(
                id: d.id,
                from: (d.data()['from'] as String?) ?? '',
                to: (d.data()['to'] as String?) ?? '',
                amount: Money((d.data()['amount'] as int?) ?? 0),
                state: SettlementState.values
                    .byName((d.data()['state'] as String?) ?? 'pending'),
              ),
          ]..sort((a, b) => b.amount.cents.compareTo(a.amount.cents)));

  @override
  Future<({String sessionId, String ticketPath})> createSession(
      NewSessionInput input) async {
    final owner = uid();
    final sessionRef = _sessions.doc();

    // Paso 1: el documento de sesión (las reglas de subdocs hacen get()).
    await sessionRef.set({
      'schemaVersion': 1,
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
      batch.set(sessionRef.collection('participants').doc('p$i'), {
        'name': input.participantNames[i],
        'isOwner': i == 0,
        'order': i,
        'claimedByDevice': '',
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
  }) async {
    final sessionRef = _sessions.doc(sessionId);
    final accounts = await sessionRef.collection('accounts').get();
    final batch = firestore.batch();
    final ticketPath = _writeAccountWithTicket(
      batch,
      sessionRef: sessionRef,
      accountIndex: accounts.size,
      accountName: ticket.merchantName,
      ticket: ticket,
      payerPid: payerPid,
    );
    batch.update(sessionRef, {
      // Con más de una cuenta la sesión es conceptualmente multi (DC-6).
      if (accounts.size >= 1) 'kind': 'multi',
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
  }) {
    final accountRef =
        sessionRef.collection('accounts').doc('a$accountIndex');
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
        'assignment': {
          'type': 'unassigned',
          'participants': const <String, Object?>{},
        },
      });
    }
    return ticketRef.path;
  }

  @override
  Stream<List<SessionTicket>> watchTickets(
          String sessionId, String accountId) =>
      _sessions
          .doc(sessionId)
          .collection('accounts')
          .doc(accountId)
          .collection('tickets')
          .snapshots()
          .map((snap) => [
                for (final d in snap.docs)
                  SessionTicket(
                    id: d.id,
                    path: d.reference.path,
                    merchantName:
                        ((d.data()['merchant'] as Map?)?['name'] as String?) ??
                            '',
                    date: d.data()['date'] as String?,
                    grandTotal:
                        Money((d.data()['grandTotal'] as int?) ?? 0),
                    paidBy:
                        (d.data()['paidByParticipantId'] as String?) ?? '',
                    kind: (d.data()['kind'] as String?) ?? 'scanned',
                    imagePath: d.data()['imagePath'] as String?,
                  ),
              ]);

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
  Future<void> setTicketImage(String ticketPath, String storagePath) =>
      firestore.doc(ticketPath).update({'imagePath': storagePath});

  @override
  Future<void> updateSettlementState(
    String sessionId,
    String settlementId,
    SettlementState state,
  ) =>
      _sessions
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
        'closedAt':
            status == SessionStatus.closed ? FieldValue.serverTimestamp() : null,
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
    final guests =
        await _sessions.doc(sessionId).collection('guestAccess').get();
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
        exports.add(TicketExport(
          merchantName: ((ticket.data()['merchant'] as Map?)?['name']
                  as String?) ??
              (account.data()['name'] as String? ?? ''),
          date: ticket.data()['date'] as String?,
          grandTotal: Money((ticket.data()['grandTotal'] as int?) ?? 0),
          paidBy: (ticket.data()['paidByParticipantId'] as String?) ?? '',
          lines: [
            for (final line in lines.docs)
              LineExport(
                name: (line.data()['name'] as String?) ?? '',
                quantityMilli:
                    (line.data()['quantityMilli'] as int?) ?? 1000,
                totalPrice:
                    Money((line.data()['totalPrice'] as int?) ?? 0),
              ),
          ],
        ));
      }
      result.add(AccountExport(
        name: (account.data()['name'] as String?) ?? '',
        tickets: exports,
      ));
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
      status: SessionStatus.values
          .byName((data['status'] as String?) ?? 'open'),
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
