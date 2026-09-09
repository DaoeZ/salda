import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/auth/data/auth_repository.dart';
import 'package:salda_mobile/features/review/application/review_draft.dart';
import 'package:salda_mobile/features/review/presentation/review_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

ReceiptExtraction _extraction({int grandTotal = 500, double confidence = 0.9}) {
  return ReceiptExtraction(
    engine: 'mlkit',
    merchantName: const Extracted('Mercadona', 1.0),
    date: const Extracted('2026-07-09', 0.95),
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
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  ReceiptExtraction extraction,
) async {
  // Pantalla alta: la ListView es perezosa y el pie debe estar construido.
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWithValue('test-user'),
      currentAppUserProvider.overrideWithValue(const AppUser(uid: 'test-user')),
    ],
  );
  addTearDown(container.dispose);
  container.read(reviewDraftProvider.notifier).loadFrom(extraction);
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

void main() {
  testWidgets('muestra líneas, totales y estado de cuadre correcto', (
    tester,
  ) async {
    await _pump(tester, _extraction()); // 180+320 == 500: cuadra
    expect(find.text('GAZPACHO'), findsOneWidget);
    expect(find.text('LECHE'), findsOneWidget);
    expect(find.text('Mercadona'), findsOneWidget);
    // A15: el estado verde habla SOLO de aritmética. Nunca certifica que el
    // ticket esté bien leído.
    expect(find.text('El total cuadra'), findsOneWidget);
    expect(find.text('El ticket cuadra'), findsNothing);
    expect(find.textContaining('Revisa el establecimiento'), findsOneWidget);
    // Y revisar con IA sigue ofreciéndose: cuadrar no es estar bien leído.
    expect(find.text('Analizar con IA'), findsOneWidget);
  });

  testWidgets('descuadre: banner con repetir foto y editar a mano', (
    tester,
  ) async {
    await _pump(tester, _extraction(grandTotal: 600)); // suma 500 ≠ 600
    expect(find.textContaining('Descuadre'), findsOneWidget);
    expect(find.text('Repetir foto'), findsOneWidget);
    expect(find.text('Editar a mano'), findsOneWidget);
    final aiButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Analizar con IA'),
        matching: find.byType(FilledButton),
      ),
    );
    // Sin proveedor configurado sigue deshabilitada (DC-13).
    expect(aiButton.onPressed, isNull);
  });

  testWidgets('editar una línea recalcula el cuadre en vivo', (tester) async {
    final container = await _pump(tester, _extraction(grandTotal: 600));
    expect(find.textContaining('Descuadre'), findsOneWidget);

    // El usuario corrige el importe de la primera línea: 1,80 → 2,80.
    container
        .read(reviewDraftProvider.notifier)
        .updateLine(
          0,
          const DraftLine(name: 'GAZPACHO', totalPrice: Money(280)),
        );
    await tester.pumpAndSettle();

    expect(find.text('El total cuadra'), findsOneWidget);
    expect(find.textContaining('Descuadre'), findsNothing);
  });
}
