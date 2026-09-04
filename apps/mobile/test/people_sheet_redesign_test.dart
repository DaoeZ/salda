import 'package:domain/domain.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/core/theme/app_theme.dart';
import 'package:salda_mobile/core/ui/badges.dart';
import 'package:salda_mobile/core/ui/states.dart';
import 'package:salda_mobile/features/review/application/review_draft.dart';
import 'package:salda_mobile/features/sessions/presentation/people_sheet.dart';
import 'package:salda_mobile/features/spaces/data/spaces_repository.dart';
import 'package:salda_mobile/features/spaces/domain/space_models.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

/// La hoja de reparto es el paso donde se decide QUIÉN participa y QUIÉN
/// paga. Una persona sin cuenta tiene que verse igual que una con cuenta:
/// pesa lo mismo económicamente (ADR-033) y puede ser el pagador (BUG-6).
void main() {
  const yo = 'owner';
  late FakeFirebaseFirestore firestore;

  setUp(() => firestore = FakeFirebaseFirestore());

  Future<void> seedGrupo({int manuales = 1, int cuentas = 1}) async {
    await firestore.doc('spaces/g1').set({
      'name': 'Piso',
      'ownerUid': yo,
      'kind': 'group',
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/g1/members/$yo').set({'uid': yo});
    for (var i = 1; i < cuentas; i++) {
      await firestore.doc('spaces/g1/members/uid-$i').set({'uid': 'uid-$i'});
      await firestore.doc('profiles/uid-$i').set({'displayName': 'Ana$i'});
    }
    for (var i = 0; i < manuales; i++) {
      await firestore.doc('spaces/g1/manualParticipants/m$i').set({
        'manualId': 'm$i',
        'displayName': 'Pablo$i',
        'linkedUid': null,
        'createdByUid': yo,
        'schemaVersion': 1,
      });
    }
  }

  Future<void> pump(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: loggedInOverrides(firestore: firestore),
    );
    addTearDown(container.dispose);
    // La hoja necesita un draft y un contexto pendiente, igual que en el
    // flujo real de escaneo.
    container
        .read(reviewDraftProvider.notifier)
        .loadFrom(
          ReceiptExtraction(
            engine: 'mlkit',
            merchantName: const Extracted('Super', 1),
            lines: [
              const ExtractedLine(
                name: 'Pan',
                totalPrice: Money(200),
                confidence: 1,
                sourceText: 'Pan 2,00',
              ),
            ],
            grandTotal: const Extracted(Money(200), 1),
          ),
        );
    container
        .read(pendingSpaceLinkProvider.notifier)
        .set('g1', 'Piso', SpaceKind.group);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: brightness == Brightness.dark
              ? AppTheme.dark()
              : AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () =>
                      showPeopleSheet(context, suggestedName: 'Super'),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> cerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('cuenta y MANUAL se pintan igual, con el mismo avatar', (
    tester,
  ) async {
    await seedGrupo();
    await pump(tester);
    // Ambos aparecen (dos veces: en «quién participa» y en «quién paga»).
    expect(find.text('Edgar'), findsWidgets);
    expect(find.text('Pablo0'), findsWidgets);
    // El mismo componente de avatar para los dos: ninguno es de segunda.
    expect(find.byType(SaldaAvatar), findsWidgets);
    // La única diferencia es una etiqueta que EXPLICA la situación.
    expect(find.text('Sin cuenta'), findsWidgets);
    await cerrar(tester);
  });

  testWidgets('un MANUAL puede seleccionarse como pagador (BUG-6)', (
    tester,
  ) async {
    await seedGrupo();
    await pump(tester);
    final pagadorManual = find
        .descendant(of: find.byType(ListTile), matching: find.text('Pablo0'))
        .last;
    await tester.ensureVisible(pagadorManual);
    await tester.pumpAndSettle();
    await tester.tap(pagadorManual);
    await tester.pumpAndSettle();
    // Queda marcado: el radio del pagador pasa a seleccionado.
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('el modo de reparto explica qué hace cada opción', (
    tester,
  ) async {
    await seedGrupo();
    await pump(tester);
    expect(find.text('Cómo se reparte'.toUpperCase()), findsOneWidget);
    expect(find.textContaining('se divide a partes iguales'), findsOneWidget);
    await tester.tap(find.text('Cada uno lo suyo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('lo no reclamado'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('con una sola persona: botón bloqueado y motivo explícito', (
    tester,
  ) async {
    await seedGrupo(manuales: 0);
    await pump(tester);
    final boton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Crear y compartir'),
    );
    expect(boton.onPressed, isNull);
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.textContaining('al menos dos personas'), findsOneWidget);
    await cerrar(tester);
  });

  testWidgets('con dos personas el botón se habilita', (tester) async {
    await seedGrupo();
    await pump(tester);
    final boton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Crear y compartir'),
    );
    expect(boton.onPressed, isNotNull);
    expect(find.byType(EmptyState), findsNothing);
    await cerrar(tester);
  });

  testWidgets('un MANUAL vinculado a un miembro no se duplica', (tester) async {
    await seedGrupo(cuentas: 2);
    await firestore.doc('spaces/g1/manualParticipants/m0').update({
      'linkedUid': 'uid-1',
    });
    await pump(tester);
    // Pablo0 ya no se lista: su cuenta (Ana1) lo representa.
    expect(find.text('Pablo0'), findsNothing);
    expect(find.text('Ana1'), findsWidgets);
    await cerrar(tester);
  });

  testWidgets('en oscuro se comporta igual', (tester) async {
    await seedGrupo();
    await pump(tester, brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
    expect(find.text('Sin cuenta'), findsWidgets);
    await cerrar(tester);
  });
}
