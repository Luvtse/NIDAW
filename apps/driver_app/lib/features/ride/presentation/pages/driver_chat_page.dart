import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';

class DriverChatPage extends StatefulWidget {
  final String rideId;
  const DriverChatPage({super.key, required this.rideId});

  @override
  State<DriverChatPage> createState() => _DriverChatPageState();
}

class _DriverChatPageState extends State<DriverChatPage> {
  final ApiClient _api = getIt<ApiClient>();
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  Timer? _refreshTimer;
  bool _loading = true;
  bool _sending = false;
  bool _historyRequestInFlight = false;
  String? _error;

  String get _messagesPath => '/api/v1/chat/rides/${widget.rideId}/messages';

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) => _loadHistory(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadHistory({bool silent = false}) async {
    if (_historyRequestInFlight) return;
    _historyRequestInFlight = true;
    if (!silent && mounted) setState(() { _loading = true; _error = null; });
    try {
      final response = await _api.get<Map<String, dynamic>>(
        _messagesPath,
        queryParameters: const {'limit': '100'},
      );
      final data = response.data;
      if (response.statusCode != 200 || data == null) throw StateError('Unexpected chat response');
      final items = (data['messages'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
      if (!mounted) return;
      setState(() { _messages = items; _loading = false; _error = null; });
      try {
        await _api.post<Map<String, dynamic>>('$_messagesPath/read');
      } catch (_) {}
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.response?.statusCode == 403
            ? 'This ride chat is only available to its rider and driver.'
            : 'Chat is unavailable. Check your connection and retry.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Chat is unavailable. Check your connection and retry.'; });
    } finally {
      _historyRequestInFlight = false;
    }
  }

  Future<void> _send() async {
    final body = _composer.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _api.post<Map<String, dynamic>>(
        _messagesPath,
        data: {'body': body},
      );
      _composer.clear();
      await _loadHistory(silent: true);
    } on DioException catch (e) {
      if (mounted) {
        final message = e.response?.statusCode == 403
            ? 'You are not a participant of this ride.'
            : 'Message could not be sent. Please retry.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ride chat')),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [TextButton(onPressed: _loadHistory, child: const Text('Retry'))],
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isDriver = message['sender_role'] == 'driver';
                      return Align(
                        alignment: isDriver ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 320),
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDriver ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(message['body'] as String? ?? ''),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      maxLength: 1000,
                      decoration: const InputDecoration(
                        hintText: 'Message rider',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
