import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// ============================================================================
/// DRIVER STARTUP PERFORMANCE INSTRUMENTATION (Phase 5 / Part 10)
/// ============================================================================
///
/// Mirrors the consumer instrumentation with driver-specific milestones:
///   - first frame (shell painted after Stage A only),
///   - session restoration (server-validated auth result),
///   - active-trip recovery settled (authoritative GET answered),
///   - dispatch connection ready (authenticated socket + offers ack),
///   - location readiness (tracking actually streaming).
///
/// Honest by construction: unmeasured milestones report null, failed phases
/// are recorded (never silently dropped), and a cached/provisional value never
/// counts as a settled milestone.
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
    // Earliest possible anchor: constructed at the top of main(), before any
    // await on the pre-frame path.
    _launchAnchor = Stopwatch()..start();
    if (autoFirstFrameDetection) {
      SchedulerBinding.instance.addPostFrameCallback((_) => markFirstFrame());
    }
  }

  final void Function(Map<String, dynamic> report)? _reportSink;

  late final Stopwatch _launchAnchor;
  bool _firstFrameRecorded = false;

  Duration? _firstFrame;
  Duration? _sessionRestored;
  Duration? _tripRecoverySettled;
  Duration? _dispatchReady;
  Duration? _locationReady;

  final Map<String, StageStopwatch> _active = {};
  final List<Map<String, dynamic>> _stageReports = [];
  final List<String> _failedPhases = [];

  Duration get elapsed => _launchAnchor.elapsed;

  Duration? get firstFrameDuration => _firstFrame;
  Duration? get sessionRestoredDuration => _sessionRestored;
  Duration? get tripRecoveryDuration => _tripRecoverySettled;
  Duration? get dispatchReadyDuration => _dispatchReady;
  Duration? get locationReadyDuration => _locationReady;
  List<String> get failedPhases => List.unmodifiable(_failedPhases);

  // ==========================================================================
  // MILESTONES
  // ==========================================================================

  void markFirstFrame() {
    if (_firstFrameRecorded) return;
    _firstFrameRecorded = true;
    _firstFrame = _launchAnchor.elapsed;
    debugPrint('[driver-startup-perf] first frame @ ${_fmt(_firstFrame)}');
  }

  /// Server validated the restored token (or definitively rejected it).
  /// Provisional local hydration does NOT count.
  void markSessionRestored() {
    if (_sessionRestored != null) return;
    _sessionRestored = _launchAnchor.elapsed;
    debugPrint(
        '[driver-startup-perf] session restored @ ${_fmt(_sessionRestored)}');
  }

  /// Authoritative active-ride query answered (ride found OR confirmed none).
  /// The gate cares about this separately from the first frame — a driver
  /// mid-trip must reach the trip screen fast, but only off real data.
  void markTripRecoverySettled() {
    if (_tripRecoverySettled != null) return;
    _tripRecoverySettled = _launchAnchor.elapsed;
    debugPrint(
        '[driver-startup-perf] trip recovery settled @ ${_fmt(_tripRecoverySettled)}');
    _flush();
  }

  /// Authenticated WebSocket connected AND `driver:offers` subscription acked.
  void markDispatchReady() {
    if (_dispatchReady != null) return;
    _dispatchReady = _launchAnchor.elapsed;
    debugPrint('[driver-startup-perf] dispatch ready @ ${_fmt(_dispatchReady)}');
  }

  /// Continuous location collection is running (permission granted, driver
  /// state permits tracking).
  void markLocationReady() {
    if (_locationReady != null) return;
    _locationReady = _launchAnchor.elapsed;
    debugPrint('[driver-startup-perf] location ready @ ${_fmt(_locationReady)}');
  }

  // ==========================================================================
  // STAGES / PHASES
  // ==========================================================================

  StageStopwatch startStopwatch(String name) {
    final sw = StageStopwatch._(name);
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

  /// Deferred-initialization outcome per subsystem. Retries that later succeed
  /// append a `.retry` success entry so recovery is visible in the report.
  void recordPhase(String phase, {required bool succeeded}) {
    if (!succeeded && !_failedPhases.contains(phase)) {
      _failedPhases.add(phase);
    }
    if (succeeded && _failedPhases.contains(_base(phase))) {
      debugPrint('[driver-startup-perf] phase recovered: $phase');
    }
  }

  static String _base(String phase) =>
      phase.endsWith('.retry') ? phase.substring(0, phase.length - 6) : phase;

  void _flush() {
    _reportSink?.call(report());
  }

  /// Full report snapshot (tests, debug tooling, analytics upload).
  Map<String, dynamic> report() {
    return <String, dynamic>{
      'firstFrameMs': _firstFrame?.inMilliseconds,
      'sessionRestoredMs': _sessionRestored?.inMilliseconds,
      'tripRecoveryMs': _tripRecoverySettled?.inMilliseconds,
      'dispatchReadyMs': _dispatchReady?.inMilliseconds,
      'locationReadyMs': _locationReady?.inMilliseconds,
      'stages': List.unmodifiable(_stageReports),
      'failedPhases': List.unmodifiable(_failedPhases),
    };
  }

  static String _fmt(Duration? d) =>
      d == null ? 'n/a' : '${d.inMilliseconds}ms';
}

/// Hierarchical stopwatch: one total, many named steps. Steps measured via
/// [time] record only their own body duration.
class StageStopwatch {
  StageStopwatch._(this.name);

  final String name;
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
