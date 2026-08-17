import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:domain/domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../auth/data/auth_repository.dart';
import '../../spaces/data/spaces_repository.dart';
import '../domain/economic_models.dart';

enum EconomicFailureCode {
  accountRequired,
  invalidAmount,
  exceedsBalance,
  notAllowed,
  alreadyResolved,
  serviceUnavailable,
  network,
  unexpected,
}

class EconomicFailure implements Exception {
  const EconomicFailure(this.code, {this.technicalCode});

  final EconomicFailureCode code;
  final String? technicalCode;
}

/// Petición de liquidación contra UNA obligación.
///
/// [amount] ausente = su pendiente completo, que es el 99 % de los casos: el
/// camino normal no obliga a teclear un importe. Indicarlo es el pago
/// parcial, y pertenece a esta obligación, no al saldo global.
class EntrySettlementRequest {
  const EntrySettlementRequest(this.entryId, {this.amount});

  final String entryId;
  final Money? amount;
}

abstract interface class EconomicFunctionsGateway {
  Future<void> rebuildMyRelations();
  Future<void> createPayment(Map<String, Object> data);
  Future<void> resolvePayment(Map<String, Object> data);
  Future<void> settleEntries(Map<String, Object> data);
}

class FirebaseEconomicFunctionsGateway implements EconomicFunctionsGateway {
  FirebaseEconomicFunctionsGateway(this.functions);

  final FirebaseFunctions functions;

  @override
  Future<void> rebuildMyRelations() async {
    await functions.httpsCallable('rebuildMyEconomicRelations').call<void>();
  }

  @override
  Future<void> createPayment(Map<String, Object> data) async {
    await functions.httpsCallable('createEconomicPayment').call<void>(data);
  }

  @override
  Future<void> resolvePayment(Map<String, Object> data) async {
    await functions.httpsCallable('resolveEconomicPayment').call<void>(data);
  }

  @override
  Future<void> settleEntries(Map<String, Object> data) async {
    await functions.httpsCallable('settleEconomicEntries').call<void>(data);
  }
}

class EconomicRepository {
  EconomicRepository({
    required this.firestore,
    required this.functions,
    required this.uid,
    required this.isFullAccount,
    String Function()? idempotencyKey,
  }) : idempotencyKey = idempotencyKey ?? const Uuid().v4;

  final FirebaseFirestore firestore;
  final EconomicFunctionsGateway functions;
  final String Function() uid;
  final bool Function() isFullAccount;
  final String Function() idempotencyKey;

  Stream<List<EconomicEntryView>> watchEntries() {
    _requireAccount();
    return firestore
        .collection('economicEntries')
        .where('memberUids', arrayContains: uid())
        .snapshots()
        .map((snapshot) => [for (final doc in snapshot.docs) _entry(doc)]);
  }

  /// Lectura económica sin acciones, permitida a toda identidad que pueda
  /// participar en el contexto. Las Rules siguen siendo la autoridad: la
  /// consulta conserva `memberUids arrayContains uid` y no abre ninguna
  /// mutación ni materialización global.
  Stream<List<EconomicEntryView>> watchReadableEntries() => firestore
      .collection('economicEntries')
      .where('memberUids', arrayContains: uid())
      .snapshots()
      .map((snapshot) => [for (final doc in snapshot.docs) _entry(doc)]);

  Stream<List<EconomicPaymentView>> watchPayments() {
    _requireAccount();
    return firestore
        .collection('economicPayments')
        .where('memberUids', arrayContains: uid())
        .snapshots()
        .map((snapshot) {
          final payments = [for (final doc in snapshot.docs) _payment(doc)];
          payments.sort(
            (a, b) => _millis(b.createdAt).compareTo(_millis(a.createdAt)),
          );
          return payments;
        });
  }

  Stream<List<EconomicPaymentView>> watchReadablePayments() => firestore
      .collection('economicPayments')
      .where('memberUids', arrayContains: uid())
      .snapshots()
      .map(_sortedPayments);

