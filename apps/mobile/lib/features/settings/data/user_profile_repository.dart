import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';

/// Métodos de pago del anfitrión (RF-70). Solo datos de contacto de cobro;
/// nunca credenciales. Vacío = el botón no aparece (ni en app ni en web).
class PaymentMethods {
  const PaymentMethods({
    this.bizumPhone = '',
    this.paypalLink = '',
    this.revolutTag = '',
    this.iban = '',
  });

  final String bizumPhone;
  final String paypalLink;
  final String revolutTag;
  final String iban;

  bool get isEmpty =>
      bizumPhone.isEmpty &&
      paypalLink.isEmpty &&
      revolutTag.isEmpty &&
      iban.isEmpty;

  Map<String, String> toSnapshot() => {
    if (bizumPhone.isNotEmpty) 'bizumPhone': bizumPhone,
    if (paypalLink.isNotEmpty) 'paypalLink': paypalLink,
    if (revolutTag.isNotEmpty) 'revolutTag': revolutTag,
    if (iban.isNotEmpty) 'iban': iban,
  };

  factory PaymentMethods.fromMap(Map<String, dynamic>? map) => PaymentMethods(
    bizumPhone: (map?['bizumPhone'] as String?) ?? '',
    paypalLink: (map?['paypalLink'] as String?) ?? '',
    revolutTag: (map?['revolutTag'] as String?) ?? '',
    iban: (map?['iban'] as String?) ?? '',
  );
}

class UserProfile {
  const UserProfile({
    this.displayName = '',
    this.paymentMethods = const PaymentMethods(),
  });

  final String displayName;
  final PaymentMethods paymentMethods;
}

/// Perfil privado del anfitrión en users/{uid} (spec §7).
class UserProfileRepository {
  UserProfileRepository({required this.firestore, required this.uid});

  final FirebaseFirestore firestore;
  final String Function() uid;

  DocumentReference<Map<String, dynamic>> get _doc =>
      firestore.collection('users').doc(uid());

  Stream<UserProfile> watch() => _doc.snapshots().map(
    (snap) => UserProfile(
      displayName: (snap.data()?['displayName'] as String?) ?? '',
      paymentMethods: PaymentMethods.fromMap(
        snap.data()?['paymentMethods'] as Map<String, dynamic>?,
      ),
    ),
  );

  Future<UserProfile> fetch() async {
    final snap = await _doc.get();
    return UserProfile(
      displayName: (snap.data()?['displayName'] as String?) ?? '',
      paymentMethods: PaymentMethods.fromMap(
        snap.data()?['paymentMethods'] as Map<String, dynamic>?,
      ),
    );
  }

  Future<void> savePaymentMethods(PaymentMethods methods) => _doc.set({
    'schemaVersion': 1,
    'paymentMethods': {
      'bizumPhone': methods.bizumPhone,
      'paypalLink': methods.paypalLink,
      'revolutTag': methods.revolutTag,
      'iban': methods.iban,
    },
  }, SetOptions(merge: true));

  Future<void> saveDisplayName(String name) => _doc.set({
    'schemaVersion': 1,
    'displayName': name,
  }, SetOptions(merge: true));
}

final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  return UserProfileRepository(
    firestore: FirebaseFirestore.instance,
    uid: () => uid,
  );
});

final userProfileProvider = StreamProvider.autoDispose<UserProfile>(
  (ref) => ref.watch(userProfileRepositoryProvider).watch(),
);
