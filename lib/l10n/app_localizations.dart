import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_id.dart';
import 'app_localizations_tr.dart';
import 'app_localizations_ur.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
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

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
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
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
    Locale('fr'),
    Locale('hi'),
    Locale('id'),
    Locale('tr'),
    Locale('ur')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Namaz Near Me'**
  String get appName;

  /// No description provided for @update.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// No description provided for @addMosque.
  ///
  /// In en, this message translates to:
  /// **'Add mosque'**
  String get addMosque;

  /// No description provided for @namazTimes.
  ///
  /// In en, this message translates to:
  /// **'Namaz Times'**
  String get namazTimes;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @fajr.
  ///
  /// In en, this message translates to:
  /// **'Fajr'**
  String get fajr;

  /// No description provided for @zohar.
  ///
  /// In en, this message translates to:
  /// **'Zohar'**
  String get zohar;

  /// No description provided for @asr.
  ///
  /// In en, this message translates to:
  /// **'Asr'**
  String get asr;

  /// No description provided for @maghrib.
  ///
  /// In en, this message translates to:
  /// **'Maghrib'**
  String get maghrib;

  /// No description provided for @isha.
  ///
  /// In en, this message translates to:
  /// **'Isha'**
  String get isha;

  /// No description provided for @juma.
  ///
  /// In en, this message translates to:
  /// **'Juma'**
  String get juma;

  /// No description provided for @eid.
  ///
  /// In en, this message translates to:
  /// **'Eid'**
  String get eid;

  /// No description provided for @navigate.
  ///
  /// In en, this message translates to:
  /// **'Navigate'**
  String get navigate;

  /// No description provided for @suggestEdit.
  ///
  /// In en, this message translates to:
  /// **'Suggest edit'**
  String get suggestEdit;

  /// No description provided for @contributorSignup.
  ///
  /// In en, this message translates to:
  /// **'Contributor signup'**
  String get contributorSignup;

  /// No description provided for @updateTimings.
  ///
  /// In en, this message translates to:
  /// **'Update timings or add a new mosque'**
  String get updateTimings;

  /// No description provided for @verifyMobile.
  ///
  /// In en, this message translates to:
  /// **'Verify your mobile number, then update timings directly.'**
  String get verifyMobile;

  /// No description provided for @yourName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get yourName;

  /// No description provided for @mobileNumber.
  ///
  /// In en, this message translates to:
  /// **'Mobile number'**
  String get mobileNumber;

  /// No description provided for @sendOtp.
  ///
  /// In en, this message translates to:
  /// **'Send OTP'**
  String get sendOtp;

  /// No description provided for @resendOtp.
  ///
  /// In en, this message translates to:
  /// **'Resend OTP'**
  String get resendOtp;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// No description provided for @otpCode.
  ///
  /// In en, this message translates to:
  /// **'OTP code'**
  String get otpCode;

  /// No description provided for @mobileVerified.
  ///
  /// In en, this message translates to:
  /// **'Mobile verified'**
  String get mobileVerified;

  /// No description provided for @otpVerification.
  ///
  /// In en, this message translates to:
  /// **'OTP verification'**
  String get otpVerification;

  /// No description provided for @role.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get role;

  /// No description provided for @volunteer.
  ///
  /// In en, this message translates to:
  /// **'Volunteer'**
  String get volunteer;

  /// No description provided for @muazzin.
  ///
  /// In en, this message translates to:
  /// **'Muazzin'**
  String get muazzin;

  /// No description provided for @imam.
  ///
  /// In en, this message translates to:
  /// **'Imam'**
  String get imam;

  /// No description provided for @city.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get city;

  /// No description provided for @area.
  ///
  /// In en, this message translates to:
  /// **'Area'**
  String get area;

  /// No description provided for @maslak.
  ///
  /// In en, this message translates to:
  /// **'Maslak / Prayer Method'**
  String get maslak;

  /// No description provided for @existing.
  ///
  /// In en, this message translates to:
  /// **'Existing'**
  String get existing;

  /// No description provided for @newMosque.
  ///
  /// In en, this message translates to:
  /// **'New mosque'**
  String get newMosque;

  /// No description provided for @selectMosque.
  ///
  /// In en, this message translates to:
  /// **'Select mosque'**
  String get selectMosque;

  /// No description provided for @newMosqueName.
  ///
  /// In en, this message translates to:
  /// **'New mosque name'**
  String get newMosqueName;

  /// No description provided for @addressLandmark.
  ///
  /// In en, this message translates to:
  /// **'Address / landmark'**
  String get addressLandmark;

  /// No description provided for @namazTimings.
  ///
  /// In en, this message translates to:
  /// **'Namaz timings'**
  String get namazTimings;

  /// No description provided for @tapToSet.
  ///
  /// In en, this message translates to:
  /// **'Tap to set'**
  String get tapToSet;

  /// No description provided for @submitUpdate.
  ///
  /// In en, this message translates to:
  /// **'Submit update'**
  String get submitUpdate;

  /// No description provided for @submitting.
  ///
  /// In en, this message translates to:
  /// **'Submitting...'**
  String get submitting;

  /// No description provided for @noMasjidFound.
  ///
  /// In en, this message translates to:
  /// **'No masjid found in this radius.'**
  String get noMasjidFound;

  /// No description provided for @findingLocation.
  ///
  /// In en, this message translates to:
  /// **'Finding your location...'**
  String get findingLocation;

  /// No description provided for @nearestMasjids.
  ///
  /// In en, this message translates to:
  /// **'Nearest masjids from your location'**
  String get nearestMasjids;

  /// No description provided for @masjidList.
  ///
  /// In en, this message translates to:
  /// **'masjid list'**
  String get masjidList;

  /// No description provided for @refreshLocation.
  ///
  /// In en, this message translates to:
  /// **'Refresh location'**
  String get refreshLocation;

  /// No description provided for @timingPending.
  ///
  /// In en, this message translates to:
  /// **'Timing pending'**
  String get timingPending;

  /// No description provided for @namazTimingPending.
  ///
  /// In en, this message translates to:
  /// **'Namaz timing pending'**
  String get namazTimingPending;

  /// No description provided for @autoCalculated.
  ///
  /// In en, this message translates to:
  /// **'Auto-calculated daily.'**
  String get autoCalculated;

  /// No description provided for @initiated.
  ///
  /// In en, this message translates to:
  /// **'Initiated by Food4U / FOODOMATIC Moradabad.'**
  String get initiated;

  /// No description provided for @searchCity.
  ///
  /// In en, this message translates to:
  /// **'Search city or state...'**
  String get searchCity;

  /// No description provided for @eidUlFitr.
  ///
  /// In en, this message translates to:
  /// **'Eid ul Fitr'**
  String get eidUlFitr;

  /// No description provided for @eidUlAzha.
  ///
  /// In en, this message translates to:
  /// **'Eid ul Azha'**
  String get eidUlAzha;

  /// No description provided for @eidTimings.
  ///
  /// In en, this message translates to:
  /// **'Eid Namaz timings'**
  String get eidTimings;

  /// No description provided for @eidTimingsNote.
  ///
  /// In en, this message translates to:
  /// **'Eid timings are annual — update once a year.'**
  String get eidTimingsNote;

  /// No description provided for @suggestAnEdit.
  ///
  /// In en, this message translates to:
  /// **'Suggest an edit'**
  String get suggestAnEdit;

  /// No description provided for @whatToEdit.
  ///
  /// In en, this message translates to:
  /// **'What do you want to edit?'**
  String get whatToEdit;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @correctMosqueName.
  ///
  /// In en, this message translates to:
  /// **'Correct mosque name'**
  String get correctMosqueName;

  /// No description provided for @correctAddress.
  ///
  /// In en, this message translates to:
  /// **'Correct address'**
  String get correctAddress;

  /// No description provided for @yourMobileNumber.
  ///
  /// In en, this message translates to:
  /// **'Your mobile number'**
  String get yourMobileNumber;

  /// No description provided for @submitEdit.
  ///
  /// In en, this message translates to:
  /// **'Submit edit'**
  String get submitEdit;

  /// No description provided for @editSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Edit submitted. Applied after 2 verifications.'**
  String get editSubmitted;

  /// No description provided for @verifyFirst.
  ///
  /// In en, this message translates to:
  /// **'Verify mobile number first.'**
  String get verifyFirst;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @timingSource.
  ///
  /// In en, this message translates to:
  /// **'Timing source'**
  String get timingSource;

  /// No description provided for @liveUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Live updates unavailable. Showing bundled mosque data.'**
  String get liveUnavailable;

  /// No description provided for @inWord.
  ///
  /// In en, this message translates to:
  /// **'in'**
  String get inWord;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
        'ar',
        'en',
        'fr',
        'hi',
        'id',
        'tr',
        'ur'
      ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
    case 'hi':
      return AppLocalizationsHi();
    case 'id':
      return AppLocalizationsId();
    case 'tr':
      return AppLocalizationsTr();
    case 'ur':
      return AppLocalizationsUr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
