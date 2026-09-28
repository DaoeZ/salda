import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/spaces/data/spaces_repository.dart';
import 'package:salda_mobile/features/spaces/domain/space_models.dart';
import 'package:salda_mobile/features/spaces/presentation/space_link_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

class _HoldingRotateRepository extends SpacesRepository {
  _HoldingRotateRepository({required super.firestore})
    : super(uid: () => 'owner', isFullAccount: () => true);

  final gate = Completer<SpaceJoinLink>();
  var rotations = 0;

  @override
  Future<SpaceJoinLink> rotateJoinLink(
    String spaceId,
    String spaceName, {
    String? previousToken,
    JoinLinkLifetime lifetime = JoinLinkLifetime.never,
  }) {
    rotations++;
    return gate.future;
  }
}

void main() {
  testWidgets('cached link stays non-mutating while its space is loading', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final link = SpaceJoinLink(
      token: 'token',
      spaceId: 'group',
      spaceName: 'Piso',
      createdByUid: 'owner',
      revoked: false,
    );
    final container = ProviderContainer(
      overrides: loggedInOverrides(firestore: firestore)
        ..addAll([
          spaceProvider('group').overrideWithValue(const AsyncLoading()),
          spaceJoinLinkProvider('group').overrideWithValue(AsyncData(link)),
        ]),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SpaceLinkScreen(spaceId: 'group'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Crear enlace'), findsNothing);
    expect(find.text('Generar un enlace nuevo'), findsNothing);
    expect(find.text('Revocar enlace'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('pending rotate is serialized to one repository call', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final repository = _HoldingRotateRepository(firestore: firestore);
    final link = SpaceJoinLink(
      token: 'token',
      spaceId: 'group',
      spaceName: 'Piso',
      createdByUid: 'owner',
      revoked: false,
    );
    final container = ProviderContainer(
      overrides:
          loggedInOverrides(firestore: firestore, spacesRepository: repository)
            ..addAll([
              spaceProvider('group').overrideWithValue(
                const AsyncData(
                  Space(
                    id: 'group',
                    name: 'Piso',
                    ownerUid: 'owner',
                    status: SpaceStatus.active,
                  ),
                ),
              ),
              spaceJoinLinkProvider('group').overrideWithValue(AsyncData(link)),
            ]),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SpaceLinkScreen(spaceId: 'group'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Generar un enlace nuevo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pump();
    expect(repository.rotations, 1);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Generar un enlace nuevo'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Generar un enlace nuevo'));
    await tester.pump();
    expect(repository.rotations, 1);

    repository.gate.complete(link);
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Generar un enlace nuevo'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('rotate stays busy when its live link disappears', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final repository = _HoldingRotateRepository(firestore: firestore);
    final links = StreamController<SpaceJoinLink?>.broadcast();
    final link = SpaceJoinLink(
      token: 'token',
      spaceId: 'group',
      spaceName: 'Piso',
      createdByUid: 'owner',
      revoked: false,
    );
    final container = ProviderContainer(
      overrides:
          loggedInOverrides(
            firestore: firestore,
            spacesRepository: repository,
          )..addAll([
            spaceProvider('group').overrideWithValue(
              const AsyncData(
                Space(
                  id: 'group',
                  name: 'Piso',
                  ownerUid: 'owner',
                  status: SpaceStatus.active,
                ),
              ),
            ),
            spaceJoinLinkProvider('group').overrideWith((ref) => links.stream),
          ]),
    );
    addTearDown(links.close);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SpaceLinkScreen(spaceId: 'group'),
        ),
      ),
    );
    links.add(link);
    await tester.pump();

    await tester.tap(find.text('Generar un enlace nuevo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pump();
    expect(repository.rotations, 1);

    links.add(null);
    await tester.pump();
    final create = find.widgetWithText(FilledButton, 'Crear enlace');
    expect(create, findsOneWidget);
    expect(tester.widget<FilledButton>(create).onPressed, isNull);
    await tester.tap(find.text('Crear enlace'));
    await tester.pump();
    expect(repository.rotations, 1);

    repository.gate.completeError(StateError('rotate failed'));
    await tester.pump();
    expect(
      find.text('No se pudo completar la acción. Inténtalo de nuevo.'),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(create).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
