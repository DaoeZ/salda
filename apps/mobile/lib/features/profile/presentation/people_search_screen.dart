import 'dart:async';

import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../data/profile_repository.dart';
import 'profile_avatar.dart';

/// Búsqueda de personas por @username o nombre visible (P2). SOLO búsqueda:
/// las solicitudes de amistad y los espacios compartidos llegan en fases
/// posteriores; por eso los resultados aún no tienen acción al tocarlos.
class PeopleSearchScreen extends ConsumerStatefulWidget {
  const PeopleSearchScreen({super.key});

  @override
  ConsumerState<PeopleSearchScreen> createState() =>
      _PeopleSearchScreenState();
}

class _PeopleSearchScreenState extends ConsumerState<PeopleSearchScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  var _searching = false;
  var _searched = false;
  List<PublicProfile> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searched = false;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final results =
          await ref.read(profileRepositoryProvider).search(value);
      if (!mounted || _query.text != value) return;
      setState(() {
        _results = results;
        _searching = false;
        _searched = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _query,
          autofocus: true,
          autocorrect: false,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: l10n.searchPeopleHint,
            border: InputBorder.none,
          ),
        ),
        bottom: _searching
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: !_searched
          ? _Hint(
              icon: Icons.person_search_outlined,
              text: l10n.searchPeopleStart,
              theme: theme,
            )
          : _results.isEmpty
              ? _Hint(
                  icon: Icons.search_off_outlined,
                  text: l10n.searchPeopleEmpty,
                  theme: theme,
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    vertical: TokenSpacing.sm,
                  ),
                  itemCount: _results.length,
                  itemBuilder: (_, index) {
                    final profile = _results[index];
                    return ListTile(
                      leading: ProfileAvatar(
                        seed: profile.uid,
                        displayName: profile.displayName,
                      ),
                      title: Text(profile.displayName),
                      subtitle: Text('@${profile.username}'),
                    );
                  },
                ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text, required this.theme});

  final IconData icon;
  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(TokenSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 56, color: theme.colorScheme.outline),
              const SizedBox(height: TokenSpacing.md),
              Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
}
