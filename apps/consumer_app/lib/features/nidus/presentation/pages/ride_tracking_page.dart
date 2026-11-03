import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/config/feature_flag_service.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/flags/ar_navigation_gate.dart';
import '../../../../core/geocoding/geocoding_service.dart';
import '../../../../core/location/device_location_service.dart';
import '../../../../core/map/live_map_widget.dart';
import '../../../../core/network/websocket_client.dart';
import '../../../../core/router/app_router.dart' show RouteNames;
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/l10n.dart';
import '../bloc/ride_bloc.dart';
import '../../data/repositories/ride_repository.dart'
    show
        Ride,
        RideRepository,
        PriceExtensionResult;
import '../widgets/cancel_ride_sheet.dart';
import '../widgets/stop_charge_card.dart';
import '../widgets/place_autocomplete_sheet.dart';
import '../widgets/driver_card.dart';
import '../widgets/payment_method_selector.dart';
import '../widgets/pre_selfie_capture_sheet.dart';
import '../widgets/rate_ride_sheet.dart';
import '../widgets/safety_widgets.dart';
import '../widgets/verify_driver_card.dart';
import '../../data/repositories/masked_call_repository.dart';
// Phase 6 (nav consistency): ChatPage / ReceiptDetailPage / SafetyToolkitPage
// are reached through their GoRouter routes now (RouteNames above), so the
// page imports are gone — deep links, flag gates and web URL sync apply to
// them like every other Nidus surface.

/// Tracking surface rebuilt on the Foundation map (§1.1):
/// - driver marker animates between successive position updates with an
///   800 ms TweenAnimationBuilder;
/// - route polyline drawn through [LiveMapWidget]'s PolylineLayer;
/// - camera follows the rider while the driver is en route and switches to
///   following the driver marker once the ride is in progress;
/// - the Recenter FAB toggles between following driver and following rider.
class RideTrackingPage extends StatefulWidget {
  final String rideId;

  const RideTrackingPage({super.key, required this.rideId});

  @override
  State<RideTrackingPage> createState() => _RideTrackingPageState();
}

