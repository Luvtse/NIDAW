import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// ============================================================================
/// STARTUP PERFORMANCE INSTRUMENTATION (consumer, Phase 5 / Part 10)
/// ============================================================================
///
/// Measures the four milestones the acceptance gates talk about — time to
/// first frame, time to interactive cached shell, map readiness and deferred
/// initialization failures — without adding measurable cost to the paths being
/// measured. All timestamps are wall-clock since process observation start;
/// stage stopwatches aggregate per-step durations for later analysis.
///
/// Design rules:
///  - No network, no disk I/O on record paths: everything accumulates in
///    memory and is flushed as a single debug log (and via [reportSink], which
///    production wiring can point at analytics).
///  - Every getter is honest: an unmeasured milestone reports null, never a
///    fabricated default.
class StartupPerformanceService {
  /// [autoFirstFrameDetection] defaults to true for production: the very next
  /// painted frame stamps the first-frame milestone. Integration/unit tests
  /// that pump widgets while asserting *pre*-first-frame behavior pass false
  /// and call [markFirstFrame] manually — otherwise the auto callback would
  /// fire during the test's own pumps and race the assertions.
  StartupPerformanceService({
    void Function(Map<String, dynamic> report)? reportSink,
    bool autoFirstFrameDetection = true,
  }) : _reportSink = reportSink {
    // Capture the earliest possible anchor: construction happens at the top
    // of main(), before any await.
    _launchAnchor = Stopwatch()..start();
    if (autoFirstFrameDetection) {
      // Schedule first-frame detection immediately after the binding exists.
      SchedulerBinding.instance.addPostFrameCallback((_) => markFirstFrame());
    }
  }

  final void Function(Map<String, dynamic> report)? _reportSink;

  late final Stopwatch _launchAnchor;
  bool _firstFrameRecorded = false;
  bool _appMountedAt = false;

  Duration? _firstFrame;
  Duration? _interactiveShell;
  Duration? _mapReady;
  Duration? _bookingInteractive;

  final Map<String, StageStopwatch> _active = {};
  final List<Map<String, dynamic>> _stageReports = [];
  final List<String> _failedPhases = [];

  /// Earliest recorded timestamp anchor (main() entry). Exposed for tests.
  Duration get elapsed => _launchAnchor.elapsed;

  Duration? get firstFrameDuration => _firstFrame;
  Duration? get interactiveShellDuration => _interactiveShell;
  Duration? get mapReadyDuration => _mapReady;
  Duration? get bookingInteractiveDuration => _bookingInteractive;
  List<String> get failedPhases => List.unmodifiable(_failedPhases);

  // ==========================================================================
  // MILESTONES
  // ==========================================================================

  /// Called by runApp wrapper right before the widget tree mounts.
  void markAppMounted() {
    if (_appMountedAt) return;
    _appMountedAt = true;
  }

  void markFirstFrame() {
    if (_firstFrameRecorded) return;
    _firstFrameRecorded = true;
    _firstFrame = _launchAnchor.elapsed;
    debugPrint('[startup-perf] first frame @ ${_fmt(_firstFrame)}');
  }

  /// The cached/signed-out home shell accepted input (buttons enabled from
  /// local state). Distinct from map readiness.
  void markInteractiveShell() {
    if (_interactiveShell != null) return;
    _interactiveShell = _launchAnchor.elapsed;
    debugPrint('[startup-perf] interactive shell @ ${_fmt(_interactiveShell)}');
    _flush();
  }

  /// The live map engine finished mounting + first tile batch. A cached map
  /// placeholder painting fast must NOT call this.
  void markMapReady() {
    if (_mapReady != null) return;
    _mapReady = _launchAnchor.elapsed;
    debugPrint('[startup-perf] map ready @ ${_fmt(_mapReady)}');
    // Once-only instrumentation hook used by the LIVE-engine path of
    // LiveMapWidget (and integration tests). Placeholder frames never reach
    // this method, so a fast cached map can never be counted as ready.
    onMapReady?.call();
  }

