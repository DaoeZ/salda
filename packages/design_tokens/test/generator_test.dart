import 'dart:convert';
import 'dart:io';

import 'package:design_tokens/src/generator.dart';
import 'package:test/test.dart';

late String _packageRoot;
late Map<String, dynamic> _brand;
late Map<String, dynamic> _tokens;

void main() {
  setUpAll(() {
    _packageRoot = _findPackageRoot();
    _brand = _readJson('$_packageRoot/assets/brand.json');
    _tokens = _readJson('$_packageRoot/assets/design_tokens.json');
  });

  test('Dart generation is deterministic for the committed inputs', () {
    final first = generateDart(_brand, _tokens);
    final second = generateDart(_brand, _tokens);

    expect(second, equals(first));
  });

  test('two consecutive pure generations are byte-identical', () {
    final first = generateArtifacts(_brand, _tokens);
    final second = generateArtifacts(_brand, _tokens);

    for (final path in first.byPath.keys) {
      expect(
        utf8.encode(second.byPath[path]!),
        orderedEquals(utf8.encode(first.byPath[path]!)),
        reason: path,
      );
    }
  });

  test('generation is independent of map insertion order', () {
    final reorderedBrand = _reverseMap(_brand);
    final reorderedTokens = _reverseMap(_tokens);
    final expected = generateArtifacts(_brand, _tokens);
    final actual = generateArtifacts(reorderedBrand, reorderedTokens);

    for (final path in expected.byPath.keys) {
      expect(
        utf8.encode(actual.byPath[path]!),
        orderedEquals(utf8.encode(expected.byPath[path]!)),
        reason: path,
      );
    }
  });

  test('avatarPalette keeps the source list order', () {
    const expected = '''  static const List<int> avatarPalette = [
    0xFF0B5E4E,
    0xFF3F6B8A,
    0xFF8A6136,
    0xFF6B5296,
    0xFF9E4A68,
    0xFF3D7A78,
    0xFF7C6A22,
    0xFF4A7C50,
  ];''';

    expect(generateDart(_brand, _tokens), contains(expected));
  });

  test('generated Dart equals the versioned file', () {
    final expected = utf8.encode(generateDart(_brand, _tokens));
    final actual = File(
      '$_packageRoot/lib/src/tokens.g.dart',
    ).readAsBytesSync();

    expect(actual, orderedEquals(expected));
  });

  test('generated artifacts use LF and end with a newline', () {
    final artifacts = generateArtifacts(_brand, _tokens);

    for (final entry in artifacts.byPath.entries) {
      final bytes = utf8.encode(entry.value);
      expect(bytes, isNotEmpty, reason: entry.key);
      expect(bytes.last, equals(0x0A), reason: entry.key);
      expect(bytes, isNot(contains(0x0D)), reason: entry.key);
    }
  });

  test('generated Dart is stable under the Dart formatter', () {
    final temporaryDirectory = Directory.systemTemp.createTempSync(
      'design_tokens_format_',
    );
    addTearDown(() {
      if (temporaryDirectory.existsSync()) {
        temporaryDirectory.deleteSync(recursive: true);
      }
    });

    final file = File('${temporaryDirectory.path}/tokens.g.dart');
    file.writeAsBytesSync(utf8.encode(generateDart(_brand, _tokens)));
    final result = Process.runSync(Platform.resolvedExecutable, <String>[
      'format',
      '--output=none',
      '--set-exit-if-changed',
      file.path,
    ]);

    expect(
      result.exitCode,
      equals(0),
      reason: '${result.stdout}\n${result.stderr}',
    );
  });

  test('stale content is reported without mutating the actual bytes', () {
    final artifacts = generateArtifacts(_brand, _tokens);
    final actual = <String, List<int>>{
      for (final entry in artifacts.byPath.entries)
        entry.key: utf8.encode(entry.value),
    };
    const stalePath = 'packages/design_tokens/lib/src/tokens.g.dart';
    final staleBytes = <int>[...actual[stalePath]!, 0x20];
    actual[stalePath] = staleBytes;

    final stale = findStalePaths(artifacts, actual);

    expect(stale, equals(<String>[stalePath]));
    expect(actual[stalePath], orderedEquals(staleBytes));
    expect(
      formatFreshnessFailure(stale),
      allOf(contains(stalePath), contains('dart run design_tokens:generate')),
    );
  });
}

String _findPackageRoot() {
  var directory = Directory.current.absolute;
  while (true) {
    final directBrand = File('${directory.path}/assets/brand.json');
    final directTokens = File('${directory.path}/assets/design_tokens.json');
    if (directBrand.existsSync() && directTokens.existsSync()) {
      return directory.path;
    }

    final nestedBrand = File(
      '${directory.path}/packages/design_tokens/assets/brand.json',
    );
    final nestedTokens = File(
      '${directory.path}/packages/design_tokens/assets/design_tokens.json',
    );
    if (nestedBrand.existsSync() && nestedTokens.existsSync()) {
      return '${directory.path}/packages/design_tokens';
    }

    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Could not find the design_tokens package root.');
    }
    directory = parent;
  }
}

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic> _reverseMap(Map<String, dynamic> source) {
  final result = <String, dynamic>{};
  for (final entry in source.entries.toList().reversed) {
    result[entry.key] = _reverseValue(entry.value);
  }
  return result;
}

Object? _reverseValue(Object? value) {
  if (value is Map<String, dynamic>) {
    return _reverseMap(value);
  }
  if (value is List<dynamic>) {
    return value.map<Object?>(_reverseValue).toList();
  }
  return value;
}
