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

  @override
  Future<void> resolvePayment(Map<String, Object> data) async {}
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

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = EconomicRepository(
      firestore: firestore,
      functions: functions,
      uid: () => 'edgar',
      isFullAccount: () => true,
      idempotencyKey: () => '1234567890abcdef',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentAppUserProvider.overrideWithValue(
            const AppUser(uid: 'edgar', emailVerified: true),
          ),
          profileRepositoryProvider.overrideWithValue(
            ProfileRepository(firestore: firestore, uid: () => 'edgar'),
          ),
          economicRepositoryProvider.overrideWithValue(repository),
          economicOverviewProvider.overrideWithValue(AsyncData(overview)),
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
    await tester.ensureVisible(find.text('Marcar como pagado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marcar como pagado'));
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
}