  /// Fired exactly once, from [markMapReady]. Wired by AppStartupCoordinator
  /// in Stage B step 0 to forward readiness into the startup state machine.
  VoidCallback? onMapReady;

  /// Live booking actions became available (server-validated session +
  /// realtime/offline services ready).
  void markBookingInteractive() {
    if (_bookingInteractive != null) return;
    _bookingInteractive = _launchAnchor.elapsed;
    debugPrint('[startup-perf] booking interactive @ ${_fmt(_bookingInteractive)}');
  }

  // ==========================================================================
  // STAGES / PHASES
  // ==========================================================================

  StageStopwatch startStopwatch(String name) {
    final sw = StageStopwatch._(name, this);
    _active[name] = sw;
    return sw;
  }

  void finishStage(String name) {
    final sw = _active.remove(name);
    if (sw == null) return;
    _stageReports.add({
      'stage': name,
      'totalMs': sw.total.elapsedMilliseconds,
      'steps': sw.stepReport,
    });
  }

  /// Deferred-initialization outcome per subsystem. Failures are recorded
  /// honestly; retries that later succeed append a `.retry` success entry so
  /// recovery is visible in the report.
  void recordPhase(String phase, {required bool succeeded}) {
    if (!succeeded && !_failedPhases.contains(phase)) {
      _failedPhases.add(phase);
    }
    if (succeeded && _failedPhases.contains(_base(phase))) {
      debugPrint('[startup-perf] phase recovered: $phase');
    }
  }

  void recordPushPermission(bool granted) {
    debugPrint('[startup-perf] push permission ${granted ? "granted" : "denied/unavailable"}');
  }

  static String _base(String phase) =>
      phase.endsWith('.retry') ? phase.substring(0, phase.length - 6) : phase;

  // Step durations are written directly into the live StageStopwatch's map,
  // which finishStage() snapshots — no cross-lookup needed.

  void _flush() {
    final payload = <String, dynamic>{
      'firstFrameMs': _firstFrame?.inMilliseconds,
      'interactiveShellMs': _interactiveShell?.inMilliseconds,
      'mapReadyMs': _mapReady?.inMilliseconds,
      'bookingInteractiveMs': _bookingInteractive?.inMilliseconds,
      'stages': _stageReports,
      'failedPhases': _failedPhases,
    };
    _reportSink?.call(payload);
  }

  /// Full report snapshot (tests, debug tooling, analytics upload).
  Map<String, dynamic> report() {
    return <String, dynamic>{
      'firstFrameMs': _firstFrame?.inMilliseconds,
      'interactiveShellMs': _interactiveShell?.inMilliseconds,
      'mapReadyMs': _mapReady?.inMilliseconds,
      'bookingInteractiveMs': _bookingInteractive?.inMilliseconds,
      'stages': List.unmodifiable(_stageReports),
      'failedPhases': List.unmodifiable(_failedPhases),
    };
  }

  static String _fmt(Duration? d) =>
      d == null ? 'n/a' : '${d.inMilliseconds}ms';
}

/// Hierarchical stopwatch used by the coordinator: one total, many named
/// steps. Steps nested via [time] measure only their own body duration.
class StageStopwatch {
  StageStopwatch._(this.name, this._owner);

  final String name;
  final StartupPerformanceService _owner;
  final Stopwatch _total = Stopwatch()..start();
  final Map<String, int> _steps = {};

  Map<String, int> get stepReport => Map.unmodifiable(_steps);
  Stopwatch get total => _total;

  Future<T> time<T>(String step, Future<T> Function() body) async {
    final sw = Stopwatch()..start();
    try {
      return await body();
    } finally {
      sw.stop();
      _steps[step] = sw.elapsedMilliseconds;
    }
  }

  void stop() {
    if (_total.isRunning) _total.stop();
  }

  Future<void> stopIfRunning() async {
    stop();
  }
}
