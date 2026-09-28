import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';

/// Identidad de INVITADO (ADR-034): quien usa la app sin crear cuenta.
///
/// **Persistencia**: la sesión anónima de Firebase Auth se guarda en el
/// dispositivo y sobrevive a reinicios y cierres de la app, así que el UID
/// —y con él todo su historial económico— se mantiene. Este documento añade
/// lo único que Auth no publica a los demás: el nombre visible que el propio
/// invitado elige.
///
/// NO es un perfil público: no tiene username, no es buscable (Rules prohíbe
/// listarla) y solo la lee quien ya conoce el UID — el anfitrión al invitarlo
/// o los miembros del contexto para pintar su nombre.
class GuestIdentity {
  const GuestIdentity({
    required this.uid,
    required this.displayName,
    this.createdAt,
  });

  final String uid;
  final String displayName;
  final DateTime? createdAt;
}

class GuestIdentityRepository {
  GuestIdentityRepository({required this.firestore, required this.uid});

  final FirebaseFirestore firestore;
  final String Function() uid;

  DocumentReference<Map<String, dynamic>> _doc(String guestUid) =>
      firestore.collection('guestIdentities').doc(guestUid);

  /// Identidad del invitado activo, en vivo (null mientras no elija nombre).
  Stream<GuestIdentity?> watchMine() =>
      _doc(uid()).snapshots().map(_fromSnapshot);

  /// Identidad de otro invitado: solo para pintar su nombre donde ya
  /// participa. Requiere conocer su UID; nunca se busca por nombre.
  Stream<GuestIdentity?> watch(String guestUid) =>
      _doc(guestUid).snapshots().map(_fromSnapshot);

  /// Elige (o cambia) el nombre visible. Es idempotente y conserva la
  /// identidad: cambiar de nombre NUNCA altera el UID ni el historial.
  Future<void> setDisplayName(String displayName) async {
    final name = displayName.trim();
    if (name.isEmpty || name.length > 40) {
      throw ArgumentError.value(displayName, 'displayName', 'Nombre inválido');
    }
    final doc = _doc(uid());
    final existing = await doc.get();
    if (existing.exists) {
      await doc.update({
        'displayName': name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }
    await doc.set({
      'uid': uid(),
      'displayName': name,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'schemaVersion': 1,
    });
  }

  GuestIdentity? _fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    return GuestIdentity(
      uid: doc.id,
      displayName: (data['displayName'] as String?) ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

final guestIdentityRepositoryProvider = Provider<GuestIdentityRepository>((
  ref,
) {
  final userId = ref.watch(currentUserIdProvider);
  return GuestIdentityRepository(
    firestore: FirebaseFirestore.instance,
    uid: () => userId,
  );
});

/// Identidad del invitado activo. Null si la cuenta no es invitada o si
/// todavía no ha elegido nombre (la app se lo pide antes de participar).
final myGuestIdentityProvider = StreamProvider.autoDispose<GuestIdentity?>((
  ref,
) {
  final user = ref.watch(currentAppUserProvider);
  if (user == null || !user.isAnonymous) return Stream.value(null);
  return ref.watch(guestIdentityRepositoryProvider).watchMine();
});

/// Nombre visible de otro invitado (para miembros de un contexto).
final guestIdentityProvider = StreamProvider.autoDispose
    .family<GuestIdentity?, String>(
      (ref, guestUid) =>
          ref.watch(guestIdentityRepositoryProvider).watch(guestUid),
    );

/// ¿La identidad activa es un invitado OPERATIVO (anónimo + nombre puesto)?
/// Es el espejo en cliente de `isGuest()` de Rules.
final isOperationalGuestProvider = Provider<bool>((ref) {
  final user = ref.watch(currentAppUserProvider);
  if (user == null || !user.isAnonymous) return false;
  return ref.watch(myGuestIdentityProvider).value != null;
});
