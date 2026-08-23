/// Configuration for connecting to a Watchdog Cloud server.
///
/// Provide an instance of this to [WatchdogConfig.cloud] when you want every
/// event mirrored to a remote dashboard instead of (or in addition to) the
/// local DevTools page at `http://<device-ip>:<port>`.
class WatchdogCloudConfig {
  const WatchdogCloudConfig({
    required this.serverUrl,
    required this.apiKey,
    this.appName = 'flutter-app',
    this.sessionId,
  });

  /// WebSocket URL of the cloud server, e.g. `ws://localhost:8080` or
  /// `wss://your-app.up.railway.app`.
  final String serverUrl;

  /// API key obtained from the cloud server's `/auth/register` endpoint.
  final String apiKey;

  /// Display name for this app in the cloud dashboard.
  final String appName;

  /// Session identifier. Auto-generated (UUID v4) per app launch when null.
  final String? sessionId;
}