class _RideTrackingPageState extends State<RideTrackingPage>
    with SingleTickerProviderStateMixin {
  static const Duration _driverAnimationDuration = Duration(milliseconds: 800);

  /// Camera-only fallback center (Addis Ababa region, matching the product's
  /// market). Never rendered as a pin or address — it just keeps the camera
  /// out of the ocean until the first real coordinate arrives via WS.
  static final LatLng _cameraFallback = LatLng(9.03, 38.74);

  final GlobalKey<LiveMapWidgetState> _mapKey =
      GlobalKey<LiveMapWidgetState>();
  late final RideBloc _rideBloc;

  // ── Phase 5: connectivity & state-honesty awareness ──────────────────────

  /// Latest settled device-connectivity verdict from the bloc's feed
  /// (OfflineService). Null means "no sample yet" — honest null: the banner
  /// renders NOTHING rather than guessing online or offline.
  bool? _isOffline;

  /// Live WebSocket link state for the tracking subscription. Distinct from
  /// device connectivity: the radio can be up while the ride socket is down,
  /// and that is exactly when the rider needs to know updates are stale.
  WebSocketConnectionState _wsState = WebSocketConnectionState.connected;

  StreamSubscription<bool>? _offlineSub;
  StreamSubscription<WebSocketConnectionState>? _wsStateSub;

  /// Set while the page holds a live ride worth keeping the reconnecting
  /// banner for (mirrors [_lastLiveRideState] updates in the listener).
  bool get _hasLiveRideNow => _hasActiveRide(_lastLiveRideState ?? const RideInitial());

  /// Previous driver fix — the tween start point for the next update.
  LatLng? _previousDriverPoint;

  /// Newest committed driver fix — the tween end point.
  LatLng? _committedDriverPoint;

  /// True while the camera follows the driver marker; false = follow rider.
  bool _followDriver = true;

  /// §2.3: guards the one-shot auto-open of the driver pre-selfie capture
  /// sheet. Reset when leaving DriverEnRouteForDriver so a re-entry (e.g.
  /// after a reconnect) can prompt again if the driver still hasn't sent.
  bool _preSelfieSheetShown = false;

  /// §4.5: timestamp identity of the RideCheck prompt already surfaced, so
  /// the modal opens exactly once per detected anomaly (the bloc's
  /// RideAnomaly carries a unique detectedAt per trigger).
  DateTime? _shownAnomalyAt;

  /// Guards against double-taps on the price-extension options while an
  /// apply POST is in flight (§4.6).
  bool _priceExtensionBusy = false;

  /// Phase 1 (UI/UX remediation): a `RideError` that reaches the tracking
  /// surface while a ride is still active no longer ejects the rider with no
  /// explanation. It is parked here and rendered as a persistent banner with
  /// explicit Stay / Leave actions (and Retry for transient load failures).
  /// Cleared when the user acts, when fresh non-error state arrives, or when
  /// the error belongs to a flow this page never triggered (see below).
  RideError? _activeErrorBanner;

  /// Phase 6 (error-surface consistency): durable, money-relevant failures
  /// raised by page-local flows (destination change, price extension) live
  /// here until the rider acknowledges them — snackbars expire silently,
  /// which is acceptable for confirmations but not for "your destination was
  /// NOT changed". Rendered right below [_activeErrorBanner].
  _DurableBannerData? _durableBanner;

  /// Last state observed that carried a live ride (Requested / Matched /
  /// EnRoute / InProgress). A `RideError` emitted by the shared bloc does not
  /// itself say whether a trip is running, so the banner logic consults this
  /// to decide "stay and explain" vs. "leave quietly". Cleared when the ride
  /// genuinely ends (completed/cancelled) so a stale value can't keep a rider
  /// parked on a dead trip.
  RideState? _lastLiveRideState;

  /// Error codes this page itself provokes — retrying them from the banner is
  /// safe and meaningful. Anything else (history/rate/estimate failures from
  /// sibling screens sharing the same RideBloc) is shown as information only:
  /// the banner explains it but offers no Retry, because re-dispatching a
  /// foreign request from tracking would be dishonest about what happens next.
  static const Set<String> _retryableTrackingErrorCodes = {
    'LOAD_FAILED', // LoadRide (recheck / WS-gap refresh)
    'CANCEL_FAILED', // CancelRide (last dispatch always originates here)
  };

  /// True while the bloc holds a live ride worth staying on-screen for.
  static bool _hasActiveRide(RideState state) =>
      state is RideRequested ||
      state is DriverMatched ||
      state is DriverEnRoute ||
      state is RideInProgress;

  @override
  void initState() {
    super.initState();
    _rideBloc = context.read<RideBloc>();
    // During DriverEnRoute the plan says followUserLocation: true (camera
    // tracks the rider heading to the pin); during RideInProgress it flips to
    // false and the camera follows the driver marker instead. We default to
    // the in-trip behavior and adjust from state transitions in build.
    _rideBloc.add(SubscribeToRideUpdates(widget.rideId));

    // Phase 5: subscribe to the two truth channels the tracking banner reads.
    // Device connectivity comes from the bloc's OfflineService feed; the WS
    // link state comes from the shared socket client. Both start null-ish /
    // optimistic and only ever render when a real sample arrives — never a
    // guessed "offline" on first frame, never a fake "reconnected".
    _isOffline = _rideBloc.currentIsOffline;
    _offlineSub = _rideBloc.offlineChanges.listen((offline) {
      if (mounted) setState(() => _isOffline = offline);
    });
    try {
      final ws = getIt<WebSocketClient>();
      _wsState = ws.isConnected
          ? WebSocketConnectionState.connected
          : WebSocketConnectionState.connecting;
      _wsStateSub = ws.stateStream.listen((s) {
        if (mounted) setState(() => _wsState = s);
      });
    } on Object {
      // Socket unavailable (tests without DI): leave _wsState at connected so
      // no reconnecting banner can fabricate an outage.
    }
  }

  @override
  void dispose() {
    _offlineSub?.cancel();
    _wsStateSub?.cancel();
    _rideBloc.add(UnsubscribeFromRideUpdates(widget.rideId));
    super.dispose();
  }

  /// Commits a fresh WS fix, remembering the previous point so the marker can
  /// tween toward the new one over [_driverAnimationDuration] instead of
  /// teleporting. Call once per build when [target] differs from the last
  /// committed fix.
  void _commitDriverFix(LatLng target) {
    if (_committedDriverPoint == target) return;
    _previousDriverPoint = _committedDriverPoint ?? target;
    _committedDriverPoint = target;
  }

  /// Driver marker widget: a TweenAnimationBuilder interpolates between the
  /// previous and newest fixes and moves the map imperatively each frame
  /// (plan §1.1: smooth with a TweenAnimationBuilder over 800 ms).
  Widget _driverMarker(LatLng latest) {
    final start = _previousDriverPoint ?? latest;
    return TweenAnimationBuilder<LatLng>(
      key: ValueKey('driver-tween-$latest.latitude-$latest.longitude'),
      tween: Tween<LatLng>(begin: start, end: latest),
      duration: _driverAnimationDuration,
      curve: Curves.linear,
      builder: (context, interpolated, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mapKey.currentState?.moveTo(interpolated);
        });
        return const SizedBox.shrink();
      },
    );
  }

  LatLng? _driverTargetFrom(RideState state) {
    if (state is DriverMatched) {
      return LatLng(state.driver.currentLat, state.driver.currentLng);
    }
    if (state is DriverEnRoute) {
      return LatLng(state.driver.currentLat, state.driver.currentLng);
    }
    if (state is RideInProgress) {
      final d = state.ride.driver;
      if (d != null) return LatLng(d.currentLat, d.currentLng);
    }
    return null;
  }

  List<LatLng> _routePoints(RideState state) {
    final pickup = _pickupOf(state);
    final dropoff = _dropoffOf(state);
    final driver = _driverTargetFrom(state);
    if (pickup == null || dropoff == null) return const [];
    // Leg already travelled: pickup -> current driver position; remaining leg:
    // driver -> dropoff. Straight legs until OSRM routing is wired (§backend).
    if (driver == null) return [pickup, dropoff];
    return [pickup, driver, dropoff];
  }

  LatLng? _pickupOf(RideState state) {
    // §4.1: coordinates are carried on every pre-trip state (sourced from the
    // rider's own request payload / REST DTO — never fabricated). Null means
    // genuinely unavailable; surfaces then hide the AR entry instead of
    // navigating to a made-up pin.
    if (state is RideRequested) {
      final lat = state.pickupLat;
      final lng = state.pickupLng;
      if (lat != null && lng != null) return LatLng(lat, lng);
      return null;
    }
    if (state is DriverMatched) {
      final lat = state.pickupLat;
      final lng = state.pickupLng;
      if (lat != null && lng != null) return LatLng(lat, lng);
      return null;
    }
    if (state is DriverEnRoute) {
      final lat = state.pickupLat;
      final lng = state.pickupLng;
      if (lat != null && lng != null) return LatLng(lat, lng);
      return null;
    }
    if (state case final RideInProgress s) {
      return LatLng(s.ride.pickupLat, s.ride.pickupLng);
    }
    if (state case final RideCompleted s) {
      return LatLng(s.ride.pickupLat, s.ride.pickupLng);
    }
    return null;
  }

  LatLng? _dropoffOf(RideState state) {
    if (state is RideRequested) {
      final lat = state.dropoffLat;
      final lng = state.dropoffLng;
      if (lat != null && lng != null) return LatLng(lat, lng);
      return null;
    }
    if (state is DriverMatched) {
      final lat = state.dropoffLat;
      final lng = state.dropoffLng;
      if (lat != null && lng != null) return LatLng(lat, lng);
      return null;
    }
    if (state is DriverEnRoute) {
      final lat = state.dropoffLat;
      final lng = state.dropoffLng;
      if (lat != null && lng != null) return LatLng(lat, lng);
      return null;
    }
    if (state case final RideInProgress s) {
      return LatLng(s.ride.dropoffLat, s.ride.dropoffLng);
    }
    if (state case final RideCompleted s) {
      return LatLng(s.ride.dropoffLat, s.ride.dropoffLng);
    }
    return null;
  }

  /// §4.1: resolved pickup place name for the AR page header. Null means the
  /// label is genuinely unknown — the AR surface falls back to reverse
  /// geocoding or "Pickup point"; we never fabricate an address here.
  String? _pickupNameOf(RideState state) {
    if (state is RideRequested) return state.pickupName;
    if (state is DriverMatched) return state.pickupName;
    if (state is DriverEnRoute) return state.pickupName;
    return null;
  }

  // ─── Phase 6 (nav consistency): GoRouter entry points ────────────────────

  /// Chat now rides a real route (`/nidus/chat/:rideId`) instead of a raw
  /// MaterialPageRoute — deep-linkable, URL-synced, one convention. The bare
  /// path is safe here: this page only ever renders while mounted inside the
  /// /nidus shell branch of the router.
  void _openChat() => context.push('/nidus/chat/${widget.rideId}');

  /// Receipt rides `/nidus/receipt/:rideId`. We hand the completed [Ride]
  /// through `extra` (fast path — no re-fetch when tracking already holds
  /// it); cold deep links load it from the repository instead (see
  /// _ReceiptRoute in app_router.dart).
  void _openReceipt(Ride ride) => context.pushNamed(
        RouteNames.rideReceipt,
        pathParameters: {'rideId': ride.id},
        extra: ride,
      );

  /// Safety Toolkit via its GoRoute, passing the LIVE bloc through `extra`
  /// so the toolkit operates on the trip in progress instead of a fresh
  /// bloc that knows nothing about the ride (the route reuses it via
  /// BlocProvider.value; a deep link without `extra` still works).
  /// `_requireActiveRide` inside the toolkit keeps the old guardrail.
  void _openSafetyToolkit() =>
      context.pushNamed(RouteNames.safetyToolkit, extra: _rideBloc);

  /// Durable-outcome banner (Phase 6 error-surface rule): destructive or
  /// money-relevant failures persist until acknowledged instead of evaporating
  /// with a snackbar timer. Transient confirmations stay snackbars.
  void _showDurableBanner({
    required String title,
    required String body,
    String? detail,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    setState(() {
      _durableBanner = _DurableBannerData(
        title: title,
        body: body,
        detail: detail,
        actionLabel: actionLabel,
        onAction: onAction,
      );
    });
  }

  /// §4.1: opens the AR walk-to-pickup surface. Triple gate exactly mirrors
  /// the router's double gate (compile switch + runtime flag) plus the
  /// no-fabricated-coordinate rule: if either gate is off or the pickup
  /// coordinate is genuinely unknown, the button is not rendered at all
  /// (kill-switch semantics: flag off renders nothing, never a dead button).
  Future<void> _openArNavigation(RideState state) async {
    final pickup = _pickupOf(state);
    if (pickup == null) return;
    if (!mounted) return;
    final name = _pickupNameOf(state);
    final params = <String, String>{
      'lat': pickup.latitude.toStringAsFixed(6),
      'lng': pickup.longitude.toStringAsFixed(6),
    };
    if (name != null && name.isNotEmpty) params['name'] = name;
    // go_router 13.x context.push() has no queryParameters argument —
    // build the query string into the location manually.
    final uri = Uri.parse('/nidus/ar-nav/${widget.rideId}')
        .replace(queryParameters: params);
    context.push(uri.toString(), extra: null);
  }

  Future<void> _callDriver() async {
    try {
      await MaskedCallRepository().callRideParticipant(widget.rideId);
    } on MaskedCallException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masked calling is not available for this ride yet.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RideBloc, RideState>(
      listenWhen: (previous, current) => previous != current,
      listener: (context, state) {
        // §2.3 driver-side trigger: when THIS session enters DriverEnRoute
        // as the ride's driver, fire the pre-selfie capture step exactly
        // once per en-route phase (plan: "capture step that fires on
        // DriverEnRoute start"). The sheet itself offers retry on upload
        // failure and an explicit skip; skipping leaves the rider with the
        // honest "Driver did not send a selfie" state — never a fake image.
        if (state is DriverEnRouteForDriver) {
          if (!_preSelfieSheetShown) {
            _preSelfieSheetShown = true;
            PreSelfieCaptureSheet.show(context, rideId: state.rideId);
          }
        } else {
          _preSelfieSheetShown = false;
        }
        if (state is RideCompleted) {
          RateRideSheet.show(
            context,
            rideId: state.ride.id,
            fare: state.ride.fareAmount ?? 0,
            currency: state.ride.currency,
          );
        } else if (state is PaymentFailed) {
          PaymentFailureSheet.show(
            context,
            message: state.message,
            errorCode: state.errorCode,
            originalRequest: state.originalRequest,
          );
        } else if (state is NoDriversFound) {
          // §4.6 Price-extension: instead of popping back to the request
          // flow, offer a higher fare that re-broadcasts to drivers through
          // the existing matching engine. Gated on the price_extension flag;
          // when the flag is off (or unavailable) we keep the pre-§4.6
          // pop-back behavior so the kill switch restores exactly yesterday's
          // UX. The sheet itself never invents numbers: projections come from
          // state.currentFare when the bloc learned one, and every apply
          // failure defers to "New price will be confirmed on retry".
          if (_priceExtensionEnabled()) {
            _showPriceExtensionSheet(state);
          } else {
            Navigator.of(context).pop();
          }
        } else if (state is RideCancelled) {
          // Intentional exit: the ride really ended, so leaving tracking is
          // the truthful behavior. Clear any parked banner first so a stale
          // error never outlives the ride it referred to.
          _activeErrorBanner = null;
          Navigator.of(context).pop();
        } else if (state is RideError) {
          if (_hasActiveRide(_lastLiveRideState ?? state)) {
            // Phase 1 fix: NEVER eject the rider from an active trip without
            // an explanation. The old code popped on every non-CANCEL_FAILED
            // error, stranding users mid-ride when the shared bloc surfaced
            // an unrelated failure. Park the error and let the persistent
            // banner decide with the user (Stay / Leave / Retry).
            _activeErrorBanner = state;
          } else if (state.errorCode == 'CANCEL_FAILED') {
            // No live ride left to stay on, but the outcome is durable money
            // information (a cancellation that may have charged a fee), so it
            // gets the same persistent banner rather than a transient toast.
            _activeErrorBanner = state;
          } else {
            // No active ride AND the failure belongs to a flow this page
            // never triggered (e.g. a sibling screen's history/rate/estimate
            // request landing while tracking was mounted): say nothing and
            // leave quietly — that surface owns its own error UI. This
            // preserves the pre-Phase-1 pop for exactly the cases where the
            // rider was never mid-ride.
            Navigator.of(context).pop();
          }
        } else if (_activeErrorBanner != null && state is! RideInitial) {
          // Fresh non-error state arrived (reconnect succeeded, new WS fix):
          // retire the banner so it can't misrepresent the current situation.
          _activeErrorBanner = null;
        }
        if (state is RideRequested ||
            state is DriverMatched ||
            state is DriverEnRoute ||
            state is RideInProgress) {
          _lastLiveRideState = state;
        } else if (state is RideCompleted || state is RideCancelled) {
          _lastLiveRideState = null;
        }
        // §4.5 RideCheck: an anomaly detected by the bloc pauses the trip UI
        // with an "Is everything OK?" prompt. Shown once per anomaly id —
        // answering ("I'm OK" → snooze, "Call for help" → SOS countdown)
        // clears pendingAnomaly in the bloc; dismissing the barrier without
        // answering counts as "OK" so the detector can re-arm after its
        // grace window rather than nagging on every rebuild.
        final anomaly = _anomalyOf(state);
        if (anomaly != null && _shownAnomalyAt != anomaly.detectedAt) {
          _shownAnomalyAt = anomaly.detectedAt;
          _showRideCheckPrompt(context, anomaly);
        }
      },
      builder: (context, state) {
        final driverTarget = _driverTargetFrom(state);
        if (driverTarget != null) _commitDriverFix(driverTarget);
        final animated = driverTarget;
        final route = _routePoints(state);
        final inTrip = state is RideInProgress;

        // Camera policy per §1.1: follow rider while en route to pickup,
        // follow the driver marker during the trip. The FAB lets the rider
        // override either way.
        final followRider = !inTrip && !_followDriver;
        final cameraTarget = _followDriver
            ? animated
            : (_pickupOf(state) ?? animated);

        return Scaffold(
          body: Stack(
            children: [
              // Live OSM map (replaces the deleted placeholder MapWidget).
              Positioned.fill(
                child: LiveMapWidget(
                  key: _mapKey,
                  initialCenter: animated ??
                      _pickupOf(state) ??
                      _dropoffOf(state) ??
                      _cameraFallback,
                  initialZoom: 15.0,
                  interactionMode: MapInteractionMode.pan,
                  showRecenterFab: true,
                  followUserLocation: cameraTarget != null,
                  recenterTarget: cameraTarget,
                  markers: [
                    if (_pickupOf(state) != null)
                      MapMarkerModel(
                        id: 'pickup',
                        position: _pickupOf(state)!,
                        kind: MapMarkerKind.pickup,
                        label: 'Pickup',
                      ),
                    if (_dropoffOf(state) != null)
                      MapMarkerModel(
                        id: 'dropoff',
                        position: _dropoffOf(state)!,
                        kind: MapMarkerKind.dropoff,
                        label: 'Dropoff',
                      ),
                    if (animated != null)
                      MapMarkerModel(
                        id: 'driver',
                        position: _committedDriverPoint ?? animated,
                        kind: MapMarkerKind.driver,
                        label: 'Driver',
                      ),
                  ],
                  polylines: [
                    if (route.length >= 2)
                      MapPolylineModel(id: 'route', points: route),
                  ],
                  onCameraIdle: (_) {},
                ),
              ),

              // Invisible 800ms tween that animates the driver marker and
              // camera between successive WS fixes (§1.1).
              if (animated != null)
                Positioned(
                  left: 0,
                  top: 0,
                  width: 0,
                  height: 0,
                  child: _driverMarker(animated),
                ),

              // Follow toggle: driver vs rider (plan: "Recenter" FAB toggles).
              if (animated != null)
                Positioned(
                  right: 16,
                  bottom: 340,
                  child: FloatingActionButton.small(
                    heroTag: 'tracking-follow-toggle',
                    tooltip: _followDriver
                        ? 'Following driver — tap to follow me'
                        : 'Following you — tap to follow driver',
                    onPressed: () => setState(() => _followDriver = !_followDriver),
                    backgroundColor: AppColors.surface,
                    foregroundColor: AppColors.primary,
                    child: Icon(_followDriver
                        ? Icons.directions_car
                        : Icons.person_pin_circle),
                  ),
                ),

              // Back Button
              Positioned(
                top: 50,
                left: 16,
                child: Container(
                  decoration: BoxDecoration(
                    // §4.4: theme token instead of hardcoded white so dark
                    // mode renders correctly; no fixed height (dynamic type).
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back',
                    onPressed: () => _confirmCancel(context, state),
                  ),
                ),
              ),

              // Safety shield — regulator-required entry point, always
              // reachable while a trip is active.
              Positioned(
                top: 50,
                right: 16,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.shield, color: AppColors.error),
                    tooltip: 'Safety Toolkit',
                    onPressed: () => _openSafetyToolkit(),
                  ),
                ),
              ),

              if (followRider)
                Positioned(
                  top: 100,
                  left: 16,
                  child: _FollowingChip(label: 'Following you'),
                ),

              // Bottom Sheet
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    // §4.4: theme token (was hardcoded Colors.white) so the
                    // sheet adapts to dark mode.
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status Indicator
                      _buildStatusIndicator(state),

                      // §3.1 Cash badge — shown only when the backend says
                      // this ride is cash-paid. Three honest states, all
                      // server-sourced: awaiting collection (driver has not
                      // confirmed yet) vs collected at a real timestamp.
                      if (state is RideInProgress && state.ride.isCashRide) ...[
                        const SizedBox(height: 8),
                        _CashRideBadge(ride: state.ride),
                      ],

                      const SizedBox(height: 24),

                      // Driver Card (matched or en route)
                      if (state is DriverMatched) ...[
                        DriverCard(
                          driverName: state.driver.name,
                          rating: state.driver.rating,
                          carModel: state.driver.vehicleType,
                          plateNumber: state.driver.vehiclePlate,
                          eta: state.etaMinutes,
                          onCall: () => _callDriver(),
                          onChat: _openChat,
                        ),
                        const SizedBox(height: 16),
                      ] else if (state is DriverEnRoute) ...[
                        DriverCard(
                          driverName: state.driver.name,
                          rating: state.driver.rating,
                          carModel: state.driver.vehicleType,
                          plateNumber: state.driver.vehiclePlate,
                          eta: state.etaMinutes,
                          onCall: () => _callDriver(),
                          onChat: _openChat,
                        ),
                        const SizedBox(height: 12),
                        // §2.3 "Verify your driver" — one honest render per
                        // backend state; never a placeholder photo.
                        VerifyDriverCard(
                          preSelfie: state.preSelfie,
                          driverName: state.driver.name,
                          onRecheck: () =>
                              context.read<RideBloc>().add(LoadRide(widget.rideId)),
                          onContactDriver: _openChat,
                        ),
                        const SizedBox(height: 12),
                        _PinCodeCard(pinCode: state.pinCode),
                        const SizedBox(height: 16),

                        // §4.1 AR walk-to-pickup entry point. Visible only
                        // when (a) the compile switch is on, (b) the runtime
                        // `ar_navigation` flag bucket includes this install,
                        // and (c) the pickup coordinate is genuinely known.
                        // Any gate failing → the button is not rendered at
                        // all (kill-switch semantics; never a dead button,
                        // never a fabricated destination). The router applies
                        // the same double gate as a redirect fallback.
                        if (AppConstants.enableARNavigation &&
                            _pickupOf(state) != null) ...[
                          _ArNavigationButton(
                            rideState: state,
                            onTap: () => _openArNavigation(state),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],

                      // §3.5 "Change destination" — visible only during the
                      // trip itself and only when the ride_stopovers flag is
                      // on (kill-switch semantics: flag off renders nothing,
                      // never a dead button). The backend gate
                      // (CanChangeDestination) is authoritative; this UI
                      // merely mirrors it for the in_progress state.
                      if (state is RideInProgress &&
                          getIt<FeatureFlagService>()
                              .isEnabled('ride_stopovers')) ...[
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _changeDestinationBusy
                                ? null
                                : () => _startChangeDestination(context),
                            icon: _changeDestinationBusy
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.alt_route),
                            label: Text(_changeDestinationBusy
                                ? 'Updating destination…'
                                : 'Change destination'),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // FARE INTEGRITY Phase 2 — rider-approved stop charges.
                      // One card per stopover while the trip runs, behind the
                      // same ride_stopovers kill switch as the destination
                      // control (flag off ⇒ nothing renders, never a dead
                      // button). Every amount inside comes from the embedded
                      // GET /rides/{id} charge projection or the quote/approve
                      // endpoints — this page holds no fee math at all.
                      if (state is RideInProgress &&
                          state.ride.stops.isNotEmpty &&
                          getIt<FeatureFlagService>()
                              .isEnabled('ride_stopovers')) ...[
                        for (final stop in state.ride.stops) ...[
                          StopChargeCard(
                            rideId: widget.rideId,
                            stop: stop,
                            onChanged: () => context
                                .read<RideBloc>()
                                .add(LoadRide(widget.rideId)),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => ShareTripSheet.showInline(
                                context,
                                rideId: widget.rideId,
                              ),
                              icon: const Icon(Icons.share_location),
                              label: const Text('Share'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.error,
                                foregroundColor: AppColors.textOnDark,
                              ),
                              onPressed: () => _confirmCancel(context, state),
                              icon: const Icon(Icons.cancel_outlined),
                              label: const Text('Cancel'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Phase 1 (UI/UX remediation): persistent, explanatory error
              // banner. Replaces the old silent `Navigator.pop()` on any
              // non-CANCEL_FAILED RideError — a rider mid-trip is never
              // ejected without being told what happened and what to do.
              if (_activeErrorBanner != null)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).size.height * 0.32,
                  child: _buildActiveErrorBanner(context),
                ),

              // Phase 6 (error-surface consistency): durable failures raised
              // by page-local flows (destination change, price extension)
              // persist until acknowledged. Stacked directly above the
              // Phase-1 error banner so at most one message owns each band;
              // both are live-region announcements for screen readers.
              if (_durableBanner != null)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).size.height * 0.32 +
                      (_activeErrorBanner != null ? 190 : 0),
                  child: _buildDurableBanner(context),
                ),

              // Phase 5 (connectivity honesty): persistent "reconnecting…"
              // surface while a live ride is showing and either the device
              // verdict says offline or the ride socket dropped. Rendered
              // ABOVE the error banner so both can coexist truthfully (a
              // stale-data error during an outage is not contradictory).
              if (_hasLiveRideNow && (_isOffline == true || _wsIsDown))
                Positioned(
                  left: 16,
                  right: 16,
                  top: MediaQuery.of(context).padding.top + 96,
                  child: _buildReconnectingBanner(context),
                ),
            ],
          ),
        );
      },
    );
  }

  // ─── Phase 5: reconnecting / offline banner ───────────────────────────────

  /// True when the shared socket link is not currently carrying updates.
  /// `connecting` counts as down for messaging purposes ("updates paused")
  /// because no fixes are flowing either way; only `connected` clears it.
  bool get _wsIsDown => _wsState != WebSocketConnectionState.connected;

  /// Persistent, explanatory connectivity surface. Two honest variants:
  ///  * Device offline → "You're offline" — positions shown are last known,
  ///    SOS still works via SMS fallback (safety toolkit owns that proof).
  ///  * Device online but socket down → "Reconnecting…" — the radio works,
  ///    the live feed does not; say precisely that instead of blaming the
  ///    rider's network.
  /// Never renders while the connectivity verdict is unsettled AND the socket
  /// is fine (honest-null rule), and never auto-dismisses on a guess — it
  /// disappears only when a real sample says the link is back.
  Widget _buildReconnectingBanner(BuildContext context) {
    final l10n = context.l10n;
    final deviceOffline = _isOffline == true;

    return Material(
      color: AppColors.surface,
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: Semantics(
        liveRegion: true,
        label: deviceOffline
            ? l10n.trackingOfflineBannerA11y
            : l10n.trackingReconnectingBannerA11y,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(
                deviceOffline ? Icons.wifi_off : Icons.sync_problem,
                size: 20,
                color: AppColors.warning,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deviceOffline
                          ? l10n.trackingOfflineBannerTitle
                          : l10n.trackingReconnectingBannerTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      deviceOffline
                          ? l10n.trackingOfflineBannerBody
                          : l10n.trackingReconnectingBannerBody,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.trackingReconnectAction,
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () {
                  // Honest retry: re-pull the authoritative ride snapshot
                  // over REST. If the socket comes back the WS listener
                  // resumes on its own; the bloc's ConnectivityChanged feed
                  // clears this banner when a real sample arrives.
                  _rideBloc.add(LoadRide(widget.rideId));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Phase 1: persistent ride-error banner ──────────────────────────────

  /// Builds the persistent failure surface for page-local flows (Phase 6).
  /// Mirrors the Phase-1 error-banner anatomy — error icon, localized
  /// title/body, raw server text demoted to a detail line, live-region
  /// semantics — but adds an explicit dismiss affordance because these
  /// outcomes never block the map underneath. The action button re-runs the
  /// failed flow and clears the banner first, so a second failure simply
  /// re-parks a fresh banner rather than stacking duplicates.
  Widget _buildDurableBanner(BuildContext context) {
    final banner = _durableBanner!;
    final l10n = context.l10n;

    return Material(
      color: AppColors.surface,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: Semantics(
        liveRegion: true,
        label: '${banner.title}. ${banner.body}',
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppColors.error, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      banner.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.durableBannerDismissTooltip,
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => setState(() => _durableBanner = null),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                banner.body,
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
              if (banner.detail != null && banner.detail!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  banner.detail!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              if (banner.actionLabel != null && banner.onAction != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.textOnDark,
                    ),
                    onPressed: () {
                      final action = banner.onAction;
                      setState(() => _durableBanner = null);
                      action?.call();
                    },
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(banner.actionLabel!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the durable error surface parked by the listener. Two honest
  /// variants:
  ///  * Live-ride error → "Your trip is still active" + Stay / Leave
  ///    (+ Retry when this page can actually re-run the failed request).
  ///  * No live ride but durable money outcome (CANCEL_FAILED) → explains
  ///    the cancellation may carry a fee; primary action is Dismiss.
  /// Raw server text is demoted to a detail line under a localized primary
  /// message so the headline always speaks the rider's language.
  Widget _buildActiveErrorBanner(BuildContext context) {
    final error = _activeErrorBanner!;
    final l10n = context.l10n;
    final hasLiveRide = _hasActiveRide(_lastLiveRideState ?? error);
    final retryable =
        error.errorCode != null && _retryableTrackingErrorCodes.contains(error.errorCode);

    return Material(
      color: AppColors.surface,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: Semantics(
        liveRegion: true,
        label: hasLiveRide ? l10n.trackingErrorLiveRideA11y : l10n.trackingErrorDetailA11y,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppColors.error, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasLiveRide
                          ? l10n.trackingErrorLiveRideTitle
                          : l10n.trackingErrorGenericTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                hasLiveRide
                    ? l10n.trackingErrorLiveRideBody
                    : l10n.trackingErrorGenericBody,
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
              // Server message demoted to detail — useful for support, never
              // the headline (it is English-only and often not user-facing).
              if (error.message.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  error.message,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  if (retryable) ...[
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.textOnDark,
                        ),
                        onPressed: () {
                          setState(() => _activeErrorBanner = null);
                          _rideBloc.add(LoadRide(widget.rideId));
                        },
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(l10n.trackingErrorRetry),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (hasLiveRide) ...[
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                        ),
                        onPressed: () =>
                            setState(() => _activeErrorBanner = null),
                        child: Text(l10n.trackingErrorStay),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(l10n.trackingErrorLeave),
                      ),
                    ),
                  ] else ...[
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                        ),
                        onPressed: () =>
                            setState(() => _activeErrorBanner = null),
                        child: Text(l10n.trackingErrorDismiss),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── §4.5 RideCheck anomaly prompt ──────────────────────────────────────

  /// Extracts the pending anomaly from any wrapped ride state that carries
  /// one (RideRequested / DriverMatched / DriverEnRoute / RideInProgress).
  /// Other states have no anomaly channel and return null.
  RideAnomaly? _anomalyOf(RideState state) {
    if (state is RideRequested) return state.pendingAnomaly;
    if (state is DriverMatched) return state.pendingAnomaly;
    if (state is DriverEnRoute) return state.pendingAnomaly;
    if (state is RideInProgress) return state.pendingAnomaly;
    return null;
  }

  /// Honest, measurement-only detail line for the prompt. Meters and
  /// confidence are shown only when the detector actually measured them —
  /// never zeros, never fabricated precision. When a measurement is missing
  /// the ARB catalog's unmeasured variant is used; nothing is invented.
  String _anomalyDetail(BuildContext context, RideAnomaly anomaly) {
    final l10n = context.l10n;
    switch (anomaly.kind) {
      case RideAnomalyKind.longStop:
        return l10n.ridecheckBodyStopped;
      case RideAnomalyKind.routeDeviation:
        final meters = anomaly.detailMeters;
        if (meters == null) {
          return l10n.ridecheckBodyDeviationUnmeasured;
        }
        return l10n.ridecheckBodyDeviationMeasured(meters.round());
      case RideAnomalyKind.lowEtaConfidence:
        final c = anomaly.confidence;
        if (c == null) {
          return l10n.ridecheckBodyLowConfidenceUnmeasured;
        }
        return l10n.ridecheckBodyLowConfidence((c * 100).round());
    }
  }

  /// Modal "Is everything OK?" barrier. Two answers only:
  /// - "I'm OK" → DismissRideCheckPrompt.ok() (bloc snoozes the detector);
  /// - "Call for help" → real GPS read, then the existing SOS countdown
  ///   machinery. If GPS is unavailable we say so honestly and keep the SOS
  ///   entry reachable via the Safety Toolkit rather than firing a location
  ///  -less SOS or a fake coordinate.
  Future<void> _showRideCheckPrompt(
      BuildContext context, RideAnomaly anomaly) async {
    final bloc = context.read<RideBloc>();
    await showDialog<void>(
      context: context,
      barrierDismissible: true, // treated as "OK" below — never silent-drop
      builder: (dialogContext) {
        final l10n = dialogContext.l10n;
        return Semantics(
          label: 'RideCheck safety prompt',
          child: AlertDialog(
            icon: const Icon(Icons.error_outline, color: AppColors.accent),
            title: Text(l10n.ridecheckTitle),
            content: Text(_anomalyDetail(dialogContext, anomaly)),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  bloc.add(const DismissRideCheckPrompt.ok());
                },
                child: Text(l10n.ridecheckImOK),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                ),
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await _callForHelp(bloc);
                },
                icon: const Icon(Icons.emergency_share),
                label: Text(l10n.ridecheckCallForHelp),
              ),
            ],
          ),
        );
      },
    );
    // Barrier dismissed without pressing either button still counts as an
    // acknowledgement so the detector re-arms after its grace window.
    if (_anomalyOf(bloc.state) != null &&
        _anomalyOf(bloc.state)?.detectedAt == anomaly.detectedAt) {
      bloc.add(const DismissRideCheckPrompt.ok());
    }
  }

  /// "Call for help": read the rider's real position and hand it to the
  /// existing SOS countdown flow (StartSosCountdown → confirm/escalate in
  /// the bloc, already tested end-to-end by the Safety Toolkit path).
  Future<void> _callForHelp(RideBloc bloc) async {
    const locationService = DeviceLocationService();
    final result = await locationService.getCurrentPosition();
    final ctx = context;
    if (result is LocationGranted) {
      bloc.add(StartSosCountdown(
        rideId: widget.rideId,
        lat: result.latitude,
        lng: result.longitude,
        message: 'RideCheck: rider requested help during the trip.',
      ));
      if (ctx.mounted) {
        // Phase 1 §4: localized (was hardcoded English).
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(context.l10n.sosStartedCountdown)),
        );
      }
    } else if (ctx.mounted) {
      // Honest degradation: no fix → no fake SOS. Route the rider to the
      // Safety Toolkit where manual emergency flows live.
      final l10n = context.l10n;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(l10n.sosLocationUnavailable),
          action: SnackBarAction(
            label: l10n.openSafetyToolkit,
            onPressed: () => _openSafetyToolkit(),
          ),
        ),
      );
    }
  }

  // ─── §4.6 Price-extension on NoDriversFound ─────────────────────────────

  /// Runtime gate mirroring every other Phase-3 surface: flag service
  /// missing or flag off → false (kill-switch restores the old pop-back).
  ///
  /// Phase 6: synchronous by necessity — this is consulted inside a bloc
  /// listener during state emission, so it cannot await. It deliberately
  /// does NOT bucket by install id: `price_extension` gates a recovery
  /// affordance (a retry sheet), not an entry point with router-side twin
  /// logic, so there is nothing to desynchronize against. The rollout-bucket
  /// path stays reserved for ArNavigationGate.resolve(). When the cached
  /// install id happens to exist we pass it along; otherwise null means
  /// "evaluate unbucketed", never "guess".
  bool _priceExtensionEnabled() {
    try {
      return getIt<FeatureFlagService>().isEnabled('price_extension');
    } catch (_) {
      return false;
    }
  }

  /// Sheet replacing the old pop-back. Projections (+10% / +20%) are derived
  /// from the fare the bloc actually broadcast; when the bloc never learned
  /// a fare the rows show "unavailable" and defer every number to the
  /// server's response — Global Rule 2 forbids inventing one here.
  void _showPriceExtensionSheet(NoDriversFound state) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final fare = state.currentFare;
        final unit = state.currency ?? '';
        String projected(double multiplier) {
          if (fare == null) return 'Price calculated on apply';
          final value = fare * multiplier;
          final text = value.toStringAsFixed(value >= 100 ? 0 : 2);
          return unit.isEmpty ? '$text' : '$unit $text';
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sheetContext.l10n.trackingNoDriversTitle,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  fare == null
                      ? sheetContext.l10n.trackingPriceFareUnavailable
                      : sheetContext.l10n.trackingNoDriversFound(
                          unit.isEmpty
                              ? fare.toStringAsFixed(2)
                              : '$unit ${fare.toStringAsFixed(2)}'),
                ),
                const SizedBox(height: 20),
                _PriceExtensionOption(
                  label: sheetContext.l10n.trackingPriceExtensionPlus10,
                  projected: projected(1.10),
                  enabled: !_priceExtensionBusy,
                  onTap: () => _applyPriceExtension(state.rideId, 1.10),
                ),
                const SizedBox(height: 12),
                _PriceExtensionOption(
                  label: sheetContext.l10n.trackingPriceExtensionPlus20,
                  projected: projected(1.20),
                  enabled: !_priceExtensionBusy,
                  onTap: () => _applyPriceExtension(state.rideId, 1.20),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: Text(sheetContext.l10n.trackingPriceExtensionKeep),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// POSTs the chosen multiplier. Success → toast with the SERVER-returned
  /// new fare and re-subscribe so tracking resumes on the re-broadcast ride.
  /// RIDE_NOT_EXTENSIBLE (a driver matched mid-tap) → honest "driver found"
  /// message, no extension claimed. Any other failure → "New price will be
  /// confirmed on retry"; the sheet stays open for another attempt.
  Future<void> _applyPriceExtension(String rideId, double multiplier) async {
    if (_priceExtensionBusy) return;
    setState(() => _priceExtensionBusy = true);
    PriceExtensionResult? outcome;
    try {
      outcome =
          await getIt<RideRepository>().applyPriceExtension(
        rideId,
        multiplier: multiplier,
      );
    } catch (_) {
      outcome = null; // network layer threw — treat as unconfirmed failure
    }
    if (!mounted) return;
    setState(() => _priceExtensionBusy = false);

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final bloc = context.read<RideBloc>();

    if (outcome != null && outcome.success) {
      navigator.pop(); // close the sheet
      final amount = outcome.newFare.toStringAsFixed(
          outcome.newFare >= 100 ? 0 : 2);
      messenger.showSnackBar(SnackBar(
        content: Text('Request re-broadcast at '
            '${outcome.currency} $amount. Still searching for drivers…'),
      ));
      bloc.add(SubscribeToRideUpdates(rideId));
      return;
    }

    if (outcome != null && outcome.rideNotExtensible) {
      navigator.pop();
      messenger.showSnackBar(const SnackBar(
        content: Text('A driver was found while you were deciding — '
            'your original fare stands.'),
      ));
      bloc.add(LoadRide(rideId));
      return;
    }

    // Failure (or exception): never claim a price. Phase 6: this is a
    // durable, money-relevant outcome ("your fare was NOT raised"), so it
    // lands in the persistent banner with an explicit Retry instead of a
    // timer-bound snackbar the rider can miss. The sheet stays open too —
    // both surfaces speak the same localized copy. `mounted` was verified
    // above, so context.l10n is safe here.
    final l10n = context.l10n;
    _showDurableBanner(
      title: l10n.priceExtendFailedTitle,
      body: l10n.priceExtendFailedBody,
      actionLabel: l10n.commonRetry,
      onAction: () => _applyPriceExtension(rideId, multiplier),
    );
  }


  // ─── §3.5 Mid-trip destination change ──────────────────────────────────

  final GeocodingService _geocoding = getIt<GeocodingService>();

  /// Guards against double-taps while the PATCH is in flight.
  bool _changeDestinationBusy = false;

  Future<void> _startChangeDestination(BuildContext context) async {
    // 1. Pick the new place through the same §1.3 autocomplete surface used
    //    at request time (provider chain, cache degradation, honest empty
    //    states all reused — no second search implementation).
    final ride = _currentRide(context);
    final bias = ride != null
        ? LatLng(ride.pickupLat, ride.pickupLng)
        : null;
    final outcome = await PlaceAutocompleteSheet.show(
      context,
      geocoding: _geocoding,
      title: 'New destination',
      bias: bias,
    );
    if (!mounted) return;
    if (outcome.kind != PlaceAutocompleteOutcomeKind.suggestion) return;
    final suggestion = outcome.suggestion!;

    // 2. Confirmation sheet BEFORE the PATCH. We cannot know the new fare
    //    without calling the server (the server owns pricing per Global
    //    Rule 2), so the sheet honestly says the fare will be recomputed
    //    and shows where the change lands — never an invented number.
    final address = suggestion.detail.isEmpty
        ? suggestion.name
        : '${suggestion.name}, ${suggestion.detail}';
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Change destination?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New destination:\n$address'),
            const SizedBox(height: 12),
            const Text(
              'Your fare will be recalculated by Nidus for the new route. '
              'The updated price is shown right after you confirm.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Keep current destination'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Change destination'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    setState(() => _changeDestinationBusy = true);
    try {
      final result = await getIt<RideRepository>().changeDestination(
        rideId: widget.rideId,
        dropoffLat: suggestion.location.latitude,
        dropoffLng: suggestion.location.longitude,
        dropoffAddress: address,
      );
      if (!mounted) return;
      setState(() => _changeDestinationBusy = false);

      if (result.isSuccess) {
        // Money lines come from the SERVER response only — previous fare →
        // new fare, exactly what the rider will pay.
        final messenger = ScaffoldMessenger.of(context);
        context.read<RideBloc>().add(LoadRide(widget.rideId));
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Destination updated. Fare ${_formatFare(result.previousFare, result.currency)} → '
              '${_formatFare(result.newFare, result.currency)}',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // The repository converts transport/auth failures into typed
      // DestinationChangeResult.failure values (never throws), so every
      // outcome below carries a server error code or an honest local one.
      switch (result.errorCode) {
        case 'DESTINATION_NOT_CHANGEABLE':
        case 'INVALID_TRANSITION':
        case 'RIDE_NOT_CHANGEABLE':
          // State race: the ride moved on (completed/cancelled) between the
          // confirmation tap and the PATCH. Re-fetch so the UI reflects the
          // truth and explain — do not retry blindly.
          final messenger = ScaffoldMessenger.of(context);
          context.read<RideBloc>().add(LoadRide(widget.rideId));
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                result.error ??
                    'The ride status changed before the update could apply. '
                        'Destination can no longer be changed.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        case 'FORBIDDEN':
        case 'UNAUTHORIZED':
        case 'NOT_FOUND':
          // Ownership or existence problem — surfaced plainly; caller-level
          // navigation handles it, we just inform and stop. No retry loop.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.error ??
                    'This ride can\'t be updated from this device.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        default:
          // Everything else (network, 5xx, malformed response): honest
          // retry affordance, never a silent success or a locally-estimated
          // fare. Phase 6: localized copy — the dialog stays (it is an
          // explicit stay-or-retry decision, not a timer surface), but its
          // strings now come from ARB like every other durable outcome.
          final l10n = context.l10n;
          final retry = await showDialog<bool>(
            context: context,
            builder: (dialogCtx) => AlertDialog(
              title: Text(l10n.destUpdateFailedTitle),
              content: Text(
                result.error ?? l10n.destUpdateFailedBody,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(false),
                  child: Text(l10n.destUpdateKeepAction),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(true),
                  child: Text(l10n.commonRetry),
                ),
              ],
            ),
          );
          if (retry == true && mounted) {
            await _submitChangeDestination(address, suggestion.location);
          }
      }
    } catch (e) {
      // Defensive: the repository contract says it never throws, but a
      // serialization bug must not strand the button in "busy" state.
      // Phase 6: durable outcome ("your destination was NOT changed") →
      // persistent banner with Retry, not a timer-bound snackbar.
      if (!mounted) return;
      setState(() => _changeDestinationBusy = false);
      debugPrint('Unexpected changeDestination throw: $e');
      final l10n = context.l10n;
      _showDurableBanner(
        title: l10n.destUpdateFailedTitle,
        body: l10n.destUpdateUnreachableBody,
        actionLabel: l10n.commonRetry,
        onAction: () => _submitChangeDestination(address, suggestion.location),
      );
    }
  }

  /// Retry path re-sends the already-confirmed selection (no re-picking).
  Future<void> _submitChangeDestination(
    String address,
    LatLng location,
  ) async {
    setState(() => _changeDestinationBusy = true);
    try {
      final result = await getIt<RideRepository>().changeDestination(
        rideId: widget.rideId,
        dropoffLat: location.latitude,
        dropoffLng: location.longitude,
        dropoffAddress: address,
      );
      if (!mounted) return;
      setState(() => _changeDestinationBusy = false);
      final messenger = ScaffoldMessenger.of(context);
      if (result.isSuccess) {
        context.read<RideBloc>().add(LoadRide(widget.rideId));
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Destination updated. Fare ${_formatFare(result.previousFare, result.currency)} → '
              '${_formatFare(result.newFare, result.currency)}',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        // Phase 6: retry-path failure is durable ("your destination was
        // still NOT changed") — persistent banner with another Retry; the
        // raw server error is demoted to the detail line per Phase-1 copy
        // rules.
        final l10n = context.l10n;
        _showDurableBanner(
          title: l10n.destUpdateFailedTitle,
          body: l10n.destUpdateFailedBody,
          detail: result.error,
          actionLabel: l10n.commonRetry,
          onAction: () => _submitChangeDestination(address, location),
        );
      }
    } catch (_) {
      // Phase 6: "Still unreachable" was the audit's headline example of a
      // durable outcome evaporating with a snackbar timer. Banner instead.
      if (!mounted) return;
      setState(() => _changeDestinationBusy = false);
      final l10n = context.l10n;
      _showDurableBanner(
        title: l10n.destUpdateFailedTitle,
        body: l10n.destUpdateUnreachableBody,
        actionLabel: l10n.commonRetry,
        onAction: () => _submitChangeDestination(address, location),
      );
    }
  }

  /// Best-effort read of the bloc's current ride for map bias; null-safe.
  Ride? _currentRide(BuildContext context) {
    final state = context.read<RideBloc>().state;
    if (state is RideInProgress) return state.ride;
    return null;
  }

  String _formatFare(double? amount, String? currency) {
    if (amount == null) return 'unavailable';
    final unit = currency ?? 'ETB';
    return '$unit ${amount.toStringAsFixed(2)}';
  }

  Future<void> _confirmCancel(BuildContext context, RideState state) async {
    final bloc = context.read<RideBloc>();

    // §2.5: the fee, reason code and free-window countdown are fetched from
    // GET /rides/{id}/cancellation-quote inside the sheet itself — computed
    // by the same backend policy service that charges the fee on cancel. No
    // client-side heuristic exists in this flow anymore.
    await CancelRideSheet.show(
      context,
      rideId: widget.rideId,
      onConfirmed: (reason) async {
        bloc.add(CancelRide(rideId: widget.rideId, reason: reason));
      },
    );
  }

  Widget _buildStatusIndicator(RideState state) {
    String statusText;
    Color statusColor;

    if (state is RideRequested) {
      statusText = 'Finding your driver...';
      statusColor = AppColors.warning;
    } else if (state is DriverEnRoute) {
      statusText = 'Your driver is arriving in ${state.etaMinutes} min';
      statusColor = AppColors.primary;
    } else if (state is DriverMatched) {
      statusText = 'Driver is on the way';
      statusColor = AppColors.success;
    } else if (state is RideInProgress) {
      statusText = 'On trip';
      statusColor = AppColors.success;
    } else if (state is RideCompleted) {
      statusText = 'Trip complete';
      statusColor = AppColors.success;
    } else if (state is RideCancelled) {
      statusText = state.wasDriverCancelled
          ? 'Driver cancelled — no fee charged'
          : 'Ride cancelled';
      statusColor = AppColors.error;
    } else if (state is NoDriversFound) {
      statusText = 'No drivers available nearby';
      statusColor = AppColors.warning;
    } else if (state is PaymentFailed) {
      statusText = 'Payment issue — resolve to continue';
      statusColor = AppColors.error;
    } else {
      statusText = 'Preparing your ride';
      statusColor = AppColors.info;
    }

    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: statusColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            statusText,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
        ),
        if (state is RideCompleted)
          TextButton(
            onPressed: () => _openReceipt(state.ride),
            child: const Text('Receipt'),
          ),
      ],
    );
  }
}

