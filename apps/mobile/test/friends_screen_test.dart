import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/auth/data/auth_repository.dart';
import 'package:salda_mobile/features/friends/data/friendship_repository.dart';
import 'package:salda_mobile/features/friends/domain/friendship.dart';
import 'package:salda_mobile/features/friends/presentation/friends_screen.dart';
import 'package:salda_mobile/features/friends/presentation/public_profile_screen.dart';
import 'package:salda_mobile/features/profile/data/profile_repository.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

const _ownerUid = 'uid-owner';
const _otherUid = 'uid-other';

Future<void> _seedProfile(
  FakeFirebaseFirestore firestore,
  String uid, {
  required String displayName,
  required String username,
}) => firestore.doc('profiles/$uid').set({
  'displayName': displayName,
  'displayNameLower': displayName.toLowerCase(),
  'username': username,
  'createdAt': DateTime(2026),
  'updatedAt': DateTime(2026),
  'schemaVersion': 1,
});

Future<void> _seedRelationship(
  FakeFirebaseFirestore firestore, {
  required String requesterUid,
  required String receiverUid,
  String status = 'pending',
}) async {
  final id = canonicalFriendshipId(requesterUid, receiverUid);
  await firestore.doc('friendships/$id').set({
    'memberUids': canonicalFriendshipMembers(requesterUid, receiverUid),
    'requesterUid': requesterUid,
    'receiverUid': receiverUid,
    'status': status,
    'createdAt': DateTime(2026),
    'updatedAt': DateTime(2026),
    if (status == 'friends') 'acceptedAt': DateTime(2026),
    'schemaVersion': 1,
  });
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required FakeFirebaseFirestore firestore,
  required Widget child,
  Size size = const Size(390, 844),
  double textScaleFactor = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      currentAppUserProvider.overrideWithValue(
        const AppUser(uid: _ownerUid, emailVerified: true),
      ),
      currentUserIdProvider.overrideWithValue(_ownerUid),
      profileRepositoryProvider.overrideWithValue(
        ProfileRepository(firestore: firestore, uid: () => _ownerUid),
      ),
      friendshipRepositoryProvider.overrideWithValue(
        FriendshipRepository(
          firestore: firestore,
          uid: () => _ownerUid,
          isFullAccount: () => true,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
          child: widget!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('amistades exige un perfil público propio', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await _pump(tester, firestore: firestore, child: const FriendsScreen());

    expect(
      find.text('Completa tu perfil antes de usar las amistades'),
      findsOneWidget,
    );
    expect(find.text('Crear perfil'), findsOneWidget);
  });

  testWidgets('una solicitud recibida se acepta desde su pestaña', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _seedProfile(
      firestore,
      _ownerUid,
      displayName: 'Edgar',
      username: 'edgar',
    );
    await _seedProfile(
      firestore,
      _otherUid,
      displayName: 'Alba',
      username: 'alba',
    );
    await _seedRelationship(
      firestore,
      requesterUid: _otherUid,
      receiverUid: _ownerUid,
    );
    await _pump(tester, firestore: firestore, child: const FriendsScreen());

    await tester.tap(find.text('Recibidas'));
    await tester.pumpAndSettle();
    expect(find.text('Alba'), findsOneWidget);
    expect(find.text('Aceptar'), findsOneWidget);
    expect(find.text('Rechazar'), findsOneWidget);

    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();
    final id = canonicalFriendshipId(_ownerUid, _otherUid);
    expect(
      (await firestore.doc('friendships/$id').get()).data()!['status'],
      'friends',
    );
  });

  testWidgets('el perfil público crea y cancela una solicitud sin optimismo', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _seedProfile(
      firestore,
      _ownerUid,
      displayName: 'Edgar',
      username: 'edgar',
    );
    await _seedProfile(
      firestore,
      _otherUid,
      displayName: 'Alba',
      username: 'alba',
    );
    await _pump(
      tester,
      firestore: firestore,
      child: const PublicProfileScreen(profileUid: _otherUid),
    );

    expect(find.text('Añadir amigo'), findsOneWidget);
    await tester.tap(find.text('Añadir amigo'));
    await tester.pumpAndSettle();
    // Confirmación doble: el SnackBar de éxito y el botón de estado.
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('Solicitud enviada'),
      ),
      findsOneWidget,
    );
    expect(find.text('Solicitud enviada'), findsNWidgets(2));
    expect(find.text('Cancelar solicitud'), findsOneWidget);

    await tester.tap(find.text('Cancelar solicitud'));
    await tester.pumpAndSettle();
    expect(find.text('Añadir amigo'), findsOneWidget);
    expect((await firestore.collection('friendships').get()).docs, isEmpty);
  });

  testWidgets('eliminar amistad confirma y no toca datos económicos', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _seedProfile(
      firestore,
      _ownerUid,
      displayName: 'Edgar',
      username: 'edgar',
    );
    await _seedProfile(
      firestore,
      _otherUid,
      displayName: 'Alba',
      username: 'alba',
    );
    await _seedRelationship(
      firestore,
      requesterUid: _ownerUid,
      receiverUid: _otherUid,
      status: 'friends',
    );
    await firestore.doc('sessions/economic-history').set({'untouched': true});
    await _pump(
      tester,
      firestore: firestore,
      child: const PublicProfileScreen(profileUid: _otherUid),
    );

    expect(find.text('Amigos'), findsOneWidget);
    await tester.tap(find.text('Eliminar amistad'));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar esta amistad?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar amistad'));
    await tester.pumpAndSettle();

    expect((await firestore.collection('friendships').get()).docs, isEmpty);
    expect(
      (await firestore.doc('sessions/economic-history').get()).exists,
      true,
    );
  });

  testWidgets('nombres largos y texto aumentado no provocan overflow', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _seedProfile(
      firestore,
      _ownerUid,
      displayName: 'Edgar',
      username: 'edgar',
    );
    await _seedProfile(
      firestore,
      _otherUid,
      displayName:
          'Nombre Extremadamente Largo Para Probar El Diseño Adaptativo',
      username: 'nombre_extraordinariamente_largo',
    );
    await _seedRelationship(
      firestore,
      requesterUid: _otherUid,
      receiverUid: _ownerUid,
    );
    await _pump(
      tester,
      firestore: firestore,
      child: const PublicProfileScreen(profileUid: _otherUid),
      size: const Size(320, 640),
      textScaleFactor: 1.5,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Aceptar'), findsOneWidget);
    expect(find.text('Rechazar'), findsOneWidget);
  });
}
