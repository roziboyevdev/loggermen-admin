import '../logging/watchdog_logger.dart';

/// Optional dependency-injection container for [Watchdog.initialize].
///
/// Consumers who need to override defaults — e.g. supply their own logger
/// implementation, inject a deterministic clock in tests, or plug in a
/// custom id generator — pass a populated [WatchdogDependencies] instance.
///
/// Any field left null falls back to the built-in default.
class WatchdogDependencies {
  const WatchdogDependencies({
    this.logger,
    this.clock,
    this.idGenerator,
  });

  /// Override the default Talker-backed logger with your own implementation.
  ///
  /// The supplied instance becomes the logger exposed via [Watchdog.logger]
  /// and receives every log call made through the [Watchdog] facade.
  final WatchdogLogger? logger;

  /// Clock used to timestamp events. Defaults to `DateTime.now`.
  final DateTime Function()? clock;

  /// Identifier generator used for event ids. Defaults to a UUID v4 generator.
  final String Function()? idGenerator;
}
