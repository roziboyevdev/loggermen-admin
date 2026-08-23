import 'package:talker/talker.dart' as talker_api;

import '../models/log_event.dart';
import '../server/watchdog_broadcaster.dart';
import 'watchdog_logger.dart';

/// Default [WatchdogLogger] implementation, backed by [Talker].
///
/// Writes every log to the underlying Talker instance (so it shows up in any
/// in-app Talker viewer) and forwards a [LogEvent] to [WatchdogBroadcaster]
/// so the DevTools Logs tab stays in sync.
class DefaultLogger implements WatchdogLogger {
  DefaultLogger({
    required this.broadcaster,
    required this.idGenerator,
    required this.clock,
    talker_api.Talker? talker,
  }) : talker = talker ??
            talker_api.Talker(
              settings: talker_api.TalkerSettings(
                useConsoleLogs: false,
                enabled: true,
              ),
            );

  final WatchdogBroadcaster broadcaster;
  final String Function() idGenerator;
  final DateTime Function() clock;

  /// The Talker instance the default logger writes to. Exposed so consumers
  /// that already use Talker in-app can share history.
  final talker_api.Talker talker;

  @override
  void log(
    WatchdogLogLevel level,
    String message, {
    String? title,
    Object? error,
    StackTrace? stackTrace,
  }) {
    switch (level) {
      case WatchdogLogLevel.verbose:
        talker.verbose(message);
        break;
      case WatchdogLogLevel.debug:
        talker.debug(message, error, stackTrace);
        break;
      case WatchdogLogLevel.info:
        talker.info(message, error, stackTrace);
        break;
      case WatchdogLogLevel.warning:
        talker.warning(message, error, stackTrace);
        break;
      case WatchdogLogLevel.error:
        talker.error(message, error, stackTrace);
        break;
      case WatchdogLogLevel.critical:
        talker.critical(message, error, stackTrace);
        break;
    }

    broadcaster.broadcastLog(
      LogEvent(
        id: idGenerator(),
        timestamp: clock(),
        level: level,
        message: message,
        title: title,
        error: error?.toString(),
        stackTrace: stackTrace?.toString(),
      ),
    );
  }

  @override
  void debug(String message, {Object? error, StackTrace? stackTrace}) =>
      log(WatchdogLogLevel.debug, message, error: error, stackTrace: stackTrace);

  @override
  void info(String message, {Object? error, StackTrace? stackTrace}) =>
      log(WatchdogLogLevel.info, message, error: error, stackTrace: stackTrace);

  @override
  void warning(String message, {Object? error, StackTrace? stackTrace}) =>
      log(WatchdogLogLevel.warning, message, error: error, stackTrace: stackTrace);

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      log(WatchdogLogLevel.error, message, error: error, stackTrace: stackTrace);

  @override
  void critical(String message, {Object? error, StackTrace? stackTrace}) =>
      log(WatchdogLogLevel.critical, message, error: error, stackTrace: stackTrace);

  @override
  void verbose(String message) => log(WatchdogLogLevel.verbose, message);
}
