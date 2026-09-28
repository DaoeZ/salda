import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'social_log.dart';

/// Vuelca el estado REAL de Auth y Firestore al empezar el flujo.
///
/// Va contra los SDK directamente —no contra los repositorios— para que la
/// traza refleje lo que ve Firebase, no lo que la app cree.
abstract final class SocialProbe {
  /// Una sonda NUNCA puede cambiar el comportamiento de lo que observa: si
  /// algo falla aquí (sin Firebase inicializado, por ejemplo) se anota y se
  /// sigue. Sin esto, el propio diagnóstico rompería el flujo que investiga.
  static Future<void> _guard(
    String flow,
    String method,
    String fase,
    Future<void> Function() body,
  ) async {
    try {
      await body();
    } on Object catch (error) {
      SocialLog.log(flow, method, {
        'fase': '$fase-sonda-fallo',
        ...SocialLog.errorFields(error),
      });
    }
  }

  static Future<void> dumpAuth(String flow, String method) =>
      _guard(flow, method, 'auth', () => _dumpAuth(flow, method));

  static Future<void> _dumpAuth(String flow, String method) async {
    try {
      final app = Firebase.app();
      SocialLog.log(flow, method, {
        'fase': 'app',
        'appNombre': app.name,
        'projectId': app.options.projectId,
        'appId': SocialLog.fingerprint(app.options.appId),
      });
    } on Object catch (error) {
      SocialLog.log(flow, method, {
        'fase': 'app',
        ...SocialLog.errorFields(error),
      });
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      SocialLog.log(flow, method, {'fase': 'auth', 'usuario': 'ninguno'});
      return;
    }
    SocialLog.log(flow, method, {
      'fase': 'auth-local',
      'uid': SocialLog.fingerprint(user.uid),
      'anonimo': user.isAnonymous,
      'emailVerificadoLocal': user.emailVerified,
      'tieneEmail': user.email != null,
      'tieneNombre': (user.displayName ?? '').trim().isNotEmpty,
      'providers': user.providerData.map((p) => p.providerId).join(','),
    });

    // Claims del ID token SIN refrescar: es lo que las Rules están leyendo
    // ahora mismo.
    await _dumpToken(flow, method, refresh: false);
  }

  static Future<void> dumpToken(String flow, String method) => _guard(
    flow,
    method,
    'token',
    () => _dumpToken(flow, method, refresh: true),
  );

  static Future<void> _dumpToken(
    String flow,
    String method, {
    required bool refresh,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final token = await user.getIdTokenResult(refresh);
      final claims = token.claims ?? const <String, dynamic>{};
      final firebase = claims['firebase'];
      SocialLog.log(flow, method, {
        'fase': refresh ? 'token-refrescado' : 'token-actual',
        'signInProvider': firebase is Map ? firebase['sign_in_provider'] : null,
        'emailVerifiedClaim': claims['email_verified'],
        'emitido': token.issuedAtTime?.toIso8601String(),
        'expira': token.expirationTime?.toIso8601String(),
        'audCoincide': claims['aud'] == Firebase.app().options.projectId,
      });
    } on Object catch (error) {
      SocialLog.log(flow, method, {
        'fase': refresh ? 'token-refrescado' : 'token-actual',
        ...SocialLog.errorFields(error),
      });
    }
  }

  static void dumpFirestore(String flow, String method) {
    try {
      final db = FirebaseFirestore.instance;
      SocialLog.log(flow, method, {
        'fase': 'firestore',
        'projectId': db.app.options.projectId,
        'host': db.settings.host ?? 'produccion',
        'emulador': db.settings.host != null,
        'sslHabilitado': db.settings.sslEnabled,
      });
    } on Object catch (error) {
      SocialLog.log(flow, method, {
        'fase': 'firestore-sonda-fallo',
        ...SocialLog.errorFields(error),
      });
    }
  }

  /// Lee un documento contra el SERVIDOR y contra la caché por separado: si
  /// la caché contesta y el servidor no, el problema es de permisos, no de
  /// existencia.
  static Future<void> probeDoc(
    String flow,
    String method,
    String etiqueta,
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    for (final origen in [Source.server, Source.cache]) {
      try {
        final snap = await ref.get(GetOptions(source: origen));
        SocialLog.log(flow, method, {
          'fase': 'lectura',
          'doc': etiqueta,
          'origen': origen.name,
          'existe': snap.exists,
          'campos': snap.data()?.keys.join(',') ?? '-',
        });
      } on Object catch (error) {
        SocialLog.log(flow, method, {
          'fase': 'lectura',
          'doc': etiqueta,
          'origen': origen.name,
          ...SocialLog.errorFields(error),
        });
      }
    }
  }
}
