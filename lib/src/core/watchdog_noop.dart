import '../logging/watchdog_logger.dart';
import '../models/instance_event.dart';
import '../models/log_event.dart';
import '../models/network_event.dart';
import '../models/route_event.dart';
import '../models/socket_event.dart';
import '../server/watchdog_broadcaster.dart';

/// A [WatchdogBroadcaster] that silently discards every event.
///
/// Used as the backing broadcaster for the fallback instances returned by the
/// [Watchdog] accessors when `Watchdog.initialize()` hasn't been awaited
/// (e.g. release builds, or DI wiring that runs before initialization).
///
/// Internal — not exported.
class NoopBroadcaster extends WatchdogBroadcaster {
  NoopBroadcaster() : super(replayBufferSize: 0);

  @override
  void broadcastNetwork(NetworkEvent event) {}

  @override
  void broadcastLog(LogEvent event) {}

  @override
  void broadcastInstance(InstanceEvent event) {}

  @override
  void broadcastRoute(RouteEvent event) {}

  @override
  void broadcastSocket(SocketEvent event) {}

  @override
  void broadcastSocketStatus({required String channel, required String state}) {}

  @override
  void broadcastClear() {}
}

/// A [WatchdogLogger] that discards every log call.
///
/// Used as the fallback logger exposed by [Watchdog.logger] before
/// initialization and in release builds where Watchdog is disabled.
///
/// Internal — not exported.
class NoopLogger implements WatchdogLogger {
  const NoopLogger();

  @override
  void log(
    WatchdogLogLevel level,
    String message, {
    String? title,
    Object? error,
    StackTrace? stackTrace,
  }) {}

  @override
  void debug(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void info(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void warning(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void critical(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void verbose(String message) {}
}