  /// Deudas de un espacio en las que participa alguien SIN cuenta.
  ///
  /// Solo las autoriza Rules a quien administra ese espacio (ADR-038), y el
  /// filtro por `hasManualParty` no es cosmético: sin él la consulta
  /// arrastraría deudas entre dos cuentas y sería denegada entera, que es
  /// justo la garantía de que un administrador no las ve.
  Stream<List<EconomicEntryView>> watchRepresentableEntries(String spaceId) =>
      firestore
          .collection('economicEntries')
          .where('spaceId', isEqualTo: spaceId)
          .where('hasManualParty', isEqualTo: true)
          .snapshots()
          .map((snapshot) => [for (final doc in snapshot.docs) _entry(doc)]);

  Stream<List<EconomicPaymentView>> watchRepresentablePayments(
    String spaceId,
  ) => firestore
      .collection('economicPayments')
      .where('spaceId', isEqualTo: spaceId)
      .where('hasManualParty', isEqualTo: true)
      .snapshots()
      .map(_sortedPayments);

  List<EconomicPaymentView> _sortedPayments(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final payments = [for (final doc in snapshot.docs) _payment(doc)];
    payments.sort(
      (a, b) => _millis(b.createdAt).compareTo(_millis(a.createdAt)),
    );
    return payments;
  }

  Future<void> rebuildMyRelations() async {
    _requireAccount();
    await _guard(functions.rebuildMyRelations);
  }

  Future<void> markPaid({
    required String receiverUid,
    required Money amount,
    required String currency,
  }) async {
    _requireAccount();
    if (amount.cents <= 0 || receiverUid == uid()) {
      throw const EconomicFailure(EconomicFailureCode.invalidAmount);
    }
    await _guard(
      () => functions.createPayment({
        'receiverUid': receiverUid,
        'amount': amount.cents,
        'currency': currency,
        'idempotencyKey': idempotencyKey(),
      }),
    );
  }

  /// Liquida obligaciones CONCRETAS (ADR-038).
  ///
  /// El caso normal —cobrado todo— no pide importe: cada deuda se salda por
  /// su pendiente. Confirmar varias a la vez es comodidad de la interfaz;
  /// cada una conserva su liquidación y su ticket.
  Future<void> settleEntries(List<EntrySettlementRequest> entries) async {
    _requireAccount();
    if (entries.isEmpty) {
      throw const EconomicFailure(EconomicFailureCode.invalidAmount);
    }
    if (entries.any((entry) => (entry.amount ?? const Money(1)).cents <= 0)) {
      throw const EconomicFailure(EconomicFailureCode.invalidAmount);
    }
    await _guard(
      () => functions.settleEntries({
        'entries': [
          for (final entry in entries)
            {
              'entryId': entry.entryId,
              if (entry.amount != null) 'amount': entry.amount!.cents,
            },
        ],
        'idempotencyKey': idempotencyKey(),
      }),
    );
  }

  /// Confirma la recepción de un pago ya declarado.
  ///
  /// Un pago legado NO vive en P5 (la callable lo rechaza por diseño): vive
  /// en la liquidación de su sesión, y allí es donde hay que escribir. Antes
  /// la pantalla de Economía ofrecía el botón igualmente y la acción moría
  /// con un error genérico.
  Future<void> confirmPayment(EconomicPaymentView payment) async {
    _requireAccount();
    if (!payment.isLegacy) return _resolve(payment.id, 'confirm');
    final sessionId = payment.sourceSessionId;
    final settlementId = payment.settlementId;
    if (sessionId == null || settlementId == null) {
      throw const EconomicFailure(EconomicFailureCode.notAllowed);
    }
    await _guard(
      () =>
          firestore.doc('sessions/$sessionId/settlements/$settlementId').update(
            {'state': 'confirmed', 'updatedAt': FieldValue.serverTimestamp()},
          ),
    );
  }

  Future<void> cancelPayment(String paymentId) => _resolve(paymentId, 'cancel');

  Future<void> rejectPayment(String paymentId) => _resolve(paymentId, 'reject');

  Future<void> _resolve(String paymentId, String action) async {
    _requireAccount();
    await _guard(
      () =>
          functions.resolvePayment({'paymentId': paymentId, 'action': action}),
    );
  }

