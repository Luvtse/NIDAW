import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'map_health.dart';
import 'map_tile_provider.dart';
import '../startup/app_startup_coordinator.dart'
    show hasStartupCoordinator, currentStartupCoordinator;

/// Marker kinds understood by [LiveMapWidget]. Each kind renders with a
/// distinct, safety-relevant visual; unknown callers should use [customPin].
enum MapMarkerKind { pickup, dropoff, driver, user, customPin, waypoint }

/// Immutable marker description passed to [LiveMapWidget].
class MapMarkerModel {
  final String id;
  final LatLng position;
  final MapMarkerKind kind;
  final String? label;

  /// Optional avatar/photo for the driver marker (rendered inside the pin).
  final ImageProvider? avatar;

  const MapMarkerModel({
    required this.id,
    required this.position,
    required this.kind,
    this.label,
    this.avatar,
  });

  MapMarkerModel copyWith({LatLng? position, String? label}) => MapMarkerModel(
        id: id,
        position: position ?? this.position,
        kind: kind,
        label: label ?? this.label,
        avatar: avatar,
      );
}

/// Immutable polyline description passed to [LiveMapWidget].
class MapPolylineModel {
  final String id;
  final List<LatLng> points;
  final Color color;
  final double width;

  const MapPolylineModel({
    required this.id,
    required this.points,
    this.color = const Color(0xFF1A73E8),
    this.width = 5.0,
  });
}

/// How the user may manipulate the map.
enum MapInteractionMode {
  /// Camera is fully locked; no gestures at all.
  none,

  /// Pan only — zoom and rotate disabled.
  pan,

  /// Everything enabled.
  full,
}

/// A flutter_map [TileProvider] that routes every tile request through the
/// mandated [MapTileProvider] fallback chain (primary → secondary → Hive
/// cache → last-known-good). Failures never throw into flutter_map's loader;
/// they surface via [MapTileProvider.health].
class ChainTileProvider extends TileProvider {
  final MapTileProvider provider;

  ChainTileProvider(this.provider);

  @override
  Future<Uint8List?> getUrlWithRetry(
    String url,
    int retries,
    Duration retryInterval,
  ) async {
    final coords = _coordsFromUrl(url);
    if (coords == null) return super.getUrlWithRetry(url, retries, retryInterval);
    return provider.getTile(coords);
  }

  static TileCoords? _coordsFromUrl(String url) {
    final match = RegExp(r'/(\d+)/(\d+)/(\d+)').firstMatch(url);
    if (match == null) return null;
    return TileCoords(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }
}

/// The single, live, OSM-backed map used by both Request and Tracking
/// (replaces the old google_maps_flutter orphan and the placeholder stub).
class LiveMapWidget extends StatefulWidget {
  final LatLng initialCenter;
  final double initialZoom;
  final List<MapMarkerModel> markers;
  final List<MapPolylineModel> polylines;
  final ValueChanged<LatLng>? onCameraIdle;
  final MapInteractionMode interactionMode;
  final bool showRecenterFab;
  final bool followUserLocation;

  /// Phase 5 (§5.1 progressive map mounting): when true, the interactive
  /// flutter_map engine is NOT built in the first frame of this widget. A
  /// lightweight placeholder (last-known camera background + explicit
  /// "preparing map" state) paints instead, and the real engine mounts one
  /// frame later via [SchedulerFlags.hasJankEnforcement]-free post-frame
  /// scheduling. Callers use this for cold-start paths so the home shell's
  /// first frame never pays the tile-engine + raster-cache construction
  /// cost. Screens that must show the map immediately (active trip) leave
  /// it false.
  final bool deferEngineMount;

  /// Fired exactly once when the LIVE engine has mounted and its controller
  /// is usable. A cached placeholder NEVER fires this — a fast placeholder
  /// must not be counted as an initialized interactive map (Part 10).
  final VoidCallback? onLiveMapReady;

  /// Where the recenter FAB should move the camera when tapped. Consumers set
  /// this to the rider position or the driver position depending on phase.
  final LatLng? recenterTarget;

  /// Called when the user long-press-drags the pickup pin. The widget shows a
  /// live drag preview; consumers commit the final position here.
  final ValueChanged<LatLng>? onPickupPinDragged;

  /// Shared tile provider (one per app session is enough; its health stream is
  /// global). When null a private default-chain provider is created.
  final MapTileProvider? tileProvider;

