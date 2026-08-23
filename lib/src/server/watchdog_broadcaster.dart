import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../cloud/watchdog_cloud_client.dart';
import '../models/instance_event.dart';
import '../models/location_event.dart';
import '../models/log_event.dart';
import '../models/network_event.dart';
import '../models/permission_event.dart';
import '../models/route_event.dart';
import '../models/socket_event.dart';

/// Holds active WebSocket connections from the HTML DevTools page and fans
/// out encoded JSON events to every connected client.
///
/// Emitted events are retained in a bounded replay buffer so that a newly
/// connecting (or reconnecting) client receives the full picture even when
/// the browser was opened after the app started.
///
/// Owned by [WatchdogRuntime]. Not a singleton — unit tests and hot restarts
/// get a fresh instance.
class WatchdogBroadcaster {
  WatchdogBroadcaster({this.replayBufferSize = 10000});

  /// Maximum number of events retained in the replay buffer.
  final int replayBufferSize;

  final List<WebSocketChannel> _clients = [];
  final List<String> _replayBuffer = [];
  WatchdogCloudClient? _cloudClient;
  Map<String, dynamic>? _deviceInfo;

  /// Stores the device/instance metadata so it can be sent to every newly
  /// connected HTML client (the local DevTools header reads it).
  void setDeviceInfo(Map<String, dynamic> info) {
    _deviceInfo = info;
  }

  /// Merges [info] into whatever device metadata is already known and
  /// broadcasts the full merged snapshot immediately — unlike [setDeviceInfo]
  /// (which only primes clients that connect *after* it's called), this
  /// updates everyone already watching, local and cloud alike.
  ///
  /// Used by [Watchdog.updateUser] to fill in user identity once it becomes
  /// known (e.g. after login), when Watchdog was already initialized at app
  /// startup with no user context yet. Also keeps the attached
  /// [WatchdogCloudClient]'s own device-info snapshot in sync, so a
  /// reconnect resends the *current* merged info, not the stale
  /// startup-time-only snapshot.
  void updateDeviceInfo(Map<String, dynamic> info) {
    _deviceInfo = {...?_deviceInfo, ...info};
    _cloudClient?.deviceInfo = _deviceInfo;
    _broadcast({'type': 'device_info', ...?_deviceInfo});
  }

  /// Attaches a cloud client. All subsequent events are also forwarded to it.
  void attachCloud(WatchdogCloudClient client) {
    _cloudClient = client;
  }

  /// Detaches (and disposes) the current cloud client, if any.
  Future<void> detachCloud() async {
    await _cloudClient?.dispose();
    _cloudClient = null;
  }

  /// Registers a newly connected HTML client. All buffered events are
  /// replayed so the client sees the full history.
  void addClient(WebSocketChannel channel) {
    _clients.add(channel);
    if (_deviceInfo != null) sendDeviceInfo(channel, _deviceInfo!);
    if (_replayBuffer.isEmpty) return;
    for (final payload in _replayBuffer) {
      try {
        channel.sink.add(payload);
      } catch (_) {
        break;
      }
    }
  }

  /// Removes a disconnected client.
  void removeClient(WebSocketChannel channel) {
    _clients.remove(channel);
  }

  /// Number of currently connected HTML clients.
  int get clientCount => _clients.length;

  void broadcastNetwork(NetworkEvent event) => _broadcast(event.toJson());
  void broadcastLog(LogEvent event) => _broadcast(event.toJson());
  void broadcastInstance(InstanceEvent event) => _broadcast(event.toJson());
  void broadcastRoute(RouteEvent event) => _broadcast(event.toJson());
  void broadcastSocket(SocketEvent event) => _broadcast(event.toJson());
  void broadcastLocation(LocationEvent event) => _broadcast(event.toJson());
  void broadcastPermission(PermissionEvent event) => _broadcast(event.toJson());

  void broadcastSocketStatus({required String channel, required String state}) {
    _broadcast({
      'type': 'socket_status',
      'channel': channel,
      'state': state,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Wipes the replay buffer and tells every connected client to clear their
  /// displayed events. Called on hot restart.
  void broadcastClear() {
    _replayBuffer.clear();
    _cloudClient?.sendClear();
    _broadcast({'type': 'clear'});
  }

  /// Sends device/app info to a single newly connected client.
  void sendDeviceInfo(WebSocketChannel channel, Map<String, dynamic> info) {
    final payload = jsonEncode({'type': 'device_info', ...info});
    try {
      channel.sink.add(payload);
    } catch (_) {}
  }

  /// Closes all client connections and clears internal state. Primarily for
  /// tests or full shutdown.
  Future<void> dispose() async {
    for (final client in _clients) {
      try {
        await client.sink.close();
      } catch (_) {}
    }
    _clients.clear();
    _replayBuffer.clear();
    await detachCloud();
  }

  void _broadcast(Map<String, dynamic> data) {
    final payload = jsonEncode(data);

    _replayBuffer.add(payload);
    if (_replayBuffer.length > replayBufferSize) {
      _replayBuffer.removeAt(0);
    }

    _cloudClient?.send(payload);

    if (_clients.isEmpty) return;

    final dead = <WebSocketChannel>[];
    for (final client in _clients) {
      try {
        client.sink.add(payload);
      } catch (_) {
        dead.add(client);
      }
    }
    for (final d in dead) {
      _clients.remove(d);
    }
  }
}
