// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get homeTagline => 'Escanea el ticket, reparte y salda cuentas.';

  @override
  String get homeEmptyHint =>
      'Los cimientos están listos. El historial de sesiones llega en M3.';

  @override
  String get scanFab => 'Escanear';

  @override
  String get scanFromCamera => 'Hacer foto';

  @override
  String get scanFromGallery => 'Elegir de la galería';

  @override
  String get scanProcessing => 'Leyendo el ticket…';

  @override
  String get scanNothingRecognized => 'No se pudo leer nada en la imagen';

  @override
  String get reviewTitle => 'Revisar ticket';

  @override
  String get reviewBannerLowConfidence =>
      'Hay datos dudosos o que no cuadran. Revísalos antes de continuar.';

  @override
  String get reviewRetake => 'Repetir foto';

  @override
  String get reviewEditManually => 'Editar a mano';

  @override
  String get reviewAnalyzeWithAi => 'Analizar con IA';

  @override
  String get reviewAiUnavailable =>
      'Disponible al configurar un proveedor de IA (Ajustes)';

  @override
  String get reviewMerchant => 'Establecimiento';

  @override
  String get reviewDate => 'Fecha';

  @override
  String get reviewTime => 'Hora';

  @override
  String get reviewLines => 'Productos';

  @override
  String get reviewAddLine => 'Añadir producto';

  @override
  String get reviewComputedTotal => 'Suma de productos';

  @override
  String get reviewGrandTotal => 'Total del ticket';

  @override
  String get reviewBalanced => 'El ticket cuadra';

  @override
  String reviewMismatch(String amount) {
    return 'Descuadre de $amount';
  }

  @override
  String get reviewTip => 'Propina';

  @override
  String get reviewDiscount => 'Descuento';

  @override
  String get lineEditTitle => 'Editar producto';

  @override
  String get lineName => 'Nombre';

  @override
  String get lineQuantity => 'Cantidad';

  @override
  String get lineUnitPrice => 'Precio unitario';

  @override
  String get lineTotalPrice => 'Importe';

  @override
  String get lineAlternatives => '¿Quizá era…?';

  @override
  String get lineDelete => 'Eliminar producto';

  @override
  String lineSource(String source) {
    return 'Texto original: $source';
  }

  @override
  String get commonSave => 'Guardar';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonContinue => 'Continuar';
}
