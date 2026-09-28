/// Harness del corpus de regresión (test/corpus/README.md).
///
/// - Los casos `mustPass: true` son contrato: si fallan, rompe la CI.
/// - Todos los casos alimentan las métricas por campo, que se imprimen al
///   final (% de acierto por campo y casos problemáticos).
library;

import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:ocr_parser/ocr_parser.dart';
import 'package:test/test.dart';

void main() {
  final parser = ReceiptParser.standard();
  final caseDirs =
      Directory('test/corpus').listSync().whereType<Directory>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final stats = _Stats();

  for (final dir in caseDirs) {
    final name = dir.path.split(Platform.pathSeparator).last;
    final expected =
        jsonDecode(File('${dir.path}/expected.json').readAsStringSync())
            as Map<String, dynamic>;
    final mustPass = expected['mustPass'] as bool? ?? true;

    test('corpus: $name${mustPass ? '' : ' (limitación conocida)'}', () {
      final input = File('${dir.path}/input.txt').readAsStringSync();
      final result = parser.parsePlainText(input);
      final diffs = _compare(expected, result);
      stats.record(name, expected, result, diffs);

      if (mustPass) {
        expect(
          diffs,
          isEmpty,
          reason: 'Diferencias en $name:\n${diffs.join('\n')}',
        );
      } else if (diffs.isEmpty) {
        fail('$name ya pasa: promociona mustPass a true en expected.json');
      }
    });
  }

  tearDownAll(stats.printReport);
}

/// Compara solo las claves presentes en expected (comparación parcial).
List<String> _compare(Map<String, dynamic> expected, ReceiptExtraction r) {
  final diffs = <String>[];
  void check(String field, Object? want, Object? got) {
    if (!_equal(want, got)) diffs.add('$field: esperado $want, obtenido $got');
  }

  if (expected.containsKey('merchantName')) {
    check('merchantName', expected['merchantName'], r.merchantName.value);
  }
  if (expected.containsKey('brandKey')) {
    check('brandKey', expected['brandKey'], r.brandKey);
  }
  if (expected.containsKey('category')) {
    check('category', expected['category'], r.category);
  }
  if (expected.containsKey('date')) {
    check('date', expected['date'], r.date.value);
  }
  if (expected.containsKey('time')) {
    check('time', expected['time'], r.time.value);
  }
  if (expected.containsKey('grandTotal')) {
    check('grandTotal', expected['grandTotal'], r.grandTotal.value?.cents);
  }
  if (expected.containsKey('subtotal')) {
    check('subtotal', expected['subtotal'], r.subtotal.value?.cents);
  }
  if (expected.containsKey('tip')) {
    check('tip', expected['tip'], r.tip.value?.cents);
  }
  if (expected.containsKey('needsReview')) {
    check('needsReview', expected['needsReview'], r.needsReview);
  }
  if (expected.containsKey('issues')) {
    check(
      'issues',
      ((expected['issues'] as List).cast<String>()..sort()).join(','),
      (r.issues.map((i) => i.code).toList()..sort()).join(','),
    );
  }
  for (final (key, actual) in [
    ('discounts', r.discounts),
    ('taxes', r.taxes),
  ]) {
    if (!expected.containsKey(key)) continue;
    final want = [
      for (final e in expected[key] as List)
        '${(e as Map)['label']}=${e['amount']}',
    ].join(';');
    final got = [
      for (final a in actual) '${a.label}=${a.amount.cents}',
    ].join(';');
    check(key, want, got);
  }
  if (expected.containsKey('lines')) {
    final want = expected['lines'] as List;
    if (want.length != r.lines.length) {
      diffs.add(
        'lines: esperadas ${want.length}, obtenidas ${r.lines.length} '
        '(${r.lines.map((l) => l.name).join(' | ')})',
      );
    } else {
      for (var i = 0; i < want.length; i++) {
        final w = want[i] as Map<String, dynamic>;
        final g = r.lines[i];
        check('lines[$i].name', w['name'], g.name);
        check('lines[$i].quantityMilli', w['quantityMilli'], g.quantityMilli);
        check('lines[$i].unitPrice', w['unitPrice'], g.unitPrice?.cents);
        check('lines[$i].totalPrice', w['totalPrice'], g.totalPrice.cents);
      }
    }
  }
  return diffs;
}

bool _equal(Object? a, Object? b) => a == b;

class _Stats {
  final Map<String, ({int ok, int total})> _fields = {};
  final List<String> _failing = [];
  int _cases = 0;
  int _casesOk = 0;

  void record(
    String name,
    Map<String, dynamic> expected,
    ReceiptExtraction r,
    List<String> diffs,
  ) {
    _cases++;
    if (diffs.isEmpty) _casesOk++;
    if (diffs.isNotEmpty) _failing.add('$name → ${diffs.first}');

    for (final field in [
      'merchantName',
      'date',
      'time',
      'grandTotal',
      'lines',
      'taxes',
      'discounts',
      'issues',
    ]) {
      if (!expected.containsKey(field)) continue;
      final failed = diffs.any((d) => d.startsWith(field));
      final current = _fields[field] ?? (ok: 0, total: 0);
      _fields[field] = (
        ok: current.ok + (failed ? 0 : 1),
        total: current.total + 1,
      );
    }
  }

  void printReport() {
    final buffer = StringBuffer()
      ..writeln('')
      ..writeln('══ INFORME DEL CORPUS ══════════════════════════')
      ..writeln(
        'Casos completos correctos: $_casesOk/$_cases '
        '(${(_casesOk * 100 / _cases).toStringAsFixed(0)}%)',
      );
    for (final e in _fields.entries) {
      buffer.writeln(
        '  ${e.key.padRight(14)} ${e.value.ok}/${e.value.total} '
        '(${(e.value.ok * 100 / e.value.total).toStringAsFixed(0)}%)',
      );
    }
    if (_failing.isNotEmpty) {
      buffer.writeln('Casos con diferencias:');
      for (final f in _failing) {
        buffer.writeln('  · $f');
      }
    }
    buffer.writeln('════════════════════════════════════════════════');
    // ignore: avoid_print
    print(buffer);
  }
}
