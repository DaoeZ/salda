import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/diagnostics/social_log.dart';
import '../../profile/data/profile_repository.dart';
import '../data/auth_repository.dart';

/// Por qué una cuenta puede —o no— escribir en el ámbito social.
///
/// Existe porque «cuenta lista» se estaba decidiendo en tres sitios que no
/// coincidían: Ajustes lo deducía de `FirebaseAuth` (nombre, correo y
/// verificación, que en Google vienen rellenos desde el primer segundo),
/// `isFullAccount` de la sesión local, y Rules de `canUseSocial()`. Con esa
/// discrepancia la pantalla afirmaba que todo estaba bien mientras el
/// servidor denegaba cada escritura.
enum SocialReadiness {
  /// Cumple las tres condiciones de `canUseSocial()`.
  ready,

  /// No hay sesión.
  notSignedIn,

  /// Invitado sin convertir. No es un fallo: es que aún no hay cuenta.
  anonymous,

  /// El correo no está verificado de verdad.
  emailNotVerified,

  /// El ID token no refleja lo que dice el usuario local. Se resuelve solo
  /// refrescándolo; solo se reporta si el refresco no basta.
  staleToken,

  /// Falta `profiles/{uid}`. **Reparable**: es la causa que dejaba a una
  /// cuenta de Google perfectamente válida sin poder crear nada.
  publicProfileMissing,

  /// El perfil existe pero no se pudo leer o completar.
  publicProfileUnavailable,
}

/// Resultado del diagnóstico, con el detalle que sirve para depurar sin
/// exponer datos personales.
class SocialAccountStatus {
  const SocialAccountStatus(this.readiness, {this.repaired = false});

  final SocialReadiness readiness;

  /// El perfil público se creó durante esta comprobación.
  final bool repaired;

  bool get isReady => readiness == SocialReadiness.ready;
}

/// Deja la cuenta en condiciones de escribir en el ámbito social, o explica
/// por qué no puede.
///
/// Orden deliberado: primero lo que se arregla solo (token), después lo que
/// depende del usuario (verificar el correo) y por último lo reparable
/// (perfil público). No hay bucle de reintentos: cada paso se intenta una vez.
class SocialAccountService {
  SocialAccountService({required this.auth, required this.profiles});

  final AuthRepository auth;
  final ProfileRepository profiles;

