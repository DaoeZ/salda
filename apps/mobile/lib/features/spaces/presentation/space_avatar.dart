import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../domain/space_models.dart';

/// Avatar básico de un espacio: emoji opcional o inicial del nombre, sobre
/// un color CONSISTENTE derivado del id (misma primitiva que las personas).
class SpaceAvatar extends StatelessWidget {
  const SpaceAvatar({super.key, required this.space, this.radius = 20});

  final Space space;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = Color(
      TokenColors.avatarPalette[avatarColorIndex(
        space.id,
        TokenColors.avatarPalette.length,
      )],
    );
    final emoji = space.avatarEmoji;
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        (emoji != null && emoji.isNotEmpty)
            ? emoji
            : avatarInitials(space.name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}
