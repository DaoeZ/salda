import 'dart:math';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/auth/data/auth_repository.dart';
import 'package:salda_mobile/features/profile/data/profile_repository.dart';
import 'package:salda_mobile/features/profile/presentation/profile_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required FakeFirebaseFirestore firestore,
  String uid = 'uid-edgar',
  String displayName = 'Edgar Cantera',
}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      currentAppUserProvider.overrideWithValue(
        AppUser(uid: uid, displayName: displayName),
      ),
      currentUserIdProvider.overrideWithValue(uid),
      profileRepositoryProvider.overrideWithValue(
        ProfileRepository(
          firestore: firestore,
          uid: () => uid,
          random: Random(7),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProfileScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('al crear propone un username natural y editable', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _pump(tester, firestore: firestore);

    // La propuesta automática precarga el campo con la base natural.
    expect(find.widgetWithText(TextFormField, 'edgar'), findsOneWidget);
    expect(find.text('Edgar Cantera'), findsOneWidget);
    expect(find.text('Disponible'), findsOneWidget);
  });

  testWidgets('si la base está ocupada propone una variante natural', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await ProfileRepository(
      firestore: firestore,
      uid: () => 'uid-otro',
    ).createProfile(displayName: 'Otro', username: 'edgar');
    await _pump(tester, firestore: firestore);

    final field = tester.widget<TextFormField>(
      find.byWidgetPredicate(
        (w) => w is TextFormField && w.controller?.text.isNotEmpty == true
            && w.controller!.text != 'Edgar Cantera',
      ),
    );
    expect(field.controller!.text, isNot('edgar'));
    expect(
      field.controller!.text,
      anyOf(matches(r'^edgar\d{2,4}$'), 'edgar_cantera'),
    );
  });

  testWidgets('guardar crea perfil + claim y un username ocupado avisa', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _pump(tester, firestore: firestore);
    await tester.tap(find.text('Crear perfil'));
    await tester.pumpAndSettle();

    expect(find.text('Perfil guardado'), findsOneWidget);
    expect(
      (await firestore.doc('profiles/uid-edgar').get()).data()!['username'],
      'edgar',
    );
    expect((await firestore.doc('usernames/edgar').get()).exists, true);
  });

  testWidgets('un username inválido muestra el motivo y bloquea guardar', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _pump(tester, firestore: firestore);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'edgar'),
      'ed',
    );
    await tester.pumpAndSettle();

    expect(find.text('Mínimo 3 caracteres'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('en edición precarga el perfil y permite cambiar el username', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await ProfileRepository(
      firestore: firestore,
      uid: () => 'uid-edgar',
    ).createProfile(displayName: 'Edgar Cantera', username: 'edgar');
    await _pump(tester, firestore: firestore);

    expect(find.text('Perfil público'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'edgar'),
      'edgar_cantera',
    );
    // Debounce de disponibilidad (400 ms) antes de poder guardar.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect((await firestore.doc('usernames/edgar').get()).exists, false);
    expect(
      (await firestore.doc('usernames/edgar_cantera').get()).data()!['uid'],
      'uid-edgar',
    );
  });
}
