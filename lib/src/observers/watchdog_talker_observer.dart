import 'package:talker/talker.dart';
import 'package:uuid/uuid.dart';

import '../models/log_event.dart';
import '../server/watchdog_broadcaster.dart';

/// A [TalkerObserver] that forwards every Talker log, error, and exception
/// to [WatchdogBroadcaster] so they appear in the HTML DevTools page.
///
/// Registered automatically when you call [Watchdog.initialize].
/// You never need to interact with this class directly.
class WatchdogTalkerObserver extends TalkerObserver {
  WatchdogTalkerObserver({required this.broadcaster});

  final WatchdogBroadcaster broadcaster;

  static const _uuid = Uuid();

  @override
  void onLog(TalkerData log) {
    _broadcast(log);
  }

  @override
  void onError(TalkerError err) {
    _broadcast(err);
  }

  @override
  void onException(TalkerException err) {
    _broadcast(err);
  }

  // ── Private ───────────────────────────────────────────────────────────────

  void _broadcast(TalkerData data) {
    final event = LogEvent(
      id: _uuid.v4(),
      timestamp: data.time,
      level: _mapLevel(data.logLevel),
      message: data.generateTextMessage(),
      title: data.title,
      error: data.error?.toString(),
      stackTrace: data.stackTrace?.toString(),
    );

    broadcaster.broadcastLog(event);
  }

  /// Maps Talker's [LogLevel] enum to [WatchdogLogLevel].
  WatchdogLogLevel _mapLevel(LogLevel? level) {
    return switch (level) {
      LogLevel.verbose => WatchdogLogLevel.verbose,
      LogLevel.debug => WatchdogLogLevel.debug,
      LogLevel.info => WatchdogLogLevel.info,
      LogLevel.warning => WatchdogLogLevel.warning,
      LogLevel.error => WatchdogLogLevel.error,
      LogLevel.critical => WatchdogLogLevel.critical,
      _ => WatchdogLogLevel.debug,
    };
  }
}