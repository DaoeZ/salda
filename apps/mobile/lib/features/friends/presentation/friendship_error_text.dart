import '../../../l10n/generated/app_localizations.dart';
import '../data/friendship_repository.dart';

String friendshipErrorText(AppLocalizations l10n, Object error) {
  if (error is! FriendshipFailure) return l10n.friendErrorUnexpected;
  return switch (error.code) {
    FriendshipFailureCode.accountRequired ||
    FriendshipFailureCode.unverifiedAccount => l10n.friendErrorUnverified,
    FriendshipFailureCode.profileRequired => l10n.friendErrorProfileRequired,
    FriendshipFailureCode.targetUnavailable => l10n.friendProfileUnavailable,
    FriendshipFailureCode.selfRequest => l10n.friendErrorUnexpected,
    FriendshipFailureCode.requestAlreadyExists => l10n.friendErrorRequestExists,
    FriendshipFailureCode.alreadyFriends => l10n.friendErrorAlreadyFriends,
    FriendshipFailureCode.permissionDenied => l10n.friendErrorPermissionDenied,
    FriendshipFailureCode.serviceUnavailable =>
      l10n.friendErrorServiceUnavailable,
    FriendshipFailureCode.network => l10n.friendErrorNetwork,
    FriendshipFailureCode.notAllowed => l10n.friendErrorPermissionDenied,
    FriendshipFailureCode.malformedData ||
    FriendshipFailureCode.unexpected => l10n.friendErrorUnexpected,
  };
}
