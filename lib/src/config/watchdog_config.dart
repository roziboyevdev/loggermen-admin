import 'watchdog_cloud_config.dart';
import 'watchdog_device.dart';

/// Immutable configuration passed to [Watchdog.initialize].
///
/// Every field is optional — a default [WatchdogConfig] is production-safe
/// (server only starts when `kDebugMode` is true).
class WatchdogConfig {
  const WatchdogConfig({
    this.apiBaseUrl,
    this.port = 8888,
    this.host = '0.0.0.0',
    this.enableLogging = true,
    this.maskSensitiveHeaders = true,
    this.replayBufferSize = 10000,
    this.enabled,
    this.global = false,
    this.cloud,
    this.device,
  });

  /// Optional hint about the API base URL — rendered in the DevTools header
  /// so developers can tell which environment they're looking at.
  final String? apiBaseUrl;

  /// Port the HTTP + WebSocket server listens on. Default: 8888.
  final int port;

  /// Host the server binds to. Default: 0.0.0.0 (all interfaces).
  final String host;

  /// Emit log events to the DevTools Logs tab. Default: true.
  final bool enableLogging;

  /// When true, `Authorization` and similar headers are masked in the HTML
  /// DevTools page so Bearer tokens never appear on screen.
  final bool maskSensitiveHeaders;

  /// Maximum number of events kept in the replay buffer. Newly connecting
  /// HTML clients receive this many historic events.
  final int replayBufferSize;

  /// Whether the server should start at all. When null, defaults to
  /// `kDebugMode` — i.e. disabled in release builds.
  final bool? enabled;

  /// Global (cloud-only) mode. When `true` **and** Watchdog is enabled, the
  /// local `localhost` DevTools server is **not** started — events are streamed
  /// only to the remote [cloud] server. Requires [cloud] to be set.
  ///
  /// When `false` (default) the local server runs, plus the cloud as an
  /// additional sink if [cloud] is provided.
  final bool global;

  /// Optional cloud configuration. When provided, events are streamed to the
  /// remote cloud dashboard (the only sink in [global] mode, an additional one
  /// otherwise).
  final WatchdogCloudConfig? cloud;

  /// Optional device/instance identity. Lets the cloud dashboard tell each
  /// running app apart by device name, session id, platform, etc.
  final WatchdogDevice? device;

  /// Returns a copy with the given fields overridden.
  WatchdogConfig copyWith({
    String? apiBaseUrl,
    int? port,
    String? host,
    bool? enableLogging,
    bool? maskSensitiveHeaders,
    int? replayBufferSize,
    bool? enabled,
    bool? global,
    WatchdogCloudConfig? cloud,
    WatchdogDevice? device,
  }) {
    return WatchdogConfig(
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      port: port ?? this.port,
      host: host ?? this.host,
      enableLogging: enableLogging ?? this.enableLogging,
      maskSensitiveHeaders: maskSensitiveHeaders ?? this.maskSensitiveHeaders,
      replayBufferSize: replayBufferSize ?? this.replayBufferSize,
      enabled: enabled ?? this.enabled,
      global: global ?? this.global,
      cloud: cloud ?? this.cloud,
      device: device ?? this.device,
    );
  }
}