  /// Imperative access: pass a `GlobalKey<LiveMapWidgetState>` here and call
  /// `key.currentState?.moveTo(...)` / `.fitBounds(...)` from the caller for
  /// driver animation and route-fit.
  final Key? mapKey;

  const LiveMapWidget({
    super.key,
    required this.initialCenter,
    this.initialZoom = 15.0,
    this.markers = const [],
    this.polylines = const [],
    this.onCameraIdle,
    this.interactionMode = MapInteractionMode.full,
    this.showRecenterFab = false,
    this.followUserLocation = false,
    this.deferEngineMount = false,
    this.onLiveMapReady,
    this.recenterTarget,
    this.onPickupPinDragged,
    this.tileProvider,
    this.mapKey,
  });

  @override
  State<LiveMapWidget> createState() => LiveMapWidgetState();
}

class LiveMapWidgetState extends State<LiveMapWidget> {
  final MapController _mapController = MapController();
  late final MapTileProvider _provider;
  final bool _ownsProvider;

  StreamSubscription<MapHealth>? _healthSub;
  MapHealth? _lastHealth;

  // Phase 5 (§5.1): progressive engine mount state. `_engineMounted` is the
  // single gate for whether the live flutter_map tree exists yet; the map-
  // ready milestone fires exactly once, only from the LIVE engine's first
  // post-mount frame — never from the placeholder.
  bool _engineMounted = true;
  bool _liveReadyFired = false;

  LatLng? _dragPreview;
  bool _dragging = false;

  LiveMapWidgetState() : _ownsProvider = true;

