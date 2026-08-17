import 'package:domain/domain.dart' show Money;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/core/theme/app_theme.dart';
import 'package:salda_mobile/features/auth/data/auth_repository.dart';
import 'package:salda_mobile/features/auth/data/guest_identity_repository.dart';
import 'package:salda_mobile/features/economy/application/identity_names.dart';
import 'package:salda_mobile/features/economy/presentation/economic_overview_screen.dart';
import 'package:salda_mobile/features/economy/presentation/economic_relation_screen.dart';
import 'package:salda_mobile/features/economy/presentation/space_economic_summary.dart';
import 'package:salda_mobile/features/sessions/domain/session_models.dart';
import 'package:salda_mobile/features/sessions/presentation/ticket_detail_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

/// En ninguna pantalla puede verse `manual:{id}`. El nombre de un
/// participante MANUAL lo custodia su espacio (ADR-033), no un perfil
/// público, y esa es la única fuente que debe usarse.
void main() {
  const yo = 'owner';
  late FakeFirebaseFirestore firestore;

  setUp(() => firestore = FakeFirebaseFirestore());

  Future<void> espacio(
    String id, {
    String kind = 'relationship',
    Map<String, String?> manuales = const {},
    List<String> cuentas = const [],
  }) async {
    await firestore.doc('spaces/$id').set({
      'name': 'Contexto',
      'ownerUid': yo,
      'kind': kind,
      'relationshipUids': kind == 'relationship' ? [yo] : <String>[],
      if (manuales.length == 1 && kind == 'relationship')
        'relationshipManualId': manuales.keys.first,
      'status': 'active',
      'schemaVersion': kind == 'relationship' ? 3 : 2,
    });
    await firestore.doc('spaces/$id/members/$yo').set({'uid': yo});
    for (final uid in cuentas) {
      await firestore.doc('spaces/$id/members/$uid').set({'uid': uid});
    }
    for (final entry in manuales.entries) {
      await firestore.doc('spaces/$id/manualParticipants/${entry.key}').set({
        'manualId': entry.key,
        'displayName': entry.value,
        'linkedUid': null,
        'createdByUid': yo,
        'schemaVersion': 1,
      });
    }
  }

  Future<void> obligacion({
    required String id,
    required String spaceId,
    required String debtor,
    String creditor = yo,
    int amount = 1500,
  }) => firestore.collection('economicEntries').doc(id).set({
    'spaceId': spaceId,
    'debtorUid': debtor,
    'creditorUid': creditor,
    'amount': amount,
    'currency': 'EUR',
    'memberUids': [yo],
    'sessionId': 's1',
    'accountId': 'a1',
    'ticketId': 't1',
    'ticketName': 'Cena',
    'schemaVersion': 1,
  });

  Future<void> ticket(String spaceId) async {
    await firestore.doc('sessions/s1').set({
      'ownerUid': yo,
      'kind': 'single',
      'status': 'open',
      'splitModeDefault': 'byItem',
      'currency': 'EUR',
      'spaceId': spaceId,
      'totals': {'grandTotal': 3000},
      'balances': {},
    });
    await firestore.doc('sessions/s1/accounts/a1').set({'name': 'C'});
    await firestore.doc('sessions/s1/accounts/a1/tickets/t1').set({
      'kind': 'manual',
      'grandTotal': 3000,
      'paidByParticipantId': 'p0',
      'merchant': {'name': 'Cena'},
      'spaceId': spaceId,
    });
  }

  Future<ProviderContainer> pump(
    WidgetTester tester,
    String spaceId, {
    String viewerUid = yo,
    AppUser? user,
  }) async {
    tester.view.physicalSize = const Size(430, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides:
          loggedInOverrides(
            firestore: firestore,
            uid: viewerUid,
            authRepository: FakeAuthRepository(
              user: user ?? AppUser(uid: viewerUid),
            ),
          )..add(
            guestIdentityRepositoryProvider.overrideWithValue(
              GuestIdentityRepository(
                firestore: firestore,
                uid: () => viewerUid,
              ),
            ),
          ),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SpaceEconomicSummary(spaceId: spaceId),
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

  /// Ninguna pantalla puede enseñar el actor interno.
  void sinIdentificador() {
    expect(find.textContaining('manual:'), findsNothing);
  }

  testWidgets('relación ACCOUNT + MANUAL: se ve el nombre, no el id', (
    tester,
  ) async {
    await espacio('rel3', manuales: {'m1': 'Pablo'});
    await ticket('rel3');
    await obligacion(id: 'e1', spaceId: 'rel3', debtor: 'manual:m1');
    await pump(tester, 'rel3');
    expect(find.textContaining('Pablo'), findsOneWidget);
    sinIdentificador();
    await cerrar(tester);
  });

  testWidgets('grupo con VARIOS manuales: cada uno con su nombre', (
    tester,
  ) async {
    await espacio('g1', kind: 'group', manuales: {'m1': 'Pablo', 'm2': 'Ana'});
    await ticket('g1');
    await obligacion(id: 'e1', spaceId: 'g1', debtor: 'manual:m1');
    await obligacion(id: 'e2', spaceId: 'g1', debtor: 'manual:m2');
    await pump(tester, 'g1');
    expect(find.textContaining('Pablo'), findsOneWidget);
    expect(find.textContaining('Ana'), findsOneWidget);
    sinIdentificador();
    await cerrar(tester);
  });

  testWidgets('grupo MIXTO: cuenta por perfil y manual por su espacio', (
    tester,
  ) async {
    await espacio(
      'g1',
      kind: 'group',
      manuales: {'m1': 'Pablo'},
      cuentas: ['uid-ana'],
    );
    await firestore.doc('profiles/uid-ana').set({'displayName': 'Ana Cuenta'});
    await ticket('g1');
    await obligacion(id: 'e1', spaceId: 'g1', debtor: 'manual:m1');
    await obligacion(id: 'e2', spaceId: 'g1', debtor: 'uid-ana');
    await pump(tester, 'g1');
    expect(find.textContaining('Pablo'), findsOneWidget);
    expect(find.textContaining('Ana Cuenta'), findsOneWidget);
    sinIdentificador();
    await cerrar(tester);
  });

  testWidgets('participante BORRADO: rótulo controlado, nunca el id', (
    tester,
  ) async {
    await espacio('rel3');
    await ticket('rel3');
    // La obligación histórica sobrevive al participante: es correcto.
    await obligacion(id: 'e1', spaceId: 'rel3', debtor: 'manual:borrado');
    await pump(tester, 'rel3');
    expect(find.textContaining('Persona sin nombre'), findsOneWidget);
    sinIdentificador();
    await cerrar(tester);
  });

  testWidgets('nombre VACÍO: rótulo controlado', (tester) async {
    await espacio('rel3', manuales: {'m1': '   '});
    await ticket('rel3');
    await obligacion(id: 'e1', spaceId: 'rel3', debtor: 'manual:m1');
    await pump(tester, 'rel3');
    expect(find.textContaining('Persona sin nombre'), findsOneWidget);
    sinIdentificador();
    await cerrar(tester);
  });

  testWidgets('nombre con emojis se respeta', (tester) async {
    await espacio('rel3', manuales: {'m1': 'Pablo 🎸'});
    await ticket('rel3');
    await obligacion(id: 'e1', spaceId: 'rel3', debtor: 'manual:m1');
    await pump(tester, 'rel3');
    expect(find.textContaining('Pablo 🎸'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('invitado resuelve el manual autorizado desde economía legible', (
    tester,
  ) async {
    await espacio('guest-space', kind: 'group', manuales: {'m1': 'Pablo'});
    await firestore.doc('spaces/guest-space/members/guest').set({
      'uid': 'guest',
      'kind': 'guest',
      'displayName': 'Invitada',
    });
    await firestore.doc('economicEntries/guest-entry').set({
      'spaceId': 'guest-space',
      'debtorUid': 'guest',
      'creditorUid': 'manual:m1',
      'amount': 1500,
      'currency': 'EUR',
      'memberUids': ['guest'],
      'sessionId': 's1',
      'accountId': 'a1',
      'ticketId': 't1',
      'ticketName': 'Cena',
    });
    await pump(
      tester,
      'guest-space',
      viewerUid: 'guest',
      user: const AppUser(uid: 'guest', isAnonymous: true),
    );
    expect(find.textContaining('Pablo'), findsOneWidget);
    sinIdentificador();
    await cerrar(tester);
  });

  testWidgets('cuenta resuelve el nombre de un invitado, no su UID', (
    tester,
  ) async {
    await espacio('guest-name', kind: 'group', cuentas: ['guest']);
    await firestore.doc('spaces/guest-name/members/guest').set({
      'uid': 'guest',
      'kind': 'guest',
      'displayName': 'Inés',
    });
    await firestore.doc('guestIdentities/guest').set({'displayName': 'Inés'});
    await ticket('guest-name');
    await obligacion(
      id: 'guest-name-entry',
      spaceId: 'guest-name',
      debtor: 'guest',
    );

    await pump(tester, 'guest-name');

    expect(find.textContaining('Inés'), findsOneWidget);
    expect(find.textContaining('guest'), findsNothing);
    await cerrar(tester);
  });

  testWidgets('nombre muy largo no desborda ni revela el id', (tester) async {
    await espacio(
      'rel3',
      manuales: {'m1': 'María del Carmen de la Santísima Trinidad Fernández'},
    );
    await ticket('rel3');
    await obligacion(id: 'e1', spaceId: 'rel3', debtor: 'manual:m1');
    await pump(tester, 'rel3');
    expect(tester.takeException(), isNull);
    sinIdentificador();
    await cerrar(tester);
  });

  testWidgets('dos manuales con el MISMO nombre no se confunden', (
    tester,
  ) async {
    await espacio(
      'g1',
      kind: 'group',
      manuales: {'m1': 'Pablo', 'm2': 'Pablo'},
    );
    await ticket('g1');
    await obligacion(id: 'e1', spaceId: 'g1', debtor: 'manual:m1');
    await obligacion(id: 'e2', spaceId: 'g1', debtor: 'manual:m2', amount: 700);
    await pump(tester, 'g1');
    // Dos filas, dos importes distintos: el nombre repetido no los fusiona
    // porque la identidad sigue siendo el actor, no el nombre.
    expect(find.textContaining('Pablo'), findsNWidgets(2));
    expect(find.textContaining('15,00'), findsOneWidget);
    expect(find.textContaining('7,00'), findsOneWidget);
    sinIdentificador();
    await cerrar(tester);
  });

  testWidgets('un MANUAL vinculado conserva su nombre y su actor', (
    tester,
  ) async {
    await espacio('rel3', manuales: {'m1': 'Pablo'});
    await firestore.doc('spaces/rel3/manualParticipants/m1').update({
      'linkedUid': 'uid-pablo',
    });
    await ticket('rel3');
    // El histórico sigue escrito con el actor manual: no se migra.
    await obligacion(id: 'e1', spaceId: 'rel3', debtor: 'manual:m1');
    await pump(tester, 'rel3');
    expect(find.textContaining('Pablo'), findsOneWidget);
    sinIdentificador();
    await cerrar(tester);
  });

  group('resumen económico global', () {
    Future<void> pumpGlobal(WidgetTester tester) async {
      tester.view.physicalSize = const Size(430, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: loggedInOverrides(firestore: firestore),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const EconomicOverviewScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('los saldos se etiquetan con el nombre del manual', (
      tester,
    ) async {
      await espacio('rel3', manuales: {'m1': 'Pablo'});
      await ticket('rel3');
      await obligacion(id: 'e1', spaceId: 'rel3', debtor: 'manual:m1');
      await pumpGlobal(tester);
      expect(find.textContaining('Pablo'), findsWidgets);
      sinIdentificador();
      await cerrar(tester);
    });

    testWidgets('mezcla de cuentas y manuales en la misma lista', (
      tester,
    ) async {
      await espacio(
        'g1',
        kind: 'group',
        manuales: {'m1': 'Pablo'},
        cuentas: ['uid-ana'],
      );
      await firestore.doc('profiles/uid-ana').set({
        'displayName': 'Ana Cuenta',
      });
      await ticket('g1');
      await obligacion(id: 'e1', spaceId: 'g1', debtor: 'manual:m1');
      await obligacion(id: 'e2', spaceId: 'g1', debtor: 'uid-ana');
      await pumpGlobal(tester);
      expect(find.textContaining('Pablo'), findsWidgets);
      expect(find.textContaining('Ana Cuenta'), findsWidgets);
      sinIdentificador();
      await cerrar(tester);
    });

    testWidgets('identidad INEXISTENTE: rótulo controlado', (tester) async {
      // Ni espacio ni perfil: puede pasar con un dato heredado.
      await ticket('desconocido');
      await obligacion(
        id: 'e1',
        spaceId: 'desconocido',
        debtor: 'manual:fantasma',
      );
      await pumpGlobal(tester);
      expect(find.textContaining('Persona sin nombre'), findsWidgets);
      sinIdentificador();
      await cerrar(tester);
    });
  });

  group('detalle de una relación económica', () {
    Future<void> pumpDetalle(WidgetTester tester, String actor) async {
      tester.view.physicalSize = const Size(430, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: loggedInOverrides(firestore: firestore),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: EconomicRelationScreen(otherUid: actor),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('el título lleva el nombre, no el identificador', (
      tester,
    ) async {
      await espacio('rel3', manuales: {'m1': 'Pablo'});
      await ticket('rel3');
      await obligacion(id: 'e1', spaceId: 'rel3', debtor: 'manual:m1');
      await pumpDetalle(tester, 'manual:m1');
      expect(find.textContaining('Pablo'), findsWidgets);
      sinIdentificador();
      await cerrar(tester);
    });

    testWidgets('el historial de obligaciones tampoco lo enseña', (
      tester,
    ) async {
      await espacio('rel3', manuales: {'m1': 'Pablo'});
      await ticket('rel3');
      await obligacion(id: 'e1', spaceId: 'rel3', debtor: 'manual:m1');
      await obligacion(
        id: 'e2',
        spaceId: 'rel3',
        debtor: 'manual:m1',
        amount: 400,
      );
      await pumpDetalle(tester, 'manual:m1');
      expect(find.textContaining('Cena'), findsWidgets);
      sinIdentificador();
      await cerrar(tester);
    });

    testWidgets('un pago pendiente nombra a quien lo marcó', (tester) async {
      await espacio('rel3', manuales: {'m1': 'Pablo'});
      await ticket('rel3');
      await obligacion(id: 'e1', spaceId: 'rel3', debtor: 'manual:m1');
      await firestore.collection('economicPayments').doc('p1').set({
        'spaceId': 'rel3',
        'payerUid': 'manual:m1',
        'receiverUid': yo,
        'amount': 500,
        'currency': 'EUR',
        'status': 'pending',
        'memberUids': [yo],
        'schemaVersion': 1,
      });
      await pumpDetalle(tester, 'manual:m1');
      expect(find.textContaining('Pablo'), findsWidgets);
      sinIdentificador();
      await cerrar(tester);
    });
  });

  group('ticket: líneas, asignaciones y participantes', () {
    // El ticket nunca habla en actores: reparte por participantId y el
    // nombre lo pone la propia sesión. Estas pruebas fijan esa frontera,
    // que es la razón de que ahí nunca se viera `manual:{id}`.
    Future<void> pumpTicket(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: loggedInOverrides(firestore: firestore),
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: TicketDetailScreen(
              ticket: TicketRef(
                sessionId: 's1',
                payerName: 'Edgar',
                ticket: const SessionTicket(
                  id: 't1',
                  path: 'sessions/s1/accounts/a1/tickets/t1',
                  merchantName: 'Bar Manolo',
                  grandTotal: Money(1200),
                  paidBy: 'p0',
                  kind: 'manual',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> ticketConManual() async {
      await espacio('g1', kind: 'group', manuales: {'m1': 'Pablo'});
      await ticket('g1');
      await firestore.doc('sessions/s1/participants/p0').set({
        'name': 'Edgar',
        'isOwner': true,
        'order': 0,
        'claimedByDevice': '',
      });
      // El participante del ticket que corresponde al MANUAL: lleva su
      // nombre, no su actor.
      await firestore.doc('sessions/s1/participants/p1').set({
        'name': 'Pablo',
        'isOwner': false,
        'order': 1,
        'manualId': 'm1',
        'claimedByDevice': '',
      });
      await firestore.doc('sessions/s1/accounts/a1/tickets/t1/lines/l1').set({
        'name': 'Pizza',
        'order': 0,
        'quantityMilli': 1000,
        'totalPrice': 1200,
        'unitIds': ['u0'],
        'assignment': {
          'type': 'units',
          'schemaVersion': 2,
          'units': {
            'u0': {'p1': true},
          },
        },
      });
    }

    testWidgets('la lista de participantes muestra nombres', (tester) async {
      await ticketConManual();
      await pumpTicket(tester);
      expect(find.textContaining('Pablo'), findsWidgets);
      sinIdentificador();
      await cerrar(tester);
    });

    testWidgets('la asignación de una línea nombra a quien la consume', (
      tester,
    ) async {
      await ticketConManual();
      await pumpTicket(tester);
      expect(find.textContaining('Pizza'), findsWidgets);
      expect(find.textContaining('Pablo'), findsWidgets);
      sinIdentificador();
      await cerrar(tester);
    });

    testWidgets('renombrar el manual no rompe la asignación', (tester) async {
      await ticketConManual();
      // El nombre del participante del ticket es independiente: el enlace
      // vive en `manualId`, nunca en el texto.
      await firestore.doc('spaces/g1/manualParticipants/m1').update({
        'displayName': 'Pablo Ruiz',
      });
      await pumpTicket(tester);
      expect(find.textContaining('Pablo'), findsWidgets);
      sinIdentificador();
      await cerrar(tester);
    });
  });

  test('la semilla del avatar no es el actor con prefijo', () {
    // Se usa el id interno para elegir color; nunca se enseña, y renombrar
    // no cambia el color.
    expect(economicAvatarSeed('manual:m1'), 'm1');
    expect(economicAvatarSeed('uid-ana'), 'uid-ana');
  });
}
