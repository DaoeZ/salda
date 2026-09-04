import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/core/theme/app_theme.dart';
import 'package:salda_mobile/features/home/home_screen.dart';
import 'package:salda_mobile/features/economy/data/economic_repository.dart';
import 'package:salda_mobile/features/economy/domain/economic_models.dart';
import 'package:salda_mobile/features/review/application/draft_store.dart';
import 'package:salda_mobile/features/spaces/data/manual_link_repository.dart';
import 'package:salda_mobile/features/spaces/data/spaces_repository.dart';
import 'package:salda_mobile/features/spaces/presentation/space_detail_screen.dart';
import 'package:salda_mobile/features/spaces/presentation/space_management_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

/// Manual visual evidence for Phase 2.5. Run explicitly with:
/// `flutter test --dart-define=UPDATE_PHASE25_GOLDENS=true
///   --update-goldens test/phase25_visual_test.dart`
///
/// The outputs live under `test/goldens/`; normal CI skips them because text
/// rasterization differs across host platforms.
void main() {
  const updateGoldens = bool.fromEnvironment('UPDATE_PHASE25_GOLDENS');
  late FakeFirebaseFirestore firestore;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await firestore.doc('spaces/group').set({
      'name': 'Piso',
      'ownerUid': 'owner',
      'kind': 'group',
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/group/members/owner').set({'uid': 'owner'});
    await firestore.doc('spaces/group/manualParticipants/pablo').set({
      'manualId': 'pablo',
      'displayName': 'Pablo',
      'createdByUid': 'owner',
      'schemaVersion': 1,
    });
    await firestore.doc('spaces/relationship').set({
      'name': 'legacy title',
      'ownerUid': 'owner',
      'kind': 'relationship',
      'relationshipUids': ['owner', 'ana'],
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/relationship/members/owner').set({
      'uid': 'owner',
    });
    await firestore.doc('spaces/relationship/members/ana').set({'uid': 'ana'});
    await firestore.doc('profiles/ana').set({'displayName': 'Ana'});
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: loggedInOverrides(firestore: firestore)
        ..addAll([
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
        ]),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Home visual', (tester) async {
    await pump(tester, const HomeScreen());
    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/phase25_home.png'),
    );
  }, skip: !updateGoldens);

  testWidgets('Group cover visual', (tester) async {
    await pump(tester, const SpaceDetailScreen(spaceId: 'group'));
    await expectLater(
      find.byType(SpaceDetailScreen),
      matchesGoldenFile('goldens/phase25_group_cover.png'),
    );
  }, skip: !updateGoldens);

  testWidgets('Relationship cover visual', (tester) async {
    await pump(tester, const SpaceDetailScreen(spaceId: 'relationship'));
    await expectLater(
      find.byType(SpaceDetailScreen),
      matchesGoldenFile('goldens/phase25_relationship_cover.png'),
    );
  }, skip: !updateGoldens);

  testWidgets('Group management visual', (tester) async {
    await pump(tester, const SpaceManagementScreen(spaceId: 'group'));
    await expectLater(
      find.byType(SpaceManagementScreen),
      matchesGoldenFile('goldens/phase25_group_management.png'),
    );
  }, skip: !updateGoldens);

  testWidgets('Relationship management visual', (tester) async {
    await pump(tester, const SpaceManagementScreen(spaceId: 'relationship'));
    await expectLater(
      find.byType(SpaceManagementScreen),
      matchesGoldenFile('goldens/phase25_relationship_management.png'),
    );
  }, skip: !updateGoldens);
}
