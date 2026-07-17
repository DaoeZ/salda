import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/core/theme/app_theme.dart';
import 'package:salda_mobile/features/sessions/presentation/session_detail_screen.dart';
import 'package:salda_mobile/features/sessions/presentation/share_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

void main() {
  testWidgets(
    'detalle y cuentas no desbordan con pantalla pequeña, texto grande y nombres largos',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final overflows = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed by')) {
          overflows.add(details);
        } else {
          previous?.call(details);
        }
      };
      addTearDown(() => FlutterError.onError = previous);

      final firestore = FakeFirebaseFirestore();
      await _seedLongSession(firestore);
      await tester.pumpWidget(
        _testApp(firestore, const SessionDetailScreen(sessionId: 's1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cuentas'));
      await tester.pumpAndSettle();

      expect(overflows, isEmpty);
    },
  );

  testWidgets('compartir se adapta a ancho pequeño y texto aumentado', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final overflows = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed by')) {
        overflows.add(details);
      } else {
        previous?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = previous);

    final firestore = FakeFirebaseFirestore();
    await _seedLongSession(firestore);
    await tester.pumpWidget(
      _testApp(firestore, const ShareScreen(sessionId: 's1')),
    );
    await tester.pumpAndSettle();

    expect(overflows, isEmpty);
  });
}

Widget _testApp(FakeFirebaseFirestore firestore, Widget home) => ProviderScope(
  overrides: loggedInOverrides(firestore: firestore),
  child: MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) {
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(textScaler: const TextScaler.linear(1.5)),
        child: child!,
      );
    },
    home: home,
  ),
);

Future<void> _seedLongSession(FakeFirebaseFirestore firestore) async {
  await firestore.doc('sessions/s1').set({
    'ownerUid': 'owner',
    'name': 'Viaje extraordinariamente largo por toda la península',
    'kind': 'single',
    'status': 'open',
    'shareCode': 'TEST-CODE-1234567890',
    'splitModeDefault': 'byItem',
    'ownerParticipantId': 'p0',
    'participantsCount': 2,
    'pendingSettlements': 1,
    'totals': {
      'grandTotal': 99999999,
      'settlementRequired': 49999999,
      'settledConfirmed': 0,
      'settledMarked': 499999,
    },
    'balances': {
      'p0': {
        'paid': 99999999,
        'consumed': 50000000,
        'net': 49999999,
        'outstanding': 49999999,
      },
      'p1': {
        'paid': 0,
        'consumed': 49999999,
        'net': -49999999,
        'outstanding': -49999999,
      },
    },
  });
  await firestore.doc('sessions/s1/participants/p0').set({
    'name': 'Edgar con un nombre compuesto extremadamente largo',
    'isOwner': true,
    'order': 0,
    'active': true,
  });
  await firestore.doc('sessions/s1/participants/p1').set({
    'name': 'Alba con apellidos extraordinariamente extensos',
    'isOwner': false,
    'order': 1,
    'active': true,
    'claimedByDevice': 'guest-device',
  });
  await firestore.doc('sessions/s1/settlements/pending_p1_p0').set({
    'from': 'p1',
    'to': 'p0',
    'amount': 49999999,
    'state': 'marked',
  });
  await firestore.doc('sessions/s1/accounts/a1').set({
    'name': 'Supermercado con una denominación comercial larguísima',
    'category': 'shopping',
    'grandTotal': 99999999,
    'order': 0,
  });
  await firestore.doc('sessions/s1/accounts/a1/tickets/t1').set({
    'kind': 'receipt',
    'merchant': {
      'name': 'Establecimiento de alimentación con nombre muy extenso',
    },
    'paidByParticipantId': 'p0',
    'grandTotal': 99999999,
    'date': '2026-07-17',
    'order': 0,
  });
}
