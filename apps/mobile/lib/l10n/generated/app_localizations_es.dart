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
  String get commonDelete => 'Eliminar';

  @override
  String get loginTitle => 'Divide gastos sin discusiones';

  @override
  String get loginWelcome => 'Qué bueno verte de nuevo';

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
  String get registerTitle => 'Crea tu cuenta';

  @override
  String get registerSubtitle =>
      'Guarda tus cuentas y accede a ellas desde cualquier dispositivo.';

  @override
  String get authNewPassword => 'Nueva contraseña';

  @override
  String get authConfirmPassword => 'Repite la contraseña';

  @override
  String get authPasswordHint => 'Mínimo 8 caracteres';

  @override
  String get authShowPassword => 'Mostrar contraseña';

  @override
  String get authHidePassword => 'Ocultar contraseña';

  @override
  String get authOr => 'o';

  @override
  String get authContinueGoogle => 'Continuar con Google';

  @override
  String get authContinueGuest => 'Continuar como invitado';

  @override
  String get authProtectGuestTitle => 'Protege tus cuentas';

  @override
  String get authProtectGuestBody =>
      'Convierte tu acceso de invitado sin perder ninguna sesión.';

  @override
  String get authProtectGuestAction => 'Crear cuenta y conservar datos';

  @override
  String get authProtectGuestGoogle => 'Vincular con Google';

  @override
  String get authUseAnotherAccount => 'Usar otra cuenta';

  @override
  String get authValidationEmailRequired => 'Escribe tu email';

  @override
  String get authValidationEmailInvalid => 'Introduce un email válido';

  @override
  String get authValidationPasswordRequired => 'Escribe tu contraseña';

  @override
  String get authValidationPasswordLength => 'Usa al menos 8 caracteres';

  @override
  String get authValidationPasswordMismatch => 'Las contraseñas no coinciden';

  @override
  String get authValidationName => 'Escribe un nombre de al menos 2 caracteres';

  @override
  String get resetTitle => 'Recupera tu contraseña';

  @override
  String get resetBody =>
      'Te enviaremos el enlace oficial de Firebase para crear una nueva.';

  @override
  String get resetAction => 'Enviar enlace';

  @override
  String get resetSentTitle => 'Revisa tu correo';

  @override
  String get resetSentBody =>
      'Si existe una cuenta con ese email, recibirás un enlace para restablecer la contraseña.';

  @override
  String get resetBackToLogin => 'Volver a iniciar sesión';

  @override
  String get resetTryAnother => 'Probar otro email';

  @override
  String get verifyTitle => 'Verifica tu email';

  @override
  String verifyBody(String email) {
    return 'Verifica $email desde el enlace del correo. Si no lo tienes, puedes reenviarlo.';
  }

  @override
  String get verifyCheck => 'Ya lo he verificado';

  @override
  String get verifyResend => 'Reenviar correo';

  @override
  String verifyResendIn(int seconds) {
    return 'Podrás reenviarlo en $seconds s';
  }

  @override
  String get verifyResent => 'Correo de verificación enviado de nuevo.';

  @override
  String get verifyNotYet =>
      'Todavía no aparece como verificado. Abre el enlace del correo y vuelve a comprobar.';

  @override
  String get authErrorInvalidCredential => 'Email o contraseña incorrectos';

  @override
  String get authErrorEmailInUse => 'Ya existe una cuenta con ese email';

  @override
  String get authErrorWeakPassword => 'La contraseña es demasiado corta';

  @override
  String get authErrorNetwork => 'Sin conexión. Inténtalo de nuevo.';

  @override
  String get authErrorTooManyRequests =>
      'Demasiados intentos. Espera unos minutos y vuelve a probar.';

  @override
  String get authErrorUserDisabled => 'Esta cuenta está desactivada.';

  @override
  String get authErrorOperationNotAllowed =>
      'Este método de acceso aún no está habilitado.';

  @override
  String get authErrorCredentialAlreadyInUse =>
      'Ese acceso ya pertenece a otra cuenta. Cierra esta sesión y entra con la cuenta existente; no hemos movido tus datos.';

  @override
  String get authErrorCancelled => 'Has cancelado el acceso.';

  @override
  String get authErrorUnknown => 'Algo ha fallado. Inténtalo de nuevo.';

  @override
  String get signOut => 'Cerrar sesión';

  @override
  String get guestAccount => 'Cuenta de invitado';

  @override
  String get guestAccountBody =>
      'Tus sesiones solo están vinculadas a este acceso.';

  @override
  String get accountVerified => 'Email verificado';

  @override
  String get guestLeave => 'Salir del modo invitado';

  @override
  String get guestSignOutTitle => '¿Salir sin proteger tus cuentas?';

  @override
  String get guestSignOutBody =>
      'No podrás recuperar las sesiones de este invitado después de salir. Crea una cuenta para conservarlas.';

  @override
  String get guestSignOutConfirm => 'Salir de todos modos';

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
  String get currentStateTitle => 'Estado actual';

  @override
  String get economicHistoryTitle => 'Histórico económico';

  @override
  String get settledState => 'Saldado';

  @override
  String get currentToReceive => 'Pendiente de cobrar';

  @override
  String get currentToPay => 'Pendiente de pagar';

  @override
  String settlementRemaining(String amount) {
    return 'Quedan $amount por liquidar';
  }

  @override
  String get settlementProgressSemantics => 'Progreso de pagos confirmados';

  @override
  String settlementProgressAmount(String confirmed, String required) {
    return '$confirmed de $required confirmados';
  }

  @override
  String settlementMarkedAmount(String amount) {
    return '$amount marcado como pagado, pendiente de confirmación';
  }

  @override
  String get noSettlementsRequired => 'No hacen falta transferencias';

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
  String get activityEmpty =>
      'Aquí aparecerá lo que vaya pasando: tickets, pagos, espacios y miembros.';

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
  String get deleteInProgress => 'Eliminando cuenta';

  @override
  String get deleteError =>
      'No se ha podido eliminar la cuenta. Comprueba la conexión e inténtalo de nuevo.';

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
  String ticketPaidBy(String name) {
    return 'Pagó $name';
  }

  @override
  String get ticketNoPhoto => 'Este ticket no tiene foto guardada.';

  @override
  String get ticketNoLines => 'Sin desglose de productos (gasto manual).';

  @override
  String historyConfirmedTitle(int count) {
    return 'Pagos confirmados ($count)';
  }

  @override
  String get menuExportPdf => 'Exportar PDF';

  @override
  String get menuShareImage => 'Compartir resumen';

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
  String get aiTitle => 'Proveedores de IA';

  @override
  String get aiHint =>
      'La IA es el último recurso cuando el OCR falla, siempre bajo tu orden. Usas TU propia clave: se guarda cifrada solo en este dispositivo y el coste (céntimos) lo pagas a tu proveedor.';

  @override
  String get aiConfigured => 'Configurado';

  @override
  String get aiPreferred => 'Usar por defecto';

  @override
  String get aiKey => 'API key';

  @override
  String get aiKeyOptional => 'Opcional en servidores locales';

  @override
  String get aiBaseUrl => 'Base URL';

  @override
  String get aiModel => 'Modelo';

  @override
  String get aiTest => 'Probar conexión';

  @override
  String get aiTestOk => 'Conexión correcta ✓';

  @override
  String get aiErrInvalidKey => 'Clave inválida o sin permisos';

  @override
  String get aiErrNoCredit => 'Sin crédito en el proveedor';

  @override
  String get aiErrRateLimited =>
      'Límite de peticiones alcanzado; espera un momento';

  @override
  String get aiErrModel => 'Ese modelo no está disponible';

  @override
  String get aiErrNetwork => 'No se pudo conectar. Revisa la red o la URL.';

  @override
  String get aiErrBadResponse => 'La IA no devolvió un ticket válido';

  @override
  String aiAnalyzing(String provider) {
    return 'Analizando con $provider…';
  }

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

  @override
  String get ticketPickHint =>
      'Marca cada unidad que consumiste. Una unidad marcada por varias personas se comparte; lo no reclamado corre a cargo de quien pagó.';

  @override
  String get lineForAll => 'Para todos';

  @override
  String lineSharedWith(String names) {
    return 'Compartido con $names';
  }

  @override
  String lineTakenBy(String names) {
    return 'Lo tiene $names';
  }

  @override
  String get lineAddUnit => 'Añadir una unidad';

  @override
  String get lineRemoveUnit => 'Quitar una unidad';

  @override
  String unitAssignment(int number, String names) {
    return 'Unidad $number: $names';
  }

  @override
  String unitResidual(String payer) {
    return 'sin reclamar (para $payer)';
  }

  @override
  String unitCompactSummary(int selected, int total, int residual) {
    return '$selected de $total tuyas · $residual sin reclamar';
  }

  @override
  String get unitsUpgradeTitle => 'Actualizar el reparto por unidades';

  @override
  String get unitsUpgradeBody =>
      'Este producto usa el reparto anterior, que no identifica cada unidad. Al actualizarlo se borrarán sus selecciones actuales y podrás marcar cada unidad sin ambigüedad.';

  @override
  String get unitsUpgradeAction => 'Repartir por unidades';

  @override
  String settlementAwaitsReceiver(String name) {
    return 'Confirmará $name al recibir el dinero';
  }

  @override
  String get activityTitle => 'Actividad';

  @override
  String get activitySeeAll => 'Ver toda';

  @override
  String get activityLoadError =>
      'No se pudo cargar la actividad. Comprueba la conexión.';

  @override
  String get activityRetry => 'Reintentar';

  @override
  String get activityLoadMore => 'Cargar más';

  @override
  String get activityGone => 'Ese elemento ya no está disponible.';

  @override
  String get activityActorFallback => 'Alguien';

  @override
  String get activityUnknown => 'Actividad';

  @override
  String get activityNow => 'ahora';

  @override
  String activityMinutesAgo(int n) {
    return 'hace $n min';
  }

  @override
  String activityHoursAgo(int n) {
    return 'hace $n h';
  }

  @override
  String activityDaysAgo(int n) {
    return 'hace $n d';
  }

  @override
  String activitySpaceCreated(String space) {
    return 'Creó el espacio \"$space\"';
  }

  @override
  String activitySpaceRenamed(String space) {
    return 'Editó el espacio \"$space\"';
  }

  @override
  String activitySpaceArchived(String space) {
    return 'Archivó el espacio \"$space\"';
  }

  @override
  String activitySpaceReactivated(String space) {
    return 'Reactivó el espacio \"$space\"';
  }

  @override
  String activitySpaceTransferred(String space) {
    return 'Transfirió el espacio \"$space\"';
  }

  @override
  String activityInviteSent(String space) {
    return 'Envió una invitación a \"$space\"';
  }

  @override
  String activityMemberJoined(String space) {
    return 'Se unió a \"$space\"';
  }

  @override
  String activityMemberLeft(String space) {
    return 'Salió de \"$space\"';
  }

  @override
  String activityMemberRemoved(String space) {
    return 'Eliminó a un miembro de \"$space\"';
  }

  @override
  String activityTicketCreated(String ticket) {
    return 'Añadió el ticket $ticket';
  }

  @override
  String activityTicketUpdated(String ticket) {
    return 'Modificó el ticket $ticket';
  }

  @override
  String activityTicketLinked(String ticket, String space) {
    return 'Vinculó $ticket al espacio \"$space\"';
  }

  @override
  String activityTicketUnlinked(String ticket) {
    return 'Desvinculó el ticket $ticket';
  }

  @override
  String activityTicketDeleted(String ticket) {
    return 'Eliminó el ticket $ticket';
  }

  @override
  String get activityPaymentMarked => 'Marcó un pago como enviado';

  @override
  String get activityPaymentConfirmed => 'Confirmó que recibió un pago';

  @override
  String get activityPaymentCancelled => 'Canceló un pago';

  @override
  String get guestNameTitle => 'Tu nombre';

  @override
  String get guestNameBody =>
      'Estás usando Salda como invitado: no hace falta cuenta. Elige el nombre con el que te verán en los grupos y relaciones.';

  @override
  String get guestNameLabel => 'Nombre visible';

  @override
  String get guestNameRequired => 'Escribe un nombre para continuar';

  @override
  String get guestNameSaved => 'Nombre guardado';

  @override
  String get guestNameError =>
      'No se pudo guardar el nombre. Inténtalo de nuevo.';

  @override
  String get guestNameBannerTitle => 'Elige tu nombre para participar';

  @override
  String get guestNameBannerAction => 'Elegir nombre';

  @override
  String get guestLimitsBody =>
      'Como invitado participas en gastos y balances. Crear grupos o relaciones, invitar personas y tener perfil público requieren una cuenta. Podrás crear gastos si el anfitrión lo permite.';

  @override
  String get guestBadge => 'Invitado';

  @override
  String get guestPolicyTitle => 'Permitir gastos a los invitados';

  @override
  String get guestPolicyBody =>
      'Si lo activas, los invitados de este contexto podrán crear gastos.';

  @override
  String get manualParticipantsTitle => 'Personas sin cuenta';

  @override
  String get manualParticipantsEmpty =>
      'Añade a quien no use Salda: solo necesitas su nombre y participará en los gastos igual que los demás.';

  @override
  String get manualParticipantAdd => 'Añadir';

  @override
  String get manualParticipantName => 'Nombre';

  @override
  String get manualParticipantHint => 'Sin cuenta · participa en los gastos';

  @override
  String get manualParticipantRename => 'Cambiar el nombre';

  @override
  String get manualParticipantRemove => 'Quitar del contexto';

  @override
  String manualParticipantRemoveBody(String name) {
    return '$name dejará de aparecer en los gastos nuevos. Su historial, sus deudas y sus pagos no se tocan.';
  }

  @override
  String get spacesTitle => 'Espacios';

  @override
  String get spacesCreate => 'Crear espacio';

  @override
  String get spacesEmptyTitle => 'Todavía no tienes espacios';

  @override
  String get spacesEmptyBody =>
      'Un espacio agrupa los gastos de un viaje, un piso, una pareja o una peña. Crea uno e invita a tus amigos.';

  @override
  String get spacesLoadError =>
      'No se pudieron cargar los espacios. Comprueba la conexión.';

  @override
  String spacesArchivedSection(int count) {
    return 'Archivados ($count)';
  }

  @override
  String get spaceNameLabel => 'Nombre del espacio';

  @override
  String get spaceNameHint => 'Viaje a Lisboa, Piso, Peña…';

  @override
  String get spaceEmojiLabel => 'Emoji (opcional)';

  @override
  String get spaceOwnerBadge => 'Propietario';

  @override
  String get personUnnamed => 'Persona sin nombre';

  @override
  String get spaceGone => 'Ya no tienes acceso a este espacio.';

  @override
  String get spaceMembersTitle => 'Miembros';

  @override
  String spaceMembersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count miembros',
      one: '1 miembro',
    );
    return '$_temp0';
  }

  @override
  String get spaceEditName => 'Editar espacio';

  @override
  String get spaceArchive => 'Archivar';

  @override
  String get spaceReactivate => 'Reactivar';

  @override
  String get spaceLeave => 'Salir del espacio';

  @override
  String get spaceLeaveBody =>
      'Dejarás de ver este espacio. Los tickets, pagos e historial no se tocan.';

  @override
  String get spaceInviteAction => 'Invitar';

  @override
  String get spaceInviteSheetTitle => 'Invitar a un amigo';

  @override
  String get spaceInviteNoFriends =>
      'Aún no tienes amigos en Salda. Añádelos desde Buscar personas.';

  @override
  String get spaceAlreadyMember => 'Ya es miembro';

  @override
  String get spaceAlreadyInvited => 'Invitado';

  @override
  String get spacePendingInvites => 'Invitaciones pendientes';

  @override
  String get spaceInviteCancel => 'Cancelar invitación';

  @override
  String spaceInviteText(String name, String space) {
    return '$name te invita al espacio \"$space\"';
  }

  @override
  String relationshipInviteText(String name) {
    return '$name quiere compartir gastos contigo';
  }

  @override
  String get spaceInviteAccept => 'Unirme';

  @override
  String get spaceInviteReject => 'Rechazar';

  @override
  String get spaceTransferTitle => 'Transferir propiedad';

  @override
  String spaceTransferBody(String name) {
    return '$name pasará a ser quien administre este espacio. Tú seguirás como miembro.';
  }

  @override
  String get spaceRemoveMemberTitle => 'Eliminar del espacio';

  @override
  String spaceRemoveMemberBody(String name) {
    return '$name dejará de ver este espacio. Sus tickets, pagos e historial no se tocan.';
  }

  @override
  String get spaceTicketsTitle => 'Tickets del espacio';

  @override
  String get spaceTicketsEmpty =>
      'Aún no hay tickets vinculados. Crea uno desde aquí o vincula uno existente desde su detalle.';

  @override
  String get spaceTicketUntitled => 'Ticket';

  @override
  String get spaceAddTicket => 'Añadir ticket';

  @override
  String get ticketGoneTitle => 'Este gasto ya no está disponible';

  @override
  String get ticketGoneBody =>
      'Puede que se haya borrado o que hayas perdido el acceso a su contexto.';

  @override
  String get spaceActionError =>
      'No se pudo completar la acción. Inténtalo de nuevo.';

  @override
  String get socialEmailNotVerified =>
      'Verifica tu correo antes de compartir gastos.';

  @override
  String get socialProfileNotReady =>
      'Necesitamos terminar de preparar tu perfil. Inténtalo de nuevo.';

  @override
  String get profileRequiredForSocial => 'Necesario para compartir gastos';

  @override
  String get spaceSessionNotReady =>
      'Tu sesión aún no está lista para compartir gastos. Comprueba que has verificado el correo y completado tu perfil, y vuelve a entrar.';

  @override
  String get spaceLinkTooltip => 'Espacio compartido';

  @override
  String spaceLinkTo(String name) {
    return 'Vincular a $name';
  }

  @override
  String get spaceUnlink => 'Desvincular del espacio';

  @override
  String get spaceLinked => 'Ticket vinculado al espacio';

  @override
  String get spaceUnlinked => 'Ticket desvinculado';

  @override
  String get chatTitle => 'Chat';

  @override
  String get chatDescription =>
      'Coordina los gastos dentro de esta relación o grupo.';

  @override
  String get chatReadOnly =>
      'El contexto está archivado. El chat es de solo lectura.';

  @override
  String get chatEmptyTitle => 'Todavía no hay mensajes';

  @override
  String get chatEmptyBody =>
      'Escribe el primero para coordinaros dentro de este contexto.';

  @override
  String get chatMessageHint => 'Escribe un mensaje';

  @override
  String get chatSend => 'Enviar mensaje';

  @override
  String get chatSending => 'Enviando…';

  @override
  String get chatSendError =>
      'No se pudo enviar el mensaje. Revisa la conexión e inténtalo de nuevo.';

  @override
  String get chatLoadError =>
      'No se pudo cargar el chat. Revisa la conexión y vuelve a intentarlo.';

  @override
  String get chatLoadOlder => 'Cargar mensajes anteriores';

  @override
  String get chatUnavailable => 'Ya no tienes acceso a este chat.';

  @override
  String get chatYou => 'Tú';

  @override
  String get chatAuthorFallback => 'Miembro';

  @override
  String get chatMessageActions => 'Acciones del mensaje';

  @override
  String get chatDelete => 'Eliminar mensaje';

  @override
  String get chatDeleteTitle => '¿Eliminar este mensaje?';

  @override
  String get chatDeleteBody => 'Se eliminará del chat para todos los miembros.';

  @override
  String get chatDeleteError => 'No se pudo eliminar el mensaje.';

  @override
  String get profileTitle => 'Perfil público';

  @override
  String get profileCreateTitle => 'Crea tu perfil';

  @override
  String get profileCreateBody =>
      'Tu nombre de usuario es único y te identifica: así podrán encontrarte tus amigos.';

  @override
  String get profileCreateAction => 'Crear perfil';

  @override
  String get profileUsername => 'Nombre de usuario';

  @override
  String get profileUsernameHelp =>
      'Único y en minúsculas: letras, números y _';

  @override
  String get profileSaved => 'Perfil guardado';

  @override
  String get profileSaveError =>
      'No se pudo guardar. Comprueba la conexión o prueba otro nombre de usuario.';

  @override
  String get profileBannerTitle => 'Completa tu perfil público';

  @override
  String get profileBannerAction => 'Crear perfil';

  @override
  String get usernameChecking => 'Comprobando disponibilidad…';

  @override
  String get usernameAvailable => 'Disponible';

  @override
  String get usernameTaken => 'Ya está en uso';

  @override
  String get usernameErrorTooShort => 'Mínimo 3 caracteres';

  @override
  String get usernameErrorTooLong => 'Máximo 20 caracteres';

  @override
  String get usernameErrorInvalidChars => 'Solo letras sin tildes, números y _';

  @override
  String get usernameErrorStartLetter => 'Debe empezar por una letra';

  @override
  String get usernameErrorUnderscores =>
      'El _ no puede ir al final ni repetido';

  @override
  String get usernameErrorReserved => 'Ese nombre está reservado';

  @override
  String get searchPeopleTitle => 'Buscar personas';

  @override
  String get searchPeopleHint => 'Nombre o @usuario';

  @override
  String get searchPeopleStart =>
      'Busca a otras personas por su nombre o su @usuario';

  @override
  String get searchPeopleEmpty => 'Sin resultados';

  @override
  String get searchPeopleError => 'No se pudo completar la búsqueda';

  @override
  String get friendsTitle => 'Amigos';

  @override
  String get friendsTabFriends => 'Amigos';

  @override
  String get friendsTabReceived => 'Recibidas';

  @override
  String get friendsTabSent => 'Enviadas';

  @override
  String get friendsEmpty => 'Todavía no tienes amigos';

  @override
  String get friendsEmptyBody => 'Busca personas y envía tu primera solicitud';

  @override
  String get friendRequestsReceivedEmpty => 'No tienes solicitudes pendientes';

  @override
  String get friendRequestsSentEmpty => 'No has enviado solicitudes';

  @override
  String get friendAdd => 'Añadir amigo';

  @override
  String get friendRequestSent => 'Solicitud enviada';

  @override
  String get friendAccept => 'Aceptar';

  @override
  String get friendReject => 'Rechazar';

  @override
  String get friendCancelRequest => 'Cancelar solicitud';

  @override
  String get friendFriendsStatus => 'Amigos';

  @override
  String get friendRemove => 'Eliminar amistad';

  @override
  String get friendRemoveTitle => '¿Eliminar esta amistad?';

  @override
  String get friendRemoveBody =>
      'Solo se eliminará la relación social. Los tickets, balances y pagos no cambiarán.';

  @override
  String get friendActionError =>
      'No se pudo actualizar la relación. Comprueba tu conexión e inténtalo de nuevo.';

  @override
  String get friendErrorUnverified =>
      'Verifica tu correo antes de usar las amistades.';

  @override
  String get friendErrorProfileRequired =>
      'Completa tu perfil antes de enviar solicitudes.';

  @override
  String get friendErrorRequestExists =>
      'Ya existe una solicitud de amistad entre estas cuentas.';

  @override
  String get friendErrorAlreadyFriends => 'Estas cuentas ya son amigas.';

  @override
  String get friendErrorPermissionDenied =>
      'Firebase ha rechazado la operación. Actualiza la app o vuelve a iniciar sesión.';

  @override
  String get friendErrorServiceUnavailable =>
      'El servicio de amistades no está disponible en este entorno.';

  @override
  String get friendErrorNetwork =>
      'No hay conexión con Firebase. Revisa tu red e inténtalo de nuevo.';

  @override
  String get friendErrorUnexpected =>
      'No se pudo actualizar la relación por un error inesperado.';

  @override
  String get friendProfileUnavailable => 'Perfil no disponible';

  @override
  String get friendProfileRequired =>
      'Completa tu perfil antes de usar las amistades';

  @override
  String get friendProfileRequiredAction => 'Crear perfil';

  @override
  String get friendEditOwnProfile => 'Editar perfil';

  @override
  String get economyTitle => 'Economía';

  @override
  String get economySummaryTitle => 'Tu balance';

  @override
  String get economyOwedToMe => 'Te deben';

  @override
  String get economyIOwe => 'Debes';

  @override
  String get economyNet => 'Saldo neto';

  @override
  String get economyRelationsTitle => 'Relaciones abiertas';

  @override
  String get economyEmptyTitle => 'No tienes saldos pendientes';

  @override
  String get economyEmptyBody =>
      'Cuando un ticket vincule dos cuentas registradas, aquí podrás ver y explicar cada importe.';

  @override
  String get economyLoadError =>
      'No se pudo cargar tu balance. Revisa la conexión y vuelve a intentarlo.';

  @override
  String economyYouOwe(String name) {
    return 'Debes a $name';
  }

  @override
  String economyOwesYou(String name) {
    return '$name te debe';
  }

  @override
  String economySettledWith(String name) {
    return 'Sin saldo pendiente con $name';
  }

  @override
  String economyDetailTitle(String name) {
    return 'Balance con $name';
  }

  @override
  String get economyOriginalDebt => 'Deuda original';

  @override
  String get economyTicketsTitle => 'Tickets que explican el saldo';

  @override
  String get economyPaymentsTitle => 'Pagos y liquidaciones';

  @override
  String get economyOutsideSpace => 'Fuera de espacios';

  @override
  String get economyInSpace => 'Espacio vinculado';

  @override
  String get economyMarkPaid => 'Marcar como pagado';

  @override
  String get economyPaymentAmount => 'Importe pagado';

  @override
  String get economyPaymentPending => 'Pendiente de confirmación';

  @override
  String get economyPaymentConfirmed => 'Confirmado por el receptor';

  @override
  String get economyPaymentCancelled => 'Cancelado';

  @override
  String get economyConfirmPayment => 'Confirmar recepción';

  @override
  String get economyRejectPayment => 'Rechazar';

  @override
  String get economyCancelPayment => 'Cancelar aviso';

  @override
  String get economyPaymentSuccess => 'Pago pendiente enviado al receptor.';

  @override
  String get economyPaymentErrorOver =>
      'El importe supera el saldo pendiente o ya está reservado por otro pago.';

  @override
  String get economyPaymentErrorPermission =>
      'Solo el deudor crea el pago y solo el receptor puede confirmarlo.';

  @override
  String get economyPaymentErrorNetwork =>
      'No se pudo contactar con el servicio de pagos.';

  @override
  String get economyPaymentErrorUnexpected => 'No se pudo actualizar el pago.';

  @override
  String get economyPendingConfirmations => 'Pagos por confirmar';

  @override
  String get economyOpenDetail => 'Ver desglose';

  @override
  String get spaceEconomicTitle => 'Tu balance en este espacio';

  @override
  String get spaceEconomicEmptyTitle => 'Sin movimientos todavía';

  @override
  String get spaceEconomicSettled =>
      'Estáis en paz: nadie debe nada en este espacio.';

  @override
  String get spaceEconomicSpent => 'Gastado aquí';

  @override
  String spaceTicketsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gastos',
      one: '1 gasto',
    );
    return '$_temp0';
  }

  @override
  String get spaceEconomicEmpty =>
      'Todavía no tienes movimientos económicos identificados en este espacio.';

  @override
  String get commonRetry => 'Reintentar';

  @override
  String get balanceHeroTitle => 'Tu saldo';

  @override
  String get balanceSettled => 'Estás en paz';

  @override
  String get balanceSettledBody => 'Nadie te debe y no debes nada.';

  @override
  String get balanceTheyOweYou => 'Te deben';

  @override
  String get balanceYouOwe => 'Debes';

  @override
  String get balanceNetPositive => 'A tu favor';

  @override
  String get balanceNetNegative => 'En tu contra';

  @override
  String get homeQuickScan => 'Escanear ticket';

  @override
  String get homeQuickMore => 'Más';

  @override
  String get homeSpacesTitle => 'Tus contextos';

  @override
  String get homeNoSpacesTitle => 'Todavía no compartes gastos con nadie';

  @override
  String get homeNoSpacesBody =>
      'Crea una relación para las cuentas de dos, o un grupo para un piso, un viaje o una cena.';

  @override
  String get homeActivityRecent => 'Reciente';

  @override
  String get homeMenuTitle => 'Menú';

  @override
  String get contextPendingShort => 'Pendiente';

  @override
  String get contextAccountRequiredTitle => 'Necesitas una cuenta';

  @override
  String get economySettledBadge => 'Saldado';

  @override
  String get economyNoPaymentsBody =>
      'Cuando marques o confirmes un pago, quedará aquí con su fecha.';

  @override
  String get friendProfileRequiredBody =>
      'Tu perfil público es lo que permite que otras personas te encuentren y te agreguen.';

  @override
  String get aiProvidersSection => 'Proveedores';

  @override
  String get peopleSectionTitle => 'Quién participa';

  @override
  String get splitSectionTitle => 'Cómo se reparte';

  @override
  String get splitEqualHelp =>
      'El importe se divide a partes iguales entre todas las personas.';

  @override
  String get splitByItemHelp =>
      'Cada persona elige lo que consumió; lo no reclamado recae en quien pagó.';

  @override
  String get createDisabledHelp =>
      'Necesitas al menos dos personas para repartir un gasto.';

  @override
  String get ticketPhotoTitle => 'Foto del ticket';

  @override
  String get ticketFallbackName => 'Gasto';

  @override
  String get ticketNoLinesBody =>
      'Este gasto se reparte por su importe total, sin detalle de productos.';

  @override
  String get reviewTicketData => 'Datos del ticket';

  @override
  String get reviewTotalsTitle => 'Desglose';

  @override
  String get reviewNoLinesTitle => 'El ticket no tiene lineas';

  @override
  String get reviewNoLinesBody =>
      'Anade al menos un producto para poder repartir el gasto entre varias personas.';

  @override
  String get relationshipNeedsAcceptanceBody =>
      'En cuanto acepte podreis registrar gastos y ver el saldo entre los dos.';

  @override
  String get groupNeedsMembersBody =>
      'Invita a alguien con cuenta, comparte el enlace del grupo o anade a una persona sin cuenta.';

  @override
  String get activityLoadingSubject => '…';

  @override
  String peopleCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personas',
      one: '1 persona',
      zero: 'Sin personas',
    );
    return '$_temp0';
  }

  @override
  String get spaceKindRelationship => 'Relación';

  @override
  String get spaceKindGroup => 'Grupo';

  @override
  String get personKindManual => 'Sin cuenta';

  @override
  String get personKindGuest => 'Invitado';

  @override
  String get personKindOwner => 'Propietario';

  @override
  String get emptyTicketsTitle => 'Sin gastos todavía';

  @override
  String get emptyTicketsBody =>
      'Escanea un ticket o apunta un gasto a mano y aparecerá aquí.';

  @override
  String get emptyActivityTitle => 'Sin movimientos';

  @override
  String get emptyActivityBody =>
      'Aquí se irá anotando lo que ocurra en tus contextos.';

  @override
  String get emptyChatTitle => 'Sin mensajes';

  @override
  String get emptyChatBody =>
      'Escribe el primero: la conversación es privada de este contexto.';

  @override
  String get historyTitle => 'Histórico sin organizar';

  @override
  String get contextCreate => 'Crear';

  @override
  String get contextAccountRequired =>
      'Convierte tu cuenta de invitado para crear relaciones y grupos permanentes.';

  @override
  String get contextInvitations => 'Invitaciones';

  @override
  String get contextInvitationPending => 'Quiere compartir gastos contigo';

  @override
  String get relationshipsTitle => 'Relaciones';

  @override
  String get relationshipsEmpty =>
      'Crea una relación para compartir gastos con otra persona';

  @override
  String get groupsTitle => 'Grupos';

  @override
  String get groupsEmpty => 'Crea un grupo para tres o más personas';

  @override
  String get relationshipCreate => 'Nueva relación';

  @override
  String get relationshipCreateHelp => 'Gastos entre dos personas';

  @override
  String get relationshipAlreadyInvited =>
      'Ya le habías invitado. Sigue pendiente de que acepte.';

  @override
  String get relationshipReinvited => 'Le hemos vuelto a enviar la invitación.';

  @override
  String get relationshipAlreadyActive => 'Ya tenéis una relación activa.';

  @override
  String get relationshipInvitedByOther =>
      'Esa persona ya te invitó. Acepta su invitación desde Inicio.';

  @override
  String get relationshipIncompatible =>
      'Esta relación tiene datos antiguos que no podemos completar. Avísanos antes de reintentar.';

  @override
  String get relationshipNotAllowed =>
      'No puedes crear una relación contigo mismo.';

  @override
  String get relationshipManualTitle => 'Añadir a alguien sin cuenta';

  @override
  String get relationshipManualBody =>
      'Participa en gastos, saldos y pagos igual que tú. Si se registra más adelante, podréis vincularlo sin perder el historial.';

  @override
  String get relationshipManualName => 'Su nombre';

  @override
  String get relationshipNoAccountTitle => '¿No tiene cuenta en Salda?';

  @override
  String get relationshipNoAccountBody =>
      'Una relación son dos cuentas. Para compartir gastos con alguien sin cuenta, crea un grupo: admite personas añadidas a mano y enlaces de invitación.';

  @override
  String get relationshipSearchHelp =>
      'Busca a la persona con la que quieres compartir gastos.';

  @override
  String get groupCreate => 'Nuevo grupo';

  @override
  String get groupCreateHelp => 'Gastos entre tres o más personas';

  @override
  String get ticketContextMissing =>
      'Abre una relación o un grupo antes de crear el ticket.';

  @override
  String get relationshipNeedsAcceptance =>
      'La otra persona debe aceptar la invitación antes de crear tickets.';

  @override
  String get groupNeedsMembers =>
      'Añade a alguien más al grupo antes de crear tickets. Si no tiene la app, añádelo como persona sin cuenta.';

  @override
  String get contextChoose => 'Elige una relación o grupo';

  @override
  String get ticketContextLocked =>
      'Este ticket pertenece a su contexto y no se puede desvincular';

  @override
  String get commonConfirm => 'Confirmar';

  @override
  String get spaceLinkTitle => 'Enlace del grupo';

  @override
  String get spaceLinkAction => 'Compartir enlace';

  @override
  String get spaceLinkEmpty =>
      'Crea un enlace para que otras personas se unan a este grupo sin que tengas que buscarlas.';

  @override
  String get spaceLinkCreate => 'Crear enlace';

  @override
  String get spaceLinkHint =>
      'Cualquiera con este enlace puede unirse al grupo. Revócalo cuando ya no lo necesites.';

  @override
  String get spaceLinkRotate => 'Generar un enlace nuevo';

  @override
  String get spaceLinkRotateConfirm =>
      'El enlace actual dejará de funcionar y tendrás que repartir el nuevo. ¿Continuar?';

  @override
  String get spaceLinkRevoke => 'Revocar el enlace';

  @override
  String get spaceLinkRevokeConfirm =>
      'Nadie más podrá unirse con este enlace. Los miembros actuales se quedan. ¿Continuar?';

  @override
  String get spaceLinkError => 'No hemos podido cargar el enlace';

  @override
  String get joinTitle => 'Unirse a un grupo';

  @override
  String get joinEntry => 'Unirme con un enlace';

  @override
  String get joinPasteHint => 'Pega aquí el enlace que te han enviado.';

  @override
  String get joinPasteLabel => 'Enlace del grupo';

  @override
  String get joinLookup => 'Continuar';

  @override
  String get joinInvitedTo => 'Te invitan a';

  @override
  String get joinIdentifyHint =>
      'Identifícate para unirte. No hace falta crear una cuenta.';

  @override
  String get joinWithAccount => 'Entrar con mi cuenta';

  @override
  String get joinAction => 'Unirme al grupo';

  @override
  String get joinLinkInvalid =>
      'Este enlace ya no sirve. Pide uno nuevo a quien te lo envió.';

  @override
  String get joinLinkError =>
      'No hemos podido unirte al grupo. Inténtalo otra vez.';

  @override
  String get joinCreateAccount => 'Crear una cuenta';

  @override
  String get joinVerifyEmail =>
      'Verifica tu correo para entrar en el grupo. Guardamos el enlace: al volver entrarás directamente.';

  @override
  String get joinVerifyEmailAction => 'Verificar mi correo';

  @override
  String get joinGuestNameHint => '¿Cómo quieres que te vean en el grupo?';

  @override
  String get ticketLinkTitle => 'Ticket compartido';

  @override
  String get ticketLinkAction => 'Compartir este ticket';

  @override
  String get ticketLinkSharedWithYou => 'Te han compartido el ticket de';

  @override
  String ticketLinkAreYou(String name) {
    return '¿Eres $name?';
  }

  @override
  String get ticketLinkAreYouHelp =>
      'Este enlace se creó para esa persona. Si no eres tú, pide el tuyo a quien te lo envió.';

  @override
  String ticketLinkIAm(String name) {
    return 'Sí, soy $name';
  }

  @override
  String get ticketLinkNotMe => 'No soy esa persona';

  @override
  String get ticketLinkNoManuals =>
      'Este enlace ya no identifica a nadie de este ticket.';

  @override
  String get ticketLinkManualTaken =>
      'Otra persona ya usó este enlace. Pide uno nuevo a quien te lo envió.';

  @override
  String ticketLinkFor(String name) {
    return 'Enlace para $name';
  }

  @override
  String get ticketLinkChooseTarget => '¿Para quién es el enlace?';

  @override
  String get ticketLinkChooseTargetHelp =>
      'Cada persona recibe su propio enlace: solo podrá identificarse como ella misma.';

  @override
  String get ticketLinkNoTargets =>
      'Este ticket no tiene participantes sin cuenta a los que enviar un enlace.';

  @override
  String get ticketLinkInvalid =>
      'Este enlace ya no sirve. Pide uno nuevo a quien te lo envió.';

  @override
  String get ticketLinkError =>
      'No hemos podido abrir el ticket. Inténtalo otra vez.';

  @override
  String get ticketLinkGone => 'Este ticket ya no está disponible.';

  @override
  String get ticketLinkLines => 'Productos';

  @override
  String get ticketLinkTotal => 'Total';

  @override
  String get ticketLinkRelease => 'No soy yo';

  @override
  String get ticketLinkTemporary =>
      'Identificación temporal, solo en este dispositivo';

  @override
  String ticketLinkViewingAs(String name) {
    return 'Estás viendo el ticket como $name';
  }

  @override
  String get ticketLinkEmpty =>
      'Crea un enlace para que quien no tenga cuenta pueda ver este ticket.';

  @override
  String get ticketLinkCreate => 'Crear enlace del ticket';

  @override
  String get ticketLinkHint =>
      'Quien reciba este enlace verá solo este ticket, nunca el resto del grupo.';

  @override
  String get ticketLinkRevoke => 'Revocar el enlace';

  @override
  String get manualLinkRequestsTitle => 'Solicitudes de identidad';

  @override
  String manualLinkRequestBody(String name, String manual) {
    return '$name dice ser $manual';
  }

  @override
  String get manualLinkRequestHelp =>
      'Si lo aceptas, esa persona pasará a ver sus gastos y su saldo. No cambia nada de lo ya registrado.';

  @override
  String get manualLinkAccept => 'Aceptar';

  @override
  String get manualLinkReject => 'Rechazar';

  @override
  String get manualLinkAccepted => 'Identidad vinculada';

  @override
  String get manualLinkRejected => 'Solicitud rechazada';

  @override
  String get manualLinkError => 'No hemos podido completar la operación';

  @override
  String get manualLinkAsk => 'Soy yo';

  @override
  String get manualLinkAskSent =>
      'Solicitud enviada. El anfitrión debe aceptarla.';

  @override
  String get manualLinkPending => 'Pendiente de que el anfitrión lo acepte';

  @override
  String get manualLinkLinked => 'Identidad vinculada';

  @override
  String manualLinkPendingInSpace(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count solicitudes',
      one: '1 solicitud',
    );
    return '$_temp0';
  }

  @override
  String get manualLinkProcessing =>
      'Vinculando… tendrás acceso en unos segundos';

  @override
  String get manualLinkFailedLegacy =>
      'Hay gastos antiguos sin contexto que impiden completar la vinculación. Avisa al anfitrión.';

  @override
  String get ticketLinkPreparing => 'Preparando el enlace…';

  @override
  String get ticketLinkNotReady =>
      'El ticket todavía se está procesando. Inténtalo de nuevo en unos segundos.';

  @override
  String get spaceLinkExpiryLabel => 'Caducidad';

  @override
  String get spaceLinkExpiryNever => 'Sin caducidad';

  @override
  String get spaceLinkExpiry1d => '1 día';

  @override
  String get spaceLinkExpiry7d => '7 días';

  @override
  String get spaceLinkExpiry30d => '30 días';

  @override
  String spaceLinkExpiresOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Caduca el $dateString';
  }
}
