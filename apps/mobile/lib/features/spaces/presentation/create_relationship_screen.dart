import 'dart:async';

import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/presentation/profile_avatar.dart';
import '../data/spaces_repository.dart';

/// Selección explícita de la segunda persona de una relación. No infiere la
/// pareja desde amistad, tickets ni deuda: crearla siempre es una decisión.
class CreateRelationshipScreen extends ConsumerStatefulWidget {
  const CreateRelationshipScreen({super.key});

  @override
  ConsumerState<CreateRelationshipScreen> createState() =>
      _CreateRelationshipScreenState();
}

class _CreateRelationshipScreenState
    extends ConsumerState<CreateRelationshipScreen> {
  final query = TextEditingController();
  Timer? debounce;
  List<PublicProfile> results = const [];
  var searching = false;
  var failed = false;
  String? creatingUid;

  @override
  void dispose() {
    debounce?.cancel();
    query.dispose();
    super.dispose();
  }

  void search(String value) {
    debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        results = const [];
        searching = false;
        failed = false;
      });
      return;
    }
    setState(() {
      searching = true;
      failed = false;
    });
    debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final ownUid = ref.read(profileRepositoryProvider).uid();
        final found = await ref.read(profileRepositoryProvider).search(value);
        if (!mounted || query.text != value) return;
        setState(() {
          results = found.where((profile) => profile.uid != ownUid).toList();
          searching = false;
        });
      } on Object {
        if (!mounted || query.text != value) return;
        setState(() {
          failed = true;
          searching = false;
          results = const [];
        });
      }
    });
  }

  Future<void> create(PublicProfile other) async {
    setState(() => creatingUid = other.uid);
    try {
      final own = ref.read(myProfileProvider).value;
      final name = own == null
          ? other.displayName
          : '${own.displayName} · ${other.displayName}';
      final id = await ref
          .read(spacesRepositoryProvider)
          .createRelationship(toUid: other.uid, name: name);
      if (mounted) context.go('/home/spaces/$id');
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).spaceActionError),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => creatingUid = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.relationshipCreate)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(TokenSpacing.lg),
            child: TextField(
              controller: query,
              autofocus: true,
              autocorrect: false,
              onChanged: search,
              decoration: InputDecoration(
                labelText: l10n.searchPeopleHint,
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
          if (searching) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: failed
                ? Center(child: Text(l10n.searchPeopleError))
                : results.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(TokenSpacing.xl),
                      child: Text(
                        l10n.relationshipSearchHelp,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (_, index) {
                      final profile = results[index];
                      final busy = creatingUid == profile.uid;
                      return ListTile(
                        leading: ProfileAvatar(
                          seed: profile.uid,
                          displayName: profile.displayName,
                        ),
                        title: Text(
                          profile.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('@${profile.username}'),
                        trailing: busy
                            ? const SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator(),
                              )
                            : const Icon(Icons.add_circle_outline),
                        enabled: creatingUid == null,
                        onTap: () => create(profile),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
