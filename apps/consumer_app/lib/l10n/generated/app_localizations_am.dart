import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Amharic (`am`).
class AppLocalizationsAm extends AppLocalizations {
  AppLocalizationsAm([String locale = 'am']) : super(locale);

  @override
  String get appTitle => 'NIDAW';

  @override
  String get navRequest => 'ጠይቅ';

  @override
  String get navTracking => 'ክትትል';

  @override
  String get navHistory => 'ታሪክ';

  @override
  String get navAccount => 'መለያ';

  @override
  String get commonRetry => 'እንደገና ሞክር';

  @override
  String get commonCancel => 'ተዋውቅ';

  @override
  String get commonConfirm => 'አረጋግጥ';

  @override
  String get commonClose => 'ዝጋ';

  @override
  String get commonSave => 'አስቀምጥ';

  @override
  String get commonBack => 'ተመለስ';

  @override
  String get commonUnavailable => 'አይገኝም';

  @override
  String get commonNotProvided => 'አልቀረበም';

  @override
  String get commonLoading => 'በመጫን ላይ…';

  @override
  String get requestTitle => 'ወዴት እየሄድኖ ነው?';

  @override
  String get requestPickupLabel => 'መነሻ ቦታ';

  @override
  String get requestDropoffLabel => 'መድረሻ';

  @override
  String get requestCurrentLocationUnavailable => 'የአሁን ቦታ (አይገኝም)';

  @override
  String get requestUseCurrentLocation => 'የአሁን ቦታዬን ተጠቀም';

  @override
  String get requestSetPinOnMap => 'በካርታ ላይ ማሰጊያ አስቀምጥ';

  @override
  String get requestAddStop => 'ገደል ጨምር';

  @override
  String get requestScheduleToggle => 'ለጊዜ ወደፊት ዕቅድ';

  @override
  String get requestPromoRow => 'የቅናሽ ኮድ';

  @override
  String get requestVoiceButton => 'በድምጽ ጉዞ ጠይቅ';

  @override
  String get requestVoiceSheetTitle => 'መድረሻዎን በድምጽ ይንገሩ';

  @override
  String get requestVoiceListening => 'በማዳመጥ ላይ… ለምሳሌ “ወደ ቦሌ አውሮፕላን ማረፊያ ውሰዱኝ” ይበሉ';

  @override
  String requestVoiceHeard(String transcript) {
    return 'የሰማሁት፦ $transcript';
  }

  @override
  String requestVoiceLowConfidence(String transcript) {
    return 'በትክክል ሳያውቀው ቀረ — “$transcript” የሚለውን ፍለጋ ክፈት?';
  }

  @override
  String get requestEstimateUnavailable => 'ዋጋ አይገኝም — እንደገና ሞክር';

  @override
  String get requestConfirmCta => 'ጉዞ አረጋግጥ';

  @override
  String get requestSelectRideType => 'ጉዞ ይምረጡ';

  @override
  String get requestOptionsPricesUnavailable =>
      'ዋጋ መግለጫ አልተገኘም — ለማደስ ይጎትቱ ወይም እንደገና ይሞክሩ።';

  @override
  String get requestOptionsSetRouteFirst =>
      'ዋጋ መግለጫ አልተገኘም — ቀጥያና መድረሻ ቦታዎችን ከመረጡ በኋላ ዋጋዎች ይጫናሉ።';

  @override
  String get trackingSearchingTitle => 'ሾፍሎችን እየፈለግን ነው…';

  @override
  String trackingSearchingSub(int seconds) {
    return 'ለ$seconds ሰከንድ እየፈለግን ነው';
  }

  @override
  String get trackingDriverEnRoute => 'ሾፍሎ በመምጣት ላይ ነው';

  @override
  String get trackingRideInProgress => 'በጉዞ ላይ ነው';

  @override
  String get trackingArrived => 'ሾፍሉ ወደ መነሻ ቦታ ደርሷል';

  @override
  String get trackingWalkToPickupAr => 'ወደ መነሻ ቦታ AR በኩል ሂድ';

  @override
  String get trackingCallDriver => 'ሾፍሉን ይደውሉ';

  @override
  String get trackingChatWithDriver => 'ከሾፍሉ ጋር ይነጋገሩ';

  @override
  String get trackingCallingUnavailable => 'መደወል አይቻልም — ቻት ይሞክሩ';

  @override
  String get trackingCancelRide => 'ጉዞ ተዋውቅ';

