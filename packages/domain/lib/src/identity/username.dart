/// Identidad pública: normalización, validación y propuesta de usernames.
///
/// El username es el identificador público principal (P2). Es SIEMPRE
/// minúsculas: la unicidad case-insensitive se consigue por construcción
/// (se almacena y compara ya normalizado), no comparando variantes.
library;

const int usernameMinLength = 3;
const int usernameMaxLength = 20;

/// Nombres que ningún usuario puede reclamar: identidades del producto,
/// soporte y términos que se prestan a suplantación. La lista se duplica
/// (conscientemente) en firestore.rules: las reglas no pueden importar Dart.
const Set<String> reservedUsernames = {
  'admin',
  'administrador',
  'salda',
  'soporte',
  'support',
  'ayuda',
  'help',
  'info',
  'api',
  'root',
  'sistema',
  'system',
  'moderador',
  'mod',
  'oficial',
  'official',
  'staff',
  'equipo',
  'team',
  'seguridad',
  'security',
  'invitado',
  'guest',
  'usuario',
  'user',
  'anonimo',
  'anonymous',
  'test',
  'prueba',
};

/// Motivos de rechazo estables (la UI los traduce; nunca mostrar el nombre
/// del enum al usuario).
enum UsernameError {
  empty,
  tooShort,
  tooLong,
  invalidCharacters,
  mustStartWithLetter,
  endsWithUnderscore,
  consecutiveUnderscores,
  reserved,
}

final RegExp _validChars = RegExp(r'^[a-z0-9_]+$');
final RegExp _startsWithLetter = RegExp(r'^[a-z]');

/// Forma canónica: espacios fuera y minúsculas. NO elimina caracteres
/// inválidos: eso sería adivinar la intención; la validación los rechaza.
String normalizeUsername(String input) => input.trim().toLowerCase();

/// Valida la forma canónica de [input]. Devuelve null si es válido.
UsernameError? validateUsername(String input) {
  final username = normalizeUsername(input);
  if (username.isEmpty) return UsernameError.empty;
  if (username.length < usernameMinLength) return UsernameError.tooShort;
  if (username.length > usernameMaxLength) return UsernameError.tooLong;
  if (!_validChars.hasMatch(username)) return UsernameError.invalidCharacters;
  if (!_startsWithLetter.hasMatch(username)) {
    return UsernameError.mustStartWithLetter;
  }
  if (username.endsWith('_')) return UsernameError.endsWithUnderscore;
  if (username.contains('__')) return UsernameError.consecutiveUnderscores;
  if (reservedUsernames.contains(username)) return UsernameError.reserved;
  return null;
}

const Map<String, String> _diacritics = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n', 'ç': 'c',
};

/// Reduce un texto libre (nombre visible) a minúsculas ASCII con espacios:
/// base tanto de los candidatos de username como de `displayNameLower`
/// (el campo por el que se busca por prefijo sin sensibilidad a tildes).
String searchableText(String text) {
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final mapped = _diacritics[char] ?? char;
    if (RegExp(r'[a-z0-9 ]').hasMatch(mapped)) buffer.write(mapped);
  }
  return buffer.toString().replaceAll(RegExp(r' +'), ' ').trim();
}

/// Candidatos de username NATURALES a partir del nombre visible, en orden
/// de preferencia: edgar → edgar27 → edgar_cantera → edgar423 → …
/// Nunca cadenas aleatorias largas. [nextInt] inyecta la aleatoriedad
/// (sembrada en tests); los dígitos son 2–4 como máximo.
List<String> usernameCandidates(
  String displayName, {
  required int Function(int max) nextInt,
  int count = 10,
}) {
  final tokens = searchableText(displayName)
      .split(' ')
      .where((token) => token.isNotEmpty)
      .toList();
  var base = tokens.isEmpty ? 'usuario' : tokens.first;
  // Un username debe empezar por letra; un nombre como "3dgar" no.
  if (!_startsWithLetter.hasMatch(base)) base = 'u$base';
  base = _clip(base, usernameMaxLength);
  final surname = tokens.length > 1 ? tokens[1] : '';

  String digits(int width) {
    final floor = width == 2 ? 10 : (width == 3 ? 100 : 1000);
    return '${floor + nextInt(floor * 9)}';
  }

  String withSuffix(String stem, String suffix) =>
      '${_clip(stem, usernameMaxLength - suffix.length)}$suffix';

  final raw = <String>[
    base,
    withSuffix(base, digits(2)),
    if (surname.isNotEmpty) _clip('${base}_$surname', usernameMaxLength),
    withSuffix(base, digits(3)),
    if (surname.isNotEmpty) withSuffix(base, surname),
    if (surname.isNotEmpty) '$base${surname[0]}',
    if (surname.isNotEmpty) withSuffix('${base}_$surname', digits(2)),
    withSuffix(base, digits(3)),
    withSuffix(base, digits(4)),
    withSuffix(base, digits(4)),
  ];

  final seen = <String>{};
  final result = <String>[];
  for (final candidate in raw) {
    if (result.length >= count) break;
    if (validateUsername(candidate) != null) continue;
    if (seen.add(candidate)) result.add(candidate);
  }
  // Los sufijos aleatorios pueden colisionar entre sí: rellenar hasta count
  // con más variantes numéricas (siguen siendo cortas y naturales).
  var guard = 0;
  while (result.length < count && guard < 50) {
    guard++;
    final candidate = withSuffix(base, digits(guard < 25 ? 3 : 4));
    if (validateUsername(candidate) == null && seen.add(candidate)) {
      result.add(candidate);
    }
  }
  return result;
}

String _clip(String text, int max) {
  var clipped = text.length <= max ? text : text.substring(0, max);
  // No dejar un '_' colgando al recortar (sería inválido).
  while (clipped.endsWith('_')) {
    clipped = clipped.substring(0, clipped.length - 1);
  }
  return clipped;
}
