import 'package:design_tokens/design_tokens.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/core/theme/app_theme.dart';
import 'package:salda_mobile/core/ui/badges.dart';
import 'package:salda_mobile/core/ui/money_text.dart';
import 'package:salda_mobile/core/ui/states.dart';
import 'package:salda_mobile/core/ui/surfaces.dart';
import 'package:salda_mobile/l10n/generated/app_localizations.dart';

/// El sistema visual es la base de todas las pantallas: si claro y oscuro no
/// están los dos terminados, o si un importe se parte, el problema aparece
/// en toda la app a la vez.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Brightness brightness = Brightness.light,
    double textScale = 1.0,
    Size size = const Size(400, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.dark
            ? AppTheme.dark()
            : AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('temas', () {
    test('claro y oscuro son sistemas DISEÑADOS, no uno derivado del otro', () {
      final light = AppTheme.light();
      final dark = AppTheme.dark();
      final lc = light.extension<SaldaColors>()!;
      final dc = dark.extension<SaldaColors>()!;

      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      // Ningún rol coincide por accidente entre los dos modos.
      expect(lc.background, isNot(dc.background));
      expect(lc.textPrimary, isNot(dc.textPrimary));
      expect(lc.primary, isNot(dc.primary));
    });

    test('el oscuro NO es negro absoluto ni el claro blanco azulado', () {
      final dc = AppTheme.dark().extension<SaldaColors>()!;
      final lc = AppTheme.light().extension<SaldaColors>()!;
      expect(dc.background, isNot(const Color(0xFF000000)));
      // Fondo carbón con matiz verde: el verde manda sobre el azul.
      expect(dc.background.g, greaterThan(dc.background.b));
      // Claro templado: el rojo manda sobre el azul (nada de blanco frío).
      expect(lc.background.r, greaterThan(lc.background.b));
    });

    test('el texto principal contrasta de sobra en ambos modos', () {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        final c = theme.extension<SaldaColors>()!;
        final ratio = _contrast(c.textPrimary, c.background);
        expect(
          ratio,
          greaterThanOrEqualTo(7.0),
          reason: 'texto principal sobre fondo (${theme.brightness})',
        );
        expect(
          _contrast(c.textSecondary, c.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'texto secundario sobre superficie (${theme.brightness})',
        );
      }
    });

    test('los estados de dinero contrastan sobre su propio fondo', () {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        final c = theme.extension<SaldaColors>()!;
        expect(_contrast(c.positive, c.positiveMuted), greaterThan(3.0));
        expect(_contrast(c.negative, c.negativeMuted), greaterThan(3.0));
        expect(_contrast(c.primary, c.background), greaterThan(3.0));
      }
    });

    test('la jerarquía es por superficie y borde, nunca por sombra', () {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        expect(theme.cardTheme.elevation, 0);
        expect(theme.appBarTheme.elevation, 0);
        expect(theme.appBarTheme.scrolledUnderElevation, 0);
        expect(theme.bottomSheetTheme.modalElevation, 0);
        expect(theme.floatingActionButtonTheme.elevation, 0);
      }
    });

    test('no se declara una fuente que no está empaquetada', () {
      // El token declaraba «Inter» sin que ningún asset la cargara: la app
      // caía en la fuente del sistema fingiendo que no lo hacía. Ahora el
      // token es null a propósito y Flutter resuelve la pila del sistema.
      expect(TokenTypography.fontFamily, isNull);
      expect(AppTheme.light().textTheme.bodyMedium?.fontFamily, 'Roboto');
    });
  });

  group('importes', () {
    testWidgets('cifras tabulares, una línea y sin partirse', (tester) async {
      await pump(tester, const MoneyText(Money(123456789)));
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.softWrap, isFalse);
      expect(text.maxLines, 1);
      expect(text.style?.fontFeatures?.map((f) => f.feature), contains('tnum'));
    });

    testWidgets('el signo no depende solo del color', (tester) async {
      // Un positivo con signo lleva «+» además del verde.
      await pump(
        tester,
        const MoneyText(Money(500), signed: true, tone: MoneyTone.positive),
      );
      expect(find.textContaining('+'), findsOneWidget);
    });

    testWidgets('un importe enorme no desborda su fila', (tester) async {
      await pump(
        tester,
        const Row(
          children: [
            Expanded(child: Text('Un concepto bastante largo de verdad')),
            MoneyText(Money(999999999), size: MoneySize.medium),
          ],
        ),
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('componentes', () {
    testWidgets('el estado vacío dice qué pasa y qué hacer', (tester) async {
      var pulsado = false;
      await pump(
        tester,
        EmptyState(
          icon: Icons.groups_outlined,
          title: 'Sin contextos',
          body: 'Crea una relación o un grupo para empezar.',
          action: 'Crear',
          onAction: () => pulsado = true,
        ),
      );
      expect(find.text('Sin contextos'), findsOneWidget);
      expect(find.textContaining('Crea una relación'), findsOneWidget);
      await tester.tap(find.text('Crear'));
      expect(pulsado, isTrue);
    });

    testWidgets('el error es accionable y no enseña nada técnico', (
      tester,
    ) async {
      await pump(
        tester,
        const ErrorStateView(message: 'No se pudo cargar tu balance.'),
      );
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('uid'), findsNothing);
    });

    testWidgets('el skeleton ocupa sitio en vez de dejar la pantalla vacía', (
      tester,
    ) async {
      await pump(tester, const SkeletonList(rows: 3));
      expect(find.byType(Skeleton), findsWidgets);
    });

    testWidgets('un badge lleva rótulo, no solo color', (tester) async {
      await pump(
        tester,
        const StatusBadge('Pendiente', tone: BadgeTone.pending),
      );
      expect(find.text('Pendiente'), findsOneWidget);
    });

    testWidgets('las superficies no se anidan unas dentro de otras', (
      tester,
    ) async {
      await pump(
        tester,
        const SaldaCardList(
          children: [
            ListTile(title: Text('Primera')),
            ListTile(title: Text('Segunda')),
          ],
        ),
      );
      // Una sola superficie con dos filas, no dos tarjetas.
      expect(find.byType(SaldaCard), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
    });
  });

  group('accesibilidad', () {
    testWidgets('con texto al 200 % nada desborda', (tester) async {
      await pump(
        tester,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SectionHeader(title: 'Tus contextos'),
            EmptyState(
              title: 'Todavía no compartes gastos con nadie',
              body:
                  'Crea una relación para las cuentas de dos, o un grupo '
                  'para un piso, un viaje o una cena.',
            ),
          ],
        ),
        textScale: 2.0,
        size: const Size(400, 1600),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('un nombre larguísimo se recorta, no rompe el layout', (
      tester,
    ) async {
      await pump(
        tester,
        const SaldaCardList(
          children: [
            ListTile(
              title: Text(
                'María del Carmen de la Santísima Trinidad Fernández',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('los controles llegan al tamaño táctil mínimo', (tester) async {
      await pump(
        tester,
        Column(
          children: [
            FilledButton(onPressed: () {}, child: const Text('Guardar')),
          ],
        ),
      );
      final size = tester.getSize(find.byType(FilledButton));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('el sistema funciona igual en oscuro', (tester) async {
      await pump(
        tester,
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: 'Saldo'),
            MoneyText(Money(4250), size: MoneySize.large),
            StatusBadge('A tu favor', tone: BadgeTone.positive),
          ],
        ),
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('A tu favor'), findsOneWidget);
    });
  });
}

/// Contraste WCAG entre dos colores opacos.
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

double _luminance(Color color) => color.computeLuminance();
