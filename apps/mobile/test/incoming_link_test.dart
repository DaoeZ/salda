import 'package:design_tokens/design_tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/core/routing/incoming_link.dart';

/// Los dos flujos de enlace —grupo y ticket— comparten parser. Estas
/// pruebas parten de la URL REAL que se comparte, no de una ruta interna
/// escrita a mano.
void main() {
  final dev = Brand.developmentHostingDomain;
  final prod = Brand.productionHostingDomain;

  group('enlace de grupo', () {
    test('la URL compartida se reconoce y conserva el token', () {
      final link = IncomingLinkParser.parse('https://$dev/g/AbC-123_xyz');
      expect(link, isA<GroupInvitationLink>());
      expect(link!.token, 'AbC-123_xyz');
      expect(link.route, '/g/AbC-123_xyz');
      expect(link.pendingKind, 'group');
    });

    test('también en producción', () {
      expect(
        IncomingLinkParser.parse('https://$prod/g/T0k3n'),
        isA<GroupInvitationLink>(),
      );
    });

    test('la entrada manual /join/{token} es el mismo enlace', () {
      final link = IncomingLinkParser.parse('https://$dev/join/T0k3n');
      expect(link, isA<GroupInvitationLink>());
      expect(link!.token, 'T0k3n');
    });

    test('pegado con basura del chat, el token sale limpio', () {
      // Lo que llega al pegar desde WhatsApp: paréntesis, punto final…
      final link = IncomingLinkParser.parse('  https://$dev/g/T0k3n?x=1  ');
      expect(link!.token, 'T0k3n');
    });

    test('percent-encoded se decodifica', () {
      final link = IncomingLinkParser.parse('https://$dev/g/T0k3n%2Dabc');
      expect(link!.token, 'T0k3n-abc');
    });
  });

  group('enlace de ticket', () {
    test('/t/{token} identifica una reclamación de participante manual', () {
      final link = IncomingLinkParser.parse('https://$dev/t/Tk1');
      expect(link, isA<ManualParticipantClaimLink>());
      expect(link!.route, '/t/Tk1');
      expect(link.pendingKind, 'ticket');
    });

    test('/ticket/{token} resuelve al mismo tipo', () {
      expect(
        IncomingLinkParser.parse('https://$dev/ticket/Tk1'),
        isA<ManualParticipantClaimLink>(),
      );
    });

    test('el enlace NO lleva sessionId ni ticketId', () {
      // La ruta canónica se alcanza tras validar el token; el enlace solo
      // porta el secreto, así que manipular la URL no cambia de ticket.
      final link = IncomingLinkParser.parse('https://$dev/t/Tk1')!;
      expect(link.route.contains('session'), isFalse);
      expect(link.token, 'Tk1');
    });
  });

  group('lo que NO es un enlace de Salda', () {
    test('otro dominio se rechaza aunque la ruta coincida', () {
      expect(IncomingLinkParser.parse('https://malo.example/g/Tk1'), isNull);
    });

    test('http sin cifrar se rechaza', () {
      expect(IncomingLinkParser.parse('http://$dev/g/Tk1'), isNull);
    });

    test('ruta desconocida del propio dominio se rechaza', () {
      expect(IncomingLinkParser.parse('https://$dev/otra/Tk1'), isNull);
    });

    test('sin token no hay enlace', () {
      expect(IncomingLinkParser.parse('https://$dev/g/'), isNull);
      expect(IncomingLinkParser.parse('https://$dev/g'), isNull);
    });

    test('vacío o nulo', () {
      expect(IncomingLinkParser.parse(null), isNull);
      expect(IncomingLinkParser.parse('   '), isNull);
    });
  });

  group('rutas internas', () {
    test('la ruta suelta que entrega el router también se reconoce', () {
      // Es lo que llega por `defaultRouteName` cuando Android abre la app
      // con la app cerrada.
      final link = IncomingLinkParser.parse('/g/Tk1');
      expect(link, isA<GroupInvitationLink>());
      expect(link!.token, 'Tk1');
    });

    test('la ruta canónica del ticket NO es un enlace entrante', () {
      // Navegación interna, no un enlace que haya que canjear.
      expect(IncomingLinkParser.parse('/home/session/s1/ticket/t1'), isNull);
    });
  });
}
