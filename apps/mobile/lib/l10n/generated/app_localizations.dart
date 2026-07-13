import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('es')];

  /// No description provided for @homeTagline.
  ///
  /// In es, this message translates to:
  /// **'Escanea el ticket, reparte y salda cuentas.'**
  String get homeTagline;

  /// No description provided for @homeEmptyHint.
  ///
  /// In es, this message translates to:
  /// **'Los cimientos están listos. El historial de sesiones llega en M3.'**
  String get homeEmptyHint;

  /// No description provided for @scanFab.
  ///
  /// In es, this message translates to:
  /// **'Escanear'**
  String get scanFab;

  /// No description provided for @scanFromCamera.
  ///
  /// In es, this message translates to:
  /// **'Hacer foto'**
  String get scanFromCamera;

  /// No description provided for @scanFromGallery.
  ///
  /// In es, this message translates to:
  /// **'Elegir de la galería'**
  String get scanFromGallery;

  /// No description provided for @scanProcessing.
  ///
  /// In es, this message translates to:
  /// **'Leyendo el ticket…'**
  String get scanProcessing;

  /// No description provided for @scanNothingRecognized.
  ///
  /// In es, this message translates to:
  /// **'No se pudo leer nada en la imagen'**
  String get scanNothingRecognized;

  /// No description provided for @reviewTitle.
  ///
  /// In es, this message translates to:
  /// **'Revisar ticket'**
  String get reviewTitle;

  /// No description provided for @reviewBannerLowConfidence.
  ///
  /// In es, this message translates to:
  /// **'Hay datos dudosos o que no cuadran. Revísalos antes de continuar.'**
  String get reviewBannerLowConfidence;

  /// No description provided for @reviewRetake.
  ///
  /// In es, this message translates to:
  /// **'Repetir foto'**
  String get reviewRetake;

  /// No description provided for @reviewEditManually.
  ///
  /// In es, this message translates to:
  /// **'Editar a mano'**
  String get reviewEditManually;

  /// No description provided for @reviewAnalyzeWithAi.
  ///
  /// In es, this message translates to:
  /// **'Analizar con IA'**
  String get reviewAnalyzeWithAi;

  /// No description provided for @reviewAiUnavailable.
  ///
  /// In es, this message translates to:
  /// **'Disponible al configurar un proveedor de IA (Ajustes)'**
  String get reviewAiUnavailable;

  /// No description provided for @reviewMerchant.
  ///
  /// In es, this message translates to:
  /// **'Establecimiento'**
  String get reviewMerchant;

  /// No description provided for @reviewDate.
  ///
  /// In es, this message translates to:
  /// **'Fecha'**
  String get reviewDate;

  /// No description provided for @reviewTime.
  ///
  /// In es, this message translates to:
  /// **'Hora'**
  String get reviewTime;

  /// No description provided for @reviewLines.
  ///
  /// In es, this message translates to:
  /// **'Productos'**
  String get reviewLines;

  /// No description provided for @reviewAddLine.
  ///
  /// In es, this message translates to:
  /// **'Añadir producto'**
  String get reviewAddLine;

  /// No description provided for @reviewComputedTotal.
  ///
  /// In es, this message translates to:
  /// **'Suma de productos'**
  String get reviewComputedTotal;

  /// No description provided for @reviewGrandTotal.
  ///
  /// In es, this message translates to:
  /// **'Total del ticket'**
  String get reviewGrandTotal;

  /// No description provided for @reviewBalanced.
  ///
  /// In es, this message translates to:
  /// **'El ticket cuadra'**
  String get reviewBalanced;

  /// No description provided for @reviewMismatch.
  ///
  /// In es, this message translates to:
  /// **'Descuadre de {amount}'**
  String reviewMismatch(String amount);

  /// No description provided for @reviewTip.
  ///
  /// In es, this message translates to:
  /// **'Propina'**
  String get reviewTip;

  /// No description provided for @reviewDiscount.
  ///
  /// In es, this message translates to:
  /// **'Descuento'**
  String get reviewDiscount;

  /// No description provided for @lineEditTitle.
  ///
  /// In es, this message translates to:
  /// **'Editar producto'**
  String get lineEditTitle;

  /// No description provided for @lineName.
  ///
  /// In es, this message translates to:
  /// **'Nombre'**
  String get lineName;

  /// No description provided for @lineQuantity.
  ///
  /// In es, this message translates to:
  /// **'Cantidad'**
  String get lineQuantity;

  /// No description provided for @lineUnitPrice.
  ///
  /// In es, this message translates to:
  /// **'Precio unitario'**
  String get lineUnitPrice;

  /// No description provided for @lineTotalPrice.
  ///
  /// In es, this message translates to:
  /// **'Importe'**
  String get lineTotalPrice;

  /// No description provided for @lineAlternatives.
  ///
  /// In es, this message translates to:
  /// **'¿Quizá era…?'**
  String get lineAlternatives;

  /// No description provided for @lineDelete.
  ///
  /// In es, this message translates to:
  /// **'Eliminar producto'**
  String get lineDelete;

  /// No description provided for @lineSource.
  ///
  /// In es, this message translates to:
  /// **'Texto original: {source}'**
  String lineSource(String source);

  /// No description provided for @commonSave.
  ///
  /// In es, this message translates to:
  /// **'Guardar'**
  String get commonSave;

  /// No description provided for @commonCancel.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get commonCancel;

  /// No description provided for @commonContinue.
  ///
  /// In es, this message translates to:
  /// **'Continuar'**
  String get commonContinue;

  /// No description provided for @commonDone.
  ///
  /// In es, this message translates to:
  /// **'Listo'**
  String get commonDone;

  /// No description provided for @loginTitle.
  ///
  /// In es, this message translates to:
  /// **'Divide gastos sin discusiones'**
  String get loginTitle;

  /// No description provided for @loginEmail.
  ///
  /// In es, this message translates to:
  /// **'Email'**
  String get loginEmail;

  /// No description provided for @loginPassword.
  ///
  /// In es, this message translates to:
  /// **'Contraseña'**
  String get loginPassword;

  /// No description provided for @loginDisplayName.
  ///
  /// In es, this message translates to:
  /// **'Tu nombre'**
  String get loginDisplayName;

  /// No description provided for @loginSignIn.
  ///
  /// In es, this message translates to:
  /// **'Entrar'**
  String get loginSignIn;

  /// No description provided for @loginRegister.
  ///
  /// In es, this message translates to:
  /// **'Crear cuenta'**
  String get loginRegister;

  /// No description provided for @loginToRegister.
  ///
  /// In es, this message translates to:
  /// **'¿No tienes cuenta? Regístrate'**
  String get loginToRegister;

  /// No description provided for @loginToSignIn.
  ///
  /// In es, this message translates to:
  /// **'¿Ya tienes cuenta? Entra'**
  String get loginToSignIn;

  /// No description provided for @loginForgot.
  ///
  /// In es, this message translates to:
  /// **'He olvidado mi contraseña'**
  String get loginForgot;

  /// No description provided for @loginResetSent.
  ///
  /// In es, this message translates to:
  /// **'Te hemos enviado un correo para restablecerla'**
  String get loginResetSent;

  /// No description provided for @authErrorInvalidCredential.
  ///
  /// In es, this message translates to:
  /// **'Email o contraseña incorrectos'**
  String get authErrorInvalidCredential;

  /// No description provided for @authErrorEmailInUse.
  ///
  /// In es, this message translates to:
  /// **'Ya existe una cuenta con ese email'**
  String get authErrorEmailInUse;

  /// No description provided for @authErrorWeakPassword.
  ///
  /// In es, this message translates to:
  /// **'La contraseña es demasiado corta'**
  String get authErrorWeakPassword;

  /// No description provided for @authErrorNetwork.
  ///
  /// In es, this message translates to:
  /// **'Sin conexión. Inténtalo de nuevo.'**
  String get authErrorNetwork;

  /// No description provided for @authErrorUnknown.
  ///
  /// In es, this message translates to:
  /// **'Algo ha fallado. Inténtalo de nuevo.'**
  String get authErrorUnknown;

  /// No description provided for @signOut.
  ///
  /// In es, this message translates to:
  /// **'Cerrar sesión'**
  String get signOut;

  /// No description provided for @sessionsEmptyTitle.
  ///
  /// In es, this message translates to:
  /// **'Escanea tu primer ticket'**
  String get sessionsEmptyTitle;

  /// No description provided for @sessionsEmptyBody.
  ///
  /// In es, this message translates to:
  /// **'Haz una foto y reparte el gasto en segundos.'**
  String get sessionsEmptyBody;

  /// No description provided for @summaryOwedToMe.
  ///
  /// In es, this message translates to:
  /// **'Te deben'**
  String get summaryOwedToMe;

  /// No description provided for @summaryIOwe.
  ///
  /// In es, this message translates to:
  /// **'Debes'**
  String get summaryIOwe;

  /// No description provided for @statusClosed.
  ///
  /// In es, this message translates to:
  /// **'Cerrada'**
  String get statusClosed;

  /// No description provided for @statusArchived.
  ///
  /// In es, this message translates to:
  /// **'Archivada'**
  String get statusArchived;

  /// No description provided for @sessionPeople.
  ///
  /// In es, this message translates to:
  /// **'{count} personas'**
  String sessionPeople(int count);

  /// No description provided for @peopleSheetTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Quién estuvo?'**
  String get peopleSheetTitle;

  /// No description provided for @peopleAddHint.
  ///
  /// In es, this message translates to:
  /// **'Añadir persona…'**
  String get peopleAddHint;

  /// No description provided for @peopleYou.
  ///
  /// In es, this message translates to:
  /// **'Tú'**
  String get peopleYou;

  /// No description provided for @peopleNeedTwo.
  ///
  /// In es, this message translates to:
  /// **'Añade al menos otra persona'**
  String get peopleNeedTwo;

  /// No description provided for @splitEqual.
  ///
  /// In es, this message translates to:
  /// **'Todo a medias'**
  String get splitEqual;

  /// No description provided for @splitByItem.
  ///
  /// In es, this message translates to:
  /// **'Cada uno lo suyo'**
  String get splitByItem;

  /// No description provided for @payerQuestion.
  ///
  /// In es, this message translates to:
  /// **'¿Quién pagó?'**
  String get payerQuestion;

  /// No description provided for @sessionNameLabel.
  ///
  /// In es, this message translates to:
  /// **'Nombre de la cuenta'**
  String get sessionNameLabel;

  /// No description provided for @createAndShare.
  ///
  /// In es, this message translates to:
  /// **'Crear y compartir'**
  String get createAndShare;

  /// No description provided for @shareTitle.
  ///
  /// In es, this message translates to:
  /// **'Invita a los demás'**
  String get shareTitle;

  /// No description provided for @shareHint.
  ///
  /// In es, this message translates to:
  /// **'Quien tenga el enlace puede ver la cuenta, elegir lo suyo y marcar que ha pagado. Sin instalar nada.'**
  String get shareHint;

  /// No description provided for @shareCopy.
  ///
  /// In es, this message translates to:
  /// **'Copiar enlace'**
  String get shareCopy;

  /// No description provided for @shareCopied.
  ///
  /// In es, this message translates to:
  /// **'Enlace copiado'**
  String get shareCopied;

  /// No description provided for @shareSystem.
  ///
  /// In es, this message translates to:
  /// **'Compartir…'**
  String get shareSystem;

  /// No description provided for @detailTabSummary.
  ///
  /// In es, this message translates to:
  /// **'Resumen'**
  String get detailTabSummary;

  /// No description provided for @detailTabAccounts.
  ///
  /// In es, this message translates to:
  /// **'Cuentas'**
  String get detailTabAccounts;

  /// No description provided for @detailTabActivity.
  ///
  /// In es, this message translates to:
  /// **'Actividad'**
  String get detailTabActivity;

  /// No description provided for @balancesTitle.
  ///
  /// In es, this message translates to:
  /// **'Balance'**
  String get balancesTitle;

  /// No description provided for @balancePaidLabel.
  ///
  /// In es, this message translates to:
  /// **'pagó {amount}'**
  String balancePaidLabel(String amount);

  /// No description provided for @balanceConsumedLabel.
  ///
  /// In es, this message translates to:
  /// **'consumió {amount}'**
  String balanceConsumedLabel(String amount);

  /// No description provided for @settlementsTitle.
  ///
  /// In es, this message translates to:
  /// **'Pagos pendientes'**
  String get settlementsTitle;

  /// No description provided for @settlementRow.
  ///
  /// In es, this message translates to:
  /// **'{from} → {to}'**
  String settlementRow(String from, String to);

  /// No description provided for @statePending.
  ///
  /// In es, this message translates to:
  /// **'Pendiente'**
  String get statePending;

  /// No description provided for @stateMarked.
  ///
  /// In es, this message translates to:
  /// **'Dice que pagó'**
  String get stateMarked;

  /// No description provided for @stateConfirmed.
  ///
  /// In es, this message translates to:
  /// **'Confirmado'**
  String get stateConfirmed;

  /// No description provided for @actionConfirm.
  ///
  /// In es, this message translates to:
  /// **'Confirmar'**
  String get actionConfirm;

  /// No description provided for @actionBackToPending.
  ///
  /// In es, this message translates to:
  /// **'Volver a pendiente'**
  String get actionBackToPending;

  /// No description provided for @allSettled.
  ///
  /// In es, this message translates to:
  /// **'Todo saldado 🎉'**
  String get allSettled;

  /// No description provided for @activityEmpty.
  ///
  /// In es, this message translates to:
  /// **'Sin actividad todavía'**
  String get activityEmpty;

  /// No description provided for @accountsEmpty.
  ///
  /// In es, this message translates to:
  /// **'Sin cuentas todavía'**
  String get accountsEmpty;

  /// No description provided for @menuShare.
  ///
  /// In es, this message translates to:
  /// **'Compartir'**
  String get menuShare;

  /// No description provided for @menuClose.
  ///
  /// In es, this message translates to:
  /// **'Cerrar la cuenta'**
  String get menuClose;

  /// No description provided for @menuReopen.
  ///
  /// In es, this message translates to:
  /// **'Reabrir'**
  String get menuReopen;

  /// No description provided for @menuArchive.
  ///
  /// In es, this message translates to:
  /// **'Archivar'**
  String get menuArchive;

  /// No description provided for @menuDelete.
  ///
  /// In es, this message translates to:
  /// **'Eliminar'**
  String get menuDelete;

  /// No description provided for @closeConfirmBody.
  ///
  /// In es, this message translates to:
  /// **'Nadie podrá modificarla hasta que la reabras. ¿Cerrar?'**
  String get closeConfirmBody;

  /// No description provided for @deleteConfirmBody.
  ///
  /// In es, this message translates to:
  /// **'Se borrará todo: tickets, fotos y pagos. Esta acción no se puede deshacer.'**
  String get deleteConfirmBody;

  /// No description provided for @closedBanner.
  ///
  /// In es, this message translates to:
  /// **'Cuenta cerrada: solo lectura'**
  String get closedBanner;

  /// No description provided for @draftResumeTitle.
  ///
  /// In es, this message translates to:
  /// **'Tienes un ticket sin terminar'**
  String get draftResumeTitle;

  /// No description provided for @draftResume.
  ///
  /// In es, this message translates to:
  /// **'Continuar'**
  String get draftResume;

  /// No description provided for @draftDiscard.
  ///
  /// In es, this message translates to:
  /// **'Descartar'**
  String get draftDiscard;

  /// No description provided for @settingsTitle.
  ///
  /// In es, this message translates to:
  /// **'Ajustes'**
  String get settingsTitle;

  /// No description provided for @settingsAppearance.
  ///
  /// In es, this message translates to:
  /// **'Apariencia'**
  String get settingsAppearance;

  /// No description provided for @themeSystem.
  ///
  /// In es, this message translates to:
  /// **'Sistema'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In es, this message translates to:
  /// **'Claro'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In es, this message translates to:
  /// **'Oscuro'**
  String get themeDark;

  /// No description provided for @settingsPayments.
  ///
  /// In es, this message translates to:
  /// **'Métodos de pago'**
  String get settingsPayments;

  /// No description provided for @settingsPaymentsHint.
  ///
  /// In es, this message translates to:
  /// **'Aparecen como botones de pago para tus invitados. Deja en blanco los que no uses.'**
  String get settingsPaymentsHint;

  /// No description provided for @paymentBizum.
  ///
  /// In es, this message translates to:
  /// **'Bizum (teléfono)'**
  String get paymentBizum;

  /// No description provided for @paymentPaypal.
  ///
  /// In es, this message translates to:
  /// **'PayPal (enlace paypal.me)'**
  String get paymentPaypal;

  /// No description provided for @paymentRevolut.
  ///
  /// In es, this message translates to:
  /// **'Revolut (revtag)'**
  String get paymentRevolut;

  /// No description provided for @paymentIban.
  ///
  /// In es, this message translates to:
  /// **'IBAN'**
  String get paymentIban;

  /// No description provided for @paymentsSaved.
  ///
  /// In es, this message translates to:
  /// **'Métodos de pago guardados'**
  String get paymentsSaved;

  /// No description provided for @settingsPeople.
  ///
  /// In es, this message translates to:
  /// **'Personas frecuentes'**
  String get settingsPeople;

  /// No description provided for @settingsPeopleEmpty.
  ///
  /// In es, this message translates to:
  /// **'Aparecerán aquí las personas con las que compartas cuentas.'**
  String get settingsPeopleEmpty;

  /// No description provided for @settingsBackup.
  ///
  /// In es, this message translates to:
  /// **'Copia de seguridad'**
  String get settingsBackup;

  /// No description provided for @backupExport.
  ///
  /// In es, this message translates to:
  /// **'Exportar todos los datos (JSON)'**
  String get backupExport;

  /// No description provided for @backupImport.
  ///
  /// In es, this message translates to:
  /// **'Importar copia'**
  String get backupImport;

  /// No description provided for @settingsAccount.
  ///
  /// In es, this message translates to:
  /// **'Cuenta'**
  String get settingsAccount;

  /// No description provided for @menuAddTicket.
  ///
  /// In es, this message translates to:
  /// **'Añadir ticket'**
  String get menuAddTicket;

  /// No description provided for @menuExportPdf.
  ///
  /// In es, this message translates to:
  /// **'Exportar PDF'**
  String get menuExportPdf;

  /// No description provided for @menuShareImage.
  ///
  /// In es, this message translates to:
  /// **'Compartir resumen'**
  String get menuShareImage;

  /// No description provided for @backupImportSummary.
  ///
  /// In es, this message translates to:
  /// **'La copia contiene {sessions} cuentas, {tickets} tickets y {lines} productos. ¿Cómo quieres importarla?'**
  String backupImportSummary(int sessions, int tickets, int lines);

  /// No description provided for @backupModeMerge.
  ///
  /// In es, this message translates to:
  /// **'Añadir a lo que ya tengo'**
  String get backupModeMerge;

  /// No description provided for @backupModeReplace.
  ///
  /// In es, this message translates to:
  /// **'Restaurar (borra lo que no esté en la copia)'**
  String get backupModeReplace;

  /// No description provided for @backupImported.
  ///
  /// In es, this message translates to:
  /// **'Copia importada'**
  String get backupImported;

  /// No description provided for @backupInvalid.
  ///
  /// In es, this message translates to:
  /// **'El archivo no es una copia de seguridad válida'**
  String get backupInvalid;

  /// No description provided for @aiTitle.
  ///
  /// In es, this message translates to:
  /// **'Proveedores de IA'**
  String get aiTitle;

  /// No description provided for @aiHint.
  ///
  /// In es, this message translates to:
  /// **'La IA es el último recurso cuando el OCR falla, siempre bajo tu orden. Usas TU propia clave: se guarda cifrada solo en este dispositivo y el coste (céntimos) lo pagas a tu proveedor.'**
  String get aiHint;

  /// No description provided for @aiConfigured.
  ///
  /// In es, this message translates to:
  /// **'Configurado'**
  String get aiConfigured;

  /// No description provided for @aiPreferred.
  ///
  /// In es, this message translates to:
  /// **'Usar por defecto'**
  String get aiPreferred;

  /// No description provided for @aiKey.
  ///
  /// In es, this message translates to:
  /// **'API key'**
  String get aiKey;

  /// No description provided for @aiKeyOptional.
  ///
  /// In es, this message translates to:
  /// **'Opcional en servidores locales'**
  String get aiKeyOptional;

  /// No description provided for @aiBaseUrl.
  ///
  /// In es, this message translates to:
  /// **'Base URL'**
  String get aiBaseUrl;

  /// No description provided for @aiModel.
  ///
  /// In es, this message translates to:
  /// **'Modelo'**
  String get aiModel;

  /// No description provided for @aiTest.
  ///
  /// In es, this message translates to:
  /// **'Probar conexión'**
  String get aiTest;

  /// No description provided for @aiTestOk.
  ///
  /// In es, this message translates to:
  /// **'Conexión correcta ✓'**
  String get aiTestOk;

  /// No description provided for @aiErrInvalidKey.
  ///
  /// In es, this message translates to:
  /// **'Clave inválida o sin permisos'**
  String get aiErrInvalidKey;

  /// No description provided for @aiErrNoCredit.
  ///
  /// In es, this message translates to:
  /// **'Sin crédito en el proveedor'**
  String get aiErrNoCredit;

  /// No description provided for @aiErrRateLimited.
  ///
  /// In es, this message translates to:
  /// **'Límite de peticiones alcanzado; espera un momento'**
  String get aiErrRateLimited;

  /// No description provided for @aiErrModel.
  ///
  /// In es, this message translates to:
  /// **'Ese modelo no está disponible'**
  String get aiErrModel;

  /// No description provided for @aiErrNetwork.
  ///
  /// In es, this message translates to:
  /// **'No se pudo conectar. Revisa la red o la URL.'**
  String get aiErrNetwork;

  /// No description provided for @aiErrBadResponse.
  ///
  /// In es, this message translates to:
  /// **'La IA no devolvió un ticket válido'**
  String get aiErrBadResponse;

  /// No description provided for @aiAnalyzing.
  ///
  /// In es, this message translates to:
  /// **'Analizando con {provider}…'**
  String aiAnalyzing(String provider);

  /// No description provided for @scanManualEntry.
  ///
  /// In es, this message translates to:
  /// **'Gasto sin ticket'**
  String get scanManualEntry;

  /// No description provided for @manualTitle.
  ///
  /// In es, this message translates to:
  /// **'Gasto sin ticket'**
  String get manualTitle;

  /// No description provided for @manualConcept.
  ///
  /// In es, this message translates to:
  /// **'Concepto'**
  String get manualConcept;

  /// No description provided for @manualAmount.
  ///
  /// In es, this message translates to:
  /// **'Importe'**
  String get manualAmount;

  /// No description provided for @manualConceptHint.
  ///
  /// In es, this message translates to:
  /// **'Taxi, entradas, gasolina…'**
  String get manualConceptHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
