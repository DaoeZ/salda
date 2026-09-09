import 'package:domain/domain.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/auth/data/auth_repository.dart';
import 'package:salda_mobile/features/economy/data/economic_repository.dart';
import 'package:salda_mobile/features/economy/domain/economic_models.dart';
import 'package:salda_mobile/features/economy/presentation/economic_overview_screen.dart';
import 'package:salda_mobile/features/economy/presentation/economic_relation_screen.dart';
import 'package:salda_mobile/features/profile/data/profile_repository.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

class _FakeFunctions implements EconomicFunctionsGateway {
  @override
  Future<void> rebuildMyRelations() async {}

  final created = <Map<String, Object>>[];

  @override
  Future<void> createPayment(Map<String, Object> data) async =>
      created.add(data);

  final settled = <Map<String, Object>>[];

  @override
  Future<void> resolvePayment(Map<String, Object> data) async {}

  @override
  Future<void> settleEntries(Map<String, Object> data) async =>
      settled.add(data);
}

class _FailingConfirmRepository extends EconomicRepository {
  _FailingConfirmRepository({
    required super.firestore,
    required super.functions,
  }) : super(
         uid: () => 'edgar',
         isFullAccount: () => true,
         idempotencyKey: () => '1234567890abcdef',
       );

  @override
  Future<void> confirmPayment(EconomicPaymentView payment) async {
    throw const EconomicFailure(EconomicFailureCode.network);
  }
}

