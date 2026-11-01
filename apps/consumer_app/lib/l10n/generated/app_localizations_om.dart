import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Oromo (`om`).
class AppLocalizationsOm extends AppLocalizations {
  AppLocalizationsOm([String locale = 'om']) : super(locale);

  @override
  String get appTitle => 'NIDAW';

  @override
  String get navRequest => 'Gaafadhu';

  @override
  String get navTracking => 'Hordoffii';

  @override
  String get navHistory => 'Seenaa';

  @override
  String get navAccount => 'Akkaawuntii';

  @override
  String get commonRetry => 'Irra deebi\'ii yaali';

  @override
  String get commonCancel => 'Haqi';

  @override
  String get commonConfirm => 'Mirmiimsi';

  @override
  String get commonClose => 'Cufi';

  @override
  String get commonSave => 'Olkaa\'i';

  @override
  String get commonBack => 'Deebi\'i';

  @override
  String get commonUnavailable => 'Hin jiru';

  @override
  String get commonNotProvided => 'Hin kennamne';

  @override
  String get commonLoading => 'Fe\'amaa jira…';

  @override
  String get requestTitle => 'Eessatti deemaa jirtu?';

  @override
  String get requestPickupLabel => 'Iddoo ka\'umsaa';

  @override
  String get requestDropoffLabel => 'Gama deemtu';

  @override
  String get requestCurrentLocationUnavailable => 'Iddoo ammaa (hin argamne)';

  @override
  String get requestUseCurrentLocation => 'Iddoo ammaatti fayyadami';

  @override
  String get requestSetPinOnMap => 'Saaffuu kaartaa irra kaa\'i';

  @override
  String get requestAddStop => 'Dhaabbata dabalai';

  @override
  String get requestScheduleToggle => 'Karoorfami';

  @override
  String get requestPromoRow => 'Koodii hir\'isaa';

  @override
  String get requestVoiceButton => 'Sagaleedhaan soora gaafadhu';

  @override
  String get requestVoiceSheetTitle => 'Bishaan kee sagaleedhaan hime';

  @override
  String get requestVoiceListening => 'Caasa\'a jira… fakkeenyaaf “Boolee xiyyaara oolfachutti na geesssi” jetti';

  @override
  String requestVoiceHeard(String transcript) {
    return 'Waan dhaga\'e: $transcript';
  }

  @override
  String requestVoiceLowConfidence(String transcript) {
    return 'Sirriitti hin beeku — “$transcript” barbaadi banuu?';
  }

  @override
  String get requestEstimateUnavailable => 'Gatii hin argamne — irra deebi\'ii yaali';

  @override
  String get requestConfirmCta => 'Soora mirkaneessi';

  @override
  String get requestSelectRideType => 'Soora filadhu';

  @override
  String get requestOptionsPricesUnavailable =>
      'Gatii hin argamne — haaruuf walxaxi ykn Irra deebi\'i tuqi.';

  @override
  String get requestOptionsSetRouteFirst =>
      'Gatii hin argamne — bakka ka\'umsaa fi dhaamsaa olkaa\'uun gatiiwwan soorata argadhu.';

  @override
  String get trackingSearchingTitle => 'Daawwitoonni barbaadamaa jiru…';

  @override
  String trackingSearchingSub(int seconds) {
    return 'Sekondii ${seconds}f barbaadaa jira';
  }

  @override
  String get trackingDriverEnRoute => 'Daawwitni kee karaa irra jira';

  @override
  String get trackingRideInProgress => 'Karaa irra jirtu';

  @override
  String get trackingArrived => 'Daawwitni iddoo ka\'umsaa gaheera';

  @override
  String get trackingWalkToPickupAr => 'AR\'n gara iddoo ka\'umsaa deemi';

  @override
  String get trackingCallDriver => 'Daawwitoon simbirro';

  @override
  String get trackingChatWithDriver => 'Daawwitoon waliin haasa\'i';

  @override
  String get trackingCallingUnavailable => 'Simbirroon hin danda\'amu — chaatii yaali';