class _FollowingChip extends StatelessWidget {
  final String label;

  const _FollowingChip({required this.label});

  @override
  Widget build(BuildContext context) {
    // §4.4: on-color comes from the theme (colorScheme.onPrimary) instead of
    // a hardcoded Colors.white, and there is no fixed height so large text
    // scales are never clipped.
    final onColor = Theme.of(context).colorScheme.onPrimary;
    return Material(
      color: AppColors.primary.withOpacity(0.9),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Semantics(
          label: label,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.gps_fixed, color: onColor, size: 14),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(color: onColor, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// §3.1 Cash-ride badge for the tracking sheet. Every state is derived from
/// server fields only — `payment_method_type`, `cash_collected_at` — never a
/// fabricated amount or status. When collection is pending the rider sees the
/// honest "collect at drop-off" note; once the driver confirms, the real
/// collected timestamp is rendered.
class _CashRideBadge extends StatelessWidget {
  final Ride ride;

  const _CashRideBadge({required this.ride});

  @override
  Widget build(BuildContext context) {
    final collected = ride.cashCollectedAt;
    final pending = ride.pendingCashCollection ?? collected == null;
    final icon = collected != null
        ? Icons.receipt_long
        : (pending ? Icons.payments_outlined : Icons.hourglass_empty);
    final label = collected != null
        ? 'Cash collected ${_formatCollected(collected)}'
        : 'Cash ride — pay the driver at drop-off';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.accentLight.withOpacity(0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.accentDark),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCollected(DateTime value) {
    final local = value.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return 'at $h:$m';
  }
}

/// Anti-impersonation card: the rider shares this PIN with the driver at
/// pickup; the driver must enter it before the trip can start.
class _PinCodeCard extends StatelessWidget {
  final String pinCode;

  const _PinCodeCard({required this.pinCode});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary),
      ),
      child: Column(
        children: [
          const Text(
            'Share this PIN with your driver',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            pinCode,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: 8,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// §4.1 "Walk to pickup (AR)" entry button on the Tracking page.
///
/// The runtime `ar_navigation` flag is evaluated asynchronously against the
/// per-install rollout bucket (FeatureFlagService.isEnabled takes an optional
/// deviceId; a partial rollout without one resolves conservatively to false).
/// A FutureBuilder keeps that evaluation inside the widget so the surrounding
/// bottom sheet never blocks on Hive while still honoring the same bucketing
/// the router gate uses — if this widget and the router disagree, the router
/// redirect to tracking is the authoritative fallback.
class _ArNavigationButton extends StatefulWidget {
  final RideState rideState;
  final VoidCallback onTap;

  const _ArNavigationButton({
    required this.rideState,
    required this.onTap,
  });

  @override
  State<_ArNavigationButton> createState() => _ArNavigationButtonState();
}

class _ArNavigationButtonState extends State<_ArNavigationButton> {
  late Future<bool> _flagFuture;

  @override
  void initState() {
    super.initState();
    _flagFuture = _resolveFlag();
  }

  Future<bool> _resolveFlag() => ArNavigationGate.resolve();
  // Phase 6: the body that used to live here re-read the Hive 'settings'
  // box inline and skipped the compile switch — a hand-copied twin of the
  // router's redirect. Both call sites now resolve through
  // ArNavigationGate.resolve(), so button visibility and route guard can no
  // longer desynchronize. Fail-closed semantics preserved (gate returns
  // false when GetIt/flag service/Hive are unavailable).

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _flagFuture,
      builder: (context, snapshot) {
        // While resolving, render nothing rather than a button that might
        // flicker away after tap. Once resolved false, stay hidden.
        if (snapshot.data != true) return const SizedBox.shrink();
        return Semantics(
          button: true,
          label: context.l10n.accessibilityWalkAr,
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.onTap,
              icon: const Icon(Icons.accessibility_new),
              label: Text(context.l10n.trackingWalkToPickupAr),
            ),
          ),
        );
      },
    );
  }
}

/// §4.6: one tappable row in the price-extension sheet. Shows the option
/// label and the projected fare (or the honest "calculated on apply" text
/// when the bloc never learned a real fare). Disabled while any extension
/// POST is in flight so double-taps cannot broadcast twice.
class _PriceExtensionOption extends StatelessWidget {
  final String label;
  final String projected;
  final bool enabled;
  final VoidCallback onTap;

  const _PriceExtensionOption({
    required this.label,
    required this.projected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label — new fare $projected',
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          alignment: Alignment.centerLeft,
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        onPressed: enabled ? onTap : null,
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text(
              projected,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (!enabled) ...[
              const SizedBox(width: 12),
              const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Immutable backing data for the page-local durable-outcome banner
/// (Phase 6 error-surface rule). Parked via `_showDurableBanner`, rendered by
/// `_buildDurableBanner`, and cleared on dismiss or after its action runs.
/// Destructive or money-relevant failures use this surface instead of a
/// timer-based snackbar so the outcome persists until acknowledged.
class _DurableBannerData {
  const _DurableBannerData({
    required this.title,
    required this.body,
    this.detail,
    this.actionLabel,
    this.onAction,
  });

  /// Localized headline (primary, rider's language).
  final String title;

  /// Localized explanation of what failed and what it means for the rider.
  final String body;

  /// Raw server message, demoted to a secondary detail line — never primary.
  final String? detail;

  /// Label for the recovery action (e.g. Retry). Null → no action button.
  final String? actionLabel;

  /// Callback invoked after the banner is cleared. Null → no action button.
  final VoidCallback? onAction;
}
