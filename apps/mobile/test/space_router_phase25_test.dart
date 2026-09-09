import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/core/routing/router.dart';
import 'package:salda_mobile/features/auth/data/auth_repository.dart';
import 'package:salda_mobile/features/auth/data/guest_identity_repository.dart';
import 'package:salda_mobile/features/activity/presentation/activity_screen.dart';
import 'package:salda_mobile/features/activity/data/activity_repository.dart';
import 'package:salda_mobile/features/chat/presentation/chat_screen.dart';
import 'package:salda_mobile/features/chat/data/chat_repository.dart';
import 'package:salda_mobile/features/economy/data/economic_repository.dart';
import 'package:salda_mobile/features/economy/domain/economic_models.dart';
import 'package:salda_mobile/features/review/application/draft_store.dart';
import 'package:salda_mobile/features/spaces/data/manual_link_repository.dart';
import 'package:salda_mobile/features/spaces/data/spaces_repository.dart';
import 'package:salda_mobile/features/spaces/presentation/space_cover_content.dart';
import 'package:salda_mobile/features/spaces/presentation/space_detail_screen.dart';
import 'package:salda_mobile/features/spaces/presentation/space_link_screen.dart';
import 'package:salda_mobile/features/spaces/presentation/space_management_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

void main() {
  testWidgets('space cover siblings preserve all nested action paths', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.doc('spaces/group').set({
      'name': 'Piso',
      'ownerUid': 'owner',
      'kind': 'group',
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/group/members/owner').set({'uid': 'owner'});
    final container = ProviderContainer(
      overrides: loggedInOverrides(firestore: firestore)
        ..addAll([
          authStateProvider.overrideWithValue(
            const AsyncData(AppUser(uid: 'owner', displayName: 'Edgar')),
          ),
          mySpaceInvitesProvider.overrideWithValue(const AsyncData([])),
          myPendingManualLinksProvider.overrideWithValue(const AsyncData([])),
          savedDraftProvider.overrideWithValue(const AsyncData(null)),
          participantEconomicOverviewProvider.overrideWithValue(
            AsyncData(
              EconomicOverview.compute(
                viewerUid: 'owner',
                entries: const [],
                payments: const [],
              ),
            ),
          ),
          spaceActivityProvider('group').overrideWithValue(const AsyncData([])),
          spaceChatProvider('group').overrideWithValue(const AsyncData([])),
          spaceJoinLinkProvider(
            'group',
          ).overrideWithValue(const AsyncData(null)),
        ]),
    );
    final router = container.read(appRouterProvider);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
      router.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    Future<void> open(String path, Type type) async {
      router.go(path);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(router.state.uri.path, path);
      expect(find.byType(type), findsOneWidget);
    }

    await open('/home/spaces/group', SpaceDetailScreen);
    await open('/home/spaces/group/manage', SpaceManagementScreen);
    await open('/home/spaces/group/tickets', SpaceTicketsScreen);
    await open('/home/spaces/group/balances', SpaceBalancesScreen);
    await open('/home/spaces/group/balances/ana', SpaceBalanceDetailScreen);
    await open('/home/spaces/group/chat', ChatScreen);
    await open('/home/spaces/group/link', SpaceLinkScreen);
    await open('/home/spaces/group/activity', ActivityScreen);
  });

  testWidgets('guest direct space chat is redirected to home', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final container = ProviderContainer(
      overrides:
          loggedInOverrides(
            firestore: firestore,
            authRepository: FakeAuthRepository(
              user: const AppUser(uid: 'guest', isAnonymous: true),
            ),
          )..addAll([
            authStateProvider.overrideWithValue(
              const AsyncData(AppUser(uid: 'guest', isAnonymous: true)),
            ),
            myGuestIdentityProvider.overrideWithValue(const AsyncData(null)),
            mySpaceInvitesProvider.overrideWithValue(const AsyncData([])),
            myPendingManualLinksProvider.overrideWithValue(const AsyncData([])),
            savedDraftProvider.overrideWithValue(const AsyncData(null)),
            participantEconomicOverviewProvider.overrideWithValue(
              AsyncData(
                EconomicOverview.compute(
                  viewerUid: 'guest',
                  entries: const [],
                  payments: const [],
                ),
              ),
            ),
          ]),
    );
    final router = container.read(appRouterProvider);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
      router.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    router.go('/home/spaces/group/chat');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(router.state.uri.path, '/home');
    expect(find.byType(ChatScreen), findsNothing);
  });
}
