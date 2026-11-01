import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'NIDAW';

  @override
  String get navRequest => 'Request';

  @override
  String get navTracking => 'Tracking';

  @override
  String get navHistory => 'History';

  @override
  String get navAccount => 'Account';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonClose => 'Close';

  @override
  String get commonSave => 'Save';

  @override
  String get commonBack => 'Back';

  @override
  String get commonUnavailable => 'Unavailable';

  @override
  String get commonNotProvided => 'Not provided';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get requestTitle => 'Where are you going?';

  @override
  String get requestPickupLabel => 'Pickup';

  @override
  String get requestDropoffLabel => 'Destination';

  @override
  String get requestCurrentLocationUnavailable => 'Current location (unavailable)';

  @override
  String get requestUseCurrentLocation => 'Use current location';

  @override
  String get requestSetPinOnMap => 'Set pin on map';

  @override
  String get requestAddStop => 'Add stop';

  @override
  String get requestScheduleToggle => 'Schedule';

  @override
  String get requestPromoRow => 'Promo code';

  @override
  String get requestVoiceButton => 'Book a ride with your voice';

  @override
  String get requestVoiceSheetTitle => 'Speak your destination';

  @override
  String get requestVoiceListening => 'Listening… say something like “take me to Bole Airport”';

  @override
  String requestVoiceHeard(String transcript) {
    return 'I heard: $transcript';
  }

  @override
  String requestVoiceLowConfidence(String transcript) {
    return 'Not sure I caught that — search for “$transcript” instead?';
  }

  @override
  String get requestEstimateUnavailable => 'Price unavailable — retry';

  @override
  String get requestConfirmCta => 'Confirm ride';

  @override
  String get requestSelectRideType => 'Choose a ride';

  @override
  String get requestOptionsPricesUnavailable =>
      'Prices unavailable — pull to refresh or tap Retry.';

  @override
  String get requestOptionsSetRouteFirst =>
      'Prices unavailable — set pickup and dropoff to load live fares.';

  @override
  String get trackingSearchingTitle => 'Looking for drivers…';

  @override
  String trackingSearchingSub(int seconds) {
    return 'Searching for $seconds seconds';
  }

  @override
  String get trackingDriverEnRoute => 'Your driver is on the way';

  @override
  String get trackingRideInProgress => 'You\'re on the move';

  @override
  String get trackingArrived => 'Driver has arrived at pickup';

  @override
  String get trackingWalkToPickupAr => 'Walk to pickup (AR)';

  @override
  String get trackingCallDriver => 'Call driver';

  @override
  String get trackingChatWithDriver => 'Chat with driver';

  @override
  String get trackingCallingUnavailable => 'Calling unavailable — try chat';

  @override
  String get trackingCancelRide => 'Cancel ride';

  @override
  String get trackingVerifyDriver => 'Verify your driver';

  @override
  String get trackingDriverNoSelfie => 'Driver did not send a selfie';

  @override
  String get trackingContactDriverPrompt => 'Contact your driver to confirm they\'re coming.';

  @override
  String get trackingChangeDestination => 'Change destination';

  @override
  String get trackingSplitFare => 'Split fare';

  @override
  String get trackingCashBadge => 'Cash ride';

  @override
  String get trackingSosButton => 'Emergency SOS';

  @override
  String get trackingNoDriversTitle => 'No drivers found nearby';

  @override
  String trackingNoDriversBody(int seconds) {
    return 'We searched for $seconds seconds without a match. Offer a higher fare to re-broadcast your request?';
  }

  @override
  String get trackingPriceExtensionKeep => 'Keep searching at current price';

  @override
  String trackingNoDriversFound(String fare) {
    return 'We could not find drivers for $fare. Offer a higher fare to re-broadcast your request.';
  }

  @override
  String get trackingPriceFareUnavailable => 'We could not find drivers for your request. Offer a higher fare to re-broadcast — the new price is confirmed by the server before it applies.';

  @override
  String get trackingPriceExtensionPlus10 => 'Increase fare by 10%';

  @override
  String get trackingPriceExtensionPlus20 => 'Increase fare by 20%';

  @override
  String get trackingPriceFeeConfirmedOnRetry => 'New price will be confirmed on retry';

  @override
  String get ridecheckTitle => 'Is everything OK?';

  @override
  String get ridecheckBodyStopped => 'Your vehicle has been stopped for over 3 minutes away from the route.';

  @override
  String ridecheckBodyDeviationMeasured(int meters) {
    return 'The vehicle is $meters m off the expected route.';
  }

  @override
  String get ridecheckBodyDeviationUnmeasured => 'The vehicle has moved noticeably off the expected route.';

  @override
  String ridecheckBodyLowConfidence(int confidencePercent) {
    return 'The arrival estimate for this trip became unreliable (confidence $confidencePercent%).';
  }

  @override
  String get ridecheckBodyLowConfidenceUnmeasured => 'The arrival estimate for this trip became unreliable.';

  @override
  String get ridecheckImOK => 'I\'m OK';

  @override
  String get ridecheckCallForHelp => 'Call for help';

  @override
  String get accessibilityWalkAr => 'Walk to pickup with augmented reality navigation';

  @override
  String get chatTitle => 'Chat';

  @override
  String get chatInputHint => 'Type a message…';

  @override
  String get chatSendButton => 'Send';

  @override
  String get chatEmptyState => 'No messages yet. Use a quick reply below.';

  @override
  String get chatSendFailed => 'Message failed to send.';

  @override
  String get chatTranslationHiddenNote => 'Translations are turned off for this ride.';

  @override
  String get cancelSheetTitle => 'Cancel this ride?';

  @override
  String get cancelSheetFeeLabel => 'Cancellation fee';

  @override
  String get cancelSheetFeeFetching => 'Checking the fee…';

  @override
  String get cancelSheetFeeUnknown => 'Fee will be confirmed on cancel';

  @override
  String cancelSheetFreeWindow(int minutes) {
    return 'Free to cancel for $minutes more min';
  }

  @override
  String get cancelSheetConfirm => 'Cancel ride';

  @override
  String get cancelSheetDismiss => 'Keep ride';

  @override
  String get cancelSheetReasonPrompt => 'Help us improve — why are you cancelling?';

  @override
  String get cancelSheetFeeLoading => 'Checking your cancellation fee…';

  @override
  String get cancelSheetNoFee => 'No cancellation fee applies right now.';

  @override
  String cancelSheetCostNow(String currency, String amount) {
    return 'Cancelling now costs $currency $amount';
  }

  @override
  String cancelSheetFreeWindowEnds(String countdown) {
    return 'Free window ends in $countdown';
  }

  @override
  String get cancelReasonOther => 'Other';

  @override
  String get requestGpsUnavailablePin => 'GPS unavailable — drag the pickup pin to set your location manually';

  @override
  String get cancelReasonWaitTooLong => 'Wait time too long';

  @override
  String get cancelReasonDriverWrongWay => 'Driver is going the wrong way';

  @override
  String get cancelReasonReschedule => 'I need to reschedule';

  @override
  String get cancelReasonEmergency => 'Emergency';

  @override
  String get cancelReasonPickupIncorrect => 'Pickup location is incorrect';

  @override
  String get cancelSheetTotalLabel => 'Total if you cancel now';

  @override
  String get cancelSheetDismissSemantics => 'Keep ride — closes this sheet and cancels nothing';

  @override
  String cancelSheetConfirmWithFee(String currency, String amount) {
    return 'Cancel ($currency $amount)';
  }

  @override
  String get cancelSheetSemanticsFeeSuffixUnknown => ' — fee will be confirmed on cancel';

  @override
  String get cancelSheetSemanticsFeeSuffixFree => ' — free, inside the cancellation window';

  @override
  String get rateSheetSubmit => 'Submit rating';

  @override
  String get paymentAddCash => 'Add cash option';

  @override
  String get receiptTitle => 'Receipt';

  @override
  String get receiptBase => 'Base fare';

  @override
  String get receiptDistance => 'Distance';

  @override
  String get receiptTime => 'Time';

  @override
  String get receiptSurge => 'Surge';

  @override
  String get receiptTolls => 'Tolls';

  @override
  String get receiptServiceFee => 'Service fee';

  @override
  String get receiptPromoDiscount => 'Promo discount';

  @override
  String get receiptTip => 'Tip';

  @override
  String get receiptTotal => 'Total';

  @override
  String get receiptDownloadPdf => 'Download PDF';

  @override
  String get receiptEmailReceipt => 'Email receipt';

  @override
  String get receiptCashPending => 'Awaiting driver cash confirmation';

  @override
  String get receiptCashCollected => 'Cash collected by driver';

  @override
  String get mapHealthBanner => 'Map tiles unavailable — showing cached or fallback tiles.';

  @override
  String get mapHealthRetry => 'Retry tiles';

  @override
  String get locationGateDeniedTitle => 'Location permission needed';

  @override
  String get locationGateDeniedBody => 'Nidus uses your location to drop the pickup pin. You can still type an address manually.';

  @override
  String get locationGateAllow => 'Allow';

  @override
  String get locationGateOpenSettings => 'Open Settings';

  @override
  String get locationGateServiceDisabledTitle => 'Location services are off';

  @override
  String get locationGateTurnOn => 'Turn on Location';

  @override
  String get geocodeNoMatches => 'No matches — try a landmark or street name.';

  @override
  String get geocodeDegraded => 'Search unavailable — showing cached results';

  @override
  String get geocodeResolving => 'Resolving address…';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsEmpty => 'Nothing here yet.';

  @override
  String get notificationsMarkAllRead => 'Mark all read';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLanguageSection => 'Language';

  @override
  String get settingsLanguageSystem => 'System default';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageAmharic => 'አማርኛ (Amharic)';

  @override
  String get settingsLanguageOromo => 'Afaan Oromoo (Oromo)';

  @override
  String get arNavTitle => 'AR Walk Guidance';

  @override
  String get arNavUnsupported => 'AR isn\'t available on this device — showing the 2D map instead.';

  @override
  String get arNavMapView => 'Map View';

  @override
  String get arNavArView => 'AR View';

  @override
  String arNavDistanceAhead(int meters) {
    return '$meters m ahead';
  }

  @override
  String get accessibilityRecenterFab => 'Recenter map on my location';

  @override
  String get accessibilityPickupPin => 'Pickup pin, drag to move';

  @override
  String get accessibilityDriverMarker => 'Driver position';

  @override
  String accessibilityUnreadBadge(int count) {
    return '$count unread notifications';
  }

  @override
  String get historyTitle => 'Ride History';

  @override
  String get historyEmpty => 'No rides yet';

  @override
  String get paymentNoneSaved => 'No saved methods yet. Add one below.';
}
