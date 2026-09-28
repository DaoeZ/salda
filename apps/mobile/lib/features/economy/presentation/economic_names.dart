import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../application/identity_names.dart';

/// Nombre visible de un actor economico, con relleno de producto cuando no
/// se le conoce. NUNCA devuelve el identificador interno.
String economicNameText(WidgetRef ref, AppLocalizations l10n, String actor) {
  final name = ref.watch(economicNameProvider(actor));
  return switch (name.source) {
    EconomicNameSource.person => name.text,
    EconomicNameSource.unnamed => l10n.personUnnamed,
    // Mientras carga, un guion discreto: mejor que parpadear un rotulo.
    EconomicNameSource.loading => '…',
  };
}