  @override
  String get trackingVerifyDriver => 'ሾፍሎን ያረጋግጡ';

  @override
  String get trackingDriverNoSelfie => 'ሾፍሉ ራስ-ላክ ላክ አልላከም';

  @override
  String get trackingContactDriverPrompt => 'እየመጡ መሆናቸውን ለማረጋገጥ ሾፍሉን ያግኙ።';

  @override
  String get trackingChangeDestination => 'መድረሻ ቀይር';

  @override
  String get trackingSplitFare => 'ክፍያ ማካፈል';

  @override
  String get trackingCashBadge => 'በጥሪት ክፍያ';

  @override
  String get trackingSosButton => 'አስቸኳይ ጥያቄ SOS';

  @override
  String get trackingNoDriversTitle => 'አቅራቢያ ሾፍሎች አልተገኙም';

  @override
  String trackingNoDriversBody(int seconds) {
    return 'ለ$seconds ሰከንድ ፍለገን አልተመደበም። ጥያቄዎን እንደገና ለማሰማጨት ከፍ ያለ ክፍያ ይጨምሩ?';
  }

  @override
  String get trackingPriceExtensionKeep => 'በአሁኑ ዋጋ ፍለጋ ይቀጥሉ';

  @override
  String trackingNoDriversFound(String fare) {
    return 'ለ$fare ሹፌሮች አናገኘንም። ጥያቄዎን እንደገና ለማስተላለፍ ከፍ ያለ ክፍያ ይጨምሩ።';
  }

  @override
  String get trackingPriceFareUnavailable => 'ለጥያቄዎ ሹፌሮችን አግኝተን አልነበረም። ከፍ ያለ ክፍያ ይጨምሩ — አዲሱ ዋጋ ከመተግበሩ በፊት በአገልግሎት ተረጋግጧል።';

  @override
  String get trackingPriceExtensionPlus10 => 'ክፍያን በ10% ጨምር';

  @override
  String get trackingPriceExtensionPlus20 => 'ክፍያን በ20% ጨምር';

  @override
  String get trackingPriceFeeConfirmedOnRetry => 'አዲሱ ዋጋ በእንደገና ሙከራ ጊዜ ይረጋገጣል';

  @override
  String get ridecheckTitle => 'ሁሉም ነገር ሰላም ነው?';

  @override
  String get ridecheckBodyStopped => 'ተሽከርካሪዎ ከመንገድ ውጭ ከ3 ደቂቃ በላይ ቆሟል።';

  @override
  String ridecheckBodyDeviationMeasured(int meters) {
    return 'ተሽከርካሪው ከሚጠበቀው መንገድ $meters ሜትር አንግልሏል።';
  }

  @override
  String get ridecheckBodyDeviationUnmeasured => 'ተሽከርካሪው ከሚጠበቀው መንገድ በጉልህ ሁኔታ ርቋል።';

  @override
  String ridecheckBodyLowConfidence(int confidencePercent) {
    return 'የዚህ ጉዞ የመድረስ ግምት አይታመን ተደርጓል (እርግጠኛነት $confidencePercent%)።';
  }

  @override
  String get ridecheckBodyLowConfidenceUnmeasured => 'የዚህ ጉዞ የመድረስ ግምት አይታመን ተደርጓል።';

  @override
  String get ridecheckImOK => 'ሰላም ነኝ';

  @override
  String get ridecheckCallForHelp => 'ለእገዛ ጥያቄ ደውል';

  @override
  String get accessibilityWalkAr => 'ወደ መነሻ ቦታ በአር ኒቪጌሽን መራመድ';

  @override
  String get chatTitle => 'ቻት';

  @override
  String get chatInputHint => 'መልዕክት ይጻፉ…';

  @override
  String get chatSendButton => 'ላክ';

  @override
  String get chatEmptyState => 'እስካሁን መልዕክቶች የሉም። ከታች ያሉትን ፈጣን ምላሾች ይጠቀሙ።';

  @override
  String get chatSendFailed => 'መልዕክቱ መላክ አልተሳካም።';

  @override
  String get chatTranslationHiddenNote => 'ለዚህ ጉዞ ትርጉሞች ተጥፍተዋል።';

  @override
  String get cancelSheetTitle => 'ይህን ጉዞ ይተዉ?';

  @override
  String get cancelSheetFeeLabel => 'የመሰረዣ ክፍያ';

