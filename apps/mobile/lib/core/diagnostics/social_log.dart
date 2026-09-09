import 'dart:isolate';

import 'package:flutter/foundation.dart';

/// Traza del flujo social para capturar en un dispositivo real.
///
/// Formato de cada línea, para poder seguir UNA ejecución concreta:
///
///     SALDA_SOCIAL|<hora>|<commit>|<flujo>|<hilo>|<método>|clave=valor …
///
/// **Nunca** se escribe un dato personal: ni correo, ni UID completo, ni
/// token, ni username, ni manualId. Lo que necesita identidad se reduce a
/// una huella corta y estable ([fingerprint]) que sirve para comparar dos
/// valores entre sí sin revelar ninguno.
abstract final class SocialLog {
  static const _prefix = 'SALDA_SOCIAL';

  /// Hash corto del commit, inyectado al compilar con
  /// `--dart-define=SALDA_COMMIT=…`.
  static const commit = String.fromEnvironment(
    'SALDA_COMMIT',
    defaultValue: 'sin-commit',
  );

  /// Identificador de UNA ejecución del flujo. Todas sus líneas lo llevan,
  /// así que un logcat con varios intentos sigue siendo legible.
  static String startFlow() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return (now & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  }

  static void log(
    String flow,
    String method, [
    Map<String, Object?> fields = const {},
  ]) {
    final campos = fields.entries
        .map((e) => '${e.key}=${_value(e.value)}')
        .join(' ');
    final linea = [
      _prefix,
      DateTime.now().toIso8601String(),
      commit,
      flow,
      Isolate.current.debugName ?? 'isolate',
      method,
      campos,
    ].join('|');
    // SÍNCRONO a propósito: `debugPrint` estrangula la salida y reordena o
    // retrasa líneas cuando hay muchas seguidas, que es justo cuando esta
    // traza importa. Va a logcat bajo la etiqueta de Flutter.
    debugPrintSynchronously(linea);
  }

  /// Huella corta y estable de un valor sensible. Permite comparar («¿es el
  /// mismo uid que antes?») sin escribir el valor.
  static String fingerprint(String? value) {
    if (value == null) return 'null';
    if (value.isEmpty) return 'vacio';
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = (hash ^ unit) * 0x01000193 & 0xFFFFFFFF;
    }
    return '#${hash.toRadixString(16).padLeft(8, '0').substring(0, 6)}';
  }

  /// Describe un error sin volcar su mensaje, que puede llevar rutas.
  static Map<String, Object?> errorFields(Object error) => {
    'errorTipo': error.runtimeType,
    'errorCodigo': _codeOf(error),
  };

  static String _codeOf(Object error) {
    // Se lee por duck typing para no acoplar este módulo a Firebase.
    try {
      final code = (error as dynamic).code;
      if (code is String) return code;
    } on Object {
      // Sin `code`: basta con el tipo.
    }
    return 'sin-codigo';
  }

  static String _value(Object? value) {
    if (value == null) return 'null';
    final texto = value.toString();
    // Corta cualquier cosa larga: nada de volcar objetos enteros.
    return texto.length <= 40 ? texto : '${texto.substring(0, 40)}…';
  }
}
