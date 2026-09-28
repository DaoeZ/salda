import 'package:domain/domain.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/ai/application/ai_analysis_controller.dart';
import 'package:salda_mobile/features/auth/data/auth_repository.dart';
import 'package:salda_mobile/features/review/application/review_draft.dart';
import 'package:salda_mobile/features/review/presentation/review_screen.dart';
import 'package:salda_mobile/features/sessions/application/add_ticket_controller.dart';
import 'package:salda_mobile/features/sessions/data/firestore_session_repository.dart';
import 'package:salda_mobile/features/sessions/domain/session_models.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

/// A15: que un ticket CUADRE no certifica que esté bien leído.
///
/// Lo que se fija aquí es que las tres salidas del usuario —corregir a mano,
/// corregir el total y pedir una revisión con IA— siguen estando ahí cuando
/// las cuentas salen, que es justo cuando antes desaparecían; y que corregir
/// no deja datos que mientan ni se pierde al guardar.
void main() {
  ReceiptExtraction extraccion({
    int grandTotal = 500,
    double confidence = 0.9,
  }) => ReceiptExtraction(
    engine: 'mlkit',
    merchantName: const Extracted('t familycash', 0.6),
    date: const Extracted('2026-08-28', 0.95),
    lines: [
      ExtractedLine(
        name: 'GAZPACHO',
        totalPrice: const Money(180),
        confidence: confidence,
      ),
      ExtractedLine(
        name: 'LECHE',
        quantityMilli: 2000,
        unitPrice: const Money(160),
        totalPrice: const Money(320),
        confidence: confidence,
      ),
    ],
    grandTotal: Extracted(Money(grandTotal), 0.92),
  );

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    ReceiptExtraction? extraction,
    String? imagePath = '/tmp/ticket.jpg',
    bool aiConfigured = false,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWithValue('test-user'),
        currentAppUserProvider.overrideWithValue(
          const AppUser(uid: 'test-user'),
        ),
        aiAvailableProvider.overrideWith((ref) async => aiConfigured),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(reviewDraftProvider.notifier)
        .loadFrom(extraction ?? extraccion());
    container.read(lastScanImageProvider.notifier).set(imagePath);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ReviewScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  group('cuadrar no certifica la lectura', () {
    testWidgets('el estado verde habla solo del total', (tester) async {
      await pump(tester);
      expect(find.text('El total cuadra'), findsOneWidget);
      expect(find.text('El ticket cuadra'), findsNothing);
    });

    testWidgets('revisar con IA sigue disponible con el total cuadrado', (
      tester,
    ) async {
      await pump(tester, aiConfigured: true);
      final boton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Analizar con IA'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(boton.onPressed, isNotNull);
    });

    testWidgets('y sigue ahí después de entrar a editar a mano', (
      tester,
    ) async {
      // Con descuadre aparece el aviso; pulsar «Editar a mano» lo descarta y
      // antes se llevaba por delante el botón de IA.
      await pump(
        tester,
        extraction: extraccion(grandTotal: 600),
        aiConfigured: true,
      );
      await tester.tap(find.text('Editar a mano'));
      await tester.pumpAndSettle();
      expect(find.text('Repetir foto'), findsNothing); // aviso descartado
      expect(find.text('Analizar con IA'), findsOneWidget);
    });

    testWidgets('el establecimiento se corrige aunque el total cuadre', (
      tester,
    ) async {
      final container = await pump(tester);
      await tester.tap(find.text('t familycash'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Family Cash');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(container.read(reviewDraftProvider)!.merchantName, 'Family Cash');
    });

    testWidgets('una línea con baja confianza sigue marcada', (tester) async {
      await pump(tester, extraction: extraccion(confidence: 0.45));
      expect(find.byIcon(Icons.warning_amber_outlined), findsNWidgets(2));
    });
  });

  group('corregir el total antes de guardar', () {
    testWidgets('el total es editable y recalcula el cuadre', (tester) async {
      final container = await pump(tester);
      expect(find.text('El total cuadra'), findsOneWidget);

      await tester.tap(find.text('Total del ticket'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '6,00');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      final draft = container.read(reviewDraftProvider)!;
      expect(draft.grandTotal, const Money(600));
      // Cambiar el total NO toca los productos: no se inventa una línea de
      // ajuste para que cuadre.
      expect(draft.lines, hasLength(2));
      expect(draft.computedTotal, const Money(500));
      expect(draft.balanced, isFalse);
      expect(find.textContaining('Descuadre'), findsOneWidget);
    });
  });

  group('precio unitario obsoleto', () {
    test('cambiar la cantidad retira el unitario que ya no se sostiene', () {
      // El unitario es informativo; el reparto usa total + cantidad. Tras
      // cambiar la cantidad, el 1,60 del OCR ya no describe nada.
      const original = DraftLine(
        name: 'LECHE',
        quantityMilli: 2000,
        unitPrice: Money(160),
        totalPrice: Money(320),
      );
      expect(
        unitPriceAfterEdit(
          original,
          quantityMilli: 5000,
          total: const Money(320),
          typed: const Money(160),
        ),
        isNull,
      );
    });

    test('cambiar el total también lo retira', () {
      const original = DraftLine(
        name: 'LECHE',
        quantityMilli: 2000,
        unitPrice: Money(160),
        totalPrice: Money(320),
      );
      expect(
        unitPriceAfterEdit(
          original,
          quantityMilli: 2000,
          total: const Money(400),
          typed: const Money(160),
        ),
        isNull,
      );
    });

    test('escribirlo a mano manda sobre todo lo demás', () {
      const original = DraftLine(
        name: 'LECHE',
        quantityMilli: 2000,
        unitPrice: Money(160),
        totalPrice: Money(320),
      );
      expect(
        unitPriceAfterEdit(
          original,
          quantityMilli: 5000,
          total: const Money(575),
          typed: const Money(115),
        ),
        const Money(115),
      );
    });

    test('sin tocar cantidad ni total, se conserva', () {
      const original = DraftLine(
        name: 'LECHE',
        quantityMilli: 2000,
        unitPrice: Money(160),
        totalPrice: Money(320),
      );
      expect(
        unitPriceAfterEdit(
          original,
          quantityMilli: 2000,
          total: const Money(320),
          typed: const Money(160),
        ),
        const Money(160),
      );
    });
  });

  group('la IA no pisa el trabajo manual en silencio', () {
    test('un borrador recién extraído no está editado', () {
      final container = ProviderContainer(
        overrides: [currentUserIdProvider.overrideWithValue('u')],
      );
      addTearDown(container.dispose);
      container.read(reviewDraftProvider.notifier).loadFrom(extraccion());
      expect(container.read(reviewDraftProvider)!.manuallyEdited, isFalse);
    });

    test('cualquier corrección lo marca', () {
      final container = ProviderContainer(
        overrides: [currentUserIdProvider.overrideWithValue('u')],
      );
      addTearDown(container.dispose);
      final notifier = container.read(reviewDraftProvider.notifier);
      notifier.loadFrom(extraccion());
      notifier.updateMerchant('Family Cash');
      expect(container.read(reviewDraftProvider)!.manuallyEdited, isTrue);
    });

    test('y una revisión de IA vuelve a dejarlo en limpio', () {
      final container = ProviderContainer(
        overrides: [currentUserIdProvider.overrideWithValue('u')],
      );
      addTearDown(container.dispose);
      final notifier = container.read(reviewDraftProvider.notifier);
      notifier.loadFrom(extraccion());
      notifier.updateGrandTotal(const Money(900));
      expect(container.read(reviewDraftProvider)!.manuallyEdited, isTrue);

      notifier.loadFrom(extraccion()); // resultado de IA
      expect(container.read(reviewDraftProvider)!.manuallyEdited, isFalse);
    });

    testWidgets('con cambios manuales pide confirmación antes de sustituir', (
      tester,
    ) async {
      final container = await pump(tester, aiConfigured: true);
      container
          .read(reviewDraftProvider.notifier)
          .updateMerchant('Family Cash');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Analizar con IA'));
      await tester.pumpAndSettle();

      expect(find.text('¿Revisar de nuevo con IA?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      // Cancelar deja el borrador exactamente como estaba.
      expect(container.read(reviewDraftProvider)!.merchantName, 'Family Cash');
    });

    testWidgets('sin cambios manuales no molesta con la confirmación', (
      tester,
    ) async {
      await pump(tester, aiConfigured: true);
      await tester.tap(find.text('Analizar con IA'));
      await tester.pumpAndSettle();
      expect(find.text('¿Revisar de nuevo con IA?'), findsNothing);
    });
  });

  group('sin la foto original', () {
    testWidgets('no se presenta como una revisión visual', (tester) async {
      await pump(tester, imagePath: null, aiConfigured: true);
      expect(find.textContaining('Sin la foto original'), findsOneWidget);
    });

    testWidgets('con la foto no se dice nada', (tester) async {
      await pump(tester, aiConfigured: true);
      expect(find.textContaining('Sin la foto original'), findsNothing);
    });
  });

  group('round-trip: lo corregido llega al ticket guardado', () {
    test(
      'la cantidad corregida genera las unidades correctas (A10/A19)',
      () async {
        // El caso real: 5 unidades a 1,15 €. Si se guarda cantidad 1, el gasto
        // nace con UNA unidad repartible de 5,75 € y el reparto por unidades
        // deja de ser posible.
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreSessionRepository(
          firestore: firestore,
          uid: () => 'owner',
          shareCodeFactory: () => 'TEST-CODE-1234567890',
        );
        final container = ProviderContainer(
          overrides: [currentUserIdProvider.overrideWithValue('owner')],
        );
        addTearDown(container.dispose);
        final notifier = container.read(reviewDraftProvider.notifier);
        notifier.loadFrom(
          ReceiptExtraction(
            engine: 'mlkit',
            merchantName: const Extracted('t familycash', 0.6),
            lines: const [
              ExtractedLine(
                name: '1,15 MACARRON ROMERO 1 KG',
                totalPrice: Money(575),
                confidence: 0.45,
              ),
            ],
            grandTotal: const Extracted(Money(575), 0.92),
          ),
        );
        // El usuario arregla lo que el OCR no supo leer.
        notifier.updateMerchant('Family Cash');
        notifier.updateLine(
          0,
          const DraftLine(
            name: 'MACARRON ROMERO 1 KG',
            quantityMilli: 5000,
            unitPrice: Money(115),
            totalPrice: Money(575),
          ),
        );

        final draft = container.read(reviewDraftProvider)!;
        final created = await repo.createSession(
          NewSessionInput(
            name: 'Compra',
            splitModeDefault: SplitMode.byItem,
            participantNames: const ['Yo', 'Alba'],
            participantUids: const ['owner', 'uid-alba'],
            participantManualIds: const ['', ''],
            payerIndex: 0,
            spaceId: 'g1',
            spaceName: 'Piso',
            paymentMethodsSnapshot: const {},
            ticket: ticketInputFromDraft(draft, fallbackName: 'Compra'),
          ),
        );

        final ticket = await firestore.doc(created.ticketPath).get();
        expect((ticket.data()!['merchant'] as Map)['name'], 'Family Cash');
        expect(ticket.data()!['grandTotal'], 575);

        final lines = await firestore
            .collection('${created.ticketPath}/lines')
            .get();
        final line = lines.docs.single.data();
        expect(line['name'], 'MACARRON ROMERO 1 KG');
        expect(line['quantityMilli'], 5000);
        expect(line['unitPrice'], 115);
        expect(line['totalPrice'], 575);
        // Cinco unidades repartibles, no una.
        expect((line['unitIds'] as List), hasLength(5));
      },
    );
  });
}
