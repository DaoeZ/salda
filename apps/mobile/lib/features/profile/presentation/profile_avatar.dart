import 'package:flutter/material.dart';

import '../../../core/ui/badges.dart';

/// Avatar de identidad pública: iniciales sobre un color CONSISTENTE
/// derivado del uid (mismo usuario = mismo color en cualquier pantalla y
/// dispositivo). Cuando exista foto de perfil, este widget la mostrará y
/// las iniciales quedarán como fallback.
///
/// Delega en [SaldaAvatar] para que una persona se pinte igual en la barra,
/// en su perfil y en una fila de balance.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.seed,
    required this.displayName,
    this.radius = 20,
  });

  /// Semilla estable del color: el uid del usuario.
  final String seed;
  final String displayName;
  final double radius;

  @override
  Widget build(BuildContext context) =>
      SaldaAvatar(seed: seed, label: displayName, radius: radius);
}
