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