  @override
  String get trackingCancelRide => 'Soora haqi';

  @override
  String get trackingVerifyDriver => 'Daawwitoon mirkaneessi';

  @override
  String get trackingDriverNoSelfie => 'Daawwitni selfie ergateef';

  @override
  String get trackingContactDriverPrompt => 'Isa dhufuu isaa mirkaneessuuf daawwitoon quunnamii.';

  @override
  String get trackingChangeDestination => 'Bishaan jijjiiri';

  @override
  String get trackingSplitFare => 'Filannoo qoodda';

  @override
  String get trackingCashBadge => 'Kaffaltii saahiliin';

  @override
  String get trackingSosButton => 'Gargaarsa hatattamaa SOS';

  @override
  String get trackingNoDriversTitle => 'Daawwitoonni naannoo hin argamne';

  @override
  String trackingNoDriversBody(int seconds) {
    return 'Sekondii ${seconds}f barbaadne garuu hin walqabanne. Gaaffii kee irra deebi\'uuf kaffaltii ol kaasuun ni danda\'ama?';
  }

  @override
  String get trackingPriceExtensionKeep => 'Gatii ammaan barbaachisa itti fufi';

  @override
  String trackingNoDriversFound(String fare) {
    return 'Yaadatuu ${fare}ufi driver arganne. Gaaffii kee irra deebi\'uun lakkooftuuf kaffaltii ol ka\'i.';
  }

  @override
  String get trackingPriceFareUnavailable => 'Yaadatuu keef driver hin arganne. Kaffaltii ol kaasi — gatii haaraan erga hojiirra oolee booda server n mirkaneessa.';

  @override
  String get trackingPriceExtensionPlus10 => 'Kaffaltii 10% ol kaasi';

  @override
  String get trackingPriceExtensionPlus20 => 'Kaffaltii 20% ol kaasi';

  @override
  String get trackingPriceFeeConfirmedOnRetry => 'Gatiin haaraan yeroo irra deebi\'amuu mirkanaa\'a';

  @override
  String get ridecheckTitle => 'Hundi gaarii?';

  @override
  String get ridecheckBodyStopped => 'Meersaan kee karaa ala daqiiqaa 3 caalaa dhaabbateera.';

  @override
  String ridecheckBodyDeviationMeasured(int meters) {
    return 'Motoraanni karaa eegamu irraa meetira $meters fagaateera.';
  }

  @override
  String get ridecheckBodyDeviationUnmeasured => 'Motoraanni karaa eegamu irraa baay\'ee fageenyaan garagaluu isaagiti mul\'ata.';

  @override
  String ridecheckBodyLowConfidence(int confidencePercent) {
    return 'Yaadni sa\'aa dhufuu imala kanaa amanamaa miti ta\'eera (ebraan $confidencePercent%).';
  }

  @override
  String get ridecheckBodyLowConfidenceUnmeasured => 'Yaadni sa\'aa dhufuu imala kanaa amanamaa miti ta\'eera.';

  @override
  String get ridecheckImOK => 'Ani gaarii dha';

  @override
  String get ridecheckCallForHelp => 'Gargaarsaaf simbirro';

  @override
  String get accessibilityWalkAr => 'Akka namuusaa tokkoon deemuuf AR fayyadamee fuula duraa deemi';

  @override
  String get chatTitle => 'Chaatii';

  @override
  String get chatInputHint => 'Ergaa barreessi…';

  @override
  String get chatSendButton => 'Ergi';

  @override
  String get chatEmptyState => 'Ammaaf ergaan hin jiru. Deebisota ariifataa gadii fayyadami.';

  @override
  String get chatSendFailed => 'Ergaan ergamuun hin milkoofne.';

  @override
  String get chatTranslationHiddenNote => 'Afaan jijjiirama soora kanaaf cufamaa dha.';

  @override
  String get cancelSheetTitle => 'Soora kana haquu?';

