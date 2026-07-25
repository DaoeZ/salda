import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Coherencia de la identidad Android entre los archivos que la repiten.
///
/// El identificador de la app vive en UN sitio —`build.gradle.kts`— porque es
/// el único valor que compila y el que ven Android, Firebase y los App Links.
/// Pero `assetlinks.json` tiene que repetirlo (es un JSON estático servido por
/// HTTP) y el manifest repite los dominios. Esa duplicación es inevitable; lo
/// que no es inevitable es que se separen en silencio.
///
/// Ya pasó una vez: `brand.json` declaraba `dev.salda.app` mientras Gradle
/// compilaba `dev.salda.salda_mobile`, y la contradicción sobrevivió a varias
/// fases sin que nada fallara. Estas pruebas convierten esa deriva en un
/// build roto.
void main() {
  // Los tests de Flutter se ejecutan con cwd = apps/mobile.
  final gradle = File('android/app/build.gradle.kts');
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  final assetlinks = File(
    '../guest_web/public/.well-known/assetlinks.json',
  );
  final brand = File('../../packages/design_tokens/assets/brand.json');

  String applicationId() {
    final match = RegExp(
      r'applicationId\s*=\s*"([^"]+)"',
    ).firstMatch(gradle.readAsStringSync());
    return match!.group(1)!;
  }

  test('el applicationId y el namespace de Gradle coinciden', () {
    final namespace = RegExp(
      r'namespace\s*=\s*"([^"]+)"',
    ).firstMatch(gradle.readAsStringSync())!.group(1);
    expect(applicationId(), namespace);
  });

  test('assetlinks.json declara el paquete que REALMENTE compila', () {
    final statements =
        jsonDecode(assetlinks.readAsStringSync()) as List<dynamic>;
    final packages = [
      for (final statement in statements)
        ((statement as Map)['target'] as Map)['package_name'] as String,
    ];
    expect(packages, contains(applicationId()));
  });

  test('assetlinks.json es válido para Android App Links', () {
    final statements =
        jsonDecode(assetlinks.readAsStringSync()) as List<dynamic>;
    expect(statements, isNotEmpty);
    for (final statement in statements.cast<Map<String, dynamic>>()) {
      expect(
        statement['relation'],
        contains('delegate_permission/common.handle_all_urls'),
      );
      final target = statement['target'] as Map<String, dynamic>;
      expect(target['namespace'], 'android_app');
      final fingerprints =
          (target['sha256_cert_fingerprints'] as List).cast<String>();
      expect(fingerprints, isNotEmpty);
      for (final fingerprint in fingerprints) {
        // 32 bytes en hex separados por ':' — un SHA-1 (20) colado aquí no
        // verifica nada y es un error difícil de ver a simple vista.
        expect(
          fingerprint,
          matches(RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$')),
          reason: 'huella que no es un SHA-256 en mayúsculas: $fingerprint',
        );
      }
    }
  });

  test('el intent-filter de App Links apunta a los dominios de la marca', () {
    final xml = manifest.readAsStringSync();
    final hosts = {
      for (final match
          in RegExp(r'android:host="([^"]+)"').allMatches(xml))
        match.group(1)!,
    };
    final brandDomains =
        ((jsonDecode(brand.readAsStringSync()) as Map)['hostingDomains']
                as Map)
            .values
            .cast<String>()
            .toSet();

    expect(hosts, brandDomains);
    // La ruta debe ser la misma que registra el router (`/g/:token`), o el
    // deep link no resolvería.
    expect(xml, contains('android:pathPrefix="/g/"'));
    expect(xml, contains('android:scheme="https"'));
    expect(xml, contains('android:autoVerify="true"'));
  });

  test('brand.json ya NO declara un identificador Android propio', () {
    final json = jsonDecode(brand.readAsStringSync()) as Map<String, dynamic>;
    // Tenerlo aquí fue justo el origen de la contradicción: un segundo valor
    // que nadie consumía y que la documentación citaba como oficial.
    expect(json.containsKey('androidApplicationId'), isFalse);
  });
}