  @override
  String get cancelSheetFeeFetching => 'ክፍያ በማረጋገጥ ላይ…';

  @override
  String get cancelSheetFeeUnknown => 'ክፍያው ሲሰረዝ ይረጋገጣል';

  @override
  String cancelSheetFreeWindow(int minutes) {
    return 'ለ$minutes ደቂቃ በነጻ መሰረዝ ይቻላል';
  }

  @override
  String get cancelSheetConfirm => 'ጉዞ ተዋውቅ';

  @override
  String get cancelSheetDismiss => 'ጉዞው ይቁጠር';

  @override
  String get cancelSheetReasonPrompt => 'እንድንሻሻል ይረዱን — ለምን እየሰረዙ ነው?';

  @override
  String get cancelSheetFeeLoading => 'የመሰረዣ ክፍያዎን በማረጋገጥ ላይ…';

  @override
  String get cancelSheetNoFee => 'በአሁኑ ሰዓት የመሰረዣ ክፍያ የለም።';

  @override
  String cancelSheetCostNow(String currency, String amount) {
    return 'አሁን ሲሰርዙ $currency $amount ይተዋል';
  }

  @override
  String cancelSheetFreeWindowEnds(String countdown) {
    return 'ነጻ የመሰረዣ ጊዜ በ$countdown ያበቃል';
  }

  @override
  String get cancelReasonOther => 'ሌላ';

  @override
  String get requestGpsUnavailablePin => 'ጂፒኤስ አይገኝም — የመነሻ ቦታዎን ለማስቀመጥ ፒኑን ይጎትቱ';

  @override
  String get cancelReasonWaitTooLong => 'የመጠበቂያ ᰰደሩ ረጅም ነው';

  @override
  String get cancelReasonDriverWrongWay => 'ሹፌሩ ወደ ስህተት አቅጣጫ እየሄደ ነው';

  @override
  String get cancelReasonReschedule => 'ጊዜውን መቀየር አለብኝ';

  @override
  String get cancelReasonEmergency => 'አስቸኳይ ጊዜ';

  @override
  String get cancelReasonPickupIncorrect => 'የመነሻ ቦታው ትክክል አይደለም';

  @override
  String get cancelSheetTotalLabel => 'አሁን ከሰረዙ አጠቃላይ';

  @override
  String get cancelSheetDismissSemantics => 'ጉዞውን ይያዙ — ይህን መስኮት ዘግቶ ምንም አይሰርዝም';

  @override
  String cancelSheetConfirmWithFee(String currency, String amount) {
    return 'ተዋውቅ ($currency $amount)';
  }

  @override
  String get cancelSheetSemanticsFeeSuffixUnknown => ' — ክፍያው ሲሰረዝ ይረጋገጣል';

  @override
  String get cancelSheetSemanticsFeeSuffixFree => ' — ነጻ፣ በመሰረዣ መስኮት ውስጥ';

  @override
  String get rateSheetSubmit => 'ደረጃ ይላኩ';

  @override
  String get paymentAddCash => 'የጥሪት ምርጫ ይጨምሩ';

  @override
  String get receiptTitle => 'ደረሰኝ';

  @override
  String get receiptBase => 'መሠረታዊ ክፍያ';

  @override
  String get receiptDistance => 'ርቀት';

  @override
  String get receiptTime => 'ጊዜ';

  @override
  String get receiptSurge => 'ጊዜያዊ ዕድገት';

  @override
  String get receiptTolls => 'የመንገድ ግብር';

  @override
  String get receiptServiceFee => 'የአገልግሎት ክፍያ';

  @override
  String get receiptPromoDiscount => 'የቅናሽ ኮድ ቅናሽ';

  @override
  String get receiptTip => 'ጫረ';

  @override
  String get receiptTotal => 'ጠቅላላ';

  @override
  String get receiptDownloadPdf => 'PDF አውርድ';

  @override
  String get receiptEmailReceipt => 'ደረሰኙን በኢሜይል ላክ';

  @override
  String get receiptCashPending => 'ሾፍሉ ጥሪት እንደተቀበለ ማረጋገጫ በመጠበቅ ላይ';

  @override
  String get receiptCashCollected => 'ጥሪት በሾፍሉ ተቀብሏል';

  @override
  String get mapHealthBanner => 'የካርታ ላካዎች አይገኙም — የተከማቹ ወይም ሰብሳቢ ላካዎች እየታዩ ነው።';