  void _requireAccount() {
    if (!isFullAccount()) {
      throw const EconomicFailure(EconomicFailureCode.accountRequired);
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseFunctionsException catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapFunctionsFailure(error), stackTrace);
    } on FirebaseException catch (error, stackTrace) {
      final code = error.code == 'unavailable'
          ? EconomicFailureCode.network
          : EconomicFailureCode.unexpected;
      Error.throwWithStackTrace(
        EconomicFailure(code, technicalCode: error.code),
        stackTrace,
      );
    }
  }

  EconomicEntryView _entry(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    return EconomicEntryView(
      id: snapshot.id,
      debtorUid: data['debtorUid'] as String,
      creditorUid: data['creditorUid'] as String,
      amount: Money(data['amount'] as int),
      currency: (data['currency'] as String?) ?? 'EUR',
      sessionId: data['sessionId'] as String,
      accountId: data['accountId'] as String,
      ticketId: data['ticketId'] as String,
      ticketName: (data['ticketName'] as String?) ?? '',
      ticketDate: data['ticketDate'] as String?,
      spaceId: data['spaceId'] as String?,
      createdAt: _date(data['createdAt']),
    );
  }

  EconomicPaymentView _payment(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    return EconomicPaymentView(
      id: snapshot.id,
      payerUid: data['payerUid'] as String,
      receiverUid: data['receiverUid'] as String,
      amount: Money(data['amount'] as int),
      currency: (data['currency'] as String?) ?? 'EUR',
      status: EconomicPaymentStatus.values.byName(data['status'] as String),
      source: (data['source'] as String?) ?? 'user',
      allocations: ((data['allocations'] as Map?) ?? const {}).map(
        (key, value) => MapEntry(key as String, Money(value as int)),
      ),
      createdAt: _date(data['createdAt']),
      confirmedAt: _date(data['confirmedAt']),
      sourceSessionId: data['sourceSessionId'] as String?,
      settlementId: data['settlementId'] as String?,
      spaceId: data['spaceId'] as String?,
      onBehalfOfManualId: data['onBehalfOfManualId'] as String?,
    );
  }
}

EconomicFailure _mapFunctionsFailure(FirebaseFunctionsException error) {
  final details = error.details;
  final message = error.message ?? '';
  final marker = '$message ${details ?? ''}';
  final code = marker.contains('PAYMENT_EXCEEDS_BALANCE')
      ? EconomicFailureCode.exceedsBalance
      : marker.contains('PAYMENT_ALREADY_RESOLVED')
      ? EconomicFailureCode.alreadyResolved
      : error.code == 'permission-denied'
      ? EconomicFailureCode.notAllowed
      : error.code == 'unavailable' || error.code == 'deadline-exceeded'
      ? EconomicFailureCode.network
      : error.code == 'not-found' || error.code == 'unimplemented'
      ? EconomicFailureCode.serviceUnavailable
      : EconomicFailureCode.unexpected;
  return EconomicFailure(code, technicalCode: error.code);
}

DateTime? _date(Object? value) => switch (value) {
  Timestamp timestamp => timestamp.toDate(),
  DateTime date => date,
  _ => null,
};

int _millis(DateTime? date) => date?.millisecondsSinceEpoch ?? 0;

final economicFunctionsGatewayProvider = Provider<EconomicFunctionsGateway>(
  (ref) => FirebaseEconomicFunctionsGateway(
    FirebaseFunctions.instanceFor(region: 'europe-west1'),
  ),
);

final economicRepositoryProvider = Provider<EconomicRepository>((ref) {
  final user = ref.watch(currentAppUserProvider);
  if (user == null) throw StateError('No hay una identidad activa');
  return EconomicRepository(
    firestore: FirebaseFirestore.instance,
    functions: ref.watch(economicFunctionsGatewayProvider),
    uid: () => user.uid,
    isFullAccount: () => user.isFullAccount,
  );
});

final economicEntriesProvider =
    StreamProvider.autoDispose<List<EconomicEntryView>>((ref) {
      final user = ref.watch(currentAppUserProvider);
      if (user == null || !user.isFullAccount) return Stream.value(const []);
      return ref.watch(economicRepositoryProvider).watchEntries();
    });

