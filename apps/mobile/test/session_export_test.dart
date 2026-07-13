import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/sessions/application/session_export.dart';
import 'package:salda_mobile/features/sessions/domain/session_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final detail = SessionDetail(
    summary: const SessionSummary(
      id: 's1',
      name: 'Viaje a Madrid',
      kind: 'multi',
      status: SessionStatus.open,
      grandTotal: Money(5190),
      settledConfirmed: Money(890),
      settledMarked: Money.zero,
      participantsCount: 2,
      pendingSettlements: 1,
      ownerParticipantId: 'p0',
      myOutstanding: Money(1730),
    ),
    shareCode: 'X',
    splitModeDefault: SplitMode.byItem,
    balances: const {
      'p0': ParticipantBalanceView(
          paid: Money(5190),
          consumed: Money(3460),
          net: Money(1730),
          outstanding: Money(1730)),
      'p1': ParticipantBalanceView(
          paid: Money.zero,
          consumed: Money(1730),
          net: Money(-1730),
          outstanding: Money(-1730)),
    },
  );
  const participants = [
    SessionParticipant(id: 'p0', name: 'Edgar', isOwner: true, order: 0),
    SessionParticipant(id: 'p1', name: 'Alba', isOwner: false, order: 1),
  ];

  test('el PDF se genera con firma %PDF y contenido', () async {
    final bytes = await buildSessionPdf(
      detail: detail,
      participants: participants,
      settlements: const [
        Settlement(
            id: 'st1',
            from: 'p1',
            to: 'p0',
            amount: Money(1730),
            state: SettlementState.pending),
      ],
      accounts: const [
        AccountExport(name: 'Hotel', tickets: [
          TicketExport(
            merchantName: 'Hotel Sol',
            date: '2026-07-10',
            grandTotal: Money(5190),
            paidBy: 'p0',
            lines: [
              LineExport(
                  name: 'Noche doble',
                  quantityMilli: 2000,
                  totalPrice: Money(5190)),
            ],
          ),
        ]),
      ],
    );
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('la imagen-resumen es un PNG válido', () async {
    final bytes = await buildSummaryImage(
        detail: detail, participants: participants);
    expect(bytes.length, greaterThan(1000));
    // Firma PNG: 89 50 4E 47.
    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });
}
