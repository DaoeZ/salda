/// Generate the design-token artifacts or check that they are fresh.
///
/// Usage from the repository root or a repository subdirectory:
/// `dart run design_tokens:generate`
/// `dart run design_tokens:generate --check`
library;

import 'dart:convert';
import 'dart:io';

import '../lib/src/generator.dart';

void main(List<String> args) {
  if (args.length > 1 || (args.isNotEmpty && args.first != '--check')) {
    stderr.writeln('Usage: dart run design_tokens:generate [--check]');
    exitCode = 64;
    return;
  }

  final repoRoot = _findRepoRoot();
  final packageRoot = '$repoRoot/packages/design_tokens';
  final brand = _readJson('$packageRoot/assets/brand.json');
  final tokens = _readJson('$packageRoot/assets/design_tokens.json');
  final artifacts = generateArtifacts(brand, tokens);

  if (args.isNotEmpty) {
    final actual = _readExistingArtifacts(repoRoot, artifacts);
    final stale = findStalePaths(artifacts, actual);
    if (stale.isNotEmpty) {
      stderr.writeln(formatFreshnessFailure(stale));
      exitCode = 1;
      return;
    }
    stdout.writeln('Generated files are fresh.');
    return;
  }

  for (final entry in artifacts.byPath.entries) {
    _writeUtf8Lf('$repoRoot/${entry.key}', entry.value);
  }
  stdout.writeln('tokens.g.dart, tokens.g.css and brand.g.ts regenerated.');
}

Map<String, List<int>> _readExistingArtifacts(
  String repoRoot,
  GeneratedArtifacts artifacts,
) {
  final actual = <String, List<int>>{};
  for (final path in artifacts.byPath.keys) {
    final file = File('$repoRoot/$path');
    actual[path] = file.existsSync() ? file.readAsBytesSync() : const <int>[];
  }
  return actual;
}

void _writeUtf8Lf(String path, String contents) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(utf8.encode(contents), flush: true);
}

String _findRepoRoot() {
  var directory = Directory.current.absolute;
  while (true) {
    if (File(
      '${directory.path}/packages/design_tokens/assets/design_tokens.json',
    ).existsSync()) {
      return directory.path;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'Could not find the repository root from ${Directory.current.path}',
      );
    }
    directory = parent;
  }
}

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
