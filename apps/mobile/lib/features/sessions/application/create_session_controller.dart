import 'dart:async';

import 'package:domain/domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/application/ai_analysis_controller.dart'
    show lastScanImageProvider;
import '../../auth/data/auth_repository.dart';
import '../../people/data/frequent_people_repository.dart';
import '../../review/application/draft_store.dart';
import '../../review/application/review_draft.dart';
import '../../scan/data/receipt_storage.dart';
import '../../settings/data/user_profile_repository.dart';
import '../data/session_repository.dart';
import '../domain/session_models.dart';
import 'add_ticket_controller.dart';

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
        ticket: ticketInputFromDraft(draft, fallbackName: sessionName),
      );
      final created =
          await ref.read(sessionRepositoryProvider).createSession(input);
      // Foto del ticket a Storage (best-effort, no bloquea el flujo).
      final imagePath = ref.read(lastScanImageProvider);
      if (imagePath != null && draft.engine != 'manual') {
        unawaited(ref.read(receiptStorageProvider).uploadOriginal(
              sessionId: created.sessionId,
              ticketPath: created.ticketPath,
              localImagePath: imagePath,
            ));
      }
      // Personas frecuentes: todas menos el anfitrión (índice 0).
      await ref
          .read(frequentPeopleRepositoryProvider)
          .recordUsage(participantNames.skip(1));
      // El borrador ya está a salvo en Firestore: fuera de la persistencia.
      ref.read(reviewDraftProvider.notifier).discard();
      ref.invalidate(savedDraftProvider);
      state = AsyncData(created.sessionId);
      return created.sessionId;
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