  Future<SocialAccountStatus> prepare({String flow = '-'}) async {
    final reloj = Stopwatch()..start();
    SocialLog.log(flow, 'prepare', {'fase': 'entra'});
    final user = auth.currentUser;
    if (user == null) {
      SocialLog.log(flow, 'prepare', {'fase': 'sale', 'motivo': 'sin-sesion'});
      return const SocialAccountStatus(SocialReadiness.notSignedIn);
    }
    if (user.isAnonymous) {
      SocialLog.log(flow, 'prepare', {'fase': 'sale', 'motivo': 'anonimo'});
      return const SocialAccountStatus(SocialReadiness.anonymous);
    }

    // 1) El token puede ir por detrás del usuario local: tras vincular una
    //    cuenta o tras verificar el correo, las Rules siguen leyendo los
    //    claims viejos. Refrescar es barato y arregla los dos casos.
    // `refreshEmailVerification` recarga el usuario Y renueva el ID token,
    // que es lo que leen las Rules.
    var verified = user.emailVerified;
    SocialLog.log(flow, 'prepare', {
      'fase': 'verificacion',
      'verificadoLocal': verified,
    });
    if (!verified) {
      verified = await auth.refreshEmailVerification();
      SocialLog.log(flow, 'prepare', {
        'fase': 'verificacion-refrescada',
        'verificado': verified,
      });
      if (!verified) {
        return const SocialAccountStatus(SocialReadiness.emailNotVerified);
      }
    }

    // 2) El perfil PÚBLICO es lo único que Rules miran además del token, y
    //    lo que Ajustes nunca comprobó. Entrar con Google no lo crea: sin
    //    pasar por la pantalla de perfil, `profiles/{uid}` no existe.
    try {
      SocialLog.log(flow, 'prepare', {
        'fase': 'lee-perfil-publico',
        'uid': SocialLog.fingerprint(user.uid),
      });
      final existing = await profiles.fetchProfile(user.uid);
      SocialLog.log(flow, 'prepare', {
        'fase': 'perfil-publico',
        'existe': existing != null,
        'tieneUsername': (existing?.username ?? '').isNotEmpty,
        'tieneNombre': (existing?.displayName ?? '').isNotEmpty,
      });
      if (existing != null) {
        SocialLog.log(flow, 'prepare', {
          'fase': 'sale',
          'motivo': 'listo',
          'ms': reloj.elapsedMilliseconds,
        });
        return const SocialAccountStatus(SocialReadiness.ready);
      }
    } on Object catch (error) {
      SocialLog.log(flow, 'prepare', {
        'fase': 'perfil-publico-error',
        ...SocialLog.errorFields(error),
      });
      return const SocialAccountStatus(
        SocialReadiness.publicProfileUnavailable,
      );
    }

    // 3) Reparación IDEMPOTENTE: se crea el perfil que falta a partir de lo
    //    que ya se sabe de la cuenta. Si otra ejecución lo creó mientras
    //    tanto, el segundo intento encuentra el documento y no escribe nada.
    final resultado = await _repair(user, flow);
    SocialLog.log(flow, 'prepare', {
      'fase': 'sale',
      'motivo': resultado.readiness.name,
      'reparado': resultado.repaired,
      'ms': reloj.elapsedMilliseconds,
    });
    return resultado;
  }

  Future<SocialAccountStatus> _repair(AppUser user, String flow) async {
    final nombre = (user.displayName ?? '').trim().isNotEmpty
        ? user.displayName!.trim()
        : (user.email ?? '').split('@').first;
    SocialLog.log(flow, 'repair', {
      'fase': 'entra',
      'origenNombre': (user.displayName ?? '').trim().isNotEmpty
          ? 'displayName'
          : 'email',
      'nombreVacio': nombre.isEmpty,
    });
    if (nombre.isEmpty) {
      return const SocialAccountStatus(SocialReadiness.publicProfileMissing);
    }
    try {
      // `suggestUsername` ya descarta los ocupados, así que no se puede
      // pisar el username de otra persona; y si aun así se perdiera la
      // carrera, Rules rechazan el batch y no se escribe nada a medias.
      final username = await profiles.suggestUsername(nombre);
      SocialLog.log(flow, 'repair', {
        'fase': 'username-sugerido',
        'longitud': username.length,
        'huella': SocialLog.fingerprint(username),
      });
      await profiles.createProfile(
        displayName: nombre,
        username: username,
        flow: flow,
      );
      SocialLog.log(flow, 'repair', {'fase': 'perfil-creado'});
      return const SocialAccountStatus(SocialReadiness.ready, repaired: true);
    } on Object catch (error) {
      SocialLog.log(flow, 'repair', {
        'fase': 'error',
        ...SocialLog.errorFields(error),
      });
      // Puede haberlo creado otra pantalla entre medias: eso NO es un fallo.
      final ahora = await profiles.fetchProfile(user.uid);
      SocialLog.log(flow, 'repair', {
        'fase': 'reintento-lectura',
        'existeAhora': ahora != null,
      });
      if (ahora != null) {
        return const SocialAccountStatus(SocialReadiness.ready);
      }
      return const SocialAccountStatus(SocialReadiness.publicProfileMissing);
    }
  }
}

final socialAccountServiceProvider = Provider<SocialAccountService>((ref) {
  return SocialAccountService(
    auth: ref.watch(authRepositoryProvider),
    profiles: ref.watch(profileRepositoryProvider),
  );
});
