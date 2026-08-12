import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Superficie base del sistema: relleno plano, borde de un pelo y radio
/// medio. Sin sombra y sin degradado — la jerarquía la dan el borde y el
/// fondo, no la profundidad.
///
/// Deliberadamente NO anida: una tarjeta dentro de otra es señal de que la
/// sección necesita un encabezado, no otra caja.
class SaldaCard extends StatelessWidget {
  const SaldaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(TokenSpacing.lg),
    this.onTap,
    this.color,
    this.borderColor,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.salda;
    final radius = BorderRadius.circular(TokenRadius.card);
    final content = Padding(padding: padding, child: child);
    // Material y no `DecoratedBox`: cualquier `ListTile` o `InkWell` dentro
    // necesita un Material ancestro para pintar su fondo y su tinta. Con una
    // caja decorada quedaban invisibles.
    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      container: true,
      child: Material(
        color: color ?? c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: borderColor ?? c.border),
        ),
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// Lista de filas separadas por líneas de un pelo dentro de UNA superficie.
/// Evita el patrón de una tarjeta por fila, que rompe la lectura vertical.
class SaldaCardList extends StatelessWidget {
  const SaldaCardList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final c = context.salda;
    return SaldaCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: TokenSpacing.lg),
                child: Divider(height: 1, color: c.border),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Encabezado de sección: rótulo corto en mayúsculas discretas y, si hace
/// falta, UNA acción a la derecha. Es lo que sustituye a envolver cada
/// bloque en su propia tarjeta con título.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
    this.trailing,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.salda;
    final titleWidget = Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: c.textMuted,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
      ),
    );
    final actionWidget = action != null && onAction != null
        ? TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, TokenLayout.minTouchTarget),
              padding: const EdgeInsets.symmetric(horizontal: TokenSpacing.sm),
            ),
            child: Text(action!),
          )
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: TokenSpacing.md),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: TokenSpacing.sm,
        runSpacing: TokenSpacing.xs,
        children: [titleWidget, ?trailing, ?actionWidget],
      ),
    );
  }
}

/// Cuerpo de pantalla con el margen del sistema y ancho máximo, para que en
/// tabletas y en horizontal el texto no cruce toda la pantalla.
class ScreenBody extends StatelessWidget {
  const ScreenBody({
    super.key,
    required this.children,
    this.padding,
    this.controller,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: TokenLayout.maxContentWidth),
      child: ListView(
        controller: controller,
        padding:
            padding ??
            const EdgeInsets.fromLTRB(
              TokenLayout.screenMargin,
              TokenSpacing.sm,
              TokenLayout.screenMargin,
              TokenSpacing.section,
            ),
        children: children,
      ),
    ),
  );
}

/// Separación vertical entre bloques, con el mismo valor en toda la app.
class SectionGap extends StatelessWidget {
  const SectionGap({super.key, this.height = TokenSpacing.xxl});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(height: height);
}
