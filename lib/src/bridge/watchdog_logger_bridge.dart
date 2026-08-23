import '../logging/watchdog_logger.dart';

/// Thin adapter that lets an existing project-level logger forward calls into
/// Watchdog without replacing the caller's API.
///
/// ## How it works
///
/// Projects commonly have a static `AppLogger` with methods like `debug`,
/// `info`, `warning`, `error`, `log`, and `forceLog`. Instead of rewriting
/// those call sites, wire them up once at startup:
///
/// ```dart
/// AppLogger.attachBridge(Watchdog.bridge);
/// ```
///
/// Every `AppLogger.info(…)` then also reaches Watchdog via this bridge.
class WatchdogLoggerBridge {
  WatchdogLoggerBridge({required this.logger});

  /// The underlying [WatchdogLogger] the bridge delegates to. Typically the
  /// default Talker-backed logger, but can be any implementation.
  final WatchdogLogger logger;

  void debug(String message, {Object? error, StackTrace? stackTrace}) =>
      logger.debug(message, error: error, stackTrace: stackTrace);

  void info(String message, {Object? error, StackTrace? stackTrace}) =>
      logger.info(message, error: error, stackTrace: stackTrace);

  void warning(String message, {Object? error, StackTrace? stackTrace}) =>
      logger.warning(message, error: error, stackTrace: stackTrace);

  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      logger.error(message, error: error, stackTrace: stackTrace);

  void log(String message) => logger.verbose(message);

  void forceLog(String message) => logger.critical('🚨 $message');
}