final economicPaymentsProvider =
    StreamProvider.autoDispose<List<EconomicPaymentView>>((ref) {
      final user = ref.watch(currentAppUserProvider);
      if (user == null || !user.isFullAccount) return Stream.value(const []);
      return ref.watch(economicRepositoryProvider).watchPayments();
    });

/// Proyección únicamente de lectura para cuentas e invitados operativos.
/// No depende de [economicProjectionWarmupProvider], que sigue siendo un
/// contrato exclusivo de la vista económica de cuentas completas.
final readableEconomicEntriesProvider =
    StreamProvider.autoDispose<List<EconomicEntryView>>((ref) {
      final user = ref.watch(currentAppUserProvider);
      if (user == null) return Stream.value(const []);
      return ref.watch(economicRepositoryProvider).watchReadableEntries();
    });

final readableEconomicPaymentsProvider =
    StreamProvider.autoDispose<List<EconomicPaymentView>>((ref) {
      final user = ref.watch(currentAppUserProvider);
      if (user == null) return Stream.value(const []);
      return ref.watch(economicRepositoryProvider).watchReadablePayments();
    });

final readableEconomicOverviewProvider =
    Provider.autoDispose<AsyncValue<EconomicOverview>>((ref) {
      final user = ref.watch(currentAppUserProvider);
      final entries = ref.watch(readableEconomicEntriesProvider);
      final payments = ref.watch(readableEconomicPaymentsProvider);
      if (user == null) {
        return const AsyncData(
          EconomicOverview(
            viewerUid: '',
            entries: [],
            payments: [],
            balances: [],
          ),
        );
      }
      if (entries.hasError) {
        return AsyncError(entries.error!, entries.stackTrace!);
      }
      if (payments.hasError) {
        return AsyncError(payments.error!, payments.stackTrace!);
      }
      if (entries.isLoading || payments.isLoading) return const AsyncLoading();
      return AsyncData(
        EconomicOverview.compute(
          viewerUid: user.uid,
          entries: entries.value ?? const [],
          payments: payments.value ?? const [],
        ),
      );
    });

/// Proyección de solo lectura limitada a un espacio. Es apta para las filas
/// de Inicio y para invitados; nunca activa la reconstrucción global.
final spaceEconomicOverviewProvider = Provider.autoDispose
    .family<AsyncValue<EconomicOverview>, String>(
      (ref, spaceId) => ref
          .watch(readableEconomicOverviewProvider)
          .whenData((overview) => overview.withinSpace(spaceId)),
    );

/// Deudas del espacio con una parte SIN cuenta, que quien lo administra puede
/// representar (ADR-038). Solo se suscribe si de verdad administra: para
/// cualquier otra persona la consulta sería denegada, y con razón.
final representableEconomicEntriesProvider = StreamProvider.autoDispose
    .family<List<EconomicEntryView>, String>((ref, spaceId) {
      if (!ref.watch(iAdministerSpaceProvider(spaceId))) {
        return Stream.value(const []);
      }
      return ref
          .watch(economicRepositoryProvider)
          .watchRepresentableEntries(spaceId);
    });

final representableEconomicPaymentsProvider = StreamProvider.autoDispose
    .family<List<EconomicPaymentView>, String>((ref, spaceId) {
      if (!ref.watch(iAdministerSpaceProvider(spaceId))) {
        return Stream.value(const []);
      }
      return ref
          .watch(economicRepositoryProvider)
          .watchRepresentablePayments(spaceId);
    });

