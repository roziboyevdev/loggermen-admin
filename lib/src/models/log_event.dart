import '../logging/watchdog_logger.dart';

export '../logging/watchdog_logger.dart' show WatchdogLogLevel;

/// A single log entry emitted by the default [WatchdogLogger] or any user-
/// supplied implementation.
class LogEvent {
  const LogEvent({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.message,
    this.title,
    this.error,
    this.stackTrace,
  });

  /// Unique ID for this log entry (UUID v4).
  final String id;

  /// When the log was recorded.
  final DateTime timestamp;

  /// Severity level.
  final WatchdogLogLevel level;

  /// Human-readable message.
  final String message;

  /// Optional category label (e.g. "AuthInterceptor", "TripService").
  final String? title;

  /// Error object — present for [WatchdogLogLevel.error] and
  /// [WatchdogLogLevel.critical].
  final String? error;

  /// Stack trace string — present when an error or exception was caught.
  final String? stackTrace;

  /// Returns true when this entry represents an error or critical problem.
  bool get isError =>
      level == WatchdogLogLevel.error || level == WatchdogLogLevel.critical;

  Map<String, dynamic> toJson() {
    return {
      'type': 'log',
      'id': id,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'level': level.name,
      'message': message,
      'title': title,
      'error': error,
      'stackTrace': stackTrace,
    };
  }

  static WatchdogLogLevel levelFromTalker(String talkerLevel) {
    return switch (talkerLevel.toLowerCase()) {
      'verbose' => WatchdogLogLevel.verbose,
      'debug' => WatchdogLogLevel.debug,
      'info' => WatchdogLogLevel.info,
      'warning' => WatchdogLogLevel.warning,
      'error' => WatchdogLogLevel.error,
      'critical' => WatchdogLogLevel.critical,
      _ => WatchdogLogLevel.debug,
    };
  }
}