  @override
  String get cancelSheetFeeLabel => 'Kaffaltii haqinsa';

  @override
  String get cancelSheetFeeFetching => 'Kaffaltii mirkanaa\'aa jira…';

  @override
  String get cancelSheetFeeUnknown => 'Kaffaltiin yeroo haqamu mirkanaa\'a';

  @override
  String cancelSheetFreeWindow(int minutes) {
    return 'Daqiiqaa ${minutes}f bilisaan haquun ni danda\'ama';
  }

  @override
  String get cancelSheetConfirm => 'Soora haqi';

  @override
  String get cancelSheetDismiss => 'Soora qabi';

  @override
  String get cancelSheetReasonPrompt => 'Akka fooyessinu nu gargaaraa — maaliif haquu jirtu?';

  @override
  String get cancelSheetFeeLoading => 'Kaffaltii haqinsa keessan mirkaneessaa jira…';

  @override
  String get cancelSheetNoFee => 'Yeroo ammaa kaffaltiin haqinsa hin jiru.';

  @override
  String cancelSheetCostNow(String currency, String amount) {
    return 'Amma yoo haqtan $currency $amount itti baasa';
  }

  @override
  String cancelSheetFreeWindowEnds(String countdown) {
    return 'Yeroon bilisaa $countdown keessa xumura';
  }

  @override
  String get cancelReasonOther => 'Kan biroo';

  @override
  String get requestGpsUnavailablePin => 'GPS hin jiru — pinii kaawuu ofii keessan qabsiisuuf harkisaa';

  @override
  String get cancelReasonWaitTooLong => 'Yeroon eeguu dheeraa dha';

  @override
  String get cancelReasonDriverWrongWay => 'Daandeesaan karaan dogoggoraa deema';

  @override
  String get cancelReasonReschedule => 'Yeroo haaromsuu nan barbaada';

  @override
  String get cancelReasonEmergency => 'Haata keessaa';

  @override
  String get cancelReasonPickupIncorrect => 'Bakka kaawuu sirrii miti';

  @override
  String get cancelSheetTotalLabel => 'Walii gala amma yoo haqtan';

  @override
  String get cancelSheetDismissSemantics => 'Soora qabi — fuula kana cufi, homaa hin haquu';

  @override
  String cancelSheetConfirmWithFee(String currency, String amount) {
    return 'Haqi ($currency $amount)';
  }

  @override
  String get cancelSheetSemanticsFeeSuffixUnknown => ' — kaffaltiin yeroo haqamu mirkanaa\'a';

  @override
  String get cancelSheetSemanticsFeeSuffixFree => ' — bilisaa, yeroo haqinsa keessatti';

  @override
  String get rateSheetSubmit => 'Sadarkaa ergi';

  @override
  String get paymentAddCash => 'Filannoo humnaa fe\'uu dabalaa';

  @override
  String get receiptTitle => 'Ramaddii kaffaltii';

  @override
  String get receiptBase => 'Kaffaltii bu\'uuraa';

  @override
  String get receiptDistance => 'Fageenya';

  @override
  String get receiptTime => 'Yeroo';

  @override
  String get receiptSurge => 'Ol-ka\'iinsa yeroon';

  @override
  String get receiptTolls => 'Taxa karaa';

  @override
  String get receiptServiceFee => 'Kaffaltii tajaajilaa';

  @override
  String get receiptPromoDiscount => 'Hir\'isaa koodii';

  @override
  String get receiptTip => 'Kennaa';

  @override
  String get receiptTotal => 'Waligala';

  @override
  String get receiptDownloadPdf => 'PDF buusi';

  @override
  String get receiptEmailReceipt => 'Ramaddiitiin email ergi';

  @override
  String get receiptCashPending => 'Mirkaneeffannoo saahilii daawwitoota eeggamaa jira';

  @override
  String get receiptCashCollected => 'Saahilliin daawwitoon fudhateera';

  @override
  String get mapHealthBanner => 'Taayila kartaa hin argamne — taayila cache\'dhaa yookaan bakka buusaa mul\'ataa jira.';

