import 'dart:convert';

const _roleOrder = <String>[
  'background',
  'surface',
  'surfaceElevated',
  'surfaceMuted',
  'border',
  'borderStrong',
  'textPrimary',
  'textSecondary',
  'textMuted',
  'primary',
  'onPrimary',
  'primaryMuted',
  'accent',
  'accentMuted',
  'positive',
  'positiveMuted',
  'negative',
  'negativeMuted',
  'warning',
  'pending',
  'disabled',
  'overlay',
  'skeleton',
  'focus',
];

const _semanticOrder = <String>[
  'settlementPending',
  'settlementMarked',
  'settlementConfirmed',
  'balancePositive',
  'balanceNegative',
];

const _scaleOrder = <String>[
  'display',
  'pageTitle',
  'sectionTitle',
  'cardTitle',
  'body',
  'bodyStrong',
  'label',
  'caption',
  'moneyLarge',
  'moneyMedium',
  'moneySmall',
];

const _spacingOrder = <String>[
  'xs',
  'sm',
  'md',
  'lg',
  'xl',
  'xxl',
  'xxxl',
  'section',
];

const _radiusOrder = <String>[
  'control',
  'field',
  'card',
  'sheet',
  'button',
  'thumbnail',
  'pill',
];

const _durationOrder = <String>['toggleMs', 'exitMs', 'enterMs', 'maxMs'];

const _layoutOrder = <String>[
  'screenMargin',
  'minTouchTarget',
  'thumbnailSize',
  'hairline',
  'maxContentWidth',
];

final class GeneratedArtifacts {
  GeneratedArtifacts({
    required String dart,
    required String css,
    required String typeScriptBrand,
  }) : dart = _normalizeLineEndings(dart),
       css = _normalizeLineEndings(css),
       typeScriptBrand = _normalizeLineEndings(typeScriptBrand);

  final String dart;
  final String css;
  final String typeScriptBrand;

  Map<String, String> get byPath => <String, String>{
    'packages/design_tokens/lib/src/tokens.g.dart': dart,
    'apps/guest_web/src/styles/tokens.g.css': css,
    'apps/guest_web/src/lib/brand.g.ts': typeScriptBrand,
  };
}

GeneratedArtifacts generateArtifacts(
  Map<String, dynamic> brand,
  Map<String, dynamic> tokens,
) {
  return GeneratedArtifacts(
    dart: generateDart(brand, tokens),
    css: generateCss(brand, tokens),
    typeScriptBrand: generateTypeScriptBrand(brand),
  );
}

List<String> findStalePaths(
  GeneratedArtifacts expected,
  Map<String, List<int>> actual,
) {
  final stale = <String>[];
  for (final entry in expected.byPath.entries) {
    final actualBytes = actual[entry.key];
    if (actualBytes == null ||
        !_sameBytes(actualBytes, utf8.encode(entry.value))) {
      stale.add(entry.key);
    }
  }
  return stale;
}

String formatFreshnessFailure(Iterable<String> stalePaths) {
  final paths = stalePaths.toList(growable: false);
  if (paths.isEmpty) {
    return '';
  }
  final lines = paths.map((path) => '  - $path').join('\n');
  return 'Generated files are stale:\n'
      '$lines\n'
      'Run dart run design_tokens:generate to refresh them.';
}

