import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/chat/data/chat_repository.dart';
import 'package:salda_mobile/features/chat/domain/chat_message.dart';
import 'package:salda_mobile/features/chat/presentation/chat_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

const _spaceId = 'sp1';
final _joinedAt = DateTime.utc(2026, 7, 1, 10);

Future<void> _seedMember(
  FakeFirebaseFirestore firestore, {
  String uid = 'owner',
  DateTime? joinedAt,
}) => firestore.doc('spaces/$_spaceId/members/$uid').set({
  'uid': uid,
  'joinedAt': Timestamp.fromDate(joinedAt ?? _joinedAt),
});

Future<void> _seedMessage(
  FakeFirebaseFirestore firestore,
  String id, {
  String authorUid = 'other',
  String text = 'Hola',
  required DateTime createdAt,
}) => firestore.doc('spaces/$_spaceId/messages/$id').set({
  'authorUid': authorUid,
  'text': text,
  'createdAt': Timestamp.fromDate(createdAt),
  'schemaVersion': 1,
});

Future<void> _seedSpace(
  FakeFirebaseFirestore firestore, {
  String status = 'active',
}) async {
  await firestore.doc('spaces/$_spaceId').set({
    'name': 'Viaje',
    'ownerUid': 'owner',
    'status': status,
    'kind': 'group',
    'createdAt': Timestamp.fromDate(_joinedAt),
    'updatedAt': Timestamp.fromDate(_joinedAt),
    'schemaVersion': 2,
  });
  await _seedMember(firestore);
}