/// Economía del espacio TAL Y COMO puede gestionarla quien mira: lo suyo,
/// más lo de las identidades sin cuenta que representa.
///
/// Deliberadamente NO alimenta el resumen global: quien administra no es
/// parte de esas deudas y sumarlas a su "te deben" sería falso.
final spaceManageableEconomicOverviewProvider = Provider.autoDispose
    .family<AsyncValue<EconomicOverview>, String>((ref, spaceId) {
      // Parte de la proyección que corresponde al ROL de quien mira (cuenta o
      // invitado), igual que hacían antes estas pantallas.
      final own = ref
          .watch(participantEconomicOverviewProvider)
          .whenData((overview) => overview.withinSpace(spaceId));
      final entries = ref.watch(representableEconomicEntriesProvider(spaceId));
      final payments = ref.watch(
        representableEconomicPaymentsProvider(spaceId),
      );
      if (own.isLoading || entries.isLoading || payments.isLoading) {
        return const AsyncLoading();
      }
      if (own.hasError) return AsyncError(own.error!, own.stackTrace!);
      final base = own.value!;
      final extraEntries = entries.value ?? const <EconomicEntryView>[];
      if (extraEntries.isEmpty) return AsyncData(base);
      final known = {for (final entry in base.entries) entry.id};
      final knownPayments = {for (final payment in base.payments) payment.id};
      return AsyncData(
        EconomicOverview.compute(
          viewerUid: base.viewerUid,
          entries: [
            ...base.entries,
            for (final entry in extraEntries)
              if (!known.contains(entry.id)) entry,
          ],
          payments: [
            ...base.payments,
            for (final payment in payments.value ?? const [])
              if (!knownPayments.contains(payment.id)) payment,
          ],
        ),
      );
    });

/// Materializa una sola vez las sesiones históricas accesibles por la cuenta.
/// La marca autoritativa vive en `users/{uid}` y hace idempotentes las aperturas
/// posteriores de la pantalla económica.
final economicProjectionWarmupProvider = FutureProvider<void>((ref) async {
  final user = ref.watch(currentAppUserProvider);
  if (user == null || !user.isFullAccount) return;
  await ref.watch(economicRepositoryProvider).rebuildMyRelations();
});

final economicOverviewProvider =
    Provider.autoDispose<AsyncValue<EconomicOverview>>((ref) {
      final user = ref.watch(currentAppUserProvider);
      final warmup = ref.watch(economicProjectionWarmupProvider);
      final entries = ref.watch(economicEntriesProvider);
      final payments = ref.watch(economicPaymentsProvider);
      if (user == null) {
        return const AsyncData(
          EconomicOverview(
            viewerUid: '',
            entries: [],
            payments: [],
            balances: [],
          ),
        );
      }
      if (warmup.hasError) {
        return AsyncError(warmup.error!, warmup.stackTrace!);
      }
      if (entries.hasError) {
        return AsyncError(entries.error!, entries.stackTrace!);
      }
      if (payments.hasError) {
        return AsyncError(payments.error!, payments.stackTrace!);
      }
      if (warmup.isLoading || entries.isLoading || payments.isLoading) {
        return const AsyncLoading();
      }
      return AsyncData(
        EconomicOverview.compute(
          viewerUid: user.uid,
          entries: entries.value ?? const [],
          payments: payments.value ?? const [],
        ),
      );
    });

/// Proyección adecuada a quien participa: las cuentas conservan su contrato
/// existente (incluida la materialización autorizada); los invitados leen la
/// misma economía ya autorizada por Rules, sin poder activar ni mutar nada.
final participantEconomicOverviewProvider =
    Provider.autoDispose<AsyncValue<EconomicOverview>>((ref) {
      final user = ref.watch(currentAppUserProvider);
      return user?.isFullAccount == true
          ? ref.watch(economicOverviewProvider)
          : ref.watch(readableEconomicOverviewProvider);
    });

/// Reintenta las fuentes reales de la proyección que corresponde al rol, no
/// solo su envoltorio derivado. Las mutaciones siguen fuera de este camino.
/// This is deliberately a [WidgetRef].  A provider [Ref] is not the ref a
/// retry button owns in Riverpod 3, and accepting it here made the UI retry
/// path fail to compile.  Keeping the invalidation at the caller boundary
/// still refreshes the role-specific source streams rather than masking the
/// error by invalidating only this derived provider.
void retryParticipantEconomicOverview(WidgetRef ref) {
  final isFullAccount =
      ref.read(currentAppUserProvider)?.isFullAccount ?? false;
  if (isFullAccount) {
    ref.invalidate(economicProjectionWarmupProvider);
    ref.invalidate(economicEntriesProvider);
    ref.invalidate(economicPaymentsProvider);
  } else {
    ref.invalidate(readableEconomicEntriesProvider);
    ref.invalidate(readableEconomicPaymentsProvider);
  }
  ref.invalidate(participantEconomicOverviewProvider);
}
