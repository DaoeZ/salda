import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
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
///
/// POR QUÉ SOLO SE BUSCA UNA CUENTA (BUG-2). Una relación son exactamente DOS
/// UID y su identificador es canónico —`relationship_{uidMenor}~{uidMayor}`,
/// ADR-030—, de modo que hay que conocer el UID de la otra persona ANTES de
/// crearla; eso es lo que hace que A→B y B→A sean el mismo contexto y no dos
/// relaciones duplicadas. De ahí que las otras vías no encajen:
///
/// - **Enlace abierto**: el identificador tendría que calcularse sin saber
///   quién va a aceptar. Incompatible sin rediseñar ADR-030.
/// - **MANUAL**: no tiene UID, así que no puede ocupar una de las dos plazas.
///   Rules lo impide ahora explícitamente.
/// - **GUEST**: sí puede ser la segunda persona —tiene UID propio— pero por
///   diseño no es buscable (ADR-034), así que no hay forma de alcanzarlo
///   desde aquí.
///
/// Para compartir gastos con alguien sin cuenta existe el GRUPO, que sí
/// admite participantes MANUAL y enlaces de incorporación. La pantalla lo
/// ofrece en vez de dejar al usuario en un callejón sin salida.
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
    if (creatingUid != null) return; // guarda de doble pulsación
    final l10n = AppLocalizations.of(context);
    setState(() => creatingUid = other.uid);
    try {
      final own = ref.read(myProfileProvider).value;
      final name = own == null
          ? other.displayName
          : '${own.displayName} · ${other.displayName}';
      final result = await ref
          .read(spacesRepositoryProvider)
          .createRelationship(toUid: other.uid, name: name);
      if (!mounted) return;
      // Cada desenlace se cuenta con sus palabras: crear, reenviar tras un
      // rechazo o descubrir que ya estaba activa no son lo mismo.
      final aviso = switch (result.outcome) {
        RelationshipOutcome.created => null,
        RelationshipOutcome.alreadyInvited => l10n.relationshipAlreadyInvited,
        RelationshipOutcome.reinvited => l10n.relationshipReinvited,
        RelationshipOutcome.alreadyActive => l10n.relationshipAlreadyActive,
      };
      if (aviso != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(aviso)));
      }
      context.go('/home/spaces/${result.id}');
    } on SpaceFailure catch (failure) {
      // BUG-3: antes TODO caía en un único «no se pudo completar la acción»,
      // justo en los casos que dependen de tu historia con esa cuenta.
      if (!mounted) return;
      final mensaje = switch (failure.code) {
        SpaceFailureCode.invitedByOther => l10n.relationshipInvitedByOther,
        SpaceFailureCode.incompatibleData => l10n.relationshipIncompatible,
        SpaceFailureCode.accountRequired => l10n.contextAccountRequired,
        SpaceFailureCode.notAllowed => l10n.relationshipNotAllowed,
        _ => l10n.spaceActionError,
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensaje)),
      );
    } on Object catch (error) {
      if (!mounted) return;
      // Diagnóstico útil sin datos sensibles: código y operación, nunca
      // tokens ni el id técnico en pantalla.
      debugPrint('createRelationship falló: $error');
      final esRed = error is FirebaseException && error.code == 'unavailable';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(esRed ? l10n.authErrorNetwork : l10n.spaceActionError),
        ),
      );
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
          // La pantalla explica QUÉ es una relación y ofrece la alternativa
          // real cuando la otra persona no tiene cuenta, en vez de ser solo
          // una caja de búsqueda sin salida.
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TokenSpacing.lg,
            ),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: Text(l10n.relationshipNoAccountTitle),
                subtitle: Text(l10n.relationshipNoAccountBody),
                trailing: const Icon(Icons.chevron_right),
                onTap: creatingUid == null
                    ? () => context.go('/home')
                    : null,
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
                        // Una cuenta puede no tener username todavía: en ese
                        // caso no se pinta un '@' huérfano.
                        subtitle: profile.username.isEmpty
                            ? null
                            : Text('@${profile.username}'),
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