  @override
  String get mapHealthRetry => 'Taayila irra deebi\'ii yaali';

  @override
  String get locationGateDeniedTitle => 'Hayyama iddoo barbaachisa';

  @override
  String get locationGateDeniedBody => 'Nidus saaffuu ka\'umsaa kaa\'uuf iddoo kee fayyadama. Adireesii harkaan barreessuu ni danda\'orta.';

  @override
  String get locationGateAllow => 'Hayyami';

  @override
  String get locationGateOpenSettings => 'Qindaa\'ot banaa';

  @override
  String get locationGateServiceDisabledTitle => 'Tajaajilli iddoo cufamaa dha';

  @override
  String get locationGateTurnOn => 'Tajaajila iddoo bani';

  @override
  String get geocodeNoMatches => 'Wanti wal-fakkaatu hin jiru — bakka beekamoo yookaan maqaa karaa yaali.';

  @override
  String get geocodeDegraded => 'Barbaachi hin argamne — bu\'aawwan cache\'dhaa mul\'ataa jiru';

  @override
  String get geocodeResolving => 'Adireesiin mirkanaa\'aa jira…';

  @override
  String get notificationsTitle => 'Beeksisa';

  @override
  String get notificationsEmpty => 'Ammaaf homaa hin jiru.';

  @override
  String get notificationsMarkAllRead => 'Hundumaa dubbifameetti mallatteessi';

  @override
  String get settingsTitle => 'Qindaa\'otii';

  @override
  String get settingsLanguageSection => 'Afaan';

  @override
  String get settingsLanguageSystem => 'Mala sistamaa';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageAmharic => 'አማርኛ';

  @override
  String get settingsLanguageOromo => 'Afaan Oromoo';

  @override
  String get arNavTitle => 'Qajeelsha AR lakkofsa';

  @override
  String get arNavUnsupported => 'AR meqaansaa kana irratti hin jiru — kaartaa 2D mul\'isi';

  @override
  String get arNavMapView => 'Mul\'ata kaartaa';

  @override
  String get arNavArView => 'Mul\'ata AR';

  @override
  String arNavDistanceAhead(int meters) {
    return 'Mmeetiraa $meters dura';
  }

  @override
  String get accessibilityRecenterFab => 'Kaartaa gara iddoo kootti deebisi';

  @override
  String get accessibilityPickupPin => 'Saaffuu ka\'umsaa, sochoosuuf harkisi';

  @override
  String get accessibilityDriverMarker => 'Iddoo daawwitoon';

  @override
  String accessibilityUnreadBadge(int count) {
    return 'Beekisa $count dubbifame mitii';
  }

  @override
  String get historyTitle => 'Seenaa dheeffannaa';

  @override
  String get historyEmpty => 'Ammaaf dheeffanni hin jiru';

  @override
  String get paymentNoneSaved => 'Hanga ammaa karaa olkaa\'amaa hin jiru. Gadi jalaa dabalaa.';

  @override
  String get trackingErrorLiveRideTitle => 'Walqunnamtiin cincaa — imalli keeti itti fufee jira';

  @override
  String get trackingErrorLiveRideBody => 'Odeeffannoo imala muraanga dhabne, garuu imalli keeti haqamaa hin jiru. Fuula kana irratti hachuu ykn ba\'uu dandeessa.';

  @override
  String get trackingErrorGenericTitle => 'Waanni tokko dogoggoraa ta\'e';

  @override
  String get trackingErrorGenericBody => 'Taksiin dhumaatti xumuramaa hin turre. Irra deebi\'uun dura bal\'ina gadii ilaali.';

  @override
  String get trackingErrorStay => 'Turi';

  @override
  String get trackingErrorLeave => 'Ba\'i';

  @override
  String get trackingErrorRetry => 'Irra deebi\'i';

  @override
  String get trackingErrorDismiss => 'Cufi';

