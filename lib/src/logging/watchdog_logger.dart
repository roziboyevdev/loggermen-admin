/// Severity level of a log entry.
///
/// Mirrors Talker's level enum one-to-one so the default logger can translate
/// without loss, but this is Watchdog's canonical level type — custom logger
/// implementations should target it.
enum WatchdogLogLevel {
  verbose,
  debug,
  info,
  warning,
  error,
  critical,
}

/// Contract every logger passed to [Watchdog.initialize] via
/// [WatchdogDependencies.logger] must satisfy.
///
/// The default implementation is Talker-backed and is created automatically
/// when no custom logger is supplied. Provide your own to integrate with an
/// existing logging stack (e.g. a company-wide `AppLogger`).
abstract class WatchdogLogger {
  /// Records a log at the given [level]. Implementations are expected to
  /// forward the entry to the configured transport (DevTools page + cloud).
  void log(
    WatchdogLogLevel level,
    String message, {
    String? title,
    Object? error,
    StackTrace? stackTrace,
  });

  /// Convenience shortcut for [WatchdogLogLevel.debug].
  void debug(String message, {Object? error, StackTrace? stackTrace}) =>
      log(WatchdogLogLevel.debug, message, error: error, stackTrace: stackTrace);

  /// Convenience shortcut for [WatchdogLogLevel.info].
  void info(String message, {Object? error, StackTrace? stackTrace}) =>
      log(WatchdogLogLevel.info, message, error: error, stackTrace: stackTrace);

  /// Convenience shortcut for [WatchdogLogLevel.warning].
  void warning(String message, {Object? error, StackTrace? stackTrace}) =>
      log(WatchdogLogLevel.warning, message, error: error, stackTrace: stackTrace);

  /// Convenience shortcut for [WatchdogLogLevel.error].
  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      log(WatchdogLogLevel.error, message, error: error, stackTrace: stackTrace);

  /// Convenience shortcut for [WatchdogLogLevel.critical].
  void critical(String message, {Object? error, StackTrace? stackTrace}) =>
      log(WatchdogLogLevel.critical, message, error: error, stackTrace: stackTrace);

  /// Convenience shortcut for [WatchdogLogLevel.verbose].
  void verbose(String message) => log(WatchdogLogLevel.verbose, message);
}
