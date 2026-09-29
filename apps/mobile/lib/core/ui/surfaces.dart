import 'dart:math' as math;

import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Hoja de contenido: un punto más clara que el papel del fondo, borde de un
/// pelo y esquina contenida. Sin sombra y sin degradado.
///
/// Deliberadamente NO anida: una hoja dentro de otra es señal de que la
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
    final content = Padding(padding: padding, child: child);
    // Material y no `DecoratedBox`: cualquier `ListTile` o `InkWell` dentro
    // necesita un Material ancestro para pintar su fondo y su tinta.
    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      container: true,
      child: Material(
        color: color ?? c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SaldaRadius.surface),
          side: BorderSide(color: borderColor ?? c.border),
        ),
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// Filas de libro dentro de UNA hoja, separadas por filetes de un pelo que
/// cruzan la hoja entera: el ritmo lo marcan las líneas, no una tarjeta por
/// fila.
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
            if (i > 0) Divider(height: 1, color: c.border),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Encabezado de sección: un subtítulo editorial en serifa, en minúsculas
/// de frase, y UNA acción a la derecha si hace falta.
///
/// Sustituye al rótulo en mayúsculas espaciadas de la versión anterior: la
/// jerarquía la da la voz tipográfica, no el tamaño minúsculo gritado.
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
    final titleWidget = Semantics(
      header: true,
      child: Text(
        title,
        style: SaldaType.serif(
          size: 18,
          weight: FontWeight.w600,
          color: c.textPrimary,
          tracking: -0.2,
          height: 1.25,
        ),
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
      padding: const EdgeInsets.only(bottom: TokenSpacing.sm),
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

/// Superficie de TINTA para la cifra agregada que manda en una pantalla
/// (tu saldo global, el neto con una persona).
///
/// Es la excepción del sistema, no un estilo de tarjeta: como mucho una por
/// pantalla. Dentro, los importes usan [SaldaColors.inkPositive] /
/// [SaldaColors.inkNegative] y el texto [SaldaColors.onInk]; un
/// `DefaultTextStyle` e `IconTheme` los fijan para que un hijo no herede la
/// tinta del papel y desaparezca.
class InkPanel extends StatelessWidget {
  const InkPanel({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(
      TokenSpacing.xl,
      TokenSpacing.lg,
      TokenSpacing.xl,
      TokenSpacing.xl,
    ),
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.salda;
    final theme = Theme.of(context);
    final content = Padding(
      padding: padding,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: c.onInk),
        child: IconTheme.merge(
          data: IconThemeData(color: c.onInkMuted),
          child: child,
        ),
      ),
    );
    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      container: true,
      child: Theme(
        // Dentro de la tinta los botones se invierten: el principal es de
        // papel sobre tinta y el de texto escribe en tinta clara. Sin esto el
        // ultramar quedaría sin contraste sobre el azul-negro.
        data: theme.copyWith(
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: c.inkAccent),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: theme.filledButtonTheme.style?.copyWith(
              backgroundColor: WidgetStatePropertyAll(c.onInk),
              foregroundColor: WidgetStatePropertyAll(c.ink),
            ),
          ),
        ),
        child: Material(
          color: c.ink,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SaldaRadius.surface),
            side: BorderSide(color: c.inkRule),
          ),
          child: onTap == null
              ? content
              : InkWell(
                  onTap: onTap,
                  splashColor: c.onInk.withValues(alpha: 0.06),
                  highlightColor: c.onInk.withValues(alpha: 0.04),
                  child: content,
                ),
        ),
      ),
    );
  }
}

/// Rótulo pequeño de una superficie: la línea que dice QUÉ es la cifra de
/// debajo («Tu saldo», «Total»). Versalita discreta, no un titular.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: color ?? context.salda.textMuted,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    ),
  );
}

/// Sello de estado: SOLO para hechos cerrados con valor económico —un cobro
/// confirmado, una cuenta saldada—. Es el único sitio donde la app «firma».
///
/// No es un badge con otra cara: si se usa para estados intermedios pierde
/// su significado. Para lo demás está [StatusBadge].
class Stamp extends StatelessWidget {
  const Stamp(
    this.label, {
    super.key,
    this.color,
    this.compact = false,
    this.tilt = true,
  });

  final String label;
  final Color? color;

  /// Versión de fila: más pequeña y sin doble filete.
  final bool compact;

  /// La leve inclinación es lo que lo lee como sello y no como botón. Se
  /// desactiva donde el sello compartiría línea con texto alineado.
  final bool tilt;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? context.salda.primary;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: ink,
      fontWeight: FontWeight.w700,
      letterSpacing: compact ? 1.0 : 1.6,
      fontSize: compact ? 10.5 : 12,
      height: 1.1,
    );
    final text = Text(
      label.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    final stamp = compact
        ? DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: ink.withValues(alpha: 0.85), width: 1),
              borderRadius: BorderRadius.circular(SaldaRadius.badge),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              child: text,
            ),
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: ink.withValues(alpha: 0.9), width: 1.6),
              borderRadius: BorderRadius.circular(SaldaRadius.badge),
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: ink.withValues(alpha: 0.55),
                    width: 0.8,
                  ),
                  borderRadius: BorderRadius.circular(1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TokenSpacing.sm,
                    vertical: 4,
                  ),
                  child: text,
                ),
              ),
            ),
          );
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: tilt
          ? Transform.rotate(angle: -3 * math.pi / 180, child: stamp)
          : stamp,
    );
  }
}
