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

  @override
  String get trackingErrorLiveRideTitle => 'Problem connecting — your trip is still active';

  @override
  String get trackingErrorLiveRideBody => 'We lost some ride information, but your ride has not been cancelled. You can stay on this screen or leave it.';

  @override
  String get trackingErrorGenericTitle => 'Something went wrong';

  @override
  String get trackingErrorGenericBody => 'The last action did not complete. Check the details below before trying again.';

  @override
  String get trackingErrorStay => 'Stay';

  @override
  String get trackingErrorLeave => 'Leave';

  @override
  String get trackingErrorRetry => 'Retry';

  @override
  String get trackingErrorDismiss => 'Dismiss';

  @override
  String get trackingErrorLiveRideA11y => 'Error during your active ride. Your trip is continuing.';

  @override
  String get trackingErrorDetailA11y => 'Error details';

  @override
  String get sosSlideLabel => 'Slide to confirm SOS';

  @override
  String get sosSliderA11y => 'SOS confirmation slider. Drag fully right, or press Enter, to send an emergency alert.';

  @override
  String get sosActivateA11y => 'Send emergency SOS now';

  @override
  String get sosTooltip => 'Hold and slide all the way to the right to confirm an emergency alert';

  @override
  String get sosTitle => 'Emergency SOS';

  @override
  String sosTileSubtitle(String number) {
    return 'Alert the emergency line at \$number with your live location';
  }

  @override
  String get sosOverlayA11y => 'Emergency SOS countdown';

  @override
  String get sosOverlayTitle => 'Emergency SOS';

  @override
  String sosOverlayCountdownBody(String number, int seconds) {
    return 'Opening your phone dialer for emergency number \$number in \$seconds s…';
  }

  @override
  String sosOverlayFallbackBody(String number) {
    return 'If the dialer does not open, use the button below or call \$number directly.';
  }

  @override
  String get sosOverlayCancel => 'Cancel — I\'m safe';

  @override
  String get sosOverlayCallNow => 'Call emergency services now';

  @override
  String sosOverlayRetryCall(String number) {
    return 'Retry call \$number';
  }

  @override
  String get sosStartedCountdown => 'SOS countdown started. Hold to confirm or tap the shield to open the Safety Toolkit.';

  @override
  String get sosLocationUnavailable => 'Location unavailable — cannot start SOS with your position.';

  @override
  String get openSafetyToolkit => 'Open Safety Toolkit';

  @override
  String sosOverlayCallDirectly(String number) {
    return 'Call \$number directly from your phone.';
  }

  @override
  String get historyFilterAll => 'All';

  @override
  String get historyFilterCompleted => 'Completed';

  @override
  String get historyFilterCancelled => 'Cancelled';

  @override
  String get historyFilterInProgress => 'In Progress';

  @override
  String historyEmptyFiltered(String filter) {
    return 'No \$filter rides yet';
  }

  @override
  String get historyEmptyBody => 'Your ride history will appear here.';

  @override
  String get historyEmptyFilteredBody => 'Try another filter to see more of your ride history.';

  @override
  String get historyClearFilter => 'Clear filter';

  @override
  String get historyRequestRide => 'Request a Ride';

  @override
  String get historyErrorPrimary => 'Couldn\'t load your rides';

  @override
  String get historyRetry => 'Retry';

  @override
  String get requestOptionChosenBadge => 'CHOSEN';

  @override
  String requestOptionEtaMinutes(int minutes) {
    return (minutes == 0 ? 'Arriving now' : '\$minutes min away');
  }

  @override
  String get requestOptionEtaUnavailable => 'ETA unavailable';

  @override
  String requestOptionSeats(int count) {
    return (count == 1 ? '1 seat' : '\$count seats');
  }

  @override
  String get requestOptionCapacityUnknown => 'Capacity not provided';

  @override
  String get requestOptionUnavailable => 'Unavailable';

  @override
  String get driverCallTooltip => 'Call driver using masked number';

  @override
  String get driverChatTooltip => 'Chat with driver';

  @override
  String get driverEtaMinutesUnit => 'min';

  @override
  String get verifySelfieTitle => 'Verify your driver';

  @override
  String verifySelfieSubtitle(String driverName) {
    return '\$driverName sent a selfie before picking you up. Tap to compare it with their profile photo.';
  }

  @override
  String get verifySelfieNotSentTitle => 'Driver did not send a selfie';

  @override
  String get verifySelfieNotSentSubtitle => 'Spot your driver by plate and vehicle. You can still message or call them before entering.';

  @override
  String get verifyContactDriver => 'Contact driver';

  @override
  String get verifySelfieExpiredTitle => 'Selfie link expired';

  @override
  String get verifySelfieExpiredSubtitle => 'Signed links last 15 minutes. Ask your driver to resend, or refresh the ride.';

  @override
  String get verifyRefresh => 'Refresh';

  @override
  String get verifyUnavailableTitle => 'Verification unavailable';

  @override
  String get verifyUnavailableUnknownSubtitle => 'The verification service returned an unexpected state. This is our side, not the driver — retry below.';

  @override
  String get verifyUnavailableSubtitle => 'Driver photo verification is not available for this ride right now. Spot your driver by plate and vehicle.';

  @override
  String get verifyRetry => 'Retry';

  @override
  String get verifySheetLinkExpired => 'The selfie link expired before it could load. Pull a fresh ride state to get a new signed link.';

  @override
  String get verifySheetStorageUnavailable => 'Verification is temporarily unavailable on our side. The driver did send a selfie — try again in a moment.';

  @override
  String verifySheetNetworkError(String status) {
    return 'Could not load the selfie (network error\$status). Tap to retry.';
  }

  @override
  String get verifySheetGenericError => 'Could not load the selfie. Tap to retry.';

  @override
  String verifyComparisonAppBarTitle(String firstName) {
    return 'Verify \$firstName';
  }

  @override
  String get verifyPanelProfileLabel => 'Profile photo (on file)';

  @override
  String get verifyPanelProfileMissing => 'No profile photo is on file for this driver, so there is nothing to compare against yet.';

  @override
  String get verifyPanelSelfieLabel => 'Just-sent selfie';

  @override
  String get verifyPanelDecodeError => 'Image failed to decode — the bytes were corrupt, not absent. Retry from the ride screen.';

  @override
  String verifyExpiryNote(String expiry) {
    return 'Selfie captured for this pickup only · valid until \$expiry';
  }

  @override
  String get verifyButtonNotThem => 'That\'s not them';

  @override
  String get verifyButtonLooksRight => 'Looks right';

  @override
  String get splitSheetTitle => 'Split fare';

  @override
  String get splitSheetIntro => 'Invites are sent by email/SMS. Your charge drops only as people accept — the totals below come straight from the server.';

  @override
  String get splitAddPerson => 'Add person';

  @override
  String splitSendInvites(String amount) {
    return 'Send invites · \$amount';
  }

  @override
  String get splitNeedOneShare => 'Add at least one share before sending.';

  @override
  String splitSharesExceedFare(String fare) {
    return 'Shares must add up to less than the fare (\$fare).';
  }

  @override
  String get splitSendFailed => 'Could not send invites — try again.';

  @override
  String get splitNotYetTitle => 'Not split yet';

  @override
  String splitNotYetSubtitle(String fare) {
    return 'Fare \$fare — you are paying the full amount until someone accepts an invite.';
  }

  @override
  String get splitStatusLabel => 'Split status';

  @override
  String get splitKvFare => 'Fare';

  @override
  String get splitKvYourShare => 'Your share after accepted invites';

  @override
  String get splitKvTotalInvited => 'Total invited';

  @override
  String get splitKvStillWaiting => 'Still waiting';

  @override
  String get splitFieldContact => 'Email or phone';

  @override
  String splitFieldShare(String currency) {
    return 'Share (\$currency)';
  }

  @override
  String get splitFieldRequired => 'Required';

  @override
  String get splitFieldInvalidContact => 'Enter a valid email or phone number';

  @override
  String get splitFieldInvalidAmount => 'Invalid';

  @override
  String get splitFieldAtLeastFare => '≥ fare';

  @override
  String get splitStatusPending => 'pending';

  @override
  String get splitStatusAccepted => 'accepted';

  @override
  String get splitStatusPaid => 'paid';

  @override
  String get splitStatusDeclined => 'declined';

  @override
  String get splitStatusExpired => 'expired';

  @override
  String get splitClose => 'Close';

  @override
  String get splitRemoveShare => 'Remove share';
}
