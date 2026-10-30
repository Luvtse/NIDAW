import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:hive/hive.dart';

/// Driver realtime channel (Phase 5 hardened).
///
/// Startup contract (§4.3): the socket may only connect once an auth token
/// exists, and reconnection is bounded + auth-gated — never a blind loop that
/// hammers the gateway while signed out. Legacy callers (AuthBloc) keep using
/// [connect], which no longer throws on a missing token; the coordinator owns
/// retry policy via [connectNow]/[setAuthGatedReconnect].
class WebSocketClient {
  WebSocketChannel? _channel;
  final String baseUrl;
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController.broadcast();

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  /// Connection-state stream so startup/UI readiness reflects reality rather
  /// than intention (mirrors the consumer client's contract).
  final StreamController<WebSocketConnectionState> _stateController =
      StreamController<WebSocketConnectionState>.broadcast();
  Stream<WebSocketConnectionState> get stateStream => _stateController.stream;
  WebSocketConnectionState _connState = WebSocketConnectionState.disconnected;

  bool _isConnected = false;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _authGated = false;
  final Set<String> _subscriptions = {};

  WebSocketClient({required this.baseUrl});

  bool get isConnected => _isConnected;

  void _setState(WebSocketConnectionState s) {
    if (_connState == s) return;
    _connState = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  /// Legacy entry point used by AuthBloc after successful authentication.
  /// Never throws when signed out: absence of a token simply means "not
  /// authorized to connect yet".
  Future<void> connect() async {
    await connectNow();
  }

  /// Explicit connect returning whether the connection was established.
  Future<bool> connectNow() async {
    try {
      // The auth box is opened pre-frame in Stage A; reuse it without
      // awaiting a redundant openBox round-trip when already available.
      final authBox = Hive.isBoxOpen('driver_auth')
          ? Hive.box('driver_auth')
          : await Hive.openBox('driver_auth');
      final token = authBox.get('access_token') as String?;

      if (token == null || token.isEmpty) {
        // Not authenticated: do NOT throw, do NOT reconnect-loop. The next
        // attempt happens when AuthBloc/coordinator calls us again.
        _setState(WebSocketConnectionState.disconnected);
        return false;
      }

      _setState(WebSocketConnectionState.connecting);

      // WS_BASE_URL is the complete WebSocket endpoint (including /ws),
      // shared with the consumer app and deployment configuration. Do not
      // derive it from API_BASE_URL or append another /ws path segment.
      // Keep the role hint in the query while authenticating with the
      // Sec-WebSocket-Protocol subprotocol, not a token query parameter.
      final wsUri = Uri.parse(baseUrl).replace(
        queryParameters: {
          ...Uri.parse(baseUrl).queryParameters,
          'type': 'driver',
        },
      );
      _channel = IOWebSocketChannel.connect(
        wsUri,
        protocols: ['nidaw-auth.$token'],
      );

      await _channel!.ready;
      _isConnected = true;
      _reconnectAttempts = 0;
      _setState(WebSocketConnectionState.connected);

      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message) as Map<String, dynamic>;
            if (data['schema_version'] != 1) {
              print('Ignoring WebSocket message with unsupported schema version');
              return;
            }
            _messageController.add(data);
          } catch (e) {
            print('Failed to parse WebSocket message: $e');
          }
        },
        onError: (error) {
          print('WebSocket error: $error');
          _isConnected = false;
          _setState(WebSocketConnectionState.error);
          _scheduleReconnect();
        },
        onDone: () {
          print('WebSocket connection closed');
          _isConnected = false;
          _setState(WebSocketConnectionState.disconnected);
          _scheduleReconnect();
        },
      );

      _startHeartbeat();
      for (final topic in _subscriptions) {
        send({'type': 'subscribe', 'payload': {'topic': topic}});
      }
      print('WebSocket connected');
      return true;
    } catch (e) {
      print('\u274c WebSocket connection failed: $e');
      _isConnected = false;
      _setState(WebSocketConnectionState.error);
      _scheduleReconnect();
      return false;
    }
  }

  /// Enable the coordinator-driven reconnect mode: this client stops its own
  /// internal reconnect scheduling so exactly ONE bounded retry policy owns
  /// recovery (the DriverStartupCoordinator's auth-gated schedule). Prevents
  /// the legacy double-loop where both layers retried simultaneously.
  void setAuthGatedReconnect(bool enabled) {
    _authGated = enabled;
    if (!enabled) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  /// Bounded reconnect with exponential backoff — and a hard stop once the
  /// driver is signed out (no token) or the coordinator owns recovery.
  void _scheduleReconnect() {
    if (_authGated) return; // coordinator owns retries in Phase 5 wiring.
    _reconnectTimer?.cancel();
    const maxAttempts = 5;
    if (_reconnectAttempts >= maxAttempts) return;
    _reconnectAttempts++;
    final delay = Duration(seconds: 2 * _reconnectAttempts);
    _reconnectTimer = Timer(delay, () async {
      if (_isConnected) return;
      final box = Hive.isBoxOpen('driver_auth')
          ? Hive.box('driver_auth')
          : await Hive.openBox('driver_auth');
      if (box.get('access_token') == null) return; // signed out: stop.
      await connectNow();
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isConnected) {
        send({'type': 'ping', 'payload': {}});
      }
    });
  }

  void subscribe(String topic) {
    _subscriptions.add(topic);
    if (_isConnected) {
      send({'type': 'subscribe', 'payload': {'topic': topic}});
    }
  }

  void unsubscribe(String topic) {
    _subscriptions.remove(topic);
    if (_isConnected) {
      send({'type': 'unsubscribe', 'payload': {'topic': topic}});
    }
  }

  void send(Map<String, dynamic> message) {
    if (_isConnected && _channel != null) {
      final outgoing = Map<String, dynamic>.from(message);
      outgoing['schema_version'] = 1;
      outgoing['timestamp'] ??= DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      if (outgoing.containsKey('data') && !outgoing.containsKey('payload')) {
        outgoing['payload'] = outgoing.remove('data');
      }
      _channel!.sink.add(jsonEncode(outgoing));
    }
  }

  void disconnect() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _isConnected = false;
    _setState(WebSocketConnectionState.disconnected);
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _stateController.close();
  }
}

enum WebSocketConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}
