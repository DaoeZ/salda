import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/core/theme/app_theme.dart';
import 'package:salda_mobile/features/sessions/presentation/session_detail_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

void main() {
  testWidgets(
    'el estado actual reacciona a recompute sin recargar la pantalla',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      addTearDown(tester.view.resetPhysicalSize);
      final firestore = FakeFirebaseFirestore();
      await firestore.doc('sessions/s1').set({
        'ownerUid': 'owner',
        'name': 'Cena',
        'kind': 'single',
        'status': 'open',
        'shareCode': 'TEST-CODE-1234567890',
        'splitModeDefault': 'equal',
        'ownerParticipantId': 'p0',
        'participantsCount': 2,
        'pendingSettlements': 1,
        'totals': {
          'grandTotal': 3000,
          'settlementRequired': 1000,
          'settledConfirmed': 0,
          'settledMarked': 0,
        },
        'balances': {
          'p0': {
            'paid': 3000,
            'consumed': 2000,
            'net': 1000,
            'outstanding': 1000,
          },
          'p1': {
            'paid': 0,
            'consumed': 1000,
            'net': -1000,
            'outstanding': -1000,
          },
        },
      });
      await firestore.doc('sessions/s1/participants/p0').set({
        'name': 'Edgar',
        'isOwner': true,
        'order': 0,
        'active': true,
      });
      await firestore.doc('sessions/s1/participants/p1').set({
        'name': 'Julen',
        'isOwner': false,
        'order': 1,
        'active': true,
      });
      await firestore.doc('sessions/s1/settlements/pending_p1_p0').set({
        'from': 'p1',
        'to': 'p0',
        'amount': 1000,
        'state': 'pending',
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: loggedInOverrides(firestore: firestore),
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SessionDetailScreen(sessionId: 's1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Quedan 10,00 € por liquidar'), findsOneWidget);
      expect(find.text('Pendiente de cobrar'), findsOneWidget);

      // Simula el batch autoritativo que publica recompute tras confirmar.
      await firestore.doc('sessions/s1').update({
        'pendingSettlements': 0,
        'totals': {
          'grandTotal': 3000,
          'settlementRequired': 1000,
          'settledConfirmed': 1000,
          'settledMarked': 0,
        },
        'balances': {
          'p0': {'paid': 3000, 'consumed': 2000, 'net': 1000, 'outstanding': 0},
          'p1': {'paid': 0, 'consumed': 1000, 'net': -1000, 'outstanding': 0},
        },
      });
      await firestore.doc('sessions/s1/settlements/pending_p1_p0').update({
        'state': 'confirmed',
      });
      await tester.pumpAndSettle();

      expect(find.text('Saldado'), findsWidgets);
      expect(find.text('Pendiente de cobrar'), findsNothing);
      // El histórico conserva el adelanto original aunque el saldo actual sea 0.
      expect(find.textContaining('pagó 30,00'), findsOneWidget);
      expect(find.text('+10,00 €'), findsOneWidget);
    },
  );
}
