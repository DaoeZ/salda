import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/features/spaces/domain/space_models.dart';
import 'package:salda_mobile/features/spaces/presentation/space_detail_screen.dart';
import 'package:salda_mobile/features/spaces/presentation/space_title_text.dart';
import 'package:salda_mobile/features/spaces/presentation/spaces_screen.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

import 'fakes.dart';

/// BUG-5 en las pantallas: el mismo documento tiene que leerse distinto
/// según quién mire. Estas pruebas comprueban que las superficies usan el
/// resolver y no vuelven a pintar el nombre persistido.
void main() {
  const edgar = 'uid-edgar';
  const pedro = 'uid-pedro';
  const legado = 'Edgar · Pedro'; // lo que había guardado y NO debe verse
  // El id CANÓNICO de verdad: es lo que permite reconocer una relación desde
  // una invitación, antes de poder leer el espacio.
  final relId = relationshipSpaceId(edgar, pedro);

  late FakeFirebaseFirestore firestore;

  Future<void> seed() async {
    // v2 entre dos cuentas, con el nombre concatenado del bug.
    await firestore.doc('spaces/$relId').set({
      'name': legado,
      'ownerUid': edgar,
      'kind': 'relationship',
      'relationshipUids': [edgar, pedro],
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/$relId/members/$edgar').set({'uid': edgar});
    await firestore.doc('spaces/$relId/members/$pedro').set({'uid': pedro});
    await firestore.doc('profiles/$edgar').set({
      'displayName': 'Edgar',
      'username': 'edgar27',
    });
    await firestore.doc('profiles/$pedro').set({
      'displayName': 'Pedro',
      'username': 'pedro_c',
    });

    // v3 con MANUAL: el título es el nombre de la persona sin cuenta.
    await firestore.doc('spaces/rel3').set({
      'name': 'nombre viejo',
      'ownerUid': edgar,
      'kind': 'relationship',
      'relationshipUids': [edgar],
      'relationshipManualId': 'm-pablo',
      'status': 'active',
      'schemaVersion': 3,
    });
    await firestore.doc('spaces/rel3/members/$edgar').set({'uid': edgar});
    await firestore.doc('spaces/rel3/manualParticipants/m-pablo').set({
      'manualId': 'm-pablo',
      'displayName': 'Pablo',
      'linkedUid': null,
      'createdByUid': edgar,
      'schemaVersion': 1,
    });

    // Grupo: su nombre no se toca.
    await firestore.doc('spaces/grupo').set({
      'name': 'Piso',
      'ownerUid': edgar,
      'kind': 'group',
      'status': 'active',
      'schemaVersion': 2,
    });
    await firestore.doc('spaces/grupo/members/$edgar').set({'uid': edgar});
  }

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await seed();
  });

  /// Monta una pantalla como [uid]. Devuelve el contenedor para poder leer
  /// el MISMO provider que usan los widgets.
  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget home, {
    String uid = edgar,
  }) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: loggedInOverrides(firestore: firestore, uid: uid),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// El detalle monta secciones con temporizadores propios (chat, actividad)
  /// y el binding los revisa ANTES de los `addTearDown`.
  Future<void> cerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('lista de espacios: Edgar ve «Pedro», nunca «Edgar · Pedro»', (
    tester,
  ) async {
    await pump(tester, const SpacesScreen());
    expect(find.text(legado), findsNothing);
    expect(find.text('Pedro'), findsWidgets);
    expect(find.text('Edgar'), findsNothing);
    // El grupo conserva su nombre.
    expect(find.text('Piso'), findsOneWidget);
    // Y la v3 enseña a la persona sin cuenta, no el nombre guardado.
    expect(find.text('Pablo'), findsWidgets);
    expect(find.text('nombre viejo'), findsNothing);
  });

  testWidgets('la MISMA relación: Pedro ve «Edgar»', (tester) async {
    await pump(tester, const SpacesScreen(), uid: pedro);
    expect(find.text(legado), findsNothing);
    expect(find.text('Edgar'), findsWidgets);
    expect(find.text('Pedro'), findsNothing);
  });

  testWidgets('detalle: la cabecera resuelve igual que la lista', (
    tester,
  ) async {
    final container = await pump(tester, SpaceDetailScreen(spaceId: relId));
    expect(find.text(legado), findsNothing);
    // AppBar + cabecera del cuerpo.
    expect(find.text('Pedro'), findsWidgets);
    // Y es literalmente el mismo resolver que usa Inicio.
    expect(
      container.read(spaceTitleProvider(relId)).person,
      'Pedro',
      reason: 'Inicio y detalle comparten resolver',
    );
    await cerrar(tester);
  });

  testWidgets('detalle de una v3: el propietario ve al MANUAL', (tester) async {
    await pump(tester, const SpaceDetailScreen(spaceId: 'rel3'));
    expect(find.text('Pablo'), findsWidgets);
    expect(find.text('nombre viejo'), findsNothing);
    // Nunca el identificador técnico.
    expect(find.textContaining('m-pablo'), findsNothing);
    expect(find.textContaining('manual:'), findsNothing);
    await cerrar(tester);
  });

  testWidgets('detalle de un grupo: nombre persistido intacto', (tester) async {
    await pump(tester, const SpaceDetailScreen(spaceId: 'grupo'));
    expect(find.text('Piso'), findsWidgets);
    await cerrar(tester);
  });

  testWidgets('v3 vinculada: el propietario sigue viendo al MANUAL', (
    tester,
  ) async {
    await firestore.doc('spaces/rel3/manualParticipants/m-pablo').update({
      'linkedUid': 'uid-pablo',
    });
    final container = await pump(tester, const SpacesScreen());
    expect(find.text('Pablo'), findsWidgets);
    expect(container.read(spaceTitleProvider('rel3')).person, 'Pablo');
  });

  testWidgets('una cuenta sin username no pinta un @ huérfano', (tester) async {
    await firestore.doc('profiles/$pedro').set({
      'displayName': 'Pedro',
      'username': '',
    });
    await pump(tester, const SpacesScreen());
    expect(find.text('Pedro'), findsWidgets);
    expect(find.textContaining('@'), findsNothing);
  });

  testWidgets('perfil ausente: rótulo de producto, nunca el UID', (
    tester,
  ) async {
    await firestore.doc('profiles/$pedro').delete();
    await pump(tester, const SpacesScreen());
    expect(find.text('Persona sin nombre'), findsWidgets);
    expect(find.textContaining(pedro), findsNothing);
    expect(find.text(legado), findsNothing);
  });

  testWidgets('la invitación a una relación anuncia a quien invita', (
    tester,
  ) async {
    // Pedro todavía no puede leer el espacio: solo tiene la invitación, con
    // su nombre denormalizado —el que no sirve— y el `fromUid`.
    await firestore.doc('spaceInvites/${relId}_$pedro').set({
      'spaceId': relId,
      'spaceName': legado,
      'fromUid': edgar,
      'toUid': pedro,
      'status': 'pending',
    });
    await pump(tester, const SpacesScreen(), uid: pedro);
    // Ni el nombre concatenado ni ninguna frase que lo cite.
    expect(find.textContaining(legado), findsNothing);
    expect(find.text('Edgar quiere compartir gastos contigo'), findsOneWidget);
  });
}
