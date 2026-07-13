import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../review/application/draft_store.dart';
import '../../review/application/review_draft.dart';
import '../data/session_repository.dart';
import '../domain/session_models.dart';

/// Si no es null, el flujo de revisión añade el ticket a ESTA sesión en
/// lugar de crear una nueva (menú "Añadir ticket" del detalle).
class AddTicketTarget extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? sessionId) => state = sessionId;
}

final addTicketTargetProvider =
    NotifierProvider<AddTicketTarget, String?>(AddTicketTarget.new);

/// Mapea el draft de revisión al ticket persistible (compartido entre
/// crear sesión y añadir a existente).
NewTicketInput ticketInputFromDraft(ReviewDraftState draft,
    {String? fallbackName}) {
  return NewTicketInput(
    kind: draft.engine == 'manual' ? 'manual' : 'scanned',
    merchantName: draft.merchantName ?? fallbackName ?? 'Ticket',
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
  );
}

class AddTicketController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<bool> addToSession(String sessionId,
      {required String payerPid}) async {
    final draft = ref.read(reviewDraftProvider);
    if (draft == null) return false;
    state = const AsyncLoading();
    try {
      await ref.read(sessionRepositoryProvider).addTicket(
            sessionId,
            ticketInputFromDraft(draft),
            payerPid: payerPid,
          );
      ref.read(reviewDraftProvider.notifier).discard();
      ref.invalidate(savedDraftProvider);
      ref.read(addTicketTargetProvider.notifier).set(null);
      state = const AsyncData(null);
      return true;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return false;
    }
  }
}

final addTicketControllerProvider =
    NotifierProvider<AddTicketController, AsyncValue<void>>(
        AddTicketController.new);
