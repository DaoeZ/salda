import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:domain/domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../auth/data/auth_repository.dart';
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

abstract interface class EconomicFunctionsGateway {
  Future<void> rebuildMyRelations();
  Future<void> createPayment(Map<String, Object> data);
  Future<void> resolvePayment(Map<String, Object> data);
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

  Future<void> confirmPayment(String paymentId) =>
      _resolve(paymentId, 'confirm');

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
