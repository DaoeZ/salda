/// Generador de tokens de diseño.
///
/// Lee `assets/brand.json` y `assets/design_tokens.json` (fuente única de
/// verdad) y emite:
///  - `lib/src/tokens.g.dart`  → constantes Dart puras para la app Flutter.
///  - `apps/guest_web/src/styles/tokens.g.css` → CSS custom properties para
///    la web de invitados (claro + oscuro).
///
/// Uso (desde cualquier directorio del repo): `dart run design_tokens:generate`
library;

import 'dart:convert';
import 'dart:io';

void main() {
  final repoRoot = _findRepoRoot();
  final pkg = '$repoRoot/packages/design_tokens';

  final brand = _readJson('$pkg/assets/brand.json');
  final tokens = _readJson('$pkg/assets/design_tokens.json');

  File('$pkg/lib/src/tokens.g.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync(_generateDart(brand, tokens));

  File('$repoRoot/apps/guest_web/src/styles/tokens.g.css')
    ..createSync(recursive: true)
    ..writeAsStringSync(_generateCss(brand, tokens));

  File('$repoRoot/apps/guest_web/src/lib/brand.g.ts')
    ..createSync(recursive: true)
    ..writeAsStringSync(_generateTypeScriptBrand(brand));

  stdout.writeln('tokens.g.dart, tokens.g.css y brand.g.ts regenerados.');
}

String _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File(
      '${dir.path}/packages/design_tokens/assets/design_tokens.json',
    ).existsSync()) {
      return dir.path.replaceAll(r'\', '/');
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'No se encontró la raíz del repo desde ${Directory.current.path}',
      );
    }
    dir = parent;
  }
}

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// `#RRGGBB` → literal Dart `0xFFRRGGBB`.
String _argb(String hex) => '0xFF${hex.substring(1).toUpperCase()}';

/// `settlementPending` → `settlement-pending`.
String _kebab(String s) =>
    s.replaceAllMapped(RegExp('[A-Z]'), (m) => '-${m[0]!.toLowerCase()}');

String _generateDart(Map<String, dynamic> brand, Map<String, dynamic> t) {
  final hosting = brand['hostingDomains'] as Map<String, dynamic>;
  final color = t['color'] as Map<String, dynamic>;
  final semantic = color['semantic'] as Map<String, dynamic>;
  final avatars = (color['avatarPalette'] as List).cast<String>();
  final typo = t['typography'] as Map<String, dynamic>;
  final scale = typo['scale'] as Map<String, dynamic>;
  final spacing = t['spacing'] as Map<String, dynamic>;
  final radius = t['radius'] as Map<String, dynamic>;
  final motion = t['motion'] as Map<String, dynamic>;
  final durations = motion['durations'] as Map<String, dynamic>;
  final layout = t['layout'] as Map<String, dynamic>;
  final easing = (motion['easingEmphasized'] as List).cast<num>();

  final b = StringBuffer()
    ..writeln('// GENERATED por design_tokens:generate — NO EDITAR A MANO.')
    ..writeln('// Fuente: assets/brand.json + assets/design_tokens.json')
    ..writeln('// ignore_for_file: public_member_api_docs')
    ..writeln()
    ..writeln('abstract final class Brand {')
    ..writeln("  static const String appName = '${brand['appName']}';")
    ..writeln("  static const String tagline = '${brand['tagline']}';")
    ..writeln('  static const bool provisional = ${brand['provisional']};')
    ..writeln(
      "  static const String developmentHostingDomain = '${hosting['development']}';",
    )
    ..writeln(
      "  static const String productionHostingDomain = '${hosting['production']}';",
    )
    ..writeln('}')
    ..writeln()
    ..writeln('/// Colores como int ARGB; la app los envuelve en `Color(...)`.')
    ..writeln('abstract final class TokenColors {')
    ..writeln("  static const int seed = ${_argb(color['seed'] as String)};");
  for (final entry in semantic.entries) {
    final v = entry.value as Map<String, dynamic>;
    b
      ..writeln(
        '  static const int ${entry.key}Light = '
        '${_argb(v['light'] as String)};',
      )
      ..writeln(
        '  static const int ${entry.key}Dark = '
        '${_argb(v['dark'] as String)};',
      );
  }
  b
    ..writeln(
      '  static const List<int> avatarPalette = ['
      '${avatars.map(_argb).join(', ')}];',
    )
    ..writeln('}')
    ..writeln()
    ..writeln('abstract final class TokenTypography {')
    ..writeln("  static const String fontFamily = '${typo['fontFamily']}';");
  for (final entry in scale.entries) {
    final v = entry.value as Map<String, dynamic>;
    b
      ..writeln('  static const double ${entry.key}Size = ${v['size']};')
      ..writeln('  static const int ${entry.key}Weight = ${v['weight']};');
  }
  b
    ..writeln('}')
    ..writeln()
    ..writeln('abstract final class TokenSpacing {');
  for (final e in spacing.entries) {
    b.writeln('  static const double ${e.key} = ${e.value};');
  }
  b
    ..writeln('}')
    ..writeln()
    ..writeln('abstract final class TokenRadius {');
  for (final e in radius.entries) {
    b.writeln('  static const double ${e.key} = ${e.value};');
  }
  b
    ..writeln('}')
    ..writeln()
    ..writeln('abstract final class TokenMotion {')
    ..writeln('  /// Curva M3 emphasized: cubic-bezier(x1, y1, x2, y2).')
    ..writeln(
      '  static const List<double> easingEmphasized = '
      '[${easing.join(', ')}];',
    );
  for (final e in durations.entries) {
    b.writeln('  static const int ${e.key} = ${e.value};');
  }
  b
    ..writeln('  static const int listStaggerMs = ${motion['listStaggerMs']};')
    ..writeln(
      '  static const int skeletonShimmerMs = '
      '${motion['skeletonShimmerMs']};',
    )
    ..writeln(
      '  static const int syncIndicatorDelayMs = '
      '${motion['syncIndicatorDelayMs']};',
    )
    ..writeln('}')
    ..writeln()
    ..writeln('abstract final class TokenLayout {');
  for (final e in layout.entries) {
    b.writeln('  static const double ${e.key} = ${e.value};');
  }
  b.writeln('}');
  return b.toString();
}

