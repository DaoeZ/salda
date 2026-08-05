import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/core/theme/app_theme.dart';
import 'package:salda_mobile/features/sessions/data/ticket_links_repository.dart';
import 'package:salda_mobile/features/spaces/data/manual_link_repository.dart';
import 'package:salda_mobile/features/sessions/presentation/linked_ticket_screen.dart';
import 'package:salda_mobile/features/spaces/presentation/space_detail_screen.dart';
import 'package:salda_mobile/features/spaces/domain/space_models.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

class _RetryGateway implements ManualLinkFunctionsGateway {
  _RetryGateway({this.failure});

  final Object? failure;
  var calls = 0;

  @override
  Future<ManualLinkRetryResult> retryPropagation(
    String spaceId,
    String manualId,
  ) async {
    calls++;
    if (failure != null) throw failure!;
    return const ManualLinkRetryResult(
      status: ManualLinkPropagationStatus.active,
      action: ManualLinkRetryAction.claimed,
    );
  }
}

void main() {
  const uid = 'uid-marta';

  Future<FakeFirebaseFirestore> seedTicket({
    String requestStatus = 'accepted',
    String? linkedUid = uid,
    String? linkStatus,
    String? linkError,
  }) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.doc('spaces/sp1').set({
      'name': 'Piso',
      'ownerUid': 'owner',
      'kind': 'group',
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/sp1/manualParticipants/m1').set({
      'manualId': 'm1',
      'displayName': 'Marta',
      'linkedUid': linkedUid,
      'createdByUid': 'owner',
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'schemaVersion': 1,
      'linkStatus': ?linkStatus,
      'linkError': ?linkError,
    });
    await firestore.doc('spaces/sp1/manualLinkRequests/m1_$uid').set({
      'manualId': 'm1',
      'uid': uid,
      'displayName': 'Marta',
      'status': requestStatus,
      'attempt': 1,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'schemaVersion': 1,
    });
    await firestore.doc('ticketLinks/TOKEN').set({
      'sessionId': 's1',
      'accountId': 'a1',
      'ticketId': 't1',
      'merchantName': 'Cena',
      'spaceId': 'sp1',
      'targetPid': 'p2',
      'targetManualId': 'm1',
      'targetName': 'Marta',
      'createdByUid': 'owner',
      'status': 'active',
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'schemaVersion': 2,
    });
    await firestore.doc('sessions/s1/ticketAccess/t1_$uid').set({
      'uid': uid,
      'token': 'TOKEN',
      'ticketId': 't1',
      'pid': 'p2',
      'manualId': 'm1',
      'createdAt': Timestamp.now(),
    });
    await firestore.doc('sessions/s1/accounts/a1/tickets/t1').set({
      'merchant': {'name': 'Cena'},
      'grandTotal': 1000,
    });
    await firestore.doc('sessions/s1/accounts/a1/tickets/t1/lines/l1').set({
      'name': 'Cena',
      'totalPrice': 1000,
      'order': 0,
      'assignment': {'type': 'one', 'participants': {'p2': 1}},
    });
    return firestore;
  }

  Future<void> pumpTicket(
    WidgetTester tester,
    FakeFirebaseFirestore firestore, {
    ManualLinkFunctionsGateway? gateway,
  }) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final links = TicketLinksRepository(
      firestore: firestore,
      uid: () => uid,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...loggedInOverrides(
            firestore: firestore,
            uid: uid,
            manualLinkFunctionsGateway: gateway,
          ),
          ticketLinksRepositoryProvider.overrideWithValue(links),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LinkedTicketScreen(token: 'TOKEN'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('la solicitud pendiente y rechazada no se confunden con activa',
      (tester) async {
    final pending = await seedTicket(requestStatus: 'pending', linkedUid: null);
    await pumpTicket(tester, pending);
    expect(find.text('Pendiente de que el anfitrión lo acepte'), findsOneWidget);
    expect(find.text('Identidad vinculada'), findsNothing);
    await close(tester);

    final rejected = await seedTicket(requestStatus: 'rejected', linkedUid: null);
    await pumpTicket(tester, rejected);
    expect(find.text('Solicitud rechazada'), findsOneWidget);
    expect(find.text('Identidad vinculada'), findsNothing);
    await close(tester);
  });

  testWidgets('accepted + linkedUid sin status se muestra propagando',
      (tester) async {
    final firestore = await seedTicket();
    await pumpTicket(tester, firestore);
    expect(find.textContaining('Vinculando'), findsWidgets);
    expect(find.text('Identidad vinculada'), findsNothing);
    await close(tester);
  });

  testWidgets('processing, active y failed se actualizan en tiempo real',
      (tester) async {
    final firestore = await seedTicket(linkStatus: 'processing');
    await pumpTicket(tester, firestore);
    expect(find.textContaining('Vinculando'), findsOneWidget);

    await firestore.doc('spaces/sp1/manualParticipants/m1').update({
      'linkStatus': 'active',
    });
    await tester.pumpAndSettle();
    expect(find.text('Identidad vinculada'), findsOneWidget);

    await firestore.doc('spaces/sp1/manualParticipants/m1').update({
      'linkStatus': 'failed',
      'linkError': 'propagation-error',
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('No hemos podido completar la vinculación'),
        findsOneWidget);
    expect(find.text('Identidad vinculada'), findsNothing);
    await close(tester);
  });

  testWidgets('fallo legacy usa el mensaje específico', (tester) async {
    final firestore = await seedTicket(
      linkStatus: 'failed',
      linkError: 'legacy-sessions-without-context',
    );
    await pumpTicket(tester, firestore);
    expect(find.textContaining('gastos antiguos sin contexto'), findsOneWidget);
    expect(find.text('Identidad vinculada'), findsNothing);
    await close(tester);
  });

  testWidgets('el claimant puede reintentar y recibe feedback de éxito',
      (tester) async {
    final firestore = await seedTicket(
      linkStatus: 'failed',
      linkError: 'propagation-error',
    );
    final gateway = _RetryGateway();
    await pumpTicket(tester, firestore, gateway: gateway);

    await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
    await tester.pumpAndSettle();

    expect(gateway.calls, 1);
    expect(find.text('Vinculación completada.'), findsOneWidget);
    await close(tester);
  });

  testWidgets('el claimant recibe feedback localizado si falla el reintento',
      (tester) async {
    final firestore = await seedTicket(
      linkStatus: 'failed',
      linkError: 'propagation-error',
    );
    final gateway = _RetryGateway(failure: StateError('network'));
    await pumpTicket(tester, firestore, gateway: gateway);

    await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
    await tester.pumpAndSettle();

    expect(gateway.calls, 1);
    expect(find.text('No hemos podido completar la operación'), findsOneWidget);
    await close(tester);
  });

  testWidgets('el anfitrión recibe feedback de propagación, no de activa',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.doc('spaces/sp1').set({
      'name': 'Piso',
      'ownerUid': 'owner',
      'kind': 'group',
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/sp1/members/owner').set({'uid': 'owner'});
    await firestore.doc('spaces/sp1/manualParticipants/m1').set({
      'manualId': 'm1',
      'displayName': 'Marta',
      'linkedUid': null,
      'createdByUid': 'owner',
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'schemaVersion': 1,
    });
    await firestore.doc('spaces/sp1/manualLinkRequests/m1_uid-marta').set({
      'manualId': 'm1',
      'uid': uid,
      'displayName': 'Marta',
      'status': 'pending',
      'attempt': 1,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'schemaVersion': 1,
    });

    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: loggedInOverrides(firestore: firestore, uid: 'owner'),
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SpaceDetailScreen(spaceId: 'sp1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Aceptar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vinculando'), findsWidgets);
    expect(find.text('Identidad vinculada'), findsNothing);
    await close(tester);
  });

  testWidgets('el anfitrión ve el fallo real y el retry enfocado',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.doc('spaces/sp1').set({
      'name': 'Piso',
      'ownerUid': 'owner',
      'kind': 'group',
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/sp1/members/owner').set({'uid': 'owner'});
    await firestore.doc('spaces/sp1/manualParticipants/m1').set({
      'manualId': 'm1',
      'displayName': 'Marta',
      'linkedUid': uid,
      'createdByUid': 'owner',
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'linkStatus': 'failed',
      'linkError': 'propagation-error',
      'schemaVersion': 1,
    });
    final gateway = _RetryGateway();
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: loggedInOverrides(
          firestore: firestore,
          uid: 'owner',
          manualLinkFunctionsGateway: gateway,
        ),
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SpaceDetailScreen(spaceId: 'sp1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No hemos podido completar la vinculación'),
        findsOneWidget);
    final manualTile = find.ancestor(
      of: find.text('Marta'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(
        of: manualTile,
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reintentar'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(gateway.calls, 1);
    expect(find.text('Vinculación completada.'), findsOneWidget);
    await close(tester);
  });
}