String generateDart(Map<String, dynamic> brand, Map<String, dynamic> tokens) {
  final hosting = brand['hostingDomains'] as Map<String, dynamic>;
  final color = tokens['color'] as Map<String, dynamic>;
  final semantic = color['semantic'] as Map<String, dynamic>;
  final roles = color['roles'] as Map<String, dynamic>;
  final avatars = (color['avatarPalette'] as List<dynamic>).cast<String>();
  final typography = tokens['typography'] as Map<String, dynamic>;
  final scale = typography['scale'] as Map<String, dynamic>;
  final spacing = tokens['spacing'] as Map<String, dynamic>;
  final radius = tokens['radius'] as Map<String, dynamic>;
  final motion = tokens['motion'] as Map<String, dynamic>;
  final durations = motion['durations'] as Map<String, dynamic>;
  final layout = tokens['layout'] as Map<String, dynamic>;
  final easing = (motion['easingEmphasized'] as List<dynamic>).cast<num>();

  final b = StringBuffer()
    ..writeln(
      '// GENERATED por design_tokens:generate \u2014 NO EDITAR A MANO.',
    )
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
    ..writeln('  static const int seed = ${_argb(color['seed'] as String)};');

  for (final entry in _canonicalEntries(roles, _roleOrder)) {
    final value = entry.value as Map<String, dynamic>;
    b
      ..writeln(
        '  static const int ${entry.key}Light = '
        '${_argb(value['light'] as String)};',
      )
      ..writeln(
        '  static const int ${entry.key}Dark = '
        '${_argb(value['dark'] as String)};',
      );
  }
  for (final entry in _canonicalEntries(semantic, _semanticOrder)) {
    final value = entry.value as Map<String, dynamic>;
    b
      ..writeln(
        '  static const int ${entry.key}Light = '
        '${_argb(value['light'] as String)};',
      )
      ..writeln(
        '  static const int ${entry.key}Dark = '
        '${_argb(value['dark'] as String)};',
      );
  }
  b.writeln('  static const List<int> avatarPalette = [');
  for (final avatar in avatars) {
    b.writeln('    ${_argb(avatar)},');
  }
  b
    ..writeln('  ];')
    ..writeln('}')
    ..writeln()
    ..writeln('abstract final class TokenTypography {')
    ..writeln(
      '  /// Vac\u00EDo = pila tipogr\u00E1fica del sistema. '
      'Ver docs/DISENO.md.',
    )
    ..writeln(
      '  static const String? fontFamily = '
      '${_fontFamilyLiteral(typography['fontFamily'] as String)};',
    );
  for (final entry in _canonicalEntries(scale, _scaleOrder)) {
    final value = entry.value as Map<String, dynamic>;
    b
      ..writeln('  static const double ${entry.key}Size = ${value['size']};')
      ..writeln('  static const int ${entry.key}Weight = ${value['weight']};')
      ..writeln(
        '  static const double ${entry.key}Tracking = '
        '${(value['tracking'] as num).toDouble()};',
      )
      ..writeln(
        '  static const double ${entry.key}Height = '
        '${(value['height'] as num).toDouble()};',
      );
  }
  b
    ..writeln('}')
    ..writeln()
    ..writeln('abstract final class TokenSpacing {');
  for (final entry in _canonicalEntries(spacing, _spacingOrder)) {
    b.writeln('  static const double ${entry.key} = ${entry.value};');
  }
  b
    ..writeln('}')
    ..writeln()
    ..writeln('abstract final class TokenRadius {');
  for (final entry in _canonicalEntries(radius, _radiusOrder)) {
    b.writeln('  static const double ${entry.key} = ${entry.value};');
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
  for (final entry in _canonicalEntries(durations, _durationOrder)) {
    b.writeln('  static const int ${entry.key} = ${entry.value};');
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
  for (final entry in _canonicalEntries(layout, _layoutOrder)) {
    b.writeln('  static const double ${entry.key} = ${entry.value};');
  }
  b.writeln('}');
  return b.toString();
}

String generateTypeScriptBrand(Map<String, dynamic> brand) {
  final hosting = brand['hostingDomains'] as Map<String, dynamic>;
  return '''// GENERATED por design_tokens:generate \u2014 NO EDITAR A MANO.
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

String generateCss(Map<String, dynamic> brand, Map<String, dynamic> tokens) {
  final color = tokens['color'] as Map<String, dynamic>;
  final semantic = color['semantic'] as Map<String, dynamic>;
  final typography = tokens['typography'] as Map<String, dynamic>;
  final spacing = tokens['spacing'] as Map<String, dynamic>;
  final radius = tokens['radius'] as Map<String, dynamic>;
  final motion = tokens['motion'] as Map<String, dynamic>;
  final durations = motion['durations'] as Map<String, dynamic>;
  final easing = (motion['easingEmphasized'] as List<dynamic>).cast<num>();
  final roles = color['roles'] as Map<String, dynamic>;

  String block(String mode) {
    final b = StringBuffer();
    for (final entry in _canonicalEntries(roles, _roleOrder)) {
      final value = entry.value as Map<String, dynamic>;
      b.writeln('  --color-${_kebab(entry.key)}: ${value[mode]};');
    }
    for (final entry in _canonicalEntries(semantic, _semanticOrder)) {
      final value = entry.value as Map<String, dynamic>;
      b.writeln('  --color-${_kebab(entry.key)}: ${value[mode]};');
    }
    return b.toString();
  }

  final shared = StringBuffer();
  shared.writeln('  --color-seed: ${color['seed']};');
  shared.writeln(
    "  --font-family: '${typography['fontFamily']}', system-ui, sans-serif;",
  );
  for (final entry in _canonicalEntries(spacing, _spacingOrder)) {
    shared.writeln('  --space-${entry.key}: ${entry.value}px;');
  }
  for (final entry in _canonicalEntries(radius, _radiusOrder)) {
    shared.writeln('  --radius-${_kebab(entry.key)}: ${entry.value}px;');
  }
  shared.writeln('  --easing-emphasized: cubic-bezier(${easing.join(', ')});');
  for (final entry in _canonicalEntries(durations, _durationOrder)) {
    shared.writeln(
      '  --duration-${_kebab(entry.key).replaceAll('-ms', '')}: '
      '${entry.value}ms;',
    );
  }

  return '''
/* GENERATED por design_tokens:generate \u2014 NO EDITAR A MANO. */
/* Fuente: packages/design_tokens/assets/ \u00B7 App: ${brand['appName']} */

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

String _normalizeLineEndings(String value) =>
    value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

List<MapEntry<String, dynamic>> _canonicalEntries(
  Map<String, dynamic> map,
  List<String> preferredOrder,
) {
  final preferred = preferredOrder.toSet();
  final entries = <MapEntry<String, dynamic>>[];
  for (final key in preferredOrder) {
    if (map.containsKey(key)) {
      entries.add(MapEntry<String, dynamic>(key, map[key]));
    }
  }
  final remainingKeys =
      map.keys.where((key) => !preferred.contains(key)).toList()..sort();
  for (final key in remainingKeys) {
    entries.add(MapEntry<String, dynamic>(key, map[key]));
  }
  return entries;
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

String _argb(String hex) => '0xFF${hex.substring(1).toUpperCase()}';

String _fontFamilyLiteral(String family) =>
    family.isEmpty ? 'null' : "'$family'";

String _kebab(String value) => value.replaceAllMapped(
  RegExp('[A-Z]'),
  (match) => '-${match[0]!.toLowerCase()}',
);
