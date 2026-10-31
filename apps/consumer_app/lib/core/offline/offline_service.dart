import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Offline service for handling operations when network is unavailable
///
/// Phase 5 startup contract:
///  - [initialize] is safe to call AFTER the first frame (the startup
///    coordinator owns that scheduling). It opens its own Hive boxes, starts
///    the connectivity stream and exposes explicit readiness/error states —
///    callers never have to guess whether the service is usable.
///  - Every cache/queue accessor degrades honestly before initialization:
///    reads return null / writes throw [OfflineServiceNotReadyException]
///    instead of touching unopened boxes or silently dropping data.
enum OfflineServiceStatus { notInitialized, initializing, ready, failed }

class OfflineServiceNotReadyException implements Exception {
  final String message;
  const OfflineServiceNotReadyException([
    this.message = 'OfflineService has not finished initializing',
  ]);

  @override
  String toString() => 'OfflineServiceNotReadyException($message)';
}

class OfflineService {
  static const String _kPendingOperationsBox = 'pending_operations';
  static const String _kCachedDataBox = 'cached_data';

  /// Cache key under which the last successful ride summary projection is
  /// stored. The home shell may render it with a "last known" freshness
  /// indicator; it must NEVER be treated as an active trip or a fresh quote
  /// until the server confirms otherwise (Phase 5 local-first rule).
  static const String lastRideSummaryKey = 'last_ride_summary';

  Box? _pendingOpsBox;
  Box? _cachedDataBox;

  final Connectivity _connectivity = Connectivity();
  StreamSubscription? _connectivitySubscription;

  bool _isOnline = true;
  OfflineServiceStatus _status = OfflineServiceStatus.notInitialized;
  Object? _initializationError;

  final StreamController<bool> _connectivityController =
      StreamController.broadcast();

  /// Completes once the FIRST connectivity check settles (online OR offline —
  /// both are definitive answers). Never completes with fabricated data: if
  /// initialization fails, this future completes with the error so waiters
  /// observe the honest failure instead of hanging forever.
  final Completer<void> _initialConnectivity = Completer<void>();

  bool get isOnline => _isOnline;
  Stream<bool> get connectivityStream => _connectivityController.stream;

  OfflineServiceStatus get status => _status;
  bool get isReady => _status == OfflineServiceStatus.ready;
  Object? get initializationError => _initializationError;

  /// Resolves when connectivity state is known; rejects if initialization
  /// itself failed. Callers should catch and render the offline state.
  Future<void> get initialConnectivitySettled => _initialConnectivity.future;

  Future<void> initialize() async {
    if (_status == OfflineServiceStatus.ready) return;
    if (_status == OfflineServiceStatus.initializing) {
      // A concurrent initializer exists; wait for its outcome via the same
      // completer rather than racing duplicate box opens.
      await _initialConnectivity.future;
      if (_status != OfflineServiceStatus.ready) {
        throw OfflineServiceNotReadyException(
            'concurrent initialization failed: $_initializationError');
      }
      return;
    }
    _status = OfflineServiceStatus.initializing;
    try {
      _pendingOpsBox = await Hive.openBox(_kPendingOperationsBox);
      _cachedDataBox = await Hive.openBox(_kCachedDataBox);

      // Check initial connectivity
      final result = await _connectivity.checkConnectivity();
      _isOnline = result != ConnectivityResult.none;
      if (!_initialConnectivity.isCompleted) _initialConnectivity.complete();

      // Listen for connectivity changes
      _connectivitySubscription =
          _connectivity.onConnectivityChanged.listen((result) {
        final wasOffline = !_isOnline;
        _isOnline = result != ConnectivityResult.none;

        _connectivityController.add(_isOnline);

        if (wasOffline && _isOnline) {
          syncPendingOperations();
        }
      });
      _status = OfflineServiceStatus.ready;
    } catch (e) {
      _status = OfflineServiceStatus.failed;
      _initializationError = e;
      if (!_initialConnectivity.isCompleted) {
        _initialConnectivity.completeError(e);
      }
      debugPrint('[offline] initialization failed: $e');
      rethrow;
    }
  }

