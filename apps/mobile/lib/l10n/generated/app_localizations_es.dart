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

  @override
  String get commonDone => 'Listo';

  @override
  String get loginTitle => 'Divide gastos sin discusiones';

  @override
  String get loginEmail => 'Email';

  @override
  String get loginPassword => 'Contraseña';

  @override
  String get loginDisplayName => 'Tu nombre';

  @override
  String get loginSignIn => 'Entrar';

  @override
  String get loginRegister => 'Crear cuenta';

  @override
  String get loginToRegister => '¿No tienes cuenta? Regístrate';

  @override
  String get loginToSignIn => '¿Ya tienes cuenta? Entra';

  @override
  String get loginForgot => 'He olvidado mi contraseña';

  @override
  String get loginResetSent => 'Te hemos enviado un correo para restablecerla';

  @override
  String get authErrorInvalidCredential => 'Email o contraseña incorrectos';

  @override
  String get authErrorEmailInUse => 'Ya existe una cuenta con ese email';

  @override
  String get authErrorWeakPassword => 'La contraseña es demasiado corta';

  @override
  String get authErrorNetwork => 'Sin conexión. Inténtalo de nuevo.';

  @override
  String get authErrorUnknown => 'Algo ha fallado. Inténtalo de nuevo.';

  @override
  String get signOut => 'Cerrar sesión';

  @override
  String get sessionsEmptyTitle => 'Escanea tu primer ticket';

  @override
  String get sessionsEmptyBody =>
      'Haz una foto y reparte el gasto en segundos.';

  @override
  String get summaryOwedToMe => 'Te deben';

  @override
  String get summaryIOwe => 'Debes';

  @override
  String get statusClosed => 'Cerrada';

  @override
  String get statusArchived => 'Archivada';

  @override
  String sessionPeople(int count) {
    return '$count personas';
  }

  @override
  String get peopleSheetTitle => '¿Quién estuvo?';

  @override
  String get peopleAddHint => 'Añadir persona…';

  @override
  String get peopleYou => 'Tú';

  @override
  String get peopleNeedTwo => 'Añade al menos otra persona';

  @override
  String get splitEqual => 'Todo a medias';

  @override
  String get splitByItem => 'Cada uno lo suyo';

  @override
  String get payerQuestion => '¿Quién pagó?';

  @override
  String get sessionNameLabel => 'Nombre de la cuenta';

  @override
  String get createAndShare => 'Crear y compartir';

  @override
  String get shareTitle => 'Invita a los demás';

  @override
  String get shareHint =>
      'Quien tenga el enlace puede ver la cuenta, elegir lo suyo y marcar que ha pagado. Sin instalar nada.';

  @override
  String get shareCopy => 'Copiar enlace';

  @override
  String get shareCopied => 'Enlace copiado';

  @override
  String get shareSystem => 'Compartir…';

  @override
  String get detailTabSummary => 'Resumen';

  @override
  String get detailTabAccounts => 'Cuentas';

  @override
  String get detailTabActivity => 'Actividad';

  @override
  String get balancesTitle => 'Balance';

  @override
  String balancePaidLabel(String amount) {
    return 'pagó $amount';
  }

  @override
  String balanceConsumedLabel(String amount) {
    return 'consumió $amount';
  }

  @override
  String get settlementsTitle => 'Pagos pendientes';

  @override
  String settlementRow(String from, String to) {
    return '$from → $to';
  }

  @override
  String get statePending => 'Pendiente';

  @override
  String get stateMarked => 'Dice que pagó';

  @override
  String get stateConfirmed => 'Confirmado';

  @override
  String get actionConfirm => 'Confirmar';

  @override
  String get actionBackToPending => 'Volver a pendiente';

  @override
  String get allSettled => 'Todo saldado 🎉';

  @override
  String get activityEmpty => 'Sin actividad todavía';

  @override
  String get accountsEmpty => 'Sin cuentas todavía';

  @override
  String get menuShare => 'Compartir';

  @override
  String get menuClose => 'Cerrar la cuenta';

  @override
  String get menuReopen => 'Reabrir';

  @override
  String get menuArchive => 'Archivar';

  @override
  String get menuDelete => 'Eliminar';

  @override
  String get closeConfirmBody =>
      'Nadie podrá modificarla hasta que la reabras. ¿Cerrar?';

  @override
  String get deleteConfirmBody =>
      'Se borrará todo: tickets, fotos y pagos. Esta acción no se puede deshacer.';

  @override
  String get closedBanner => 'Cuenta cerrada: solo lectura';

  @override
  String get draftResumeTitle => 'Tienes un ticket sin terminar';

  @override
  String get draftResume => 'Continuar';

  @override
  String get draftDiscard => 'Descartar';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get settingsAppearance => 'Apariencia';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get settingsPayments => 'Métodos de pago';

  @override
  String get settingsPaymentsHint =>
      'Aparecen como botones de pago para tus invitados. Deja en blanco los que no uses.';

  @override
  String get paymentBizum => 'Bizum (teléfono)';

  @override
  String get paymentPaypal => 'PayPal (enlace paypal.me)';

  @override
  String get paymentRevolut => 'Revolut (revtag)';

  @override
  String get paymentIban => 'IBAN';

  @override
  String get paymentsSaved => 'Métodos de pago guardados';

  @override
  String get settingsPeople => 'Personas frecuentes';

  @override
  String get settingsPeopleEmpty =>
      'Aparecerán aquí las personas con las que compartas cuentas.';

  @override
  String get settingsBackup => 'Copia de seguridad';

  @override
  String get backupExport => 'Exportar todos los datos (JSON)';

  @override
  String get backupImport => 'Importar copia';

  @override
  String get settingsAccount => 'Cuenta';

  @override
  String get menuAddTicket => 'Añadir ticket';

  @override
  String backupImportSummary(int sessions, int tickets, int lines) {
    return 'La copia contiene $sessions cuentas, $tickets tickets y $lines productos. ¿Cómo quieres importarla?';
  }

  @override
  String get backupModeMerge => 'Añadir a lo que ya tengo';

  @override
  String get backupModeReplace =>
      'Restaurar (borra lo que no esté en la copia)';

  @override
  String get backupImported => 'Copia importada';

  @override
  String get backupInvalid => 'El archivo no es una copia de seguridad válida';

  @override
  String get scanManualEntry => 'Gasto sin ticket';

  @override
  String get manualTitle => 'Gasto sin ticket';

  @override
  String get manualConcept => 'Concepto';

  @override
  String get manualAmount => 'Importe';

  @override
  String get manualConceptHint => 'Taxi, entradas, gasolina…';
}
