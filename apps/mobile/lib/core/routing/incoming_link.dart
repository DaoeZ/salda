import 'package:design_tokens/design_tokens.dart';

/// Enlace entrante que la app sabe atender.
///
/// Antes cada flujo interpretaba su URL por su cuenta —una ruta para grupos,
/// otra para tickets, y cadenas sueltas repartidas por pantallas y router—,
/// así que cualquier detalle del formato había que arreglarlo dos veces y en
/// sitios distintos. Aquí se decide UNA vez qué es un enlace y qué token
/// lleva; quién puede canjearlo lo siguen decidiendo Rules.
sealed class IncomingLink {
  const IncomingLink(this.token);

  /// Secreto portador de 128 bits. Es el ÚNICO dato de autorización: el
  /// resto de la URL no se cree nunca (ADR-035/036).
  final String token;

  /// Ruta interna a la que resuelve. La canónica del ticket
  /// (`/home/session/:sid/ticket/:tid`) se alcanza DESPUÉS de validar el
  /// token, no desde el enlace.
  String get route;

  /// Dónde se guarda mientras la persona se identifica, para que
  /// autenticarse no pierda el enlace.
  String get pendingKind;
}

/// `https://<host>/g/{token}` — incorporación a un GRUPO (ADR-035).
class GroupInvitationLink extends IncomingLink {
  const GroupInvitationLink(super.token);

  @override
  String get route => '/g/$token';

  @override
  String get pendingKind => 'group';
}

/// `https://<host>/t/{token}` — acceso a un TICKET y, si procede,
/// identificación como uno de sus participantes MANUAL (ADR-036).
class ManualParticipantClaimLink extends IncomingLink {
  const ManualParticipantClaimLink(super.token);

  @override
  String get route => '/t/$token';

  @override
  String get pendingKind => 'ticket';
}

/// Parser ÚNICO de enlaces entrantes.
///
/// Acepta la URL completa, la ruta suelta o el texto pegado a mano en
/// «Unirme con un enlace»: son la misma cosa vista desde sitios distintos.
/// Un host desconocido se rechaza — un enlace de otro dominio no es de
/// Salda por mucho que su ruta se parezca.
abstract final class IncomingLinkParser {
  static const _hosts = {
    Brand.developmentHostingDomain,
    Brand.productionHostingDomain,
  };

  /// Devuelve null si no es un enlace de Salda reconocible.
  static IncomingLink? parse(String? raw) {
    final texto = raw?.trim() ?? '';
    if (texto.isEmpty) return null;

    // Con esquema: se valida el host. Sin él, se trata como ruta interna.
    final uri = Uri.tryParse(texto);
    if (uri == null) return null;
    if (uri.hasScheme) {
      if (uri.scheme != 'https') return null;
      if (!_hosts.contains(uri.host)) return null;
    }

    final segmentos = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segmentos.length < 2) return null;
    final token = _cleanToken(segmentos[1]);
    if (token.isEmpty) return null;

    return switch (segmentos.first) {
      'g' => GroupInvitationLink(token),
      't' || 'ticket' => ManualParticipantClaimLink(token),
      // `/join/{token}` es la entrada manual del mismo enlace de grupo.
      'join' => GroupInvitationLink(token),
      _ => null,
    };
  }

  /// El token viaja como segmento de ruta, así que puede llegar percent-
  /// encoded desde un navegador o con basura pegada al copiarlo.
  static String _cleanToken(String segment) {
    final decoded = Uri.decodeComponent(segment).trim();
    // Solo el alfabeto de un ShareCode base64url: cortar aquí evita
    // arrastrar un `?utm=…` o un paréntesis del chat.
    final match = RegExp(r'^[A-Za-z0-9_-]+').firstMatch(decoded);
    return match?.group(0) ?? '';
  }
}