  @override
  String get mapHealthRetry => 'ላካዎችን እንደገና ሞክር';

  @override
  String get locationGateDeniedTitle => 'የአካባቢ ፈቃድ ያስፈልጋል';

  @override
  String get locationGateDeniedBody => 'ኒዱስ መነሻ ማሰጊያ ለማስቀመጥ አካባቢዎን ይጠቀማል። አድራሻ በእጅ መጻፍ ይችላሉ።';

  @override
  String get locationGateAllow => 'ፍቃድ ስጥ';

  @override
  String get locationGateOpenSettings => 'ቅንብሮች ክፈት';

  @override
  String get locationGateServiceDisabledTitle => 'የአካባቢ አገልግሎቶች ጠፍተዋል';

  @override
  String get locationGateTurnOn => 'የአካባቢ አገልግሎት አብራ';

  @override
  String get geocodeNoMatches => 'ተመሳሳይ የለም — ታዋቂ ቦታ ወይም የዘወትር ስም ይሞክሩ።';

  @override
  String get geocodeDegraded => 'ፍለጋ አይገኝም — የተከማቹ ውጤቶች እየታዩ ነው';

  @override
  String get geocodeResolving => 'አድራሻ በማግኘት ላይ…';

  @override
  String get notificationsTitle => 'ማሳወቂያዎች';

  @override
  String get notificationsEmpty => 'እስካሁን ምንም የለም።';

  @override
  String get notificationsMarkAllRead => 'ሁሉንም የተነበብኩ ምልክት አድርግ';

  @override
  String get settingsTitle => 'ቅንብሮች';

  @override
  String get settingsLanguageSection => 'ቋንቋ';

  @override
  String get settingsLanguageSystem => 'የስርዓተ ነባሪ';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageAmharic => 'አማርኛ';

  @override
  String get settingsLanguageOromo => 'Afaan Oromoo';

  @override
  String get arNavTitle => 'AR የእግር መመሪያ';

  @override
  String get arNavUnsupported => 'AR በዚህ መሣሪያ ላይ የለም — ይልቁንም 2D ካርታ እየታየ ነው።';

  @override
  String get arNavMapView => 'ካርታ እይታ';

  @override
  String get arNavArView => 'AR እይታ';

  @override
  String arNavDistanceAhead(int meters) {
    return '$meters ሜትር ፊት';
  }

  @override
  String get accessibilityRecenterFab => 'ካርታውን ወደ እኔ አካባቢ መልስ';

  @override
  String get accessibilityPickupPin => 'የመነሻ ማሰጊያ ለማንቀሳቀስ ይጎትቱ';

  @override
  String get accessibilityDriverMarker => 'የሾፍሉ ቦታ';

  @override
  String accessibilityUnreadBadge(int count) {
    return '$count ያልተነበቡ ማሳወቂያዎች';
  }

  @override
  String get historyTitle => 'የጉዞ ታሪክ';

  @override
  String get historyEmpty => 'እስካሁን ጉዞ የለም';

  @override
  String get paymentNoneSaved => 'እስካሁን የተቀመጡ ዘዴዎች የሉም። ከታች ይጨምሩ።';

  @override
  String get trackingErrorLiveRideTitle => 'ግንኙነት ተቋረጠ — ጉዞዎ ገና በሂደት ላይ ነው';

  @override
  String get trackingErrorLiveRideBody => 'አንዳንድ የጉዞ መረጃ አጥተናል፣ ነገር ግን ጉዞዎ አልተሰረዘም። በዚህ ማያ ገጽ ላይ ሊቆዩ ወይም ሊወጡ ይችላሉ።';

  @override
  String get trackingErrorGenericTitle => 'አንድ ነገር ተስላሏል';

  @override
  String get trackingErrorGenericBody => 'የመጨረሻው እርምጃ አልተጠናቀቀም። እንደገና ከመሞከርዎ በፊት ዝርዝሮቹን ይመልከቱ።';

  @override
  String get trackingErrorStay => 'ቆይ';

  @override
  String get trackingErrorLeave => 'ውጣ';

  @override
  String get trackingErrorRetry => 'እንደገና ሞክር';

  @override
  String get trackingErrorDismiss => 'ዝጋ';

  @override
  String get trackingErrorLiveRideA11y => 'በንቁ ጉዞዎ ወቅት ስህተት። ጉዞዎ እየተቀጠለ ነው።';

  @override
  String get trackingErrorDetailA11y => 'የስህተት ዝርዝር';

