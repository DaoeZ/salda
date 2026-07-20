import 'dart:math';

import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeUsername', () {
    test('recorta espacios y pasa a minúsculas', () {
      expect(normalizeUsername('  Edgar_98 '), 'edgar_98');
      expect(normalizeUsername('EDGAR'), 'edgar');
    });
  });

  group('validateUsername', () {
    test('acepta usernames válidos', () {
      for (final username in [
        'edgar',
        'edgar98',
        'edgar_cantera',
        'abc',
        'a2345678901234567890', // 20 exactos
        'e_c_2',
      ]) {
        expect(validateUsername(username), isNull, reason: username);
      }
    });

    test('es case-insensitive: valida la forma normalizada', () {
      expect(validateUsername('  EDGAR '), isNull);
    });

    test('vacío y longitudes fuera de rango', () {
      expect(validateUsername(''), UsernameError.empty);
      expect(validateUsername('   '), UsernameError.empty);
      expect(validateUsername('ed'), UsernameError.tooShort);
      expect(
        validateUsername('a23456789012345678901'), // 21
        UsernameError.tooLong,
      );
    });

    test('caracteres inválidos: tildes, ñ, espacios, símbolos', () {
      for (final username in ['edgár', 'ñoño', 'ed gar', 'edgar!', 'ed-gar']) {
        expect(
          validateUsername(username),
          UsernameError.invalidCharacters,
          reason: username,
        );
      }
    });

    test('debe empezar por letra', () {
      expect(validateUsername('9edgar'), UsernameError.mustStartWithLetter);
      expect(validateUsername('_edgar'), UsernameError.mustStartWithLetter);
    });

    test('guiones bajos: ni final ni consecutivos', () {
      expect(validateUsername('edgar_'), UsernameError.endsWithUnderscore);
      expect(validateUsername('ed__gar'), UsernameError.consecutiveUnderscores);
    });

    test('nombres reservados, también con mayúsculas', () {
      expect(validateUsername('admin'), UsernameError.reserved);
      expect(validateUsername('Salda'), UsernameError.reserved);
      expect(validateUsername('SOPORTE'), UsernameError.reserved);
    });
  });

  group('searchableText', () {
    test('quita diacríticos y baja a minúsculas', () {
      expect(searchableText('Édgar Cañtera'), 'edgar cantera');
      expect(searchableText('MARÍA José'), 'maria jose');
    });

    test('descarta símbolos y colapsa espacios', () {
      expect(searchableText('  Edgar   J. Cantera! '), 'edgar j cantera');
    });
  });

  group('usernameCandidates', () {
    test(
      'orden natural: base, base+2 dígitos, base_apellido, base+3 dígitos',
      () {
        final random = Random(7);
        final candidates = usernameCandidates(
          'Edgar Cantera',
          nextInt: random.nextInt,
        );
        expect(candidates.first, 'edgar');
        expect(candidates[1], matches(r'^edgar\d{2}$'));
        expect(candidates[2], 'edgar_cantera');
        expect(candidates[3], matches(r'^edgar\d{3}$'));
        expect(candidates, contains('edgarcantera'));
        expect(candidates, contains('edgarc'));
      },
    );

    test('todos los candidatos son válidos y sin duplicados', () {
      final random = Random(42);
      for (final name in [
        'Edgar Cantera',
        'María José García',
        'Ñoño',
        '  A  ',
        '', // sin nombre: cae al genérico
        '3dgar', // empieza por dígito
        'Æthelred von Hohenzollern-Sigmaringen',
      ]) {
        final candidates = usernameCandidates(name, nextInt: random.nextInt);
        expect(candidates, isNotEmpty, reason: name);
        expect(candidates.toSet().length, candidates.length, reason: name);
        for (final candidate in candidates) {
          expect(validateUsername(candidate), isNull, reason: candidate);
        }
      }
    });

    test('nombre de una sola palabra no propone variantes con apellido', () {
      final random = Random(1);
      final candidates = usernameCandidates('Edgar', nextInt: random.nextInt);
      expect(candidates.first, 'edgar');
      for (final candidate in candidates.skip(1)) {
        expect(candidate, matches(r'^edgar\d{2,4}$'));
      }
    });

    test('nombres largos se recortan a 20 sin guion bajo colgando', () {
      final random = Random(3);
      final candidates = usernameCandidates(
        'Maximiliano Domínguez de Todos los Santos',
        nextInt: random.nextInt,
      );
      for (final candidate in candidates) {
        expect(candidate.length, lessThanOrEqualTo(usernameMaxLength));
        expect(candidate.endsWith('_'), isFalse);
      }
    });

    test('con la misma semilla las propuestas son reproducibles', () {
      List<String> generate() =>
          usernameCandidates('Edgar Cantera', nextInt: Random(99).nextInt);
      expect(generate(), generate());
    });
  });

  group('avatar', () {
    test('el color es determinista y estable para el mismo uid', () {
      final a = avatarColorIndex('uid-abc-123', 8);
      expect(avatarColorIndex('uid-abc-123', 8), a);
      expect(a, inInclusiveRange(0, 7));
    });

    test('uids distintos se reparten por la paleta', () {
      final indices = <int>{
        for (var i = 0; i < 40; i++) avatarColorIndex('uid-$i', 8),
      };
      // No exigimos uniformidad perfecta, solo que use varios colores.
      expect(indices.length, greaterThan(3));
    });

    test('iniciales: dos palabras, una palabra y texto vacío', () {
      expect(avatarInitials('Edgar Cantera'), 'EC');
      expect(avatarInitials('edgar'), 'E');
      expect(avatarInitials('  maría   josé  '), 'MJ');
      expect(avatarInitials(''), '?');
    });
  });
}