  Box get _requirePendingOpsBox {
    final box = _pendingOpsBox;
    if (box == null || _status != OfflineServiceStatus.ready) {
      throw const OfflineServiceNotReadyException('pending-operations queue');
    }
    return box;
  }

  Box get _requireCachedDataBox {
    final box = _cachedDataBox;
    if (box == null || _status != OfflineServiceStatus.ready) {
      throw const OfflineServiceNotReadyException('cached-data store');
    }
    return box;
  }

  // ==========================================================================
  // PENDING OPERATIONS
  // ==========================================================================

  /// Queue an operation for later execution
  Future<String> queueOperation({
    required String endpoint,
    required String method,
    required Map<String, dynamic> data,
    int priority = 0,
  }) async {
    final box = _requirePendingOpsBox;
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    final operation = {
      'id': id,
      'endpoint': endpoint,
      'method': method,
      'data': data,
      'priority': priority,
      'timestamp': DateTime.now().toIso8601String(),
      'retryCount': 0,
    };

    await box.put(id, operation);
    return id;
  }

  /// Sync all pending operations when back online
  Future<void> syncPendingOperations() async {
    if (!_isOnline) return;
    if (_status != OfflineServiceStatus.ready) return;

    final box = _requirePendingOpsBox;
    final operations = box.values.toList()
      ..sort((a, b) => (b['priority'] as int).compareTo(a['priority'] as int));

    for (final op in operations) {
      try {
        await _executeOperation(op);
        await box.delete(op['id']);
      } catch (e) {
        int retryCount = op['retryCount'] ?? 0;
        if (retryCount < 3) {
          op['retryCount'] = retryCount + 1;
          await box.put(op['id'], op);
        } else {
          await box.delete(op['id']);
          // TODO: Notify user of failed operation
        }
      }
    }
  }

  Future<void> _executeOperation(Map<String, dynamic> operation) async {
    // This would integrate with your ApiClient
    // For now, just a placeholder
    final endpoint = operation['endpoint'] as String;
    final method = operation['method'] as String;
    final data = operation['data'] as Map<String, dynamic>;

    // TODO: Call actual API
    print('Executing offline operation: $method $endpoint');
  }

  int get pendingOperationCount =>
      _status == OfflineServiceStatus.ready ? _requirePendingOpsBox.length : 0;

  // ==========================================================================
  // CACHED DATA
  // ==========================================================================

  /// Cache data for offline access
  Future<void> cacheData(String key, dynamic data, {Duration? ttl}) async {
    final box = _requireCachedDataBox;
    final cacheEntry = {
      'data': data,
      'cachedAt': DateTime.now().toIso8601String(),
      'expiresAt': ttl != null
          ? DateTime.now().add(ttl).toIso8601String()
          : null,
    };

    await box.put(key, cacheEntry);
  }

  /// Get cached data. Returns null (never throws) while the service is still
  /// initializing so read-only UI paths can render "no cache yet" honestly.
  dynamic getCachedData(String key) {
    if (_status != OfflineServiceStatus.ready) return null;
    final box = _cachedDataBox!;
    final entry = box.get(key);
    if (entry == null) return null;

    // Check expiration
    if (entry['expiresAt'] != null) {
      final expiresAt = DateTime.parse(entry['expiresAt']);
      if (DateTime.now().isAfter(expiresAt)) {
        box.delete(key);
        return null;
      }
    }

    return entry['data'];
  }

  /// Check if data is cached
  bool hasCachedData(String key) {
    return getCachedData(key) != null;
  }

  /// Clear all cached data
  Future<void> clearCache() async {
    if (_status != OfflineServiceStatus.ready) return;
    await _cachedDataBox!.clear();
  }

  // ==========================================================================
  // CLEANUP
  // ==========================================================================

  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivityController.close();
  }
}