  @override
  void initState() {
    super.initState();
    _engineMounted = !widget.deferEngineMount;
    if (widget.tileProvider != null) {
      _provider = widget.tileProvider!;
    } else {
      _provider = MapTileProvider.defaultChain();
    }
    _healthSub = _provider.health.listen((h) {
      if (mounted) setState(() => _lastHealth = h);
    });
    if (widget.deferEngineMount) {
      // Mount the real engine right after this (placeholder) frame paints.
      // One-frame deferral is enough to keep the shell's first frame cheap;
      // no artificial timers — readiness drives the rest, not wall clock.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _engineMounted = true);
      });
    }
  }

  /// Called by the live FlutterMap subtree once its controller is usable.
  void _notifyLiveMapReadyOnce() {
    if (_liveReadyFired) return;
    _liveReadyFired = true;
    widget.onLiveMapReady?.call();
    // Startup instrumentation: only a REAL mounted engine counts as map
    // ready (§5.1/Part 10: cached placeholder must not be counted).
    if (hasStartupCoordinator) {
      currentStartupCoordinator.perf.markMapReady();
    }
  }

  @override
  void didUpdateWidget(covariant LiveMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.followUserLocation &&
        widget.recenterTarget != null &&
        widget.recenterTarget != oldWidget.recenterTarget) {
      _moveTo(widget.recenterTarget!);
    }
  }

  @override
  void dispose() {
    _healthSub?.cancel();
    if (_ownsProvider) _provider.dispose();
    super.dispose();
  }

  /// Imperative camera move exposed for callers holding the state
  /// (driver animation, route fit).
  void moveTo(LatLng point, {double? zoom}) {
    _moveTo(point, zoom: zoom);
  }

  /// Fit the camera to include [points], padding the viewport by [paddingDp]
  /// on every side (default 80 top/bottom per the plan).
  void fitBounds(List<LatLng> points, {double paddingDp = 80.0}) {
    if (points.isEmpty) return;
    try {
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: points,
          padding: EdgeInsets.all(paddingDp),
        ),
      );
    } catch (e) {
      debugPrint('LiveMapWidget: fitBounds failed: $e');
    }
  }

  void _moveTo(LatLng point, {double? zoom}) {
    try {
      _mapController.move(point, zoom ?? _mapCameraZoom());
    } catch (e) {
      debugPrint('LiveMapWidget: move failed: $e');
    }
  }

  double _mapCameraZoom() {
    try {
      return _mapController.camera.zoom;
    } catch (_) {
      return widget.initialZoom;
    }
  }

  @override
  Widget build(BuildContext context) {
    final flags = switch (widget.interactionMode) {
      MapInteractionMode.none => const MapOptions(
          interactionOptions:
              InteractionOptions(flags: InteractiveFlag.none),
        ),
      MapInteractionMode.pan => const MapOptions(
          interactionOptions:
              InteractionOptions(flags: InteractiveFlag.drag),
        ),
      MapInteractionMode.full => const MapOptions(
          interactionOptions: InteractionOptions(
            flags: InteractiveFlag.drag |
                InteractiveFlag.flingAnimation |
                InteractiveFlag.pinchMove |
                InteractiveFlag.pinchZoom |
                InteractiveFlag.doubleTapZoom,
          ),
        ),
    };

    final options = flags.copyWith(
      initialCenter: widget.initialCenter,
      initialZoom: widget.initialZoom,
      minZoom: 3,
      maxZoom: 19,
      onMapEvent: (event) {
        if (event.source == MapEventSource.mapController) return;
        if (event is MapEventWithMove &&
            (event.source == MapEventSource.dragEnd ||
                event.source == MapEventSource.pinchZoom ||
                event.source == MapEventSource.doubleTap)) {
          widget.onCameraIdle?.call(event.center);
        }
      },
    );

    return Stack(
      children: [
        // §5.1 progressive mounting: until the deferral window closes we
        // paint a cheap, HONEST placeholder instead of constructing the
        // tile engine. It is visibly distinct from the live map ("Preparing
        // map…" + grid pattern) and never claims driver presence.
        if (!_engineMounted)
          _MapPlaceholder(center: widget.initialCenter)
        else
          FlutterMap(
            mapController: _mapController,
            options: options,
            children: [
              TileLayer(
                urlTemplate: _provider.mirrors.isEmpty
                    ? 'https://tiles.invalid/{z}/{x}/{y}.png'
                    : _provider.mirrors.first.urlTemplate,
                userAgentPackageName: 'com.nidaw.nidus',
                maxZoom: 19,
                tileProvider: ChainTileProvider(_provider),
                errorTileCallback: (tile, exception, stackTrace) {
                  // Errors are already reported through MapTileProvider.health;
                  // swallow here so flutter_map renders the blank/error tile.
                },
              ),
              if (widget.polylines.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    for (final p in widget.polylines)
                      Polyline(
                        points: p.points,
                        color: p.color,
                        strokeWidth: p.width,
                      ),
                  ],
                ),
              MarkerLayer(markers: _buildMarkers()),
              // Live-engine readiness detector: this child only exists inside
              // the real FlutterMap tree, so its first painted frame proves
              // the engine mounted (placeholder frames can never fire it).
              const _LiveMapReadyNotifier(),
            ],
          ),
        Positioned(
          left: 8,
          bottom: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.88),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              child: Text(
                '© OpenStreetMap contributors',
                style: TextStyle(fontSize: 10),
              ),
            ),
          ),
        ),
        if (widget.showRecenterFab)
          Positioned(
            right: 16,
            bottom: 24,
            child: FloatingActionButton.small(
              heroTag: 'live-map-recenter',
              onPressed: () {
                final target = widget.recenterTarget;
                if (target != null) _moveTo(target);
              },
              child: const Icon(Icons.my_location),
            ),
          ),
        if (_lastHealth != null && _lastHealth!.isFullyBroken)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: MapHealthBanner(
              health: _lastHealth!,
              onRetry: () {
                _provider.rePrime();
                _mapController.reloadTiles();
              },
            ),
          ),
      ],
    );
  }

  List<Marker> _buildMarkers() {
    final result = <Marker>[];
    for (final m in widget.markers) {
      final isPickup = m.kind == MapMarkerKind.pickup;
      final position = isPickup && _dragging && _dragPreview != null
          ? _dragPreview!
          : m.position;
      result.add(
        Marker(
          markerId: MarkerId(m.id),
          point: position,
          width: 48,
          height: 64,
          child: isPickup
              ? _DraggablePickupPin(
                  marker: m,
                  onDragUpdate: (globalPosition) {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    final local = box.globalToLocal(globalPosition);
                    final latLng = _mapController.camera.pointToLatLng(
                      local,
                      _mapCameraZoom(),
                    );
                    setState(() {
                      _dragging = true;
                      _dragPreview = latLng;
                    });
                  },
                  onDragEnd: () {
                    final preview = _dragPreview;
                    setState(() {
                      _dragging = false;
                      _dragPreview = null;
                    });
                    if (preview != null) {
                      widget.onPickupPinDragged?.call(preview);
                    }
                  },
                )
              : _pinFor(m),
        ),
      );
    }
    return result;
  }

  Widget _pinFor(MapMarkerModel m) {
    final color = switch (m.kind) {
      MapMarkerKind.dropoff => const Color(0xFFE53935),
      MapMarkerKind.driver => const Color(0xFF1A73E8),
      MapMarkerKind.user => const Color(0xFF00897B),
      // §3.5 intermediate stops render amber so they are visually distinct
      // from both the green pickup and the red dropoff pins.
      MapMarkerKind.waypoint => const Color(0xFFF9A825),
      _ => const Color(0xFF43A047),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
          ),
          child: m.kind == MapMarkerKind.driver && m.avatar != null
              ? ClipOval(child: Image(image: m.avatar!, fit: BoxFit.cover))
              : Icon(
                  switch (m.kind) {
                    MapMarkerKind.driver => Icons.directions_car,
                    MapMarkerKind.user => Icons.person,
                    _ => Icons.place,
                  },
                  color: Colors.white,
                  size: 18,
                ),
        ),
        if (m.label != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              m.label!,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}

