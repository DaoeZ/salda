import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

/// Avatar de identidad pública: iniciales sobre un color CONSISTENTE
/// derivado del uid (mismo usuario = mismo color en cualquier pantalla y
/// dispositivo). Cuando exista foto de perfil, este widget la mostrará y
/// las iniciales quedarán como fallback.
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
  Widget build(BuildContext context) {
    final color = Color(
      TokenColors.avatarPalette[avatarColorIndex(
        seed,
        TokenColors.avatarPalette.length,
      )],
    );
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        avatarInitials(displayName),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}
