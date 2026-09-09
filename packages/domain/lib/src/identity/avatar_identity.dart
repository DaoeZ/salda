/// Avatar automático de la identidad pública (P2): iniciales + color
/// CONSISTENTE derivado del usuario. Se deriva siempre (no se almacena):
/// así app y web pintan idéntico sin sincronizar nada.
library;

import 'package:characters/characters.dart';

/// Índice determinista sobre una paleta de [paletteLength] colores.
/// FNV-1a de 32 bits sobre el uid: estable entre plataformas y ejecuciones.
int avatarColorIndex(String seed, int paletteLength) {
  assert(paletteLength > 0);
  var hash = 0x811c9dc5;
  for (final unit in seed.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash % paletteLength;
}

/// Iniciales para el avatar: primera letra de las dos primeras palabras
/// ("Edgar Cantera" → "EC", "Edgar" → "E"). Si no hay letras, "?".
///
/// Se recorta por GRAFEMAS, no por unidades UTF-16: `word[0]` sobre un
/// nombre que empieza por emoji devuelve medio par sustituto y Flutter
/// lanza al construir el TextSpan. Un participante puede llamarse "🎸 Pablo".
String avatarInitials(String displayName) {
  final words = displayName
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2);
  final buffer = StringBuffer();
  for (final word in words) {
    buffer.write(word.characters.first.toUpperCase());
  }
  return buffer.isEmpty ? '?' : buffer.toString();
}