  @override
  String get sosSlideLabel => 'SOS ለማረጋገጥ ወደ ቀኝ ጎትት';

  @override
  String get sosSliderA11y => 'የSOS ማረጋገጫ መንሸራተች። ወደ ቀኝ ሙሉ ለሙሉ ጎትተው ወይም Enter ጠቅተው የአደጋ ማሳወቂያ ይላኩ።';

  @override
  String get sosActivateA11y => 'አሁን የአደጋ SOS ይላኩ';

  @override
  String get sosTooltip => 'የአደጋ ማሳወቂያ ለማረጋገጥ ይያዙ እና ሙሉ ለሙሉ ወደ ቀኝ ይንሸራትቱ';

  @override
  String get sosTitle => 'የአደጋ SOS';

  @override
  String sosTileSubtitle(String number) {
    return 'የቀጥታ አድራሻዎን ከ911 ጋር በማገናኘት የአደጋ መስመር ያስገንዝቡ';
  }

  @override
  String get sosOverlayA11y => 'የአደጋ SOS ቆጣሪ';

  @override
  String get sosOverlayTitle => 'የአደጋ SOS';

  @override
  String sosOverlayCountdownBody(String number, int seconds) {
    return 'ስልክዎ በ\$seconds ሰከንድ ውስገ \$number የአደጋ ቁጥር ላይ ይደውላል…';
  }

  @override
  String sosOverlayFallbackBody(String number) {
    return 'ስልክዎ ካልተከፈተ፣ ከታች ያለውን ቁልፍ ይጠቀሙ ወይም በቀጥታ \$numberን ይደውሉ።';
  }

  @override
  String get sosOverlayCancel => 'ሰርዝ — ደህንነቴ ጥሩ ነው';

  @override
  String get sosOverlayCallNow => 'የአደጋ አገልግሎቶችን አሁን ደውሉ';

  @override
  String sosOverlayRetryCall(String number) {
    return '\$numberን መደወል እንደገና ሞክር';
  }

  @override
  String get sosStartedCountdown => 'የSOS ቆጣሪ ተጀምሯል ለማረጋገጥ ይያዙ ወይም Safety Toolkit ለመክፈት መጋረጃውን ይንኩ። (native review pending)';

  @override
  String get sosLocationUnavailable => 'አካባቢ ማግኘት አልተቻለም — ከአካባቢዎ ጋር SOS መጀመር አይቻልም። (native review pending)';

  @override
  String get openSafetyToolkit => 'Safety Toolkit ይክፈቱ (native review pending)';

  @override
  String sosOverlayCallDirectly(String number) {
    return '\$numberን ከስልክዎ በቀጥታ ይደውሉ።';
  }

  @override
  String get historyFilterAll => 'ሁሉም';

  @override
  String get historyFilterCompleted => 'የተጠናቀቀ';

  @override
  String get historyFilterCancelled => 'ተሰርዟል';

  @override
  String get historyFilterInProgress => 'በሂደት ላይ';

  @override
  String historyEmptyFiltered(String filter) {
    return 'እስካሁን \$filter ጉዞ የለም';
  }

  @override
  String get historyEmptyBody => 'የጉዞ ታሪክዎ እዚህ ይታያል።';

  @override
  String get historyEmptyFilteredBody => 'ተጨማሪ ጉዞዎችን ለማየት ሌላ ማጣሪያ ይሞክሩ።';

  @override
  String get historyClearFilter => 'ማጣሪያ አጽዳ';

  @override
  String get historyRequestRide => 'ጉዞ ይጠይቁ';

  @override
  String get historyErrorPrimary => 'ጉዞዎችን መጫን አልተሳካም';

  @override
  String get historyRetry => 'እንደገና ሞክር';

  @override
  String get requestOptionChosenBadge => 'ተመርጧል';

  @override
  String requestOptionEtaMinutes(int minutes) {
    return (minutes == 0 ? 'አሁን እየመᣣ ል።' : '\$minutes ደቂቃ ርቀት ል።');
  }

  @override
  String get requestOptionEtaUnavailable => 'ETA አልተገኘም';

  @override
  String requestOptionSeats(int count) {
    return (count == 1 ? '1 ቦታ' : '\$count ቦታዎች');
  }

  @override
  String get requestOptionCapacityUnknown => 'የሰው ብዛት አልቀረበም';

  @override
  String get requestOptionUnavailable => 'አይገኝም';
}
