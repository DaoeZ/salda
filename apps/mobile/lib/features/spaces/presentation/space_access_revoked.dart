import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/states.dart';
import '../../../core/ui/surfaces.dart';
import '../../../l10n/generated/app_localizations.dart';

/// ¿Este error significa que se ha perdido el acceso al contexto? (A11d)
///
/// Cuando desaparece `spaces/{id}/members/{uid}` —una expulsión, o haber
/// salido desde otro dispositivo— Firestore corta los listeners abiertos con
/// `permission-denied`. Distinguirlo importa: un fallo de red se reintenta,
/// pero aquí el permiso no va a volver y ofrecer «reintentar» deja a la
/// persona pulsando un botón que no puede funcionar.
bool isSpaceAccessRevoked(Object error) =>
    error is FirebaseException && error.code == 'permission-denied';

/// Pantalla de una superficie de grupo cuya membresía ya no existe.
///
/// Da la única salida útil —volver a la lista de contextos— y dice lo que
/// de verdad importa: el dinero no se ha movido. Las deudas, los pagos y los
/// gastos en los que participó siguen estando en su Economía.
class SpaceAccessRevokedScreen extends StatelessWidget {
  const SpaceAccessRevokedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: ScreenBody(
        children: [
          EmptyState(
            icon: Icons.lock_outline,
            title: l10n.spaceAccessRevokedTitle,
            body: l10n.spaceAccessRevokedBody,
            action: l10n.spaceAccessRevokedAction,
            onAction: () => context.go('/home/spaces'),
          ),
        ],
      ),
    );
  }
}