String _generateTypeScriptBrand(Map<String, dynamic> brand) {
  final hosting = brand['hostingDomains'] as Map<String, dynamic>;
  return '''// GENERATED por design_tokens:generate — NO EDITAR A MANO.
// Fuente: packages/design_tokens/assets/brand.json
export const BRAND = {
  appName: ${jsonEncode(brand['appName'])},
  tagline: ${jsonEncode(brand['tagline'])},
  hostingDomains: {
    development: ${jsonEncode(hosting['development'])},
    production: ${jsonEncode(hosting['production'])},
  },
} as const;
''';
}

String _generateCss(Map<String, dynamic> brand, Map<String, dynamic> t) {
  final color = t['color'] as Map<String, dynamic>;
  final semantic = color['semantic'] as Map<String, dynamic>;
  final typo = t['typography'] as Map<String, dynamic>;
  final spacing = t['spacing'] as Map<String, dynamic>;
  final radius = t['radius'] as Map<String, dynamic>;
  final motion = t['motion'] as Map<String, dynamic>;
  final durations = motion['durations'] as Map<String, dynamic>;
  final easing = (motion['easingEmphasized'] as List).cast<num>();

  String block(String mode) {
    final b = StringBuffer();
    for (final entry in semantic.entries) {
      final v = entry.value as Map<String, dynamic>;
      b.writeln('  --color-${_kebab(entry.key)}: ${v[mode]};');
    }
    return b.toString();
  }

  final shared = StringBuffer();
  shared.writeln('  --color-seed: ${color['seed']};');
  shared.writeln(
    "  --font-family: '${typo['fontFamily']}', system-ui, sans-serif;",
  );
  for (final e in spacing.entries) {
    shared.writeln('  --space-${e.key}: ${e.value}px;');
  }
  for (final e in radius.entries) {
    shared.writeln('  --radius-${_kebab(e.key)}: ${e.value}px;');
  }
  shared.writeln('  --easing-emphasized: cubic-bezier(${easing.join(', ')});');
  for (final e in durations.entries) {
    shared.writeln(
      '  --duration-${_kebab(e.key).replaceAll('-ms', '')}: ${e.value}ms;',
    );
  }

  return '''
/* GENERATED por design_tokens:generate — NO EDITAR A MANO. */
/* Fuente: packages/design_tokens/assets/ · App: ${brand['appName']} */

:root {
$shared${block('light')}}

@media (prefers-color-scheme: dark) {
  :root {
${block('dark')}  }
}

/* El toggle manual de tema (si existe) estampa data-theme y debe ganar. */
:root[data-theme='light'] {
${block('light')}}

:root[data-theme='dark'] {
${block('dark')}}
''';
}
