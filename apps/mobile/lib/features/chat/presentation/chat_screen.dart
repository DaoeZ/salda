import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/presentation/profile_avatar.dart';
import '../../spaces/data/spaces_repository.dart';
import '../data/chat_repository.dart';
import '../domain/chat_message.dart';

/// Chat contextual de una Relación o Grupo (P7).
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final List<ChatMessage> _older = [];
  var _loadingMore = false;
  var _exhausted = false;
  var _sending = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refreshComposer);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_refreshComposer)
      ..dispose();
    super.dispose();
  }

  void _refreshComposer() {
    if (mounted) setState(() {});
  }

  Future<void> _loadOlder(List<ChatMessage> live) async {
    if (_loadingMore || _exhausted) return;
    final first = (_older.isNotEmpty ? _older : live).firstOrNull?.createdAt;
    if (first == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(chatRepositoryProvider)
          .fetchOlder(widget.spaceId, first);
      if (!mounted) return;
      setState(() {
        final known = {...live.map((m) => m.id), ..._older.map((m) => m.id)};
        _older.insertAll(
          0,
          page.where((message) => !known.contains(message.id)),
        );
        _exhausted = page.length < ChatRepository.pageSize;
      });
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).chatLoadError)),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _send() async {
    if (_sending || _controller.text.trim().isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final sendError = AppLocalizations.of(context).chatSendError;
    setState(() => _sending = true);
    try {
      await ref
          .read(chatRepositoryProvider)
          .send(widget.spaceId, _controller.text);
      _controller.clear();
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(sendError)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(ChatMessage message) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.chatDeleteTitle),
        content: Text(l10n.chatDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.chatDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(chatRepositoryProvider).delete(widget.spaceId, message.id);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.chatDeleteError)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spaceAsync = ref.watch(spaceProvider(widget.spaceId));
    final space = spaceAsync.value;

    if (spaceAsync.isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.chatTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (space == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.chatTitle)),
        body: Center(child: Text(l10n.chatUnavailable)),
      );
    }

    final live = ref.watch(spaceChatProvider(widget.spaceId));
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.chatTitle),
            Text(
              space.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: live.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ChatError(
                onRetry: () =>
                    ref.invalidate(spaceChatProvider(widget.spaceId)),
              ),
              data: (messages) {
                if (messages.isEmpty && _older.isEmpty) {
                  return const _ChatEmpty();
                }
                final seen = <String>{};
                final all = [
                  ..._older,
                  ...messages,
                ].where((message) => seen.add(message.id)).toList();
                final canLoadMore =
                    !_exhausted &&
                    (messages.length >= ChatRepository.pageSize ||
                        _older.isNotEmpty);
                return ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TokenSpacing.md,
                    vertical: TokenSpacing.sm,
                  ),
                  children: [
                    if (canLoadMore)
                      Center(
                        child: _loadingMore
                            ? const Padding(
                                padding: EdgeInsets.all(TokenSpacing.sm),
                                child: SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : TextButton(
                                onPressed: () => _loadOlder(messages),
                                child: Text(l10n.chatLoadOlder),
                              ),
                      ),
                    for (final message in all)
                      ChatMessageBubble(
                        message: message,
                        isOwn:
                            message.authorUid ==
                            ref.watch(currentChatUserIdProvider),
                        canDelete: space.isActive,
                        onDelete: () => _delete(message),
                      ),
                  ],
                );
              },
            ),
          ),
          _ChatComposer(
            controller: _controller,
            enabled: space.isActive && !_sending,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.controller,
    required this.enabled,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!enabled && !sending) {
      return SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(TokenSpacing.lg),
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Text(l10n.chatReadOnly, textAlign: TextAlign.center),
        ),
      );
    }
    final canSend = enabled && controller.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            TokenSpacing.md,
            TokenSpacing.sm,
            TokenSpacing.sm,
            TokenSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: ChatRepository.maxMessageLength,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    hintText: l10n.chatMessageHint,
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: TokenSpacing.sm),
              IconButton.filled(
                onPressed: canSend ? onSend : null,
                tooltip: l10n.chatSend,
                icon: sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatMessageBubble extends ConsumerWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isOwn,
    required this.canDelete,
    required this.onDelete,
  });

  final ChatMessage message;
  final bool isOwn;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final profile = ref.watch(publicProfileProvider(message.authorUid)).value;
    final authorName = isOwn
        ? l10n.chatYou
        : profile?.displayName ?? l10n.chatAuthorFallback;
    final time = message.createdAt == null
        ? l10n.chatSending
        : MaterialLocalizations.of(
            context,
          ).formatTimeOfDay(TimeOfDay.fromDateTime(message.createdAt!));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TokenSpacing.xs),
      child: Row(
        mainAxisAlignment: isOwn
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isOwn) ...[
            ProfileAvatar(
              seed: message.authorUid,
              displayName: authorName,
              radius: 14,
            ),
            const SizedBox(width: TokenSpacing.sm),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isOwn
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(TokenRadius.card),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    TokenSpacing.md,
                    TokenSpacing.sm,
                    TokenSpacing.sm,
                    TokenSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              authorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium,
                            ),
                          ),
                          if (isOwn && canDelete)
                            PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              tooltip: l10n.chatMessageActions,
                              onSelected: (_) => onDelete(),
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(l10n.chatDelete),
                                ),
                              ],
                              icon: const Icon(Icons.more_horiz, size: 18),
                            ),
                        ],
                      ),
                      Text(message.text),
                      const SizedBox(height: TokenSpacing.xs),
                      Text(
                        time,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatEmpty extends StatelessWidget {
  const _ChatEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TokenSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 52,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: TokenSpacing.md),
            Text(
              l10n.chatEmptyTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: TokenSpacing.sm),
            Text(l10n.chatEmptyBody, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ChatError extends StatelessWidget {
  const _ChatError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TokenSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(l10n.chatLoadError, textAlign: TextAlign.center),
            const SizedBox(height: TokenSpacing.md),
            FilledButton.tonal(
              onPressed: onRetry,
              child: Text(l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}
