import 'dart:convert';

/// Direction of a WebSocket message.
enum SocketDirection { send, receive }

/// A single WebSocket message — sent or received.
class SocketEvent {
  const SocketEvent({
    required this.id,
    required this.timestamp,
    required this.direction,
    required this.channel,
    this.messageType,
    this.data,
    this.sizeBytes,
    this.error,
  });

  /// Unique event ID.
  final String id;

  /// When the message was sent/received.
  final DateTime timestamp;

  /// Whether this was sent or received.
  final SocketDirection direction;

  /// Channel/connection label (e.g. "main", "wss://api.example.com/ws").
  final String channel;

  /// Application-level message type (e.g. "hos_timer", "ping", "hos_remaining").
  final String? messageType;

  /// Message payload — can be a Map, List, String, or null.
  final dynamic data;

  /// Size of the raw message in bytes.
  final int? sizeBytes;

  /// Error message if the send/receive failed.
  final String? error;

  // ── Helpers ──────────────────────────────────────────────────────────────

  bool get isSend => direction == SocketDirection.send;
  bool get isReceive => direction == SocketDirection.receive;
  bool get hasError => error != null;

  /// Human-readable size label.
  String get sizeLabel {
    if (sizeBytes == null) return '';
    if (sizeBytes! < 1024) return '${sizeBytes}B';
    if (sizeBytes! < 1024 * 1024) return '${(sizeBytes! / 1024).toStringAsFixed(1)}KB';
    return '${(sizeBytes! / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() {
    return {
      'type': 'socket',
      'id': id,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'direction': direction.name,
      'channel': channel,
      'messageType': messageType,
      'data': _toJsonSafe(data),
      'sizeBytes': sizeBytes,
      'error': error,
    };
  }

  static dynamic _toJsonSafe(dynamic body) {
    if (body == null) return null;
    if (body is String) {
      try {
        return jsonDecode(body);
      } catch (_) {
        return body;
      }
    }
    if (body is Map || body is List) return body;
    return body.toString();
  }
}
