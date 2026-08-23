import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/socket_event.dart';
import '../server/watchdog_broadcaster.dart';

/// Tracks WebSocket messages and broadcasts them to Watchdog DevTools.
///
/// Usage:
/// ```dart
/// final tracker = Watchdog.socketTracker;
///
/// // Track an outgoing message
/// tracker.trackSend(
///   channel: 'wss://api.example.com/ws',
///   data: {'type': 'ping'},
/// );
///
/// // Track an incoming message
/// tracker.trackReceive(
///   channel: 'wss://api.example.com/ws',
///   data: decoded,
///   messageType: decoded['type'],
/// );
/// ```
class WatchdogSocketTracker {
  WatchdogSocketTracker({required this.broadcaster});

  final WatchdogBroadcaster broadcaster;

  static const _uuid = Uuid();

  /// Track an outgoing WebSocket message.
  void trackSend({
    required String channel,
    dynamic data,
    String? messageType,
    String? error,
  }) {
    final raw = data is String ? data : (data != null ? jsonEncode(data) : null);
    final event = SocketEvent(
      id: _uuid.v4(),
      timestamp: DateTime.now(),
      direction: SocketDirection.send,
      channel: channel,
      messageType: messageType ?? _extractType(data),
      data: data,
      sizeBytes: raw?.length,
      error: error,
    );
    broadcaster.broadcastSocket(event);
  }

  /// Track an incoming WebSocket message.
  void trackReceive({
    required String channel,
    dynamic data,
    String? messageType,
    String? rawMessage,
    String? error,
  }) {
    final raw = rawMessage ?? (data is String ? data : (data != null ? jsonEncode(data) : null));
    final event = SocketEvent(
      id: _uuid.v4(),
      timestamp: DateTime.now(),
      direction: SocketDirection.receive,
      channel: channel,
      messageType: messageType ?? _extractType(data),
      data: data,
      sizeBytes: raw?.length,
      error: error,
    );
    broadcaster.broadcastSocket(event);
  }

  /// Track a WebSocket connection state change.
  void trackConnectionState({
    required String channel,
    required String state,
  }) {
    broadcaster.broadcastSocketStatus(
      channel: channel,
      state: state,
    );
  }

  /// Try to extract a "type" field from the data.
  String? _extractType(dynamic data) {
    if (data is Map && data.containsKey('type')) {
      return data['type']?.toString();
    }
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map && decoded.containsKey('type')) {
          return decoded['type']?.toString();
        }
      } catch (_) {}
    }
    return null;
  }
}
