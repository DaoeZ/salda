import 'package:domain/domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../people/data/frequent_people_repository.dart';
import '../../review/application/draft_store.dart';
import '../../settings/data/user_profile_repository.dart';
import '../../review/application/review_draft.dart';
import '../data/session_repository.dart';
import '../domain/session_models.dart';

/// Crea la sesión a partir del draft de revisión + elección de gente/reparto.
/// Devuelve el id de sesión; registra las personas como frecuentes.
class CreateSessionController extends Notifier<AsyncValue<String?>> {
  @override
  AsyncValue<String?> build() => const AsyncData(null);

  Future<String?> create({
    required List<String> participantNames,
    required int payerIndex,
    required SplitMode splitMode,
    required String sessionName,
  }) async {
    final draft = ref.read(reviewDraftProvider);
    if (draft == null || participantNames.length < 2) return null;
    state = const AsyncLoading();
    try {
      // Snapshot de métodos de pago (RF-72): congelado al crear.
      final profile =
          await ref.read(userProfileRepositoryProvider).fetch();
      final input = NewSessionInput(
        paymentMethodsSnapshot: profile.paymentMethods.toSnapshot(),
        name: sessionName,
        splitModeDefault: splitMode,
        participantNames: participantNames,
        payerIndex: payerIndex,
        ticket: NewTicketInput(
          kind: draft.engine == 'manual' ? 'manual' : 'scanned',
          merchantName: draft.merchantName ?? sessionName,
          brandKey: draft.brandKey,
          category: draft.category,
          date: draft.date,
          time: draft.time,
          engine: draft.engine,
          confidence: draft.sourceConfidence,
          grandTotal: draft.grandTotal ?? draft.computedTotal,
          tip: draft.tip,
          discounts: draft.discounts,
          taxes: draft.taxes,
          lines: [
            for (final line in draft.lines)
              NewLineInput(
                name: line.name,
                quantityMilli: line.quantityMilli,
                unitPrice: line.unitPrice,
                totalPrice: line.totalPrice,
              ),
          ],
        ),
      );
      final sid =
          await ref.read(sessionRepositoryProvider).createSession(input);
      // Personas frecuentes: todas menos el anfitrión (índice 0).
      await ref
          .read(frequentPeopleRepositoryProvider)
          .recordUsage(participantNames.skip(1));
      // El borrador ya está a salvo en Firestore: fuera de la persistencia.
      ref.read(reviewDraftProvider.notifier).discard();
      ref.invalidate(savedDraftProvider);
      state = AsyncData(sid);
      return sid;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return null;
    }
  }
}

final createSessionControllerProvider =
    NotifierProvider<CreateSessionController, AsyncValue<String?>>(
        CreateSessionController.new);

/// Personas frecuentes para los chips del paso de gente.
final frequentPeopleProvider = StreamProvider.autoDispose(
    (ref) => ref.watch(frequentPeopleRepositoryProvider).watch());

/// Nombre visible del anfitrión (primer participante).
final hostDisplayNameProvider = Provider<String>((ref) {
  final user = ref.watch(authRepositoryProvider).currentUser;
  final name = user?.displayName?.trim();
  return (name == null || name.isEmpty) ? 'Yo' : name;
});