void main() {
  late FakeFirebaseFirestore firestore;
  late _FakeFunctions functions;
  late EconomicOverview overview;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    functions = _FakeFunctions();
    await firestore.doc('profiles/alba').set({
      'displayName': 'Alba García con un nombre especialmente largo',
      'displayNameLower': 'alba garcia con un nombre especialmente largo',
      'username': 'alba',
      'createdAt': DateTime(2026),
      'updatedAt': DateTime(2026),
      'schemaVersion': 1,
    });
    overview = EconomicOverview.compute(
      viewerUid: 'edgar',
      entries: const [
        EconomicEntryView(
          id: 'e1',
          debtorUid: 'edgar',
          creditorUid: 'alba',
          amount: Money(2500),
          currency: 'EUR',
          sessionId: 's1',
          accountId: 'a1',
          ticketId: 't1',
          ticketName: 'Cena de celebración con descripción muy larga',
          spaceId: 'space1',
        ),
      ],
      payments: const [],
    );
  });

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    AppUser user = const AppUser(uid: 'edgar', emailVerified: true),
    EconomicOverview? displayedOverview,
    EconomicRepository? repositoryOverride,
    AsyncValue<EconomicOverview>? participantState,
  }) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository =
        repositoryOverride ??
        EconomicRepository(
          firestore: firestore,
          functions: functions,
          uid: () => 'edgar',
          isFullAccount: () => true,
          idempotencyKey: () => '1234567890abcdef',
        );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentAppUserProvider.overrideWithValue(user),
          profileRepositoryProvider.overrideWithValue(
            ProfileRepository(firestore: firestore, uid: () => 'edgar'),
          ),
          economicRepositoryProvider.overrideWithValue(repository),
          economicOverviewProvider.overrideWithValue(AsyncData(overview)),
          participantEconomicOverviewProvider.overrideWithValue(
            participantState ?? AsyncData(displayedOverview ?? overview),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, widget) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: widget!,
          ),
          home: child,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('resumen global muestra moneda y relación sin overflow', (
    tester,
  ) async {
    await pump(tester, const EconomicOverviewScreen());

    expect(find.text('Economía'), findsOneWidget);
    expect(find.textContaining('25,00'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detalle explica ticket y permite pago parcial', (tester) async {
    await pump(tester, const EconomicRelationScreen(otherUid: 'alba'));

    // La tarjeta de saldo es ahora una cabecera con el importe en grande,
    // así que el botón puede quedar bajo el pliegue en pantallas cortas.
    await tester.ensureVisible(find.text('Ya he pagado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ya he pagado'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '10,00');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(functions.created.single['amount'], 1000);
    await tester.scrollUntilVisible(
      find.textContaining('Cena de celebración'),
      180,
    );
    expect(find.textContaining('Cena de celebración'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invitado operativo lee economía sin controles de mutación', (
    tester,
  ) async {
    final guestOverview = EconomicOverview.compute(
      viewerUid: 'guest',
      entries: const [
        EconomicEntryView(
          id: 'guest-entry',
          debtorUid: 'guest',
          creditorUid: 'alba',
          amount: Money(2500),
          currency: 'EUR',
          sessionId: 's1',
          accountId: 'a1',
          ticketId: 't1',
          ticketName: 'Cena invitada',
        ),
      ],
      payments: const [
        EconomicPaymentView(
          id: 'pending',
          payerUid: 'alba',
          receiverUid: 'guest',
          amount: Money(500),
          currency: 'EUR',
          status: EconomicPaymentStatus.pending,
          source: 'user',
        ),
      ],
    );
    const guest = AppUser(uid: 'guest', isAnonymous: true);

    await pump(
      tester,
      const EconomicOverviewScreen(),
      user: guest,
      displayedOverview: guestOverview,
    );
    expect(find.textContaining('25,00'), findsWidgets);
    expect(find.text('Confirmar pago'), findsNothing);

    await pump(
      tester,
      const EconomicRelationScreen(otherUid: 'alba'),
      user: guest,
      displayedOverview: guestOverview,
    );
    expect(find.text('Ya he pagado'), findsNothing);
    expect(find.text('Confirmar pago'), findsNothing);
    expect(functions.created, isEmpty);
  });

  testWidgets('confirmación global fallida muestra feedback y recupera botón', (
    tester,
  ) async {
    final pending = EconomicOverview.compute(
      viewerUid: 'edgar',
      entries: const [],
      payments: const [
        EconomicPaymentView(
          id: 'pending-failure',
          payerUid: 'alba',
          receiverUid: 'edgar',
          amount: Money(500),
          currency: 'EUR',
          status: EconomicPaymentStatus.pending,
          source: 'user',
        ),
      ],
    );
    await pump(
      tester,
      const EconomicOverviewScreen(),
      displayedOverview: pending,
      repositoryOverride: _FailingConfirmRepository(
        firestore: firestore,
        functions: functions,
      ),
    );

    await tester.tap(find.text('Confirmar recepción'));
    await tester.pump();

    expect(
      find.text('No se pudo contactar con el servicio de pagos.'),
      findsOneWidget,
    );
    expect(find.text('Confirmar recepción'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detalle económico reintenta fuentes de participante fallidas', (
    tester,
  ) async {
    await pump(
      tester,
      const EconomicRelationScreen(otherUid: 'alba'),
      participantState: AsyncError(
        StateError('economy unavailable'),
        StackTrace.empty,
      ),
    );

    expect(find.text('Reintentar'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reintentar invitado invalida la fuente legible y recupera datos',
    (tester) async {
      var entryAttempts = 0;
      const guest = AppUser(uid: 'guest', isAnonymous: true);
      final entry = EconomicEntryView(
        id: 'retry-entry',
        debtorUid: 'alba',
        creditorUid: 'guest',
        amount: Money(2500),
        currency: 'EUR',
        sessionId: 's1',
        accountId: 'a1',
        ticketId: 't1',
        ticketName: 'Recuperada',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentAppUserProvider.overrideWithValue(guest),
            profileRepositoryProvider.overrideWithValue(
              ProfileRepository(firestore: firestore, uid: () => 'guest'),
            ),
            readableEconomicEntriesProvider.overrideWith((ref) {
              entryAttempts++;
              return entryAttempts == 1
                  ? Stream.error(StateError('offline'))
                  : Stream.value([entry]);
            }),
            readableEconomicPaymentsProvider.overrideWith(
              (ref) => Stream.value(const <EconomicPaymentView>[]),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const EconomicOverviewScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reintentar'), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(entryAttempts, greaterThanOrEqualTo(2));
      expect(find.textContaining('25,00'), findsWidgets);
      expect(find.text('Reintentar'), findsNothing);
    },
  );
}