/// §5.1 progressive mounting: cheap placeholder painted while the live
/// flutter_map engine has not mounted yet. It is VISIBLY distinct from a
/// real map (flat grid pattern + explicit "Preparing map…" label) and never
/// shows vehicles, routes or driver positions — it cannot be mistaken for
/// current availability, and it can never fire the map-ready milestone.
class _MapPlaceholder extends StatelessWidget {
  final LatLng center;

  const _MapPlaceholder({required this.center});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Static grid background evoking a map without pretending to be one.
        CustomPaint(
          painter: _MapGridPainter(color: scheme.onSurface.withOpacity(0.06)),
          child: const SizedBox.expand(),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: scheme.primary.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Preparing map…',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Simple non-animated grid painter used by [_MapPlaceholder]. Deliberately
/// static: no tiles, no markers, no animation beyond the small spinner in
/// the placeholder itself, so first-frame raster cost stays minimal.
class _MapGridPainter extends CustomPainter {
  final Color color;

  _MapGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    const spacing = 48.0;
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MapGridPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Lives exclusively inside the real [FlutterMap] children list. Its first
/// painted frame proves the LIVE engine mounted; it walks up to the owning
/// [LiveMapWidgetState] exactly once and triggers the readiness milestone.
/// The placeholder branch never contains this widget, so a cached/placeholder
/// frame can never be counted as an initialized interactive map (Part 10).
class _LiveMapReadyNotifier extends StatefulWidget {
  const _LiveMapReadyNotifier();

  @override
  State<_LiveMapReadyNotifier> createState() => _LiveMapReadyNotifierState();
}

class _LiveMapReadyNotifierState extends State<_LiveMapReadyNotifier> {
  bool _notified = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_notified || !mounted) return;
      _notified = true;
      final owner = context.findAncestorStateOfType<LiveMapWidgetState>();
      owner?._notifyLiveMapReadyOnce();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Pickup pin that responds to long-press-drag gestures, updating its LatLng
/// through the parent's preview mechanism.
class _DraggablePickupPin extends StatelessWidget {
  final MapMarkerModel marker;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  const _DraggablePickupPin({
    required this.marker,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (d) => onDragUpdate(d.globalPosition),
      onLongPressMoveUpdate: (d) => onDragUpdate(d.globalPosition),
      onLongPressEnd: (_) => onDragEnd(),
      child: Tooltip(
        message: 'Long-press and drag to set pickup',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0xFF43A047),
                shape: BoxShape.circle,
                border: Border(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.place, color: Colors.white, size: 18),
            ),
            if (marker.label != null)
              Text(
                marker.label!,
                style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

/// Banner shown only when the tile provider reports total failure, with a
/// Retry button that re-primes the provider — the visible half of the
/// "one down, the other takes over" requirement.
class MapHealthBanner extends StatelessWidget {
  final MapHealth health;
  final VoidCallback onRetry;

  const MapHealthBanner({super.key, required this.health, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.orange.shade700,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.cloud_off, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Map tiles unavailable from all providers.',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              TextButton(
                onPressed: onRetry,
                child: const Text('Retry',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
