import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Connects the Flutter app to a Watchdog Cloud server via WebSocket.
///
/// All events are forwarded to the cloud in addition to the local
/// DevTools page. This allows remote debugging from any browser.
class WatchdogCloudClient {
  WatchdogCloudClient({
    required this.serverUrl,
    required this.apiKey,
    required this.sessionId,
    this.appName = 'flutter-app',
    this.deviceInfo,
    this.onLocationRefreshRequested,
  });

  /// The cloud server URL, e.g. `ws://localhost:8080` or `wss://your-railway-app.up.railway.app`.
  final String serverUrl;

  /// API key for authentication.
  final String apiKey;

  /// Unique session identifier for this app run.
  final String sessionId;

  /// Display name for the app in the session list.
  final String appName;

  /// Optional device/instance metadata, sent as a `device_info` event on every
  /// (re)connect so the cloud dashboard can label this session. Mutable (not
  /// `final`) so [WatchdogBroadcaster.updateDeviceInfo] can keep it current —
  /// otherwise a reconnect would resend only the stale startup-time snapshot.
  Map<String, dynamic>? deviceInfo;

  /// Called when the cloud relay forwards a `location_refresh_request`
  /// command from the dashboard (the Location tab's refresh button). Wired
  /// by [WatchdogRuntime] to [WatchdogLocationTracker.refreshLocation].
  final void Function()? onLocationRefreshRequested;

  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  int _reconnectDelay = 1;
  bool _disposed = false;
  bool _connected = false;
  bool _connecting = false;
  bool _firstConnect = true;

  /// Events sent while not yet connected (or between a drop and a
  /// reconnect), held in order and flushed once the socket opens.
  ///
  /// Without this, anything broadcast in the window between
  /// `Watchdog.start()` returning and the WebSocket handshake actually
  /// completing was silently dropped forever — [connect] doesn't wait for
  /// the handshake, so that window is real, not theoretical. This bit
  /// hardest for one-shot reports fired right at startup (most notably
  /// `Watchdog.permissionTracker.checkAndReportCommon()`), since nothing
  /// re-sends a one-shot report the way continuous location/network
  /// traffic eventually "gets lucky" once the socket is up.
  final List<String> _pendingBuffer = [];
  static const int _maxPendingBuffer = 2000;

  bool get isConnected => _connected;

  /// Connects to the cloud server.
  Future<void> connect() async {
    if (_disposed) return;
    _connect();
  }

  /// Forces an **immediate** reconnect attempt, bypassing the backoff timer.
  ///
  /// Call this when the app returns to the foreground — on mobile the OS often
  /// suspends/drops the socket while backgrounded, and waiting out the backoff
  /// would feel sluggish. No-op if already connected or a connect is in flight.
  void reconnectNow() {
    if (_disposed || _connected || _connecting) return;
    _reconnectTimer?.cancel();
    _reconnectDelay = 1;
    _connect();
  }

  Future<void> _connect() async {
    if (_disposed || _connecting) return;
    _connecting = true;

    final uri = Uri.parse(
      '$serverUrl/ws/app'
      '?apiKey=${Uri.encodeComponent(apiKey)}'
      '&sessionId=${Uri.encodeComponent(sessionId)}'
      '&appName=${Uri.encodeComponent(appName)}',
    );

    try {
      _channel = WebSocketChannel.connect(uri);

      // Wait for the connection to actually establish before marking connected.
      // This catches SocketException (connection refused) etc.
      await _channel!.ready;

      _connected = true;
      _reconnectDelay = 1;
      debugPrint('[Watchdog Cloud] Connected to $serverUrl (session: $sessionId)');

      // On the first connect of this app process, wipe any stale buffer left
      // by a previous run of this (stable) session so only the current run's
      // events show. Reconnects within the same run keep their events.
      if (_firstConnect) {
        _firstConnect = false;
        sendClear();
      }

      // Announce who we are so the dashboard can list/label this device.
      if (deviceInfo != null) {
        sendEvent({'type': 'device_info', ...deviceInfo!});
      }

      // Flush anything queued while we were still connecting/reconnecting —
      // after clear + device_info above, so the dashboard has the right
      // session identity before these land.
      _flushPending();

      _channel!.stream.listen(
        (dynamic message) {
          // Commands from the dashboard, relayed by the cloud server (e.g.
          // the Location tab's refresh button). Anything unrecognized is
          // ignored — this must stay forward-compatible with server builds
          // that send command types this client doesn't know about yet.
          if (message is! String) return;
          try {
            final data = jsonDecode(message) as Map<String, dynamic>;
            if (data['type'] == 'location_refresh_request') {
              onLocationRefreshRequested?.call();
            }
          } catch (_) {
            // Not JSON / not a recognized command — ignore.
          }
        },
        onDone: () {
          _connected = false;
          debugPrint('[Watchdog Cloud] Disconnected. Reconnecting in ${_reconnectDelay}s...');
          _scheduleReconnect();
        },
        onError: (Object error) {
          _connected = false;
          debugPrint('[Watchdog Cloud] Stream error: $error');
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      _connected = false;
      _channel = null;
      debugPrint('[Watchdog Cloud] Connection failed: $e. Retrying in ${_reconnectDelay}s...');
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  /// Sends an encoded JSON event to the cloud server. Queued (not dropped)
  /// when not currently connected — see [_pendingBuffer].
  void send(String jsonPayload) {
    if (_disposed) return;
    if (!_connected || _channel == null) {
      _pendingBuffer.add(jsonPayload);
      if (_pendingBuffer.length > _maxPendingBuffer) {
        _pendingBuffer.removeAt(0);
      }
      return;
    }
    try {
      _channel!.sink.add(jsonPayload);
    } catch (_) {
      _connected = false;
      _pendingBuffer.add(jsonPayload);
    }
  }

  /// Sends everything queued in [_pendingBuffer], in order. Called right
  /// after a (re)connect completes. If sending fails partway through, the
  /// remainder is put back so the next successful connect retries them.
  void _flushPending() {
    if (_pendingBuffer.isEmpty || _channel == null) return;
    final pending = List<String>.of(_pendingBuffer);
    _pendingBuffer.clear();
    for (var i = 0; i < pending.length; i++) {
      try {
        _channel!.sink.add(pending[i]);
      } catch (_) {
        _connected = false;
        _pendingBuffer.addAll(pending.sublist(i));
        break;
      }
    }
  }

  /// Sends a map as JSON to the cloud server.
  void sendEvent(Map<String, dynamic> data) {
    send(jsonEncode(data));
  }

  /// Sends a clear signal (e.g. on hot restart).
  void sendClear() {
    sendEvent({'type': 'clear'});
  }

  /// Disconnects and prevents reconnection.
  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _channel?.sink.close();
    _channel = null;
    _connected = false;
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelay), () {
      _reconnectDelay = (_reconnectDelay * 2).clamp(1, 10);
      _connect();
    });
  }
}
