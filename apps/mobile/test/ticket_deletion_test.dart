import 'package:domain/domain.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/sessions/application/session_providers.dart';
import 'package:salda_mobile/features/sessions/data/firestore_session_repository.dart';
import 'package:salda_mobile/features/sessions/domain/session_models.dart';
import 'package:salda_mobile/features/sessions/presentation/ticket_detail_screen.dart';
import 'package:salda_mobile/features/sessions/presentation/ticket_navigation.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

/// A2: eliminar un gasto.
///
/// Lo que se fija aquí es la mitad de cliente: a quién se le OFRECE la acción
/// —las Rules son la autoridad, esto solo decide qué se enseña—, qué se le
/// advierte antes de un borrado irreversible, y que el commit que sale es el
/// atómico (evidencia + borrado) y no un borrado suelto que P6 no podría
/// atribuir.
void main() {
  const ticketPath = 'sessions/s1/accounts/a1/tickets/t1';
  const ticket = SessionTicket(
    id: 't1',
    path: ticketPath,
    merchantName: 'Súper',
    grandTotal: Money(2000),
    paidBy: 'p1',
    kind: 'manual',
    spaceId: 'g1',
    contextModelVersion: 1,
  );

  late FakeFirebaseFirestore firestore;

  setUp(() => firestore = FakeFirebaseFirestore());

  Future<void> sembrar({
    String status = 'open',
    String kind = 'group',
    String ownerUid = 'owner',
  }) async {
    await firestore.doc('spaces/g1').set({
      'name': 'Piso',
      'ownerUid': 'jefa',
      'kind': kind,
      'relationshipUids': kind == 'relationship' ? ['owner', 'pareja'] : [],
      'status': 'active',
      'schemaVersion': 2,
    });
    for (final uid in ['jefa', 'owner', 'admin', 'miembro', 'pareja']) {
      await firestore.doc('spaces/g1/members/$uid').set({
        'uid': uid,
        if (uid == 'admin') 'role': 'admin',
      });
    }
    await firestore.doc('sessions/s1').set({
      'ownerUid': ownerUid,
      'kind': 'single',
      'name': 'Compra',
      'status': status,
      'splitModeDefault': 'byItem',
      'shareCode': 'TEST-CODE-1234567890',
      'currency': 'EUR',
      'spaceId': 'g1',
      'contextModelVersion': 1,
    });
    await firestore.doc('sessions/s1/accounts/a1').set({'name': 'Súper'});
    await firestore.doc(ticketPath).set({
      'kind': 'manual',
      'grandTotal': 2000,
      'paidByParticipantId': 'p1',
      'merchant': {'name': 'Súper'},
      'spaceId': 'g1',
      'contextModelVersion': 1,
    });
  }

  /// Obligación del ticket y un pago humano ligado a ella.
  Future<void> deuda({
    required String estado,
    int amount = 1000,
    String id = 'pay1',
  }) async {
    await firestore.doc('economicEntries/e1').set({
      'spaceId': 'g1',
      'debtorUid': 'otra',
      'creditorUid': 'owner',
      'amount': 2000,
      'currency': 'EUR',
      'memberUids': ['owner', 'otra'],
      'sessionId': 's1',
      'accountId': 'a1',
      'ticketId': 't1',
      'ticketName': 'Súper',
      'schemaVersion': 1,
    });
    await firestore.doc('economicPayments/$id').set({
      'memberUids': ['owner', 'otra'],
      'payerUid': 'otra',
      'receiverUid': 'owner',
      'amount': amount,
      'currency': 'EUR',
      'status': estado,
      'source': 'user',
      'allocations': {'e1': amount},
      'sessionIds': ['s1'],
      'schemaVersion': 1,
    });
  }

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    String uid = 'owner',
  }) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        ...loggedInOverrides(firestore: firestore, uid: uid),
        // El emulador de pruebas no aplica Rules, y en producción SOLO la
        // dueña de la sesión la lee (ahí vive el `shareCode`). Sin esto
        // cualquier uid parecería el creador del gasto y la pantalla ofrecía
        // borrar a quien las Rules van a rechazar.
        if (uid != 'owner')
          sessionDetailProvider('s1').overrideWith(
            (ref) => Stream<SessionDetail?>.error(
              FirebaseException(
                plugin: 'cloud_firestore',
                code: 'permission-denied',
              ),
            ),
          ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const TicketDetailScreen(
            ticket: TicketRef(
              sessionId: 's1',
              payerName: 'Edgar',
              ticket: ticket,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> cerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  final accionBorrar = find.byIcon(Icons.delete_outline);

  group('a quién se le ofrece eliminar', () {
    testWidgets('el creador del gasto (dueño de la sesión), sí', (
      tester,
    ) async {
      await sembrar();
      await pump(tester);
      expect(accionBorrar, findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('quien administra el grupo, sobre el gasto ajeno', (
      tester,
    ) async {
      await sembrar();
      await pump(tester, uid: 'admin');
      expect(accionBorrar, findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('el propietario del grupo, sobre el gasto ajeno', (
      tester,
    ) async {
      await sembrar();
      await pump(tester, uid: 'jefa');
      expect(accionBorrar, findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('un miembro normal, NO', (tester) async {
      await sembrar();
      await pump(tester, uid: 'miembro');
      expect(accionBorrar, findsNothing);
      await cerrar(tester);
    });

    testWidgets('la contraparte de una RELACIÓN, NO', (tester) async {
      await sembrar(kind: 'relationship');
      await pump(tester, uid: 'pareja');
      expect(accionBorrar, findsNothing);
      await cerrar(tester);
    });

    testWidgets('con la sesión CERRADA, a nadie', (tester) async {
      await sembrar(status: 'closed');
      await pump(tester);
      expect(accionBorrar, findsNothing);
      await cerrar(tester);
    });
  });

  group('confirmación', () {
    testWidgets('sin pagos: confirmación destructiva normal', (tester) async {
      await sembrar();
      await pump(tester);
      await tester.tap(accionBorrar);
      await tester.pumpAndSettle();

      expect(find.text('¿Eliminar este gasto?'), findsOneWidget);
      expect(
        find.textContaining('los balances se recalcularán'),
        findsOneWidget,
      );
      // Nada de pagos: no se inventa una advertencia que no toca.
      expect(find.textContaining('pagos registrados'), findsNothing);
      expect(find.textContaining('pendientes de confirmación'), findsNothing);
      await cerrar(tester);
    });

    testWidgets('con pago confirmado: aviso reforzado con importe', (
      tester,
    ) async {
      await sembrar();
      await deuda(estado: 'confirmed');
      await pump(tester);
      await tester.tap(accionBorrar);
      await tester.pumpAndSettle();

      expect(find.text('Este gasto tiene pagos registrados'), findsOneWidget);
      expect(find.textContaining('1 pago confirmado de 10,00'), findsOneWidget);
      expect(find.textContaining('invertirse'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('con declaración pendiente: se distingue del pago confirmado', (
      tester,
    ) async {
      await sembrar();
      await deuda(estado: 'pending', amount: 2000);
      await pump(tester);
      await tester.tap(accionBorrar);
      await tester.pumpAndSettle();

      // La declaración NO se cuenta como pago confirmado: son dos hechos
      // distintos y mezclarlos mentiría sobre el saldo.
      expect(find.text('Este gasto tiene pagos registrados'), findsNothing);
      expect(find.textContaining('1 pago declarado de 20,00'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('cancelar no borra nada', (tester) async {
      await sembrar();
      await pump(tester);
      await tester.tap(accionBorrar);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect((await firestore.doc(ticketPath).get()).exists, isTrue);
      await cerrar(tester);
    });
  });

  group('el borrado', () {
    testWidgets('confirmar borra el ticket y deja la evidencia del actor', (
      tester,
    ) async {
      await sembrar();
      await pump(tester, uid: 'admin');
      await tester.tap(accionBorrar);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();

      expect((await firestore.doc(ticketPath).get()).exists, isFalse);
      final evidencia = await firestore
          .doc('sessions/s1/ticketRemovals/t1')
          .get();
      expect(evidencia.exists, isTrue);
      // El actor es quien borra, no el dueño de la sesión: es lo único que
      // impide que P6 atribuya el hecho a quien creó el gasto.
      expect(evidencia.data()!['removedBy'], 'admin');
      expect(evidencia.data()!['accountId'], 'a1');
      // El resumen se copia del ticket: las Rules lo comparan con el real.
      expect(evidencia.data()!['merchantName'], 'Súper');
      expect(evidencia.data()!['grandTotal'], 2000);
      expect(find.text('Gasto eliminado'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('un fallo no puede parecer un éxito', (tester) async {
      await sembrar();
      final container = ProviderContainer(
        overrides: loggedInOverrides(
          firestore: firestore,
          sessionRepository: _RepositorioQueFalla(firestore),
        ),
      );
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const TicketDetailScreen(
              ticket: TicketRef(
                sessionId: 's1',
                payerName: 'Edgar',
                ticket: ticket,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(accionBorrar);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No se pudo eliminar'), findsOneWidget);
      expect(find.text('Gasto eliminado'), findsNothing);
      // La pantalla sigue donde estaba y el gasto también.
      expect(find.byType(TicketDetailScreen), findsOneWidget);
      expect((await firestore.doc(ticketPath).get()).exists, isTrue);
      await cerrar(tester);
    });

    testWidgets('borrar dos veces no es un error', (tester) async {
      await sembrar();
      final repo = FirestoreSessionRepository(
        firestore: firestore,
        uid: () => 'owner',
        shareCodeFactory: () => 'X',
      );
      await repo.deleteTicket(ticketPath);
      await repo.deleteTicket(ticketPath);
      expect((await firestore.doc(ticketPath).get()).exists, isFalse);
    });
  });

  group('un gasto eliminado ya no se abre', () {
    testWidgets(
      'quien no tiene acceso ve «ya no está disponible», no un error',
      (tester) async {
        // Un ex-miembro (A11d) pierde con el gasto su derecho histórico: ni
        // llega por él, ni puede listar las cuentas. Antes acababa en un error
        // de carga genérico que invitaba a reintentar para siempre.
        await sembrar();
        await firestore.doc(ticketPath).delete();
        final container = ProviderContainer(
          overrides: [
            ...loggedInOverrides(firestore: firestore, uid: 'ex-miembro'),
            accountsProvider('s1').overrideWith(
              (ref) => Stream<List<SessionAccount>>.error(
                FirebaseException(
                  plugin: 'cloud_firestore',
                  code: 'permission-denied',
                ),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const TicketRoute(sessionId: 's1', ticketId: 't1'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Este gasto ya no está disponible'), findsOneWidget);
        await cerrar(tester);
      },
    );
  });
}

/// Repositorio que rechaza el borrado, como harían las Rules con una sesión
/// cerrada o sin autoridad.
class _RepositorioQueFalla extends FirestoreSessionRepository {
  _RepositorioQueFalla(FakeFirebaseFirestore firestore)
    : super(
        firestore: firestore,
        uid: () => 'owner',
        shareCodeFactory: () => 'X',
      );

  @override
  Future<void> deleteTicket(String ticketPath) => Future<void>.error(
    FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
  );
}
