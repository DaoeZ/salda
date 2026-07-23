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

  /// No description provided for @commonDelete.
  ///
  /// In es, this message translates to:
  /// **'Eliminar'**
  String get commonDelete;

  /// No description provided for @loginTitle.
  ///
  /// In es, this message translates to:
  /// **'Divide gastos sin discusiones'**
  String get loginTitle;

  /// No description provided for @loginWelcome.
  ///
  /// In es, this message translates to:
  /// **'Qué bueno verte de nuevo'**
  String get loginWelcome;

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

  /// No description provided for @registerTitle.
  ///
  /// In es, this message translates to:
  /// **'Crea tu cuenta'**
  String get registerTitle;

  /// No description provided for @registerSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Guarda tus cuentas y accede a ellas desde cualquier dispositivo.'**
  String get registerSubtitle;

  /// No description provided for @authNewPassword.
  ///
  /// In es, this message translates to:
  /// **'Nueva contraseña'**
  String get authNewPassword;

  /// No description provided for @authConfirmPassword.
  ///
  /// In es, this message translates to:
  /// **'Repite la contraseña'**
  String get authConfirmPassword;

  /// No description provided for @authPasswordHint.
  ///
  /// In es, this message translates to:
  /// **'Mínimo 8 caracteres'**
  String get authPasswordHint;

  /// No description provided for @authShowPassword.
  ///
  /// In es, this message translates to:
  /// **'Mostrar contraseña'**
  String get authShowPassword;

  /// No description provided for @authHidePassword.
  ///
  /// In es, this message translates to:
  /// **'Ocultar contraseña'**
  String get authHidePassword;

  /// No description provided for @authOr.
  ///
  /// In es, this message translates to:
  /// **'o'**
  String get authOr;

  /// No description provided for @authContinueGoogle.
  ///
  /// In es, this message translates to:
  /// **'Continuar con Google'**
  String get authContinueGoogle;

  /// No description provided for @authContinueGuest.
  ///
  /// In es, this message translates to:
  /// **'Continuar como invitado'**
  String get authContinueGuest;

  /// No description provided for @authProtectGuestTitle.
  ///
  /// In es, this message translates to:
  /// **'Protege tus cuentas'**
  String get authProtectGuestTitle;

  /// No description provided for @authProtectGuestBody.
  ///
  /// In es, this message translates to:
  /// **'Convierte tu acceso de invitado sin perder ninguna sesión.'**
  String get authProtectGuestBody;

  /// No description provided for @authProtectGuestAction.
  ///
  /// In es, this message translates to:
  /// **'Crear cuenta y conservar datos'**
  String get authProtectGuestAction;

  /// No description provided for @authProtectGuestGoogle.
  ///
  /// In es, this message translates to:
  /// **'Vincular con Google'**
  String get authProtectGuestGoogle;

  /// No description provided for @authUseAnotherAccount.
  ///
  /// In es, this message translates to:
  /// **'Usar otra cuenta'**
  String get authUseAnotherAccount;

  /// No description provided for @authValidationEmailRequired.
  ///
  /// In es, this message translates to:
  /// **'Escribe tu email'**
  String get authValidationEmailRequired;

  /// No description provided for @authValidationEmailInvalid.
  ///
  /// In es, this message translates to:
  /// **'Introduce un email válido'**
  String get authValidationEmailInvalid;

  /// No description provided for @authValidationPasswordRequired.
  ///
  /// In es, this message translates to:
  /// **'Escribe tu contraseña'**
  String get authValidationPasswordRequired;

  /// No description provided for @authValidationPasswordLength.
  ///
  /// In es, this message translates to:
  /// **'Usa al menos 8 caracteres'**
  String get authValidationPasswordLength;

  /// No description provided for @authValidationPasswordMismatch.
  ///
  /// In es, this message translates to:
  /// **'Las contraseñas no coinciden'**
  String get authValidationPasswordMismatch;

  /// No description provided for @authValidationName.
  ///
  /// In es, this message translates to:
  /// **'Escribe un nombre de al menos 2 caracteres'**
  String get authValidationName;

  /// No description provided for @resetTitle.
  ///
  /// In es, this message translates to:
  /// **'Recupera tu contraseña'**
  String get resetTitle;

  /// No description provided for @resetBody.
  ///
  /// In es, this message translates to:
  /// **'Te enviaremos el enlace oficial de Firebase para crear una nueva.'**
  String get resetBody;

  /// No description provided for @resetAction.
  ///
  /// In es, this message translates to:
  /// **'Enviar enlace'**
  String get resetAction;

  /// No description provided for @resetSentTitle.
  ///
  /// In es, this message translates to:
  /// **'Revisa tu correo'**
  String get resetSentTitle;

  /// No description provided for @resetSentBody.
  ///
  /// In es, this message translates to:
  /// **'Si existe una cuenta con ese email, recibirás un enlace para restablecer la contraseña.'**
  String get resetSentBody;

  /// No description provided for @resetBackToLogin.
  ///
  /// In es, this message translates to:
  /// **'Volver a iniciar sesión'**
  String get resetBackToLogin;

  /// No description provided for @resetTryAnother.
  ///
  /// In es, this message translates to:
  /// **'Probar otro email'**
  String get resetTryAnother;

  /// No description provided for @verifyTitle.
  ///
  /// In es, this message translates to:
  /// **'Verifica tu email'**
  String get verifyTitle;

  /// No description provided for @verifyBody.
  ///
  /// In es, this message translates to:
  /// **'Verifica {email} desde el enlace del correo. Si no lo tienes, puedes reenviarlo.'**
  String verifyBody(String email);

  /// No description provided for @verifyCheck.
  ///
  /// In es, this message translates to:
  /// **'Ya lo he verificado'**
  String get verifyCheck;

  /// No description provided for @verifyResend.
  ///
  /// In es, this message translates to:
  /// **'Reenviar correo'**
  String get verifyResend;

  /// No description provided for @verifyResendIn.
  ///
  /// In es, this message translates to:
  /// **'Podrás reenviarlo en {seconds} s'**
  String verifyResendIn(int seconds);

  /// No description provided for @verifyResent.
  ///
  /// In es, this message translates to:
  /// **'Correo de verificación enviado de nuevo.'**
  String get verifyResent;

  /// No description provided for @verifyNotYet.
  ///
  /// In es, this message translates to:
  /// **'Todavía no aparece como verificado. Abre el enlace del correo y vuelve a comprobar.'**
  String get verifyNotYet;

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

  /// No description provided for @authErrorTooManyRequests.
  ///
  /// In es, this message translates to:
  /// **'Demasiados intentos. Espera unos minutos y vuelve a probar.'**
  String get authErrorTooManyRequests;

  /// No description provided for @authErrorUserDisabled.
  ///
  /// In es, this message translates to:
  /// **'Esta cuenta está desactivada.'**
  String get authErrorUserDisabled;

  /// No description provided for @authErrorOperationNotAllowed.
  ///
  /// In es, this message translates to:
  /// **'Este método de acceso aún no está habilitado.'**
  String get authErrorOperationNotAllowed;

  /// No description provided for @authErrorCredentialAlreadyInUse.
  ///
  /// In es, this message translates to:
  /// **'Ese acceso ya pertenece a otra cuenta. Cierra esta sesión y entra con la cuenta existente; no hemos movido tus datos.'**
  String get authErrorCredentialAlreadyInUse;

  /// No description provided for @authErrorCancelled.
  ///
  /// In es, this message translates to:
  /// **'Has cancelado el acceso.'**
  String get authErrorCancelled;

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

  /// No description provided for @guestAccount.
  ///
  /// In es, this message translates to:
  /// **'Cuenta de invitado'**
  String get guestAccount;

  /// No description provided for @guestAccountBody.
  ///
  /// In es, this message translates to:
  /// **'Tus sesiones solo están vinculadas a este acceso.'**
  String get guestAccountBody;

  /// No description provided for @accountVerified.
  ///
  /// In es, this message translates to:
  /// **'Email verificado'**
  String get accountVerified;

  /// No description provided for @guestLeave.
  ///
  /// In es, this message translates to:
  /// **'Salir del modo invitado'**
  String get guestLeave;

  /// No description provided for @guestSignOutTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Salir sin proteger tus cuentas?'**
  String get guestSignOutTitle;

  /// No description provided for @guestSignOutBody.
  ///
  /// In es, this message translates to:
  /// **'No podrás recuperar las sesiones de este invitado después de salir. Crea una cuenta para conservarlas.'**
  String get guestSignOutBody;

  /// No description provided for @guestSignOutConfirm.
  ///
  /// In es, this message translates to:
  /// **'Salir de todos modos'**
  String get guestSignOutConfirm;

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

  /// No description provided for @currentStateTitle.
  ///
  /// In es, this message translates to:
  /// **'Estado actual'**
  String get currentStateTitle;

  /// No description provided for @economicHistoryTitle.
  ///
  /// In es, this message translates to:
  /// **'Histórico económico'**
  String get economicHistoryTitle;

  /// No description provided for @settledState.
  ///
  /// In es, this message translates to:
  /// **'Saldado'**
  String get settledState;

  /// No description provided for @currentToReceive.
  ///
  /// In es, this message translates to:
  /// **'Pendiente de cobrar'**
  String get currentToReceive;

  /// No description provided for @currentToPay.
  ///
  /// In es, this message translates to:
  /// **'Pendiente de pagar'**
  String get currentToPay;

  /// No description provided for @settlementRemaining.
  ///
  /// In es, this message translates to:
  /// **'Quedan {amount} por liquidar'**
  String settlementRemaining(String amount);

  /// No description provided for @settlementProgressSemantics.
  ///
  /// In es, this message translates to:
  /// **'Progreso de pagos confirmados'**
  String get settlementProgressSemantics;

  /// No description provided for @settlementProgressAmount.
  ///
  /// In es, this message translates to:
  /// **'{confirmed} de {required} confirmados'**
  String settlementProgressAmount(String confirmed, String required);

  /// No description provided for @settlementMarkedAmount.
  ///
  /// In es, this message translates to:
  /// **'{amount} marcado como pagado, pendiente de confirmación'**
  String settlementMarkedAmount(String amount);

  /// No description provided for @noSettlementsRequired.
  ///
  /// In es, this message translates to:
  /// **'No hacen falta transferencias'**
  String get noSettlementsRequired;

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
  /// **'Aquí aparecerá lo que vaya pasando: tickets, pagos, espacios y miembros.'**
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

  /// No description provided for @deleteInProgress.
  ///
  /// In es, this message translates to:
  /// **'Eliminando cuenta'**
  String get deleteInProgress;

  /// No description provided for @deleteError.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido eliminar la cuenta. Comprueba la conexión e inténtalo de nuevo.'**
  String get deleteError;

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

  /// No description provided for @ticketPaidBy.
  ///
  /// In es, this message translates to:
  /// **'Pagó {name}'**
  String ticketPaidBy(String name);

  /// No description provided for @ticketNoPhoto.
  ///
  /// In es, this message translates to:
  /// **'Este ticket no tiene foto guardada.'**
  String get ticketNoPhoto;

  /// No description provided for @ticketNoLines.
  ///
  /// In es, this message translates to:
  /// **'Sin desglose de productos (gasto manual).'**
  String get ticketNoLines;

  /// No description provided for @historyConfirmedTitle.
  ///
  /// In es, this message translates to:
  /// **'Pagos confirmados ({count})'**
  String historyConfirmedTitle(int count);

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

  /// No description provided for @ticketPickHint.
  ///
  /// In es, this message translates to:
  /// **'Marca cada unidad que consumiste. Una unidad marcada por varias personas se comparte; lo no reclamado corre a cargo de quien pagó.'**
  String get ticketPickHint;

  /// No description provided for @lineForAll.
  ///
  /// In es, this message translates to:
  /// **'Para todos'**
  String get lineForAll;

  /// No description provided for @lineSharedWith.
  ///
  /// In es, this message translates to:
  /// **'Compartido con {names}'**
  String lineSharedWith(String names);

  /// No description provided for @lineTakenBy.
  ///
  /// In es, this message translates to:
  /// **'Lo tiene {names}'**
  String lineTakenBy(String names);

  /// No description provided for @lineAddUnit.
  ///
  /// In es, this message translates to:
  /// **'Añadir una unidad'**
  String get lineAddUnit;

  /// No description provided for @lineRemoveUnit.
  ///
  /// In es, this message translates to:
  /// **'Quitar una unidad'**
  String get lineRemoveUnit;

  /// No description provided for @unitAssignment.
  ///
  /// In es, this message translates to:
  /// **'Unidad {number}: {names}'**
  String unitAssignment(int number, String names);

  /// No description provided for @unitResidual.
  ///
  /// In es, this message translates to:
  /// **'sin reclamar (para {payer})'**
  String unitResidual(String payer);

  /// No description provided for @unitCompactSummary.
  ///
  /// In es, this message translates to:
  /// **'{selected} de {total} tuyas · {residual} sin reclamar'**
  String unitCompactSummary(int selected, int total, int residual);

  /// No description provided for @unitsUpgradeTitle.
  ///
  /// In es, this message translates to:
  /// **'Actualizar el reparto por unidades'**
  String get unitsUpgradeTitle;

  /// No description provided for @unitsUpgradeBody.
  ///
  /// In es, this message translates to:
  /// **'Este producto usa el reparto anterior, que no identifica cada unidad. Al actualizarlo se borrarán sus selecciones actuales y podrás marcar cada unidad sin ambigüedad.'**
  String get unitsUpgradeBody;

  /// No description provided for @unitsUpgradeAction.
  ///
  /// In es, this message translates to:
  /// **'Repartir por unidades'**
  String get unitsUpgradeAction;

  /// No description provided for @settlementAwaitsReceiver.
  ///
  /// In es, this message translates to:
  /// **'Confirmará {name} al recibir el dinero'**
  String settlementAwaitsReceiver(String name);

  /// No description provided for @activityTitle.
  ///
  /// In es, this message translates to:
  /// **'Actividad'**
  String get activityTitle;

  /// No description provided for @activitySeeAll.
  ///
  /// In es, this message translates to:
  /// **'Ver toda'**
  String get activitySeeAll;

  /// No description provided for @activityLoadError.
  ///
  /// In es, this message translates to:
  /// **'No se pudo cargar la actividad. Comprueba la conexión.'**
  String get activityLoadError;

  /// No description provided for @activityRetry.
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get activityRetry;

  /// No description provided for @activityLoadMore.
  ///
  /// In es, this message translates to:
  /// **'Cargar más'**
  String get activityLoadMore;

  /// No description provided for @activityGone.
  ///
  /// In es, this message translates to:
  /// **'Ese elemento ya no está disponible.'**
  String get activityGone;

  /// No description provided for @activityActorFallback.
  ///
  /// In es, this message translates to:
  /// **'Alguien'**
  String get activityActorFallback;

  /// No description provided for @activityUnknown.
  ///
  /// In es, this message translates to:
  /// **'Actividad'**
  String get activityUnknown;

  /// No description provided for @activityNow.
  ///
  /// In es, this message translates to:
  /// **'ahora'**
  String get activityNow;

  /// No description provided for @activityMinutesAgo.
  ///
  /// In es, this message translates to:
  /// **'hace {n} min'**
  String activityMinutesAgo(int n);

  /// No description provided for @activityHoursAgo.
  ///
  /// In es, this message translates to:
  /// **'hace {n} h'**
  String activityHoursAgo(int n);

  /// No description provided for @activityDaysAgo.
  ///
  /// In es, this message translates to:
  /// **'hace {n} d'**
  String activityDaysAgo(int n);

  /// No description provided for @activitySpaceCreated.
  ///
  /// In es, this message translates to:
  /// **'Creó el espacio \"{space}\"'**
  String activitySpaceCreated(String space);

  /// No description provided for @activitySpaceRenamed.
  ///
  /// In es, this message translates to:
  /// **'Editó el espacio \"{space}\"'**
  String activitySpaceRenamed(String space);

  /// No description provided for @activitySpaceArchived.
  ///
  /// In es, this message translates to:
  /// **'Archivó el espacio \"{space}\"'**
  String activitySpaceArchived(String space);

  /// No description provided for @activitySpaceReactivated.
  ///
  /// In es, this message translates to:
  /// **'Reactivó el espacio \"{space}\"'**
  String activitySpaceReactivated(String space);

  /// No description provided for @activitySpaceTransferred.
  ///
  /// In es, this message translates to:
  /// **'Transfirió el espacio \"{space}\"'**
  String activitySpaceTransferred(String space);

  /// No description provided for @activityInviteSent.
  ///
  /// In es, this message translates to:
  /// **'Envió una invitación a \"{space}\"'**
  String activityInviteSent(String space);

  /// No description provided for @activityMemberJoined.
  ///
  /// In es, this message translates to:
  /// **'Se unió a \"{space}\"'**
  String activityMemberJoined(String space);

  /// No description provided for @activityMemberLeft.
  ///
  /// In es, this message translates to:
  /// **'Salió de \"{space}\"'**
  String activityMemberLeft(String space);

  /// No description provided for @activityMemberRemoved.
  ///
  /// In es, this message translates to:
  /// **'Eliminó a un miembro de \"{space}\"'**
  String activityMemberRemoved(String space);

  /// No description provided for @activityTicketCreated.
  ///
  /// In es, this message translates to:
  /// **'Añadió el ticket {ticket}'**
  String activityTicketCreated(String ticket);

  /// No description provided for @activityTicketUpdated.
  ///
  /// In es, this message translates to:
  /// **'Modificó el ticket {ticket}'**
  String activityTicketUpdated(String ticket);

  /// No description provided for @activityTicketLinked.
  ///
  /// In es, this message translates to:
  /// **'Vinculó {ticket} al espacio \"{space}\"'**
  String activityTicketLinked(String ticket, String space);

  /// No description provided for @activityTicketUnlinked.
  ///
  /// In es, this message translates to:
  /// **'Desvinculó el ticket {ticket}'**
  String activityTicketUnlinked(String ticket);

  /// No description provided for @activityTicketDeleted.
  ///
  /// In es, this message translates to:
  /// **'Eliminó el ticket {ticket}'**
  String activityTicketDeleted(String ticket);

  /// No description provided for @activityPaymentMarked.
  ///
  /// In es, this message translates to:
  /// **'Marcó un pago como enviado'**
  String get activityPaymentMarked;

  /// No description provided for @activityPaymentConfirmed.
  ///
  /// In es, this message translates to:
  /// **'Confirmó que recibió un pago'**
  String get activityPaymentConfirmed;

  /// No description provided for @activityPaymentCancelled.
  ///
  /// In es, this message translates to:
  /// **'Canceló un pago'**
  String get activityPaymentCancelled;

  /// No description provided for @spacesTitle.
  ///
  /// In es, this message translates to:
  /// **'Espacios'**
  String get spacesTitle;

  /// No description provided for @spacesCreate.
  ///
  /// In es, this message translates to:
  /// **'Crear espacio'**
  String get spacesCreate;

  /// No description provided for @spacesEmptyTitle.
  ///
  /// In es, this message translates to:
  /// **'Todavía no tienes espacios'**
  String get spacesEmptyTitle;

  /// No description provided for @spacesEmptyBody.
  ///
  /// In es, this message translates to:
  /// **'Un espacio agrupa los gastos de un viaje, un piso, una pareja o una peña. Crea uno e invita a tus amigos.'**
  String get spacesEmptyBody;

  /// No description provided for @spacesLoadError.
  ///
  /// In es, this message translates to:
  /// **'No se pudieron cargar los espacios. Comprueba la conexión.'**
  String get spacesLoadError;

  /// No description provided for @spacesArchivedSection.
  ///
  /// In es, this message translates to:
  /// **'Archivados ({count})'**
  String spacesArchivedSection(int count);

  /// No description provided for @spaceNameLabel.
  ///
  /// In es, this message translates to:
  /// **'Nombre del espacio'**
  String get spaceNameLabel;

  /// No description provided for @spaceNameHint.
  ///
  /// In es, this message translates to:
  /// **'Viaje a Lisboa, Piso, Peña…'**
  String get spaceNameHint;

  /// No description provided for @spaceEmojiLabel.
  ///
  /// In es, this message translates to:
  /// **'Emoji (opcional)'**
  String get spaceEmojiLabel;

  /// No description provided for @spaceOwnerBadge.
  ///
  /// In es, this message translates to:
  /// **'Propietario'**
  String get spaceOwnerBadge;

  /// No description provided for @spaceGone.
  ///
  /// In es, this message translates to:
  /// **'Ya no tienes acceso a este espacio.'**
  String get spaceGone;

  /// No description provided for @spaceMembersTitle.
  ///
  /// In es, this message translates to:
  /// **'Miembros'**
  String get spaceMembersTitle;

  /// No description provided for @spaceMembersCount.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 miembro} other{{count} miembros}}'**
  String spaceMembersCount(int count);

  /// No description provided for @spaceEditName.
  ///
  /// In es, this message translates to:
  /// **'Editar espacio'**
  String get spaceEditName;

  /// No description provided for @spaceArchive.
  ///
  /// In es, this message translates to:
  /// **'Archivar'**
  String get spaceArchive;

  /// No description provided for @spaceReactivate.
  ///
  /// In es, this message translates to:
  /// **'Reactivar'**
  String get spaceReactivate;

  /// No description provided for @spaceLeave.
  ///
  /// In es, this message translates to:
  /// **'Salir del espacio'**
  String get spaceLeave;

  /// No description provided for @spaceLeaveBody.
  ///
  /// In es, this message translates to:
  /// **'Dejarás de ver este espacio. Los tickets, pagos e historial no se tocan.'**
  String get spaceLeaveBody;

  /// No description provided for @spaceInviteAction.
  ///
  /// In es, this message translates to:
  /// **'Invitar'**
  String get spaceInviteAction;

  /// No description provided for @spaceInviteSheetTitle.
  ///
  /// In es, this message translates to:
  /// **'Invitar a un amigo'**
  String get spaceInviteSheetTitle;

  /// No description provided for @spaceInviteNoFriends.
  ///
  /// In es, this message translates to:
  /// **'Aún no tienes amigos en Salda. Añádelos desde Buscar personas.'**
  String get spaceInviteNoFriends;

  /// No description provided for @spaceAlreadyMember.
  ///
  /// In es, this message translates to:
  /// **'Ya es miembro'**
  String get spaceAlreadyMember;

  /// No description provided for @spaceAlreadyInvited.
  ///
  /// In es, this message translates to:
  /// **'Invitado'**
  String get spaceAlreadyInvited;

  /// No description provided for @spacePendingInvites.
  ///
  /// In es, this message translates to:
  /// **'Invitaciones pendientes'**
  String get spacePendingInvites;

  /// No description provided for @spaceInviteCancel.
  ///
  /// In es, this message translates to:
  /// **'Cancelar invitación'**
  String get spaceInviteCancel;

  /// No description provided for @spaceInviteText.
  ///
  /// In es, this message translates to:
  /// **'{name} te invita al espacio \"{space}\"'**
  String spaceInviteText(String name, String space);

  /// No description provided for @spaceInviteAccept.
  ///
  /// In es, this message translates to:
  /// **'Unirme'**
  String get spaceInviteAccept;

  /// No description provided for @spaceInviteReject.
  ///
  /// In es, this message translates to:
  /// **'Rechazar'**
  String get spaceInviteReject;

  /// No description provided for @spaceTransferTitle.
  ///
  /// In es, this message translates to:
  /// **'Transferir propiedad'**
  String get spaceTransferTitle;

  /// No description provided for @spaceTransferBody.
  ///
  /// In es, this message translates to:
  /// **'{name} pasará a ser quien administre este espacio. Tú seguirás como miembro.'**
  String spaceTransferBody(String name);

  /// No description provided for @spaceRemoveMemberTitle.
  ///
  /// In es, this message translates to:
  /// **'Eliminar del espacio'**
  String get spaceRemoveMemberTitle;

  /// No description provided for @spaceRemoveMemberBody.
  ///
  /// In es, this message translates to:
  /// **'{name} dejará de ver este espacio. Sus tickets, pagos e historial no se tocan.'**
  String spaceRemoveMemberBody(String name);

  /// No description provided for @spaceTicketsTitle.
  ///
  /// In es, this message translates to:
  /// **'Tickets del espacio'**
  String get spaceTicketsTitle;

  /// No description provided for @spaceTicketsEmpty.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay tickets vinculados. Crea uno desde aquí o vincula uno existente desde su detalle.'**
  String get spaceTicketsEmpty;

  /// No description provided for @spaceTicketUntitled.
  ///
  /// In es, this message translates to:
  /// **'Ticket'**
  String get spaceTicketUntitled;

  /// No description provided for @spaceAddTicket.
  ///
  /// In es, this message translates to:
  /// **'Añadir ticket'**
  String get spaceAddTicket;

  /// No description provided for @spaceActionError.
  ///
  /// In es, this message translates to:
  /// **'No se pudo completar la acción. Inténtalo de nuevo.'**
  String get spaceActionError;

  /// No description provided for @spaceLinkTooltip.
  ///
  /// In es, this message translates to:
  /// **'Espacio compartido'**
  String get spaceLinkTooltip;

  /// No description provided for @spaceLinkTo.
  ///
  /// In es, this message translates to:
  /// **'Vincular a {name}'**
  String spaceLinkTo(String name);

  /// No description provided for @spaceUnlink.
  ///
  /// In es, this message translates to:
  /// **'Desvincular del espacio'**
  String get spaceUnlink;

  /// No description provided for @spaceLinked.
  ///
  /// In es, this message translates to:
  /// **'Ticket vinculado al espacio'**
  String get spaceLinked;

  /// No description provided for @spaceUnlinked.
  ///
  /// In es, this message translates to:
  /// **'Ticket desvinculado'**
  String get spaceUnlinked;

  /// No description provided for @profileTitle.
  ///
  /// In es, this message translates to:
  /// **'Perfil público'**
  String get profileTitle;

  /// No description provided for @profileCreateTitle.
  ///
  /// In es, this message translates to:
  /// **'Crea tu perfil'**
  String get profileCreateTitle;

  /// No description provided for @profileCreateBody.
  ///
  /// In es, this message translates to:
  /// **'Tu nombre de usuario es único y te identifica: así podrán encontrarte tus amigos.'**
  String get profileCreateBody;

  /// No description provided for @profileCreateAction.
  ///
  /// In es, this message translates to:
  /// **'Crear perfil'**
  String get profileCreateAction;

  /// No description provided for @profileUsername.
  ///
  /// In es, this message translates to:
  /// **'Nombre de usuario'**
  String get profileUsername;

  /// No description provided for @profileUsernameHelp.
  ///
  /// In es, this message translates to:
  /// **'Único y en minúsculas: letras, números y _'**
  String get profileUsernameHelp;

  /// No description provided for @profileSaved.
  ///
  /// In es, this message translates to:
  /// **'Perfil guardado'**
  String get profileSaved;

  /// No description provided for @profileSaveError.
  ///
  /// In es, this message translates to:
  /// **'No se pudo guardar. Comprueba la conexión o prueba otro nombre de usuario.'**
  String get profileSaveError;

  /// No description provided for @profileBannerTitle.
  ///
  /// In es, this message translates to:
  /// **'Completa tu perfil público'**
  String get profileBannerTitle;

  /// No description provided for @profileBannerAction.
  ///
  /// In es, this message translates to:
  /// **'Crear perfil'**
  String get profileBannerAction;

  /// No description provided for @usernameChecking.
  ///
  /// In es, this message translates to:
  /// **'Comprobando disponibilidad…'**
  String get usernameChecking;

  /// No description provided for @usernameAvailable.
  ///
  /// In es, this message translates to:
  /// **'Disponible'**
  String get usernameAvailable;

  /// No description provided for @usernameTaken.
  ///
  /// In es, this message translates to:
  /// **'Ya está en uso'**
  String get usernameTaken;

  /// No description provided for @usernameErrorTooShort.
  ///
  /// In es, this message translates to:
  /// **'Mínimo 3 caracteres'**
  String get usernameErrorTooShort;

  /// No description provided for @usernameErrorTooLong.
  ///
  /// In es, this message translates to:
  /// **'Máximo 20 caracteres'**
  String get usernameErrorTooLong;

  /// No description provided for @usernameErrorInvalidChars.
  ///
  /// In es, this message translates to:
  /// **'Solo letras sin tildes, números y _'**
  String get usernameErrorInvalidChars;

  /// No description provided for @usernameErrorStartLetter.
  ///
  /// In es, this message translates to:
  /// **'Debe empezar por una letra'**
  String get usernameErrorStartLetter;

  /// No description provided for @usernameErrorUnderscores.
  ///
  /// In es, this message translates to:
  /// **'El _ no puede ir al final ni repetido'**
  String get usernameErrorUnderscores;

  /// No description provided for @usernameErrorReserved.
  ///
  /// In es, this message translates to:
  /// **'Ese nombre está reservado'**
  String get usernameErrorReserved;

  /// No description provided for @searchPeopleTitle.
  ///
  /// In es, this message translates to:
  /// **'Buscar personas'**
  String get searchPeopleTitle;

  /// No description provided for @searchPeopleHint.
  ///
  /// In es, this message translates to:
  /// **'Nombre o @usuario'**
  String get searchPeopleHint;

  /// No description provided for @searchPeopleStart.
  ///
  /// In es, this message translates to:
  /// **'Busca a otras personas por su nombre o su @usuario'**
  String get searchPeopleStart;

  /// No description provided for @searchPeopleEmpty.
  ///
  /// In es, this message translates to:
  /// **'Sin resultados'**
  String get searchPeopleEmpty;

  /// No description provided for @searchPeopleError.
  ///
  /// In es, this message translates to:
  /// **'No se pudo completar la búsqueda'**
  String get searchPeopleError;

  /// No description provided for @friendsTitle.
  ///
  /// In es, this message translates to:
  /// **'Amigos'**
  String get friendsTitle;

  /// No description provided for @friendsTabFriends.
  ///
  /// In es, this message translates to:
  /// **'Amigos'**
  String get friendsTabFriends;

  /// No description provided for @friendsTabReceived.
  ///
  /// In es, this message translates to:
  /// **'Recibidas'**
  String get friendsTabReceived;

  /// No description provided for @friendsTabSent.
  ///
  /// In es, this message translates to:
  /// **'Enviadas'**
  String get friendsTabSent;

  /// No description provided for @friendsEmpty.
  ///
  /// In es, this message translates to:
  /// **'Todavía no tienes amigos'**
  String get friendsEmpty;

  /// No description provided for @friendsEmptyBody.
  ///
  /// In es, this message translates to:
  /// **'Busca personas y envía tu primera solicitud'**
  String get friendsEmptyBody;

  /// No description provided for @friendRequestsReceivedEmpty.
  ///
  /// In es, this message translates to:
  /// **'No tienes solicitudes pendientes'**
  String get friendRequestsReceivedEmpty;

  /// No description provided for @friendRequestsSentEmpty.
  ///
  /// In es, this message translates to:
  /// **'No has enviado solicitudes'**
  String get friendRequestsSentEmpty;

  /// No description provided for @friendAdd.
  ///
  /// In es, this message translates to:
  /// **'Añadir amigo'**
  String get friendAdd;

  /// No description provided for @friendRequestSent.
  ///
  /// In es, this message translates to:
  /// **'Solicitud enviada'**
  String get friendRequestSent;

  /// No description provided for @friendAccept.
  ///
  /// In es, this message translates to:
  /// **'Aceptar'**
  String get friendAccept;

  /// No description provided for @friendReject.
  ///
  /// In es, this message translates to:
  /// **'Rechazar'**
  String get friendReject;

  /// No description provided for @friendCancelRequest.
  ///
  /// In es, this message translates to:
  /// **'Cancelar solicitud'**
  String get friendCancelRequest;

  /// No description provided for @friendFriendsStatus.
  ///
  /// In es, this message translates to:
  /// **'Amigos'**
  String get friendFriendsStatus;

  /// No description provided for @friendRemove.
  ///
  /// In es, this message translates to:
  /// **'Eliminar amistad'**
  String get friendRemove;

  /// No description provided for @friendRemoveTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Eliminar esta amistad?'**
  String get friendRemoveTitle;

  /// No description provided for @friendRemoveBody.
  ///
  /// In es, this message translates to:
  /// **'Solo se eliminará la relación social. Los tickets, balances y pagos no cambiarán.'**
  String get friendRemoveBody;

  /// No description provided for @friendActionError.
  ///
  /// In es, this message translates to:
  /// **'No se pudo actualizar la relación. Comprueba tu conexión e inténtalo de nuevo.'**
  String get friendActionError;

  /// No description provided for @friendErrorUnverified.
  ///
  /// In es, this message translates to:
  /// **'Verifica tu correo antes de usar las amistades.'**
  String get friendErrorUnverified;

  /// No description provided for @friendErrorProfileRequired.
  ///
  /// In es, this message translates to:
  /// **'Completa tu perfil antes de enviar solicitudes.'**
  String get friendErrorProfileRequired;

  /// No description provided for @friendErrorRequestExists.
  ///
  /// In es, this message translates to:
  /// **'Ya existe una solicitud de amistad entre estas cuentas.'**
  String get friendErrorRequestExists;

  /// No description provided for @friendErrorAlreadyFriends.
  ///
  /// In es, this message translates to:
  /// **'Estas cuentas ya son amigas.'**
  String get friendErrorAlreadyFriends;

  /// No description provided for @friendErrorPermissionDenied.
  ///
  /// In es, this message translates to:
  /// **'Firebase ha rechazado la operación. Actualiza la app o vuelve a iniciar sesión.'**
  String get friendErrorPermissionDenied;

  /// No description provided for @friendErrorServiceUnavailable.
  ///
  /// In es, this message translates to:
  /// **'El servicio de amistades no está disponible en este entorno.'**
  String get friendErrorServiceUnavailable;

  /// No description provided for @friendErrorNetwork.
  ///
  /// In es, this message translates to:
  /// **'No hay conexión con Firebase. Revisa tu red e inténtalo de nuevo.'**
  String get friendErrorNetwork;

  /// No description provided for @friendErrorUnexpected.
  ///
  /// In es, this message translates to:
  /// **'No se pudo actualizar la relación por un error inesperado.'**
  String get friendErrorUnexpected;

  /// No description provided for @friendProfileUnavailable.
  ///
  /// In es, this message translates to:
  /// **'Perfil no disponible'**
  String get friendProfileUnavailable;

  /// No description provided for @friendProfileRequired.
  ///
  /// In es, this message translates to:
  /// **'Completa tu perfil antes de usar las amistades'**
  String get friendProfileRequired;

  /// No description provided for @friendProfileRequiredAction.
  ///
  /// In es, this message translates to:
  /// **'Crear perfil'**
  String get friendProfileRequiredAction;

  /// No description provided for @friendEditOwnProfile.
  ///
  /// In es, this message translates to:
  /// **'Editar perfil'**
  String get friendEditOwnProfile;

  /// No description provided for @economyTitle.
  ///
  /// In es, this message translates to:
  /// **'Economía'**
  String get economyTitle;

  /// No description provided for @economySummaryTitle.
  ///
  /// In es, this message translates to:
  /// **'Tu balance'**
  String get economySummaryTitle;

  /// No description provided for @economyOwedToMe.
  ///
  /// In es, this message translates to:
  /// **'Te deben'**
  String get economyOwedToMe;

  /// No description provided for @economyIOwe.
  ///
  /// In es, this message translates to:
  /// **'Debes'**
  String get economyIOwe;

  /// No description provided for @economyNet.
  ///
  /// In es, this message translates to:
  /// **'Saldo neto'**
  String get economyNet;

  /// No description provided for @economyRelationsTitle.
  ///
  /// In es, this message translates to:
  /// **'Relaciones abiertas'**
  String get economyRelationsTitle;

  /// No description provided for @economyEmptyTitle.
  ///
  /// In es, this message translates to:
  /// **'No tienes saldos pendientes'**
  String get economyEmptyTitle;

  /// No description provided for @economyEmptyBody.
  ///
  /// In es, this message translates to:
  /// **'Cuando un ticket vincule dos cuentas registradas, aquí podrás ver y explicar cada importe.'**
  String get economyEmptyBody;

  /// No description provided for @economyLoadError.
  ///
  /// In es, this message translates to:
  /// **'No se pudo cargar tu balance. Revisa la conexión y vuelve a intentarlo.'**
  String get economyLoadError;

  /// No description provided for @economyYouOwe.
  ///
  /// In es, this message translates to:
  /// **'Debes a {name}'**
  String economyYouOwe(String name);

  /// No description provided for @economyOwesYou.
  ///
  /// In es, this message translates to:
  /// **'{name} te debe'**
  String economyOwesYou(String name);

  /// No description provided for @economySettledWith.
  ///
  /// In es, this message translates to:
  /// **'Sin saldo pendiente con {name}'**
  String economySettledWith(String name);

  /// No description provided for @economyDetailTitle.
  ///
  /// In es, this message translates to:
  /// **'Balance con {name}'**
  String economyDetailTitle(String name);

  /// No description provided for @economyOriginalDebt.
  ///
  /// In es, this message translates to:
  /// **'Deuda original'**
  String get economyOriginalDebt;

  /// No description provided for @economyTicketsTitle.
  ///
  /// In es, this message translates to:
  /// **'Tickets que explican el saldo'**
  String get economyTicketsTitle;

  /// No description provided for @economyPaymentsTitle.
  ///
  /// In es, this message translates to:
  /// **'Pagos y liquidaciones'**
  String get economyPaymentsTitle;

  /// No description provided for @economyOutsideSpace.
  ///
  /// In es, this message translates to:
  /// **'Fuera de espacios'**
  String get economyOutsideSpace;

  /// No description provided for @economyInSpace.
  ///
  /// In es, this message translates to:
  /// **'Espacio vinculado'**
  String get economyInSpace;

  /// No description provided for @economyMarkPaid.
  ///
  /// In es, this message translates to:
  /// **'Marcar como pagado'**
  String get economyMarkPaid;

  /// No description provided for @economyPaymentAmount.
  ///
  /// In es, this message translates to:
  /// **'Importe pagado'**
  String get economyPaymentAmount;

  /// No description provided for @economyPaymentPending.
  ///
  /// In es, this message translates to:
  /// **'Pendiente de confirmación'**
  String get economyPaymentPending;

  /// No description provided for @economyPaymentConfirmed.
  ///
  /// In es, this message translates to:
  /// **'Confirmado por el receptor'**
  String get economyPaymentConfirmed;

  /// No description provided for @economyPaymentCancelled.
  ///
  /// In es, this message translates to:
  /// **'Cancelado'**
  String get economyPaymentCancelled;

  /// No description provided for @economyConfirmPayment.
  ///
  /// In es, this message translates to:
  /// **'Confirmar recepción'**
  String get economyConfirmPayment;

  /// No description provided for @economyRejectPayment.
  ///
  /// In es, this message translates to:
  /// **'Rechazar'**
  String get economyRejectPayment;

  /// No description provided for @economyCancelPayment.
  ///
  /// In es, this message translates to:
  /// **'Cancelar aviso'**
  String get economyCancelPayment;

  /// No description provided for @economyPaymentSuccess.
  ///
  /// In es, this message translates to:
  /// **'Pago pendiente enviado al receptor.'**
  String get economyPaymentSuccess;

  /// No description provided for @economyPaymentErrorOver.
  ///
  /// In es, this message translates to:
  /// **'El importe supera el saldo pendiente o ya está reservado por otro pago.'**
  String get economyPaymentErrorOver;

  /// No description provided for @economyPaymentErrorPermission.
  ///
  /// In es, this message translates to:
  /// **'Solo el deudor crea el pago y solo el receptor puede confirmarlo.'**
  String get economyPaymentErrorPermission;

  /// No description provided for @economyPaymentErrorNetwork.
  ///
  /// In es, this message translates to:
  /// **'No se pudo contactar con el servicio de pagos.'**
  String get economyPaymentErrorNetwork;

  /// No description provided for @economyPaymentErrorUnexpected.
  ///
  /// In es, this message translates to:
  /// **'No se pudo actualizar el pago.'**
  String get economyPaymentErrorUnexpected;

  /// No description provided for @economyPendingConfirmations.
  ///
  /// In es, this message translates to:
  /// **'Pagos por confirmar'**
  String get economyPendingConfirmations;

  /// No description provided for @economyOpenDetail.
  ///
  /// In es, this message translates to:
  /// **'Ver desglose'**
  String get economyOpenDetail;

  /// No description provided for @spaceEconomicTitle.
  ///
  /// In es, this message translates to:
  /// **'Tu balance en este espacio'**
  String get spaceEconomicTitle;

  /// No description provided for @spaceEconomicEmpty.
  ///
  /// In es, this message translates to:
  /// **'Todavía no tienes movimientos económicos identificados en este espacio.'**
  String get spaceEconomicEmpty;

  /// No description provided for @commonRetry.
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get commonRetry;
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
