import 'package:design_tokens/design_tokens.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// ÚNICO sitio donde se decide cómo se representa la marca en pantalla.
///
/// El símbolo definitivo **no está aprobado**, así que hoy esto es el
/// wordmark textual «Salda» leído de `brand.json`. No se dibuja un símbolo
/// provisional: un logo improvisado se filtra a capturas, a la tienda y a la
/// cabeza de la gente, y después hay que desaprenderlo.
///
/// Cuando el símbolo llegue (`assets/brand/salda_symbol.svg`, ver el README
/// de ese directorio), se antepone aquí y aparece a la vez en la barra de
/// Inicio, en autenticación y en cualquier otro sitio que use este widget.
class SaldaWordmark extends StatelessWidget {
  const SaldaWordmark({super.key, this.size = 20, this.color});

  /// Altura tipográfica del wordmark. Cuando exista símbolo, marcará también
  /// su lado, para que los dos escalen juntos.
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    Brand.appName,
    style: Theme.of(context).textTheme.titleLarge?.copyWith(
      color: color ?? context.salda.primary,
      fontSize: size,
      letterSpacing: -0.6,
      fontWeight: FontWeight.w700,
    ),
  );
}