void main() {
  group('ChatRepository', () {
    late FakeFirebaseFirestore firestore;
    late ChatRepository repository;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      repository = ChatRepository(firestore: firestore, uid: () => 'owner');
      await _seedMember(firestore);
    });

    test(
      'solo observa mensajes posteriores a joinedAt y los ordena para UI',
      () async {
        await _seedMessage(
          firestore,
          'before',
          createdAt: _joinedAt.subtract(const Duration(minutes: 1)),
        );
        await _seedMessage(
          firestore,
          'second',
          createdAt: _joinedAt.add(const Duration(hours: 2)),
        );
        await _seedMessage(
          firestore,
          'first',
          createdAt: _joinedAt.add(const Duration(hours: 1)),
        );

        final messages = await repository.watchFirstPage(_spaceId).first;

        expect(messages.map((message) => message.id), ['first', 'second']);
      },
    );

    test('pagina hacia atrás sin repetir la primera página', () async {
      for (var index = 0; index < 45; index++) {
        await _seedMessage(
          firestore,
          'm$index',
          createdAt: _joinedAt.add(Duration(minutes: index)),
        );
      }

      final first = await repository.watchFirstPage(_spaceId).first;
      final older = await repository.fetchOlder(
        _spaceId,
        first.first.createdAt!,
      );

      expect(first.length, ChatRepository.pageSize);
      expect(older.length, 5);
      expect(older.map((message) => message.id), [
        'm0',
        'm1',
        'm2',
        'm3',
        'm4',
      ]);
      expect(
        {
          ...first.map((message) => message.id),
        }.intersection({...older.map((message) => message.id)}),
        isEmpty,
      );
    });

    test('envía texto recortado con identidad y esquema canónicos', () async {
      final id = await repository.send(_spaceId, '  Hola, grupo  ');
      final data = (await firestore.doc('spaces/$_spaceId/messages/$id').get())
          .data()!;

      expect(data['authorUid'], 'owner');
      expect(data['text'], 'Hola, grupo');
      expect(data['schemaVersion'], 1);
      expect(data['createdAt'], isA<Timestamp>());
    });

    test('rechaza mensajes vacíos y superiores al límite', () async {
      await expectLater(
        repository.send(_spaceId, '   '),
        throwsA(
          isA<ChatFailure>().having(
            (failure) => failure.code,
            'code',
            ChatFailureCode.emptyMessage,
          ),
        ),
      );
      await expectLater(
        repository.send(_spaceId, 'x' * (ChatRepository.maxMessageLength + 1)),
        throwsA(
          isA<ChatFailure>().having(
            (failure) => failure.code,
            'code',
            ChatFailureCode.messageTooLong,
          ),
        ),
      );
    });

    test('falla de forma tipada si no existe la membresía', () async {
      final outsider = ChatRepository(
        firestore: firestore,
        uid: () => 'outsider',
      );
      await expectLater(
        outsider.watchFirstPage(_spaceId).first,
        throwsA(
          isA<ChatFailure>().having(
            (failure) => failure.code,
            'code',
            ChatFailureCode.notMember,
          ),
        ),
      );
    });

    test('retira un mensaje por id', () async {
      await _seedMessage(
        firestore,
        'mine',
        authorUid: 'owner',
        createdAt: _joinedAt,
      );

      await repository.delete(_spaceId, 'mine');

      expect(
        (await firestore.doc('spaces/$_spaceId/messages/mine').get()).exists,
        false,
      );
    });
  });

  group('ChatScreen', () {
    Future<FakeFirebaseFirestore> pump(
      WidgetTester tester, {
      FakeFirebaseFirestore? firestore,
      String status = 'active',
    }) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fake = firestore ?? FakeFirebaseFirestore();
      await _seedSpace(fake, status: status);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...loggedInOverrides(firestore: fake),
            chatRepositoryProvider.overrideWithValue(
              ChatRepository(firestore: fake, uid: () => 'owner'),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ChatScreen(spaceId: _spaceId),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return fake;
    }

    testWidgets('muestra estado vacío y permite enviar', (tester) async {
      final firestore = await pump(tester);
      expect(find.text('Todavía no hay mensajes'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Primer mensaje');
      await tester.pump();
      await tester.tap(find.byTooltip('Enviar mensaje'));
      await tester.pumpAndSettle();

      expect(find.text('Primer mensaje'), findsOneWidget);
      final snapshot = await firestore
          .collection('spaces/$_spaceId/messages')
          .get();
      expect(snapshot.docs.single.data()['authorUid'], 'owner');
    });

    testWidgets('renderiza mensajes propios y ajenos largos sin overflow', (
      tester,
    ) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.doc('profiles/other').set({
        'displayName': 'Una persona con un nombre especialmente largo',
        'displayNameLower': 'una persona con un nombre especialmente largo',
        'username': 'persona_larga',
        'createdAt': Timestamp.fromDate(_joinedAt),
        'updatedAt': Timestamp.fromDate(_joinedAt),
        'schemaVersion': 1,
      });
      await _seedMessage(
        firestore,
        'other',
        text:
            'Un mensaje ajeno suficientemente largo para ocupar varias líneas.',
        createdAt: _joinedAt.add(const Duration(minutes: 1)),
      );
      await _seedMessage(
        firestore,
        'mine',
        authorUid: 'owner',
        text: 'Mi respuesta',
        createdAt: _joinedAt.add(const Duration(minutes: 2)),
      );

      await pump(tester, firestore: firestore);

      expect(find.byType(ChatMessageBubble), findsNWidgets(2));
      expect(find.text('Mi respuesta'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un contexto archivado conserva lectura sin compositor', (
      tester,
    ) async {
      await pump(tester, status: 'archived');

      expect(find.textContaining('archivado'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip('Enviar mensaje'), findsNothing);
    });

    testWidgets('el autor confirma y elimina su propio mensaje', (
      tester,
    ) async {
      final firestore = FakeFirebaseFirestore();
      await _seedMessage(
        firestore,
        'mine',
        authorUid: 'owner',
        text: 'Retirable',
        createdAt: _joinedAt.add(const Duration(minutes: 1)),
      );
      await pump(tester, firestore: firestore);

      await tester.tap(find.byTooltip('Acciones del mensaje'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar mensaje'));
      await tester.pumpAndSettle();
      expect(find.text('Eliminar mensaje'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar mensaje'));
      await tester.pumpAndSettle();

      expect(find.text('Retirable'), findsNothing);
      expect(
        (await firestore.doc('spaces/$_spaceId/messages/mine').get()).exists,
        false,
      );
    });
  });
}
