import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_am.dart';
import 'app_localizations_en.dart';
import 'app_localizations_om.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen_l10n/app_localizations.dart';
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
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('am'),
    Locale('en'),
    Locale('om')
  ];

  /// Application title shown in the app bar and OS launcher.
  ///
  /// In en, this message translates to:
  /// **'NIDAW'**
  String get appTitle;

  /// No description provided for @navRequest.
  ///
  /// In en, this message translates to:
  /// **'Request'**
  String get navRequest;

  /// No description provided for @navTracking.
  ///
  /// In en, this message translates to:
  /// **'Tracking'**
  String get navTracking;

  /// No description provided for @navHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get navHistory;

  /// No description provided for @navAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get navAccount;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get commonUnavailable;

  /// No description provided for @commonNotProvided.
  ///
  /// In en, this message translates to:
  /// **'Not provided'**
  String get commonNotProvided;

  /// No description provided for @commonLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get commonLoading;

  /// No description provided for @requestTitle.
  ///
  /// In en, this message translates to:
  /// **'Where are you going?'**
  String get requestTitle;

  /// No description provided for @requestPickupLabel.
  ///
  /// In en, this message translates to:
  /// **'Pickup'**
  String get requestPickupLabel;

  /// No description provided for @requestDropoffLabel.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get requestDropoffLabel;

  /// No description provided for @requestCurrentLocationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Current location (unavailable)'**
  String get requestCurrentLocationUnavailable;

  /// No description provided for @requestUseCurrentLocation.
  ///
  /// In en, this message translates to:
  /// **'Use current location'**
  String get requestUseCurrentLocation;

  /// No description provided for @requestSetPinOnMap.
  ///
  /// In en, this message translates to:
  /// **'Set pin on map'**
  String get requestSetPinOnMap;

  /// No description provided for @requestAddStop.
  ///
  /// In en, this message translates to:
  /// **'Add stop'**
  String get requestAddStop;

  /// No description provided for @requestScheduleToggle.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get requestScheduleToggle;

  /// No description provided for @requestPromoRow.
  ///
  /// In en, this message translates to:
  /// **'Promo code'**
  String get requestPromoRow;

  /// No description provided for @requestVoiceButton.
  ///
  /// In en, this message translates to:
  /// **'Book a ride with your voice'**
  String get requestVoiceButton;

  /// No description provided for @requestVoiceSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Speak your destination'**
  String get requestVoiceSheetTitle;

  /// No description provided for @requestVoiceListening.
  ///
  /// In en, this message translates to:
  /// **'Listening… say something like “take me to Bole Airport”'**
  String get requestVoiceListening;

  /// No description provided for @requestVoiceHeard.
  ///
  /// In en, this message translates to:
  /// **'I heard: {transcript}'**
  String requestVoiceHeard(String transcript);

  /// No description provided for @requestVoiceLowConfidence.
  ///
  /// In en, this message translates to:
  /// **'Not sure I caught that — search for “{transcript}” instead?'**
  String requestVoiceLowConfidence(String transcript);

  /// No description provided for @requestEstimateUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Price unavailable — retry'**
  String get requestEstimateUnavailable;

  /// No description provided for @requestConfirmCta.
  ///
  /// In en, this message translates to:
  /// **'Confirm ride'**
  String get requestConfirmCta;

  /// No description provided for @requestSelectRideType.
  ///
  /// In en, this message translates to:
  /// **'Choose a ride'**
  String get requestSelectRideType;

  /// Phase 2 dead-code reconnect: carousel retry strip shown when GET
  /// /rides/estimates fails after locations are set. Server detail is appended
  /// by the page, never used alone.
  ///
  /// In en, this message translates to:
  /// **'Prices unavailable — pull to refresh or tap Retry.'**
  String get requestOptionsPricesUnavailable;

  /// Phase 2 dead-code reconnect: carousel placeholder before both endpoints
  /// exist; honest 'unavailable', never a fabricated price.
  ///
  /// In en, this message translates to:
  /// **'Prices unavailable — set pickup and dropoff to load live fares.'**
  String get requestOptionsSetRouteFirst;

  /// No description provided for @trackingSearchingTitle.
  ///
  /// In en, this message translates to:
  /// **'Looking for drivers…'**
  String get trackingSearchingTitle;

  /// No description provided for @trackingSearchingSub.
  ///
  /// In en, this message translates to:
  /// **'Searching for {seconds} seconds'**
  String trackingSearchingSub(int seconds);

  /// No description provided for @trackingDriverEnRoute.
  ///
  /// In en, this message translates to:
  /// **'Your driver is on the way'**
  String get trackingDriverEnRoute;

  /// No description provided for @trackingRideInProgress.
  ///
  /// In en, this message translates to:
  /// **'You\'re on the move'**
  String get trackingRideInProgress;

  /// No description provided for @trackingArrived.
  ///
  /// In en, this message translates to:
  /// **'Driver has arrived at pickup'**
  String get trackingArrived;

  /// No description provided for @trackingWalkToPickupAr.
  ///
  /// In en, this message translates to:
  /// **'Walk to pickup (AR)'**
  String get trackingWalkToPickupAr;

  /// No description provided for @trackingCallDriver.
  ///
  /// In en, this message translates to:
  /// **'Call driver'**
  String get trackingCallDriver;

  /// No description provided for @trackingChatWithDriver.
  ///
  /// In en, this message translates to:
  /// **'Chat with driver'**
  String get trackingChatWithDriver;

  /// No description provided for @trackingCallingUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Calling unavailable — try chat'**
  String get trackingCallingUnavailable;

  /// No description provided for @trackingCancelRide.
  ///
  /// In en, this message translates to:
  /// **'Cancel ride'**
  String get trackingCancelRide;

  /// No description provided for @trackingVerifyDriver.
  ///
  /// In en, this message translates to:
  /// **'Verify your driver'**
  String get trackingVerifyDriver;

  /// No description provided for @trackingDriverNoSelfie.
  ///
  /// In en, this message translates to:
  /// **'Driver did not send a selfie'**
  String get trackingDriverNoSelfie;

  /// No description provided for @trackingContactDriverPrompt.
  ///
  /// In en, this message translates to:
  /// **'Contact your driver to confirm they\'re coming.'**
  String get trackingContactDriverPrompt;

  /// No description provided for @trackingChangeDestination.
  ///
  /// In en, this message translates to:
  /// **'Change destination'**
  String get trackingChangeDestination;

  /// No description provided for @trackingSplitFare.
  ///
  /// In en, this message translates to:
  /// **'Split fare'**
  String get trackingSplitFare;

  /// No description provided for @trackingCashBadge.
  ///
  /// In en, this message translates to:
  /// **'Cash ride'**
  String get trackingCashBadge;

  /// No description provided for @trackingSosButton.
  ///
  /// In en, this message translates to:
  /// **'Emergency SOS'**
  String get trackingSosButton;

  /// No description provided for @trackingNoDriversTitle.
  ///
  /// In en, this message translates to:
  /// **'No drivers found nearby'**
  String get trackingNoDriversTitle;

  /// No description provided for @trackingNoDriversBody.
  ///
  /// In en, this message translates to:
  /// **'We searched for {seconds} seconds without a match. Offer a higher fare to re-broadcast your request?'**
  String trackingNoDriversBody(int seconds);

  /// No description provided for @trackingPriceExtensionKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep searching at current price'**
  String get trackingPriceExtensionKeep;

  /// Price-extension sheet body when current fare is known
  ///
  /// In en, this message translates to:
  /// **'We could not find drivers for {fare}. Offer a higher fare to re-broadcast your request.'**
  String trackingNoDriversFound(String fare);

  /// Price-extension sheet body when the bloc never learned a real fare
  ///
  /// In en, this message translates to:
  /// **'We could not find drivers for your request. Offer a higher fare to re-broadcast — the new price is confirmed by the server before it applies.'**
  String get trackingPriceFareUnavailable;

  /// Price-extension option: +10 percent
  ///
  /// In en, this message translates to:
  /// **'Increase fare by 10%'**
  String get trackingPriceExtensionPlus10;

  /// Price-extension option: +20 percent
  ///
  /// In en, this message translates to:
  /// **'Increase fare by 20%'**
  String get trackingPriceExtensionPlus20;

  /// No description provided for @trackingPriceFeeConfirmedOnRetry.
  ///
  /// In en, this message translates to:
  /// **'New price will be confirmed on retry'**
  String get trackingPriceFeeConfirmedOnRetry;

  /// No description provided for @ridecheckTitle.
  ///
  /// In en, this message translates to:
  /// **'Is everything OK?'**
  String get ridecheckTitle;

  /// No description provided for @ridecheckBodyStopped.
  ///
  /// In en, this message translates to:
  /// **'Your vehicle has been stopped for over 3 minutes away from the route.'**
  String get ridecheckBodyStopped;

  /// RideCheck prompt detail when deviation distance was measured
  ///
  /// In en, this message translates to:
  /// **'The vehicle is {meters} m off the expected route.'**
  String ridecheckBodyDeviationMeasured(int meters);

  /// RideCheck prompt detail when deviation distance could not be measured
  ///
  /// In en, this message translates to:
  /// **'The vehicle has moved noticeably off the expected route.'**
  String get ridecheckBodyDeviationUnmeasured;

  /// RideCheck prompt detail with ETA confidence percentage
  ///
  /// In en, this message translates to:
  /// **'The arrival estimate for this trip became unreliable (confidence {confidencePercent}%).'**
  String ridecheckBodyLowConfidence(int confidencePercent);

  /// RideCheck prompt detail when confidence value unavailable
  ///
  /// In en, this message translates to:
  /// **'The arrival estimate for this trip became unreliable.'**
  String get ridecheckBodyLowConfidenceUnmeasured;

  /// No description provided for @ridecheckImOK.
  ///
  /// In en, this message translates to:
  /// **'I\'m OK'**
  String get ridecheckImOK;

  /// No description provided for @ridecheckCallForHelp.
  ///
  /// In en, this message translates to:
  /// **'Call for help'**
  String get ridecheckCallForHelp;

  /// Semantics label for the AR walk-to-pickup button
  ///
  /// In en, this message translates to:
  /// **'Walk to pickup with augmented reality navigation'**
  String get accessibilityWalkAr;

  /// No description provided for @chatTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chatTitle;

  /// No description provided for @chatInputHint.
  ///
  /// In en, this message translates to:
  /// **'Type a message…'**
  String get chatInputHint;

  /// No description provided for @chatSendButton.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chatSendButton;

  /// No description provided for @chatEmptyState.
  ///
  /// In en, this message translates to:
  /// **'No messages yet. Use a quick reply below.'**
  String get chatEmptyState;

  /// No description provided for @chatSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Message failed to send.'**
  String get chatSendFailed;

  /// No description provided for @chatTranslationHiddenNote.
  ///
  /// In en, this message translates to:
  /// **'Translations are turned off for this ride.'**
  String get chatTranslationHiddenNote;

  /// No description provided for @cancelSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this ride?'**
  String get cancelSheetTitle;

  /// No description provided for @cancelSheetFeeLabel.
  ///
  /// In en, this message translates to:
  /// **'Cancellation fee'**
  String get cancelSheetFeeLabel;

  /// No description provided for @cancelSheetFeeFetching.
  ///
  /// In en, this message translates to:
  /// **'Checking the fee…'**
  String get cancelSheetFeeFetching;

  /// No description provided for @cancelSheetFeeUnknown.
  ///
  /// In en, this message translates to:
  /// **'Fee will be confirmed on cancel'**
  String get cancelSheetFeeUnknown;

  /// No description provided for @cancelSheetFreeWindow.
  ///
  /// In en, this message translates to:
  /// **'Free to cancel for {minutes} more min'**
  String cancelSheetFreeWindow(int minutes);

  /// No description provided for @cancelSheetConfirm.
  ///
  /// In en, this message translates to:
  /// **'Cancel ride'**
  String get cancelSheetConfirm;

  /// No description provided for @cancelSheetDismiss.
  ///
  /// In en, this message translates to:
  /// **'Keep ride'**
  String get cancelSheetDismiss;

  /// No description provided for @cancelSheetReasonPrompt.
  ///
  /// In en, this message translates to:
  /// **'Help us improve — why are you cancelling?'**
  String get cancelSheetReasonPrompt;

  /// No description provided for @cancelSheetFeeLoading.
  ///
  /// In en, this message translates to:
  /// **'Checking your cancellation fee…'**
  String get cancelSheetFeeLoading;

  /// No description provided for @cancelSheetNoFee.
  ///
  /// In en, this message translates to:
  /// **'No cancellation fee applies right now.'**
  String get cancelSheetNoFee;

  /// No description provided for @cancelSheetCostNow.
  ///
  /// In en, this message translates to:
  /// **'Cancelling now costs {currency} {amount}'**
  String cancelSheetCostNow(String currency, String amount);

  /// No description provided for @cancelSheetFreeWindowEnds.
  ///
  /// In en, this message translates to:
  /// **'Free window ends in {countdown}'**
  String cancelSheetFreeWindowEnds(String countdown);

  /// §4.3 extracted from cancel_ride_sheet.dart kRideCancellationReasons.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get cancelReasonOther;

  /// §4.3 extracted from cancel_ride_sheet.dart reason list.
  ///
  /// In en, this message translates to:
  /// **'GPS unavailable — drag the pickup pin to set your location manually'**
  String get requestGpsUnavailablePin;

  /// §4.3 extracted from cancel_ride_sheet.dart kRideCancellationReasons.
  ///
  /// In en, this message translates to:
  /// **'Wait time too long'**
  String get cancelReasonWaitTooLong;

  /// §4.3 extracted from cancel_ride_sheet.dart kRideCancellationReasons.
  ///
  /// In en, this message translates to:
  /// **'Driver is going the wrong way'**
  String get cancelReasonDriverWrongWay;

  /// §4.3 extracted from cancel_ride_sheet.dart kRideCancellationReasons.
  ///
  /// In en, this message translates to:
  /// **'I need to reschedule'**
  String get cancelReasonReschedule;

  /// §4.3 extracted from cancel_ride_sheet.dart kRideCancellationReasons.
  ///
  /// In en, this message translates to:
  /// **'Emergency'**
  String get cancelReasonEmergency;

  /// §4.3 extracted from cancel_ride_sheet.dart kRideCancellationReasons.
  ///
  /// In en, this message translates to:
  /// **'Pickup location is incorrect'**
  String get cancelReasonPickupIncorrect;

  /// No description provided for @cancelSheetTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Total if you cancel now'**
  String get cancelSheetTotalLabel;

  /// No description provided for @cancelSheetDismissSemantics.
  ///
  /// In en, this message translates to:
  /// **'Keep ride — closes this sheet and cancels nothing'**
  String get cancelSheetDismissSemantics;

  /// No description provided for @cancelSheetConfirmWithFee.
  ///
  /// In en, this message translates to:
  /// **'Cancel ({currency} {amount})'**
  String cancelSheetConfirmWithFee(String currency, String amount);

  /// No description provided for @cancelSheetSemanticsFeeSuffixUnknown.
  ///
  /// In en, this message translates to:
  /// **' — fee will be confirmed on cancel'**
  String get cancelSheetSemanticsFeeSuffixUnknown;

  /// No description provided for @cancelSheetSemanticsFeeSuffixFree.
  ///
  /// In en, this message translates to:
  /// **' — free, inside the cancellation window'**
  String get cancelSheetSemanticsFeeSuffixFree;

  /// No description provided for @rateSheetSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit rating'**
  String get rateSheetSubmit;

  /// No description provided for @paymentAddCash.
  ///
  /// In en, this message translates to:
  /// **'Add cash option'**
  String get paymentAddCash;

  /// No description provided for @receiptTitle.
  ///
  /// In en, this message translates to:
  /// **'Receipt'**
  String get receiptTitle;

  /// No description provided for @receiptBase.
  ///
  /// In en, this message translates to:
  /// **'Base fare'**
  String get receiptBase;

  /// No description provided for @receiptDistance.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get receiptDistance;

  /// No description provided for @receiptTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get receiptTime;

  /// No description provided for @receiptSurge.
  ///
  /// In en, this message translates to:
  /// **'Surge'**
  String get receiptSurge;

  /// No description provided for @receiptTolls.
  ///
  /// In en, this message translates to:
  /// **'Tolls'**
  String get receiptTolls;

  /// No description provided for @receiptServiceFee.
  ///
  /// In en, this message translates to:
  /// **'Service fee'**
  String get receiptServiceFee;

  /// No description provided for @receiptPromoDiscount.
  ///
  /// In en, this message translates to:
  /// **'Promo discount'**
  String get receiptPromoDiscount;

  /// No description provided for @receiptTip.
  ///
  /// In en, this message translates to:
  /// **'Tip'**
  String get receiptTip;

  /// No description provided for @receiptTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get receiptTotal;

  /// No description provided for @receiptDownloadPdf.
  ///
  /// In en, this message translates to:
  /// **'Download PDF'**
  String get receiptDownloadPdf;

  /// No description provided for @receiptEmailReceipt.
  ///
  /// In en, this message translates to:
  /// **'Email receipt'**
  String get receiptEmailReceipt;

  /// No description provided for @receiptCashPending.
  ///
  /// In en, this message translates to:
  /// **'Awaiting driver cash confirmation'**
  String get receiptCashPending;

  /// No description provided for @receiptCashCollected.
  ///
  /// In en, this message translates to:
  /// **'Cash collected by driver'**
  String get receiptCashCollected;

  /// No description provided for @mapHealthBanner.
  ///
  /// In en, this message translates to:
  /// **'Map tiles unavailable — showing cached or fallback tiles.'**
  String get mapHealthBanner;

  /// No description provided for @mapHealthRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry tiles'**
  String get mapHealthRetry;

  /// No description provided for @locationGateDeniedTitle.
  ///
  /// In en, this message translates to:
  /// **'Location permission needed'**
  String get locationGateDeniedTitle;

  /// No description provided for @locationGateDeniedBody.
  ///
  /// In en, this message translates to:
  /// **'Nidus uses your location to drop the pickup pin. You can still type an address manually.'**
  String get locationGateDeniedBody;

  /// No description provided for @locationGateAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get locationGateAllow;

  /// No description provided for @locationGateOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get locationGateOpenSettings;

  /// No description provided for @locationGateServiceDisabledTitle.
  ///
  /// In en, this message translates to:
  /// **'Location services are off'**
  String get locationGateServiceDisabledTitle;

  /// No description provided for @locationGateTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on Location'**
  String get locationGateTurnOn;

  /// No description provided for @geocodeNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches — try a landmark or street name.'**
  String get geocodeNoMatches;

  /// No description provided for @geocodeDegraded.
  ///
  /// In en, this message translates to:
  /// **'Search unavailable — showing cached results'**
  String get geocodeDegraded;

  /// No description provided for @geocodeResolving.
  ///
  /// In en, this message translates to:
  /// **'Resolving address…'**
  String get geocodeResolving;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @notificationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.'**
  String get notificationsEmpty;

  /// No description provided for @notificationsMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get notificationsMarkAllRead;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsLanguageSection.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageSection;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsLanguageAmharic.
  ///
  /// In en, this message translates to:
  /// **'አማርኛ (Amharic)'**
  String get settingsLanguageAmharic;

  /// No description provided for @settingsLanguageOromo.
  ///
  /// In en, this message translates to:
  /// **'Afaan Oromoo (Oromo)'**
  String get settingsLanguageOromo;

  /// No description provided for @arNavTitle.
  ///
  /// In en, this message translates to:
  /// **'AR Walk Guidance'**
  String get arNavTitle;

  /// No description provided for @arNavUnsupported.
  ///
  /// In en, this message translates to:
  /// **'AR isn\'t available on this device — showing the 2D map instead.'**
  String get arNavUnsupported;

  /// No description provided for @arNavMapView.
  ///
  /// In en, this message translates to:
  /// **'Map View'**
  String get arNavMapView;

  /// No description provided for @arNavArView.
  ///
  /// In en, this message translates to:
  /// **'AR View'**
  String get arNavArView;

  /// No description provided for @arNavDistanceAhead.
  ///
  /// In en, this message translates to:
  /// **'{meters} m ahead'**
  String arNavDistanceAhead(int meters);

  /// No description provided for @accessibilityRecenterFab.
  ///
  /// In en, this message translates to:
  /// **'Recenter map on my location'**
  String get accessibilityRecenterFab;

  /// No description provided for @accessibilityPickupPin.
  ///
  /// In en, this message translates to:
  /// **'Pickup pin, drag to move'**
  String get accessibilityPickupPin;

  /// No description provided for @accessibilityDriverMarker.
  ///
  /// In en, this message translates to:
  /// **'Driver position'**
  String get accessibilityDriverMarker;

  /// No description provided for @accessibilityUnreadBadge.
  ///
  /// In en, this message translates to:
  /// **'{count} unread notifications'**
  String accessibilityUnreadBadge(int count);

  /// App bar title of the ride history page (Phase 3 §4.3 extraction).
  ///
  /// In en, this message translates to:
  /// **'Ride History'**
  String get historyTitle;

  /// Empty-state label when the rider has no past or scheduled rides.
  ///
  /// In en, this message translates to:
  /// **'No rides yet'**
  String get historyEmpty;

  /// §4.3 extracted from payment_method_selector.dart empty state.
  ///
  /// In en, this message translates to:
  /// **'No saved methods yet. Add one below.'**
  String get paymentNoneSaved;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['am', 'en', 'om'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'am': return AppLocalizationsAm();
    case 'en': return AppLocalizationsEn();
    case 'om': return AppLocalizationsOm();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );

  /// Phase 1: headline of the persistent error banner shown while a ride is live on the tracking page (replaces silent pop()).
  ///
  /// In en, this message translates to:
  /// **Problem connecting — your trip is still active**
  String get trackingErrorLiveRideTitle;

  /// Phase 1: body of the live-ride error banner; reassures the rider the trip continues.
  ///
  /// In en, this message translates to:
  /// **We lost some ride information, but your ride has not been cancelled. You can stay on this screen or leave it.**
  String get trackingErrorLiveRideBody;

  /// Phase 1: headline when an error arrives but no live ride exists (e.g. failed cancellation).
  ///
  /// In en, this message translates to:
  /// **Something went wrong**
  String get trackingErrorGenericTitle;

  /// Phase 1: body for the non-live-ride banner variant (CANCEL_FAILED durable outcome).
  ///
  /// In en, this message translates to:
  /// **The last action did not complete. Check the details below before trying again.**
  String get trackingErrorGenericBody;

  /// Phase 1: primary action keeping the rider on the tracking screen.
  ///
  /// In en, this message translates to:
  /// **Stay**
  String get trackingErrorStay;

  /// Phase 1: explicit user-chosen exit from tracking (never automatic).
  ///
  /// In en, this message translates to:
  /// **Leave**
  String get trackingErrorLeave;

  /// Phase 1: re-dispatches LoadRide; only offered for errors this page can actually recover.
  ///
  /// In en, this message translates to:
  /// **Retry**
  String get trackingErrorRetry;

  /// Phase 1: acknowledges a durable outcome (e.g. cancel fee) without staying visible.
  ///
  /// In en, this message translates to:
  /// **Dismiss**
  String get trackingErrorDismiss;

  /// Phase 1: screen-reader live-region label for the live-ride banner variant.
  ///
  /// In en, this message translates to:
  /// **Error during your active ride. Your trip is continuing.**
  String get trackingErrorLiveRideA11y;

  /// Phase 1: screen-reader live-region label for the generic banner variant.
  ///
  /// In en, this message translates to:
  /// **Error details**
  String get trackingErrorDetailA11y;

  /// Phase 1: track text of the SOS slide-to-confirm control (safety surface — must be localized).
  ///
  /// In en, this message translates to:
  /// **Slide to confirm SOS**
  String get sosSlideLabel;

  /// Phase 1: TalkBack/VoiceOver label announcing both the drag gesture and the keyboard alternative.
  ///
  /// In en, this message translates to:
  /// **SOS confirmation slider. Drag fully right, or press Enter, to send an emergency alert.**
  String get sosSliderA11y;

  /// Phase 1: custom assistive action on the draggable thumb — direct activation path.
  ///
  /// In en, this message translates to:
  /// **Send emergency SOS now**
  String get sosActivateA11y;

  /// Phase 1: tooltip explaining the deliberate two-step SOS confirmation.
  ///
  /// In en, this message translates to:
  /// **Hold and slide all the way to the right to confirm an emergency alert**
  String get sosTooltip;

  /// Phase 1: Safety Toolkit tile title for the SOS action.
  ///
  /// In en, this message translates to:
  /// **Emergency SOS**
  String get sosTitle;

  /// Phase 1: Safety Toolkit SOS tile subtitle.
  ///
  /// In en, this message translates to:
  /// **Alert the emergency line at {number} with your live location**
  String sosTileSubtitle(String number);

  /// Phase 1: barrier label so screen readers announce the modal countdown overlay.
  ///
  /// In en, this message translates to:
  /// **Emergency SOS countdown**
  String get sosOverlayA11y;

  /// Phase 1: headline of the full-screen pre-alarm countdown overlay.
  ///
  /// In en, this message translates to:
  /// **Emergency SOS**
  String get sosOverlayTitle;

  /// Phase 1: countdown body text.
  ///
  /// In en, this message translates to:
  /// **Opening your phone dialer for emergency number {number} in {seconds} s…**
  String sosOverlayCountdownBody(String number, int seconds);

  /// Phase 1: shown once the countdown has elapsed / dialer hand-off state.
  ///
  /// In en, this message translates to:
  /// **If the dialer does not open, use the button below or call {number} directly.**
  String sosOverlayFallbackBody(String number);

  /// Phase 1: abort-SOS action on the countdown overlay.
  ///
  /// In en, this message translates to:
  /// **Cancel — I'm safe**
  String get sosOverlayCancel;

  /// Phase 1: immediate escalation button on the countdown overlay.
  ///
  /// In en, this message translates to:
  /// **Call emergency services now**
  String get sosOverlayCallNow;

  /// Phase 1: escalation button label after a failed dialer launch.
  ///
  /// In en, this message translates to:
  /// **Retry call {number}**
  String sosOverlayRetryCall(String number);

  /// Phase 1: shown after an SOS countdown is armed from RideCheck 'Call for help'. Localized (was hardcoded English).
  ///
  /// In en, this message translates to:
  /// **SOS countdown started. Hold to confirm or tap the shield to open the Safety Toolkit.**
  String get sosStartedCountdown;

  /// Phase 1: honest degradation when no GPS fix; we never send a locationless SOS. Localized (was hardcoded English).
  ///
  /// In en, this message translates to:
  /// **Location unavailable — cannot start SOS with your position.**
  String get sosLocationUnavailable;

  /// Phase 1: snackbar action label routing the rider to manual emergency flows.
  ///
  /// In en, this message translates to:
  /// **Open Safety Toolkit**
  String get openSafetyToolkit;

  /// Phase 1: snackbar when the app could not open the dialer.
  ///
  /// In en, this message translates to:
  /// **Call {number} directly from your phone.**
  String sosOverlayCallDirectly(String number);

  /// Phase 1: history filter chip — show every ride.
  ///
  /// In en, this message translates to:
  /// **All**
  String get historyFilterAll;

  /// Phase 1: history filter chip — completed rides.
  ///
  /// In en, this message translates to:
  /// **Completed**
  String get historyFilterCompleted;

  /// Phase 1: history filter chip — cancelled rides.
  ///
  /// In en, this message translates to:
  /// **Cancelled**
  String get historyFilterCancelled;

  /// Phase 1: history filter chip — rides currently running.
  ///
  /// In en, this message translates to:
  /// **In Progress**
  String get historyFilterInProgress;

  /// Phase 1: empty state when a filter hides everything; {filter} is the localized chip label.
  ///
  /// In en, this message translates to:
  /// **No {filter} rides yet**
  String historyEmptyFiltered(String filter);

  /// Phase 1: secondary line under the unfiltered empty state.
  ///
  /// In en, this message translates to:
  /// **Your ride history will appear here.**
  String get historyEmptyBody;

  /// Phase 1: secondary line under the filtered empty state.
  ///
  /// In en, this message translates to:
  /// **Try another filter to see more of your ride history.**
  String get historyEmptyFilteredBody;

  /// Phase 1: resets the history list to all rides.
  ///
  /// In en, this message translates to:
  /// **Clear filter**
  String get historyClearFilter;

  /// Phase 1: CTA on the empty history state.
  ///
  /// In en, this message translates to:
  /// **Request a Ride**
  String get historyRequestRide;

  /// Phase 1: localized headline replacing raw 'Error loading rides'; the server message is demoted to a detail line.
  ///
  /// In en, this message translates to:
  /// **Couldn't load your rides**
  String get historyErrorPrimary;

  /// Phase 1: re-runs the history request.
  ///
  /// In en, this message translates to:
  /// **Retry**
  String get historyRetry;

  /// Phase 3 localization sweep: highlight badge on the selected ride-option card in the carousel.
  ///
  /// In en, this message translates to:
  /// **CHOSEN**
  String get requestOptionChosenBadge;

  /// Phase 3 localization sweep: ETA line on a ride-option card.
  ///
  /// In en, this message translates to:
  /// **{minutes, plural, =0{Arriving now} other{{minutes} min away}}**
  String requestOptionEtaMinutes(int minutes);

  /// Phase 3 localization sweep: honest degradation when the server omits an ETA; never a fabricated time.
  ///
  /// In en, this message translates to:
  /// **ETA unavailable**
  String get requestOptionEtaUnavailable;

  /// Phase 3 localization sweep: capacity line on a ride-option card.
  ///
  /// In en, this message translates to:
  /// **{count, plural, =1{1 seat} other{{count} seats}}**
  String requestOptionSeats(int count);

  /// Phase 3 localization sweep: honest degradation when the server omits capacity.
  ///
  /// In en, this message translates to:
  /// **Capacity not provided**
  String get requestOptionCapacityUnknown;

  /// Phase 3 localization sweep: availability flag on a ride-option card.
  ///
  /// In en, this message translates to:
  /// **Unavailable**
  String get requestOptionUnavailable;

  /// Phase 3 localization sweep: tooltip/semantics for the call action on the tracking driver card.
  ///
  /// In en, this message translates to:
  /// **Call driver using masked number**
  String get driverCallTooltip;

  /// Phase 3 localization sweep: tooltip/semantics for the chat action on the tracking driver card.
  ///
  /// In en, this message translates to:
  /// **Chat with driver**
  String get driverChatTooltip;

  /// Phase 3 localization sweep: unit label under the ETA badge on the tracking driver card.
  ///
  /// In en, this message translates to:
  /// **min**
  String get driverEtaMinutesUnit;

  /// Phase 1 safety localization: headline of the rider-side pre-selfie verification card (available state).
  ///
  /// In en, this message translates to:
  /// **Verify your driver**
  String get verifySelfieTitle;

  /// Phase 1 safety localization: body copy for the available-state verification card.
  ///
  /// In en, this message translates to:
  /// **{driverName} sent a selfie before picking you up. Tap to compare it with their profile photo.**
  String verifySelfieSubtitle(String driverName);

  /// Phase 1 safety localization: honest title when the driver skipped the pre-selfie; never blames our stack.
  ///
  /// In en, this message translates to:
  /// **Driver did not send a selfie**
  String get verifySelfieNotSentTitle;

  /// Phase 1 safety localization: guidance shown alongside the not-sent state.
  ///
  /// In en, this message translates to:
  /// **Spot your driver by plate and vehicle. You can still message or call them before entering.**
  String get verifySelfieNotSentSubtitle;

  /// Phase 1 safety localization: action opening chat/call from the not-sent verification state.
  ///
  /// In en, this message translates to:
  /// **Contact driver**
  String get verifyContactDriver;

  /// Phase 1 safety localization: title when the signed redeem link aged out.
  ///
  /// In en, this message translates to:
  /// **Selfie link expired**
  String get verifySelfieExpiredTitle;

  /// Phase 1 safety localization: explanation for the expired-link state.
  ///
  /// In en, this message translates to:
  /// **Signed links last 15 minutes. Ask your driver to resend, or refresh the ride.**
  String get verifySelfieExpiredSubtitle;

  /// Phase 1 safety localization: re-poll action on the expired verification state.
  ///
  /// In en, this message translates to:
  /// **Refresh**
  String get verifyRefresh;

  /// Phase 1 safety localization: title when OUR stack or the feature flag failed — explicitly not blamed on the driver.
  ///
  /// In en, this message translates to:
  /// **Verification unavailable**
  String get verifyUnavailableTitle;

  /// Phase 1 safety localization: unknown wire value folded into honest-unavailable; never rendered as success.
  ///
  /// In en, this message translates to:
  /// **The verification service returned an unexpected state. This is our side, not the driver — retry below.**
  String get verifyUnavailableUnknownSubtitle;

  /// Phase 1 safety localization: body copy for the unavailable verification state.
  ///
  /// In en, this message translates to:
  /// **Driver photo verification is not available for this ride right now. Spot your driver by plate and vehicle.**
  String get verifyUnavailableSubtitle;

  /// Phase 1 safety localization: re-check action on the unavailable verification state.
  ///
  /// In en, this message translates to:
  /// **Retry**
  String get verifyRetry;

  /// Phase 1 safety localization: snackbar when the redeem link ages out mid-fetch.
  ///
  /// In en, this message translates to:
  /// **The selfie link expired before it could load. Pull a fresh ride state to get a new signed link.**
  String get verifySheetLinkExpired;

  /// Phase 1 safety localization: snackbar for storage failure on our side; keeps truth that the driver complied.
  ///
  /// In en, this message translates to:
  /// **Verification is temporarily unavailable on our side. The driver did send a selfie — try again in a moment.**
  String get verifySheetStorageUnavailable;

  /// Phase 1 safety localization: snackbar for fetch failures. 'status' is the caller-built suffix like ' HTTP 503' or empty; keep the parenthesis pattern.
  ///
  /// In en, this message translates to:
  /// **Could not load the selfie (network error{status}). Tap to retry.**
  String verifySheetNetworkError(String status);

  /// Phase 1 safety localization: defensive snackbar for unmapped failures; must not show a fake image.
  ///
  /// In en, this message translates to:
  /// **Could not load the selfie. Tap to retry.**
  String get verifySheetGenericError;

  /// Phase 1 safety localization: app bar of the full-screen selfie comparison view.
  ///
  /// In en, this message translates to:
  /// **Verify {firstName}**
  String verifyComparisonAppBarTitle(String firstName);

  /// Phase 1 safety localization: left panel label in the comparison view.
  ///
  /// In en, this message translates to:
  /// **Profile photo (on file)**
  String get verifyPanelProfileLabel;

  /// Phase 1 safety localization: honest note instead of a placeholder avatar pretending to be the registered photo.
  ///
  /// In en, this message translates to:
  /// **No profile photo is on file for this driver, so there is nothing to compare against yet.**
  String get verifyPanelProfileMissing;

  /// Phase 1 safety localization: right panel label in the comparison view.
  ///
  /// In en, this message translates to:
  /// **Just-sent selfie**
  String get verifyPanelSelfieLabel;

  /// Phase 1 safety localization: honest degradation when fetched bytes are corrupt; distinguishes corrupt from absent.
  ///
  /// In en, this message translates to:
  /// **Image failed to decode — the bytes were corrupt, not absent. Retry from the ride screen.**
  String get verifyPanelDecodeError;

  /// Phase 1 safety localization: privacy/expiry footnote under the comparison panels.
  ///
  /// In en, this message translates to:
  /// **Selfie captured for this pickup only · valid until {expiry}**
  String verifyExpiryNote(String expiry);

  /// Phase 1 safety localization: negative verdict button in the comparison view.
  ///
  /// In en, this message translates to:
  /// **That's not them**
  String get verifyButtonNotThem;

  /// Phase 1 safety localization: positive verdict button in the comparison view.
  ///
  /// In en, this message translates to:
  /// **Looks right**
  String get verifyButtonLooksRight;
}