  @override
  String get trackingErrorLiveRideA11y => 'Imala hojiirra ooluu keessatti dogoggorri mul\'ate. Imalli keeti itti fufee jira.';

  @override
  String get trackingErrorDetailA11y => 'Bal\'ina dogoggoraa';

  @override
  String get sosSlideLabel => 'SOS mirgaan fageenyaan simsimsi';

  @override
  String get sosSliderA11y => 'Harkisa mirga SOS. Mirga guutuutti simsimsi ykn Enter cuqaasi oguu gargaarsa hatattamaa ergachuuf.';

  @override
  String get sosActivateA11y => 'Amma SOS hatattamaa ergi';

  @override
  String get sosTooltip => 'Oguu gargaarsa hatattamaa mirkaneessuuf qabi, mirga guutuutti simsimsi';

  @override
  String get sosTitle => 'SOS Hatattamaa';

  @override
  String sosTileSubtitle(String number) {
    return 'Lakkoofsa hatattamaa \$number bakka qabuun olkaa\'amtee waliin beeksisi';
  }

  @override
  String get sosOverlayA11y => 'Lakkoofsa duubaa SOS hatattamaa';

  @override
  String get sosOverlayTitle => 'SOS Hatattamaa';

  @override
  String sosOverlayCountdownBody(String number, int seconds) {
    return 'Bilbilli si\'a \$seconds\'tti lakkoofsa hatattamaa \$number bana…';
  }

  @override
  String sosOverlayFallbackBody(String number) {
    return 'Bilbilli yoo hin banne, tuqaa gadii fayyadami ykn kallattiin \$number bilbili.';
  }

  @override
  String get sosOverlayCancel => 'Haqi — nagaan ani jira';

  @override
  String get sosOverlayCallNow => 'Tajaajila hatattamaa amma bilbili';

  @override
  String sosOverlayRetryCall(String number) {
    return '\$number bilbilaan irra deebi\'i';
  }

  @override
  String get sosStartedCountdown => 'SOS herregaa eegalame. Mireeduu qabi yookiin Safety Toolkit banaaf shield tuqi. (native review pending)';

  @override
  String get sosLocationUnavailable => 'Bakni argamuu dide — bakka keetiin SOS eegaluun hin danda\'amu. (native review pending)';

  @override
  String get openSafetyToolkit => 'Safety Toolkit banii (native review pending)';

  @override
  String sosOverlayCallDirectly(String number) {
    return '\$number bilbila keetiin kallattiin bilbili.';
  }

  @override
  String get historyFilterAll => 'Hunda';

  @override
  String get historyFilterCompleted => 'Xumurame';

  @override
  String get historyFilterCancelled => 'Haqame';

  @override
  String get historyFilterInProgress => 'Hojiirra ooluu';

  @override
  String historyEmptyFiltered(String filter) {
    return 'Imala \$filter\'aa hanga ammaa hin qabu';
  }

  @override
  String get historyEmptyBody => 'Seenaan imala keetii as mul\'ata.';

  @override
  String get historyEmptyFilteredBody => 'Imala dabalataa argachuuf filannoo biraa yaali.';

  @override
  String get historyClearFilter => 'Filannoo balleessi';

  @override
  String get historyRequestRide => 'Imala gaadhi';

  @override
  String get historyErrorPrimary => 'Imaloonni keetii fe\'amuu hin dandeenye';

  @override
  String get historyRetry => 'Irra deebi\'i';

  @override
  String get requestOptionChosenBadge => 'FILATAME';

  @override
  String requestOptionEtaMinutes(int minutes) {
    return (minutes == 0 ? 'Amma dhufaa jira' : '\$minutes daqiqaa fageenya');
  }

  @override
  String get requestOptionEtaUnavailable => 'ETA hin argamne';

  @override
  String requestOptionSeats(int count) {
    return (count == 1 ? '1 teessoo' : '\$count teessoo');
  }

  @override
  String get requestOptionCapacityUnknown => 'Odeeffannoo teessoo hin kennine';

  @override
  String get requestOptionUnavailable => 'Hin argamu';

