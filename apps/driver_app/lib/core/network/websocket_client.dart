import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:hive/hive.dart';

class WebSocketClient {
  WebSocketChannel? _channel;
  final String baseUrl;
  final StreamController<Map<String, dynamic>> _messageController = 
      StreamController.broadcast();
  
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  
  bool _isConnected = false;
  Timer? _heartbeatTimer;
  final Set<String> _subscriptions = {};

  WebSocketClient({required this.baseUrl});

  Future<void> connect() async {
    try {
      final authBox = await Hive.openBox('driver_auth');
      final token = authBox.get('access_token');
      
      if (token == null) {
        throw Exception('No authentication token found');
      }

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
          _scheduleReconnect();
        },
        onDone: () {
          print('WebSocket connection closed');
          _isConnected = false;
          _scheduleReconnect();
        },
      );

      _startHeartbeat();
      for (final topic in _subscriptions) {
        send({'type': 'subscribe', 'payload': {'topic': topic}});
      }
      print('WebSocket connected');
    } catch (e) {
      print('❌ WebSocket connection failed: $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    Future.delayed(const Duration(seconds: 5), () {
      if (!_isConnected) {
        connect();
      }
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
    _channel?.sink.close();
    _isConnected = false;
  }

  void dispose() {
    disconnect();
    _messageController.close();
  }
}