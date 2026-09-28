import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:domain/domain.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/auth/data/guest_identity_repository.dart';
import 'package:salda_mobile/features/economy/data/economic_repository.dart';
import 'package:salda_mobile/features/economy/domain/economic_models.dart';
import 'package:salda_mobile/features/spaces/presentation/space_cover_content.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

/// Bug comprobado en dispositivo: «Balance con Test» enseñaba «Test te debe
/// 14,73» y NINGUNA forma de cobrarlo, mientras que Economía global sí
/// ofrecía confirmar. Ahora toda superficie con un saldo accionable lleva al
/// mismo sistema de confirmación (ADR-038).
void main() {
  EconomicEntryView entry(String id, int cents, String name) =>
      EconomicEntryView(
        id: id,
        debtorUid: 'test',
        creditorUid: 'owner',
        amount: Money(cents),
        currency: 'EUR',
        sessionId: 's1',
        accountId: 'a1',
        ticketId: 't$id',
        ticketName: name,
        spaceId: 'group',
      );

  Future<void> pump(
    WidgetTester tester,
    EconomicOverview overview, {
    bool seedSpace = false,
  }) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.doc('profiles/test').set({'displayName': 'Test'});
    if (seedSpace) {
      // El espacio y su manual: sin ellos no hay a quién representar.
      await firestore.doc('spaces/group').set({
        'name': 'Piso',
        'ownerUid': 'owner',
        'status': 'active',
        'schemaVersion': 2,
      });
      await firestore.doc('spaces/group/members/owner').set({
        'uid': 'owner',
        'joinedAt': Timestamp.now(),
      });
      await firestore.doc('spaces/group/manualParticipants/javi').set({
        'manualId': 'javi',
        'displayName': 'Javi',
        'linkedUid': null,
        'createdByUid': 'owner',
        'schemaVersion': 1,
      });
    }
    final container = ProviderContainer(
      overrides: loggedInOverrides(firestore: firestore)
        ..addAll([
          guestIdentityRepositoryProvider.overrideWithValue(
            GuestIdentityRepository(firestore: firestore, uid: () => 'owner'),
          ),
          participantEconomicOverviewProvider.overrideWithValue(
            AsyncData(overview),
          ),
        ]),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      container.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SpaceBalanceDetailScreen(
            spaceId: 'group',
            otherUid: 'test',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('el balance del contexto explica y permite cobrar cada deuda', (
    tester,
  ) async {
    await pump(
      tester,
      EconomicOverview.compute(
        viewerUid: 'owner',
        entries: [
          entry('e1', 675, 'Familycash'),
          entry('e2', 798, 't familycash'),
        ],
        payments: const [],
      ),
    );

    // El agregado se sigue viendo…
    expect(find.textContaining('14,73'), findsWidgets);
    // …pero ya no es un callejón sin salida: están las dos deudas y la
    // acción para confirmar el cobro.
    expect(find.text('Familycash'), findsOneWidget);
    expect(find.text('t familycash'), findsOneWidget);
    expect(find.textContaining('6,75'), findsWidgets);
    expect(find.textContaining('7,98'), findsWidgets);
    expect(find.text('Confirmar recepción'), findsWidgets);
  });

  testWidgets('quien DEBE no ve la acción de cobrar', (tester) async {
    await pump(
      tester,
      EconomicOverview.compute(
        viewerUid: 'owner',
        entries: [
          EconomicEntryView(
            id: 'e9',
            debtorUid: 'owner',
            creditorUid: 'test',
            amount: const Money(500),
            currency: 'EUR',
            sessionId: 's1',
            accountId: 'a1',
            ticketId: 't9',
            ticketName: 'Cena',
            spaceId: 'group',
          ),
        ],
        payments: const [],
      ),
    );

    expect(find.text('Confirmar recepción'), findsNothing);
  });

  testWidgets(
    'quien administra cobra POR una identidad sin cuenta, y se dice',
    (tester) async {
      // Test debe a Javi, que no tiene cuenta. El administrador no es parte
      // de esa deuda: ni se le presenta como suya ni se le niega la acción,
      // porque si no nadie podría cerrarla nunca (ADR-038).
      await pump(
        tester,
        EconomicOverview.compute(
          viewerUid: 'owner',
          entries: [
            EconomicEntryView(
              id: 'em',
              debtorUid: 'test',
              creditorUid: 'manual:javi',
              amount: const Money(1000),
              currency: 'EUR',
              sessionId: 's1',
              accountId: 'a1',
              ticketId: 'tm',
              ticketName: 'Cena',
              spaceId: 'group',
            ),
          ],
          payments: const [],
        ),
        seedSpace: true,
      );

      // No se pinta como «te debe»: la deuda es de Javi, no del que mira.
      expect(find.textContaining('te debe'), findsNothing);
      expect(find.text('Test debe a Javi'), findsOneWidget);
      expect(find.text('Confirmar recepción'), findsWidgets);
    },
  );

  testWidgets('ser administrador NO permite cobrar lo de una cuenta ajena', (
    tester,
  ) async {
    // Javi (sin cuenta) debe a Test (con cuenta). La deuda es legible por
    // tener parte manual, pero el cobro es de Test y de nadie más.
    await pump(
      tester,
      EconomicOverview.compute(
        viewerUid: 'owner',
        entries: [
          EconomicEntryView(
            id: 'em2',
            debtorUid: 'manual:javi',
            creditorUid: 'test',
            amount: const Money(1000),
            currency: 'EUR',
            sessionId: 's1',
            accountId: 'a1',
            ticketId: 'tm2',
            ticketName: 'Cena',
            spaceId: 'group',
          ),
        ],
        payments: const [],
      ),
      seedSpace: true,
    );

    expect(find.text('Javi debe a Test'), findsOneWidget);
    expect(find.text('Confirmar recepción'), findsNothing);
  });

  testWidgets('una deuda ya cobrada desaparece de la lista', (tester) async {
    await pump(
      tester,
      EconomicOverview.compute(
        viewerUid: 'owner',
        entries: [
          entry('e1', 675, 'Familycash'),
          entry('e2', 798, 't familycash'),
        ],
        payments: [
          EconomicPaymentView(
            id: 'settle_e1',
            payerUid: 'test',
            receiverUid: 'owner',
            amount: const Money(675),
            currency: 'EUR',
            status: EconomicPaymentStatus.confirmed,
            source: 'user',
            allocations: const {'e1': Money(675)},
            spaceId: 'group',
          ),
        ],
      ),
    );

    expect(find.text('Familycash'), findsNothing);
    expect(find.text('t familycash'), findsOneWidget);
    // El agregado se recalcula solo: 14,73 → 7,98.
    expect(find.textContaining('7,98'), findsWidgets);
    expect(find.textContaining('14,73'), findsNothing);
  });
}