  @override
  String get driverCallTooltip => 'Diree daandiqa\'aan bilbilaan waamaa';

  @override
  String get driverChatTooltip => 'Diree daandiqa\'aan waliin haalaawaa';

  @override
  String get driverEtaMinutesUnit => 'daq';

  @override
  String get verifySelfieTitle => 'Diree daandii keessan mirkaneessaa';

  @override
  String verifySelfieSubtitle(String driverName) {
    return '\$driverName fuula dura keessan walu gahuu dursee selfie ergesera. Fuula agarsiisa isa waliin wal bira qabuuf tuqi.';
  }

  @override
  String get verifySelfieNotSentTitle => 'Direen daandii selfie hin ergine';

  @override
  String get verifySelfieNotSentSubtitle => 'Diree daandii keessan lakkoofsa paalaatii fi raabaan beekadhaa. Seenuun dura ergaa ergachuu ykn bilbilaan waamu ni dandeessu.';

  @override
  String get verifyContactDriver => 'Diree daandii qukkubaa';

  @override
  String get verifySelfieExpiredTitle => 'Geessi selfie yeroon isaa darbeera';

  @override
  String get verifySelfieExpiredSubtitle => 'Geessonni mallattoo qaban daqiiqaa 15 qofa turu. Diree daandii keessan akka irra deebi\'an gaafadhaa ykn sochii haaraa gochuuf gubbaa haaromsaa.';

  @override
  String get verifyRefresh => 'Haaromsi';

  @override
  String get verifyUnavailableTitle => 'Mirkanneessin hin jiru';

  @override
  String get verifyUnavailableUnknownSubtitle => 'Tajaajilli mirkaneessinaa haala adda ta\'e ergeseera. Kun gara keenya malee diree daandii miti — gubbaa irra deebi\'aa yaalaa.';

  @override
  String get verifyUnavailableSubtitle => 'Mirkanneessi suura diree daandii sochii kanaaf amma hin jiru. Diree daandii keessan lakkoofsa paalaatii fi raabaan beekadhaa.';

  @override
  String get verifyRetry => 'Irra deebi\'aa yaali';

  @override
  String get verifySheetLinkExpired => 'Geessi selfie guutuu dura yeroon isaa darbeera. Geessa haaraa argachuuf haala sochii haaraa fe\'i.';

  @override
  String get verifySheetStorageUnavailable => 'Mirkanneessi yeroofacha gara keenyatti rakkoo qaba. Direen daandii selfie ergeera — yeroo gabaabaa keessatti irra deebi\'aa yaali.';

  @override
  String verifySheetNetworkError(String status) {
    return 'Selfie banuu hin dandeenye (dogoggora network\$status). Irra deebi\'uuf tuqi.';
  }

  @override
  String get verifySheetGenericError => 'Selfie banuu hin dandeenye. Irra deebi\'uuf tuqi.';

  @override
  String verifyComparisonAppBarTitle(String firstName) {
    return '\$firstName mirkaneessi';
  }

  @override
  String get verifyPanelProfileLabel => 'Suura agarsiisaa (galmaa irra jiru)';

  @override
  String get verifyPanelProfileMissing => 'Diree daandii kanaaf suura agarsiisaa galmaa irra jiru hin qabu; kanaaf ammoo wanta wal bira qabamu hin jiru.';

  @override
  String get verifyPanelSelfieLabel => 'Selfie amma ergame';

  @override
  String get verifyPanelDecodeError => 'Suurni hiikamuu hin dandeenye — bayitoonni sun cabe malee hin dhabaman. Gabatee sochii irraa irra deebi\'aa yaali.';

  @override
  String verifyExpiryNote(String expiry) {
    return 'Selfiin wal qabxii kanaaf qofa kaafame · \$expiry haa barbaachisu';
  }

  @override
  String get verifyButtonNotThem => 'Isa/Ishee miti';

  @override
  String get verifyButtonLooksRight => 'Sirreedha ta\'a';
}
