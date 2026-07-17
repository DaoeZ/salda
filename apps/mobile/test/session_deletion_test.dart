import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:salda_mobile/core/theme/app_theme.dart';
import 'package:salda_mobile/features/sessions/data/firestore_session_repository.dart';
import 'package:salda_mobile/features/sessions/presentation/session_detail_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

void main() {
  testWidgets('eliminar navega a una ruta válida y detiene el loader', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _seedSession(firestore);
    await _pumpDetail(tester, firestore: firestore);

    await _confirmDelete(tester);

    expect(find.text('Inicio válido'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect((await firestore.doc('sessions/s1').get()).exists, isFalse);
  });

  testWidgets('un fallo libera el estado y muestra un error comprensible', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _seedSession(firestore);
    final repository = _ThrowingDeleteRepository(firestore);
    await _pumpDetail(tester, firestore: firestore, repository: repository);

    await _confirmDelete(tester);

    expect(repository.deleteCalls, 1);
    expect(find.textContaining('No se ha podido eliminar'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
  });

  testWidgets('si otro dispositivo elimina el documento abandona la vista', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _seedSession(firestore);
    await _pumpDetail(tester, firestore: firestore);

    await firestore.doc('sessions/s1').delete();
    await tester.pumpAndSettle();

    expect(find.text('Inicio válido'), findsOneWidget);
  });

  testWidgets('no actualiza un widget desmontado durante la eliminación', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _seedSession(firestore);
    final repository = _DeferredDeleteRepository(firestore);
    final router = await _pumpDetail(
      tester,
      firestore: firestore,
      repository: repository,
    );

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pump();
    router.go('/home');
    await tester.pumpAndSettle();
    repository.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repository.deleteCalls, 1);
  });
}

Future<GoRouter> _pumpDetail(
  WidgetTester tester, {
  required FakeFirebaseFirestore firestore,
  FirestoreSessionRepository? repository,
}) async {
  final router = GoRouter(
    initialLocation: '/session',
    routes: [
      GoRoute(
        path: '/session',
        builder: (_, _) => const SessionDetailScreen(sessionId: 's1'),
      ),
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(body: Text('Inicio válido')),
      ),
    ],
  );
  addTearDown(router.dispose);
  final effectiveRepository =
      repository ??
      FirestoreSessionRepository(
        firestore: firestore,
        uid: () => 'owner',
        shareCodeFactory: () => 'TEST-CODE-1234567890',
      );
  await tester.pumpWidget(
    ProviderScope(
      overrides: loggedInOverrides(
        firestore: firestore,
        sessionRepository: effectiveRepository,
      ),
      child: MaterialApp.router(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _confirmDelete(WidgetTester tester) async {
  await tester.tap(find.byType(PopupMenuButton<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Eliminar'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continuar'));
  await tester.pumpAndSettle();
}

Future<void> _seedSession(FakeFirebaseFirestore firestore) =>
    firestore.doc('sessions/s1').set({
      'ownerUid': 'owner',
      'name': 'Cuenta de prueba',
      'kind': 'single',
      'status': 'open',
      'shareCode': 'TEST-CODE-1234567890',
      'splitModeDefault': 'equal',
      'ownerParticipantId': 'p0',
      'participantsCount': 1,
      'pendingSettlements': 0,
      'totals': {
        'grandTotal': 0,
        'settlementRequired': 0,
        'settledConfirmed': 0,
        'settledMarked': 0,
      },
      'balances': <String, Object?>{},
    });

class _ThrowingDeleteRepository extends FirestoreSessionRepository {
  _ThrowingDeleteRepository(FakeFirebaseFirestore firestore)
    : super(
        firestore: firestore,
        uid: () => 'owner',
        shareCodeFactory: () => 'TEST-CODE-1234567890',
      );

  int deleteCalls = 0;

  @override
  Future<void> deleteSession(String sessionId) async {
    deleteCalls++;
    throw Exception('network');
  }
}

class _DeferredDeleteRepository extends FirestoreSessionRepository {
  _DeferredDeleteRepository(FakeFirebaseFirestore firestore)
    : super(
        firestore: firestore,
        uid: () => 'owner',
        shareCodeFactory: () => 'TEST-CODE-1234567890',
      );

  final _completer = Completer<void>();
  int deleteCalls = 0;

  @override
  Future<void> deleteSession(String sessionId) {
    deleteCalls++;
    return _completer.future;
  }

  void complete() => _completer.complete();
}
