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
import '../../spaces/data/spaces_repository.dart';
import '../../spaces/domain/space_identities.dart';
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
    required List<String> participantUids,
    required int payerIndex,
    required SplitMode splitMode,
    required String sessionName,

    /// Identidad manual por posición (ADR-033); '' para quien tiene cuenta.
    List<String> participantManualIds = const [],
  }) async {
    final draft = ref.read(reviewDraftProvider);
    if (draft == null || participantNames.length < 2) return null;
    state = const AsyncLoading();
    try {
      final pendingSpace = ref.read(pendingSpaceLinkProvider);
      if (pendingSpace == null) {
        throw const MissingTicketContextException();
      }
      // Guarda de último recurso contra un fallo de la UI. Cuenta PERSONAS,
      // igual que la hoja de reparto y el detalle (BUG-6): exigir tres en un
      // grupo bloqueaba repartir con alguien sin cuenta.
      final validCount = contextReadyForExpenses(
        pendingSpace.kind,
        participantNames.length,
      );
      if (!validCount || participantUids.length != participantNames.length) {
        throw const MissingTicketContextException();
      }
      // Cada participante tiene UNA identidad: cuenta o manual. Sin ninguna
      // no puede entrar en el reparto de un contexto (ADR-033).
      final manualIds = participantManualIds.length == participantNames.length
          ? participantManualIds
          : List<String>.filled(participantNames.length, '');
      for (var i = 0; i < participantNames.length; i++) {
        final hasAccount = participantUids[i].isNotEmpty;
        final hasManual = manualIds[i].isNotEmpty;
        if (hasAccount == hasManual) {
          throw const MissingTicketContextException();
        }
      }
      final user = ref.read(authRepositoryProvider).currentUser;
      // Un invitado no tiene users/{uid}; su snapshot y sus frecuentes son
      // vacíos hasta que proteja la cuenta.
      final profile = user?.isFullAccount ?? false
          ? await ref.read(userProfileRepositoryProvider).fetch()
          : const UserProfile();
      final input = NewSessionInput(
        paymentMethodsSnapshot: profile.paymentMethods.toSnapshot(),
        name: sessionName,
        splitModeDefault: splitMode,
        participantNames: participantNames,
        participantUids: participantUids,
        participantManualIds: manualIds,
        payerIndex: payerIndex,
        spaceId: pendingSpace.id,
        spaceName: pendingSpace.name,
        ticket: ticketInputFromDraft(draft, fallbackName: sessionName),
      );
      final created = await ref
          .read(sessionRepositoryProvider)
          .createSession(input);
      ref.read(pendingSpaceLinkProvider.notifier).clear();
      // Foto del ticket: copia local durable ANTES de perder el archivo del
      // picker, y subida con reintento en segundo plano (no bloquea el flujo).
      final imagePath = ref.read(lastScanImageProvider);
      if (imagePath != null && draft.engine != 'manual') {
        final store = ref.read(receiptImageStoreProvider);
        await store.cacheLocalOriginal(created.ticketPath, imagePath);
        unawaited(store.upload(created.ticketPath));
      }
      // "Crear ticket desde el espacio" (P4): si el flujo partió de un
      // espacio, el ticket recién creado se vincula a él. Best-effort: un
      // fallo de vínculo no invalida el ticket ya guardado.
      // Personas frecuentes: todas menos el anfitrión (índice 0).
      if (user?.isFullAccount ?? false) {
        await ref
            .read(frequentPeopleRepositoryProvider)
            .recordUsage(participantNames.skip(1));
      }
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
      CreateSessionController.new,
    );

/// Personas frecuentes para los chips del paso de gente.
final frequentPeopleProvider = StreamProvider.autoDispose((ref) {
  final user = ref.watch(authStateProvider).value;
  if (!(user?.isFullAccount ?? false)) {
    return Stream.value(const <FrequentPerson>[]);
  }
  return ref.watch(frequentPeopleRepositoryProvider).watch();
});

/// Nombre visible del anfitrión (primer participante).
final hostDisplayNameProvider = Provider<String>((ref) {
  final user = ref.watch(authRepositoryProvider).currentUser;
  final name = user?.displayName?.trim();
  return (name == null || name.isEmpty) ? 'Yo' : name;
});
