import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../bridge/watchdog_logger_bridge.dart';
import '../config/watchdog_config.dart';
import '../config/watchdog_dependencies.dart';
import '../interceptors/watchdog_chopper_interceptor.dart';
import '../interceptors/watchdog_dio_interceptor.dart';
import '../logging/watchdog_logger.dart';
import '../observers/watchdog_bloc_observer.dart';
import '../observers/watchdog_provider_observer.dart';
import '../observers/watchdog_route_observer.dart';
import '../trackers/watchdog_getit_tracker.dart';
import '../trackers/watchdog_location_tracker.dart';
import '../trackers/watchdog_permission_tracker.dart';
import '../trackers/watchdog_socket_tracker.dart';
import 'watchdog_noop.dart';
import 'watchdog_runtime.dart';

/// The single public entry point for the Watchdog package.
///
/// ## Minimal setup
///
/// ```dart
/// await Watchdog.initialize(
///   config: const WatchdogConfig(
///     apiBaseUrl: 'https://api.example.com',
///     enableLogging: true,
///   ),
/// );
/// Watchdog.start();
/// ```
///
/// Then wire the observers/interceptor into your app:
///
/// ```dart
/// MaterialApp.router(
///   routerConfig: appRouter.config(
///     navigatorObservers: () => [Watchdog.routeObserver],
///   ),
/// );
///
/// ChopperClient(interceptors: [Watchdog.chopperInterceptor]);
/// ```
///
/// Nothing else in the package is intended to be referenced directly.
abstract final class Watchdog {
  static WatchdogRuntime? _runtime;
  static Completer<void>? _initializing;

  /// Whether [initialize] has completed successfully.
  static bool get isInitialized => _runtime != null;

  /// Whether the local server (and optional cloud connection) is live.
  static bool get isRunning => _runtime?.isRunning ?? false;

  /// Initializes the package. Safe to call multiple times — only the first
  /// call performs work; concurrent callers await the same future; repeat
  /// calls after completion are a no-op.
  ///
  /// In release builds ([kReleaseMode] / [kProfileMode]) this is a no-op
  /// unless [WatchdogConfig.enabled] is explicitly set to `true`.
  static Future<void> initialize({
    WatchdogConfig config = const WatchdogConfig(),
    WatchdogDependencies dependencies = const WatchdogDependencies(),
  }) async {
    if (_runtime != null) return;
    if (_initializing != null) return _initializing!.future;

    final shouldRun = config.enabled ?? kDebugMode;
    if (!shouldRun) return;

    final completer = _initializing = Completer<void>();
    try {
      final runtime = WatchdogRuntime(
        config: config,
        dependencies: dependencies,
      );
      await runtime.boot();
      _runtime = runtime;
      completer.complete();
    } catch (error, stack) {
      completer.completeError(error, stack);
      rethrow;
    } finally {
      _initializing = null;
    }
  }

  /// Starts event capture: opens the local DevTools server and connects to
  /// the cloud (when configured). Idempotent.
  ///
  /// This is the **single-call entry point** — if [initialize] hasn't run yet
  /// it is performed automatically with the supplied [config]/[dependencies],
  /// so the common case is just:
  ///
  /// ```dart
  /// await Watchdog.start();                       // defaults
  /// await Watchdog.start(config: myConfig);        // with config
  /// ```
  ///
  /// Calling [initialize] separately beforehand still works; in that case the
  /// [config]/[dependencies] passed here are ignored. No-op if Watchdog is
  /// disabled (release builds without `enabled: true`).
  static Future<void> start({
    WatchdogConfig config = const WatchdogConfig(),
    WatchdogDependencies dependencies = const WatchdogDependencies(),
  }) async {
    if (_runtime == null) {
      await initialize(config: config, dependencies: dependencies);
    }
    final runtime = _runtime;
    if (runtime == null) return;
    await runtime.start();
  }

  /// Stops event capture without disposing the runtime. Use this to pause
  /// collection without losing the replay buffer. Idempotent.
  static Future<void> stop() async {
    await _runtime?.stop();
  }

  /// Fully disposes the runtime. Primarily used by hot-restart handling and
  /// tests. After calling this, [initialize] must be awaited again.
  static Future<void> dispose() async {
    await _runtime?.shutdown();
    _runtime = null;
  }

  // ── Accessors ─────────────────────────────────────────────────────────────
  //
  // These are safe to access **before** `initialize()` completes and in
  // release builds where Watchdog is disabled. When the runtime is absent
  // each accessor returns a cached no-op fallback, so host-app wiring code
  // (DI, router, Chopper) can reference them unconditionally without
  // worrying about initialization order.

  /// The active [WatchdogLogger]. Returns a no-op logger when Watchdog
  /// hasn't been initialized or is disabled.
  static WatchdogLogger get logger => _runtime?.logger ?? _fallbackLogger;

  /// Thin adapter for legacy project-level loggers. See [WatchdogLoggerBridge].
  static WatchdogLoggerBridge get bridge =>
      _runtime?.bridge ?? _fallbackBridge;

  /// BLoC observer. When the runtime isn't ready, a no-op observer is
  /// returned so callers can wire `Bloc.observer` unconditionally.
  static WatchdogBlocObserver get blocObserver =>
      _runtime?.blocObserver ?? _fallbackBlocObserver;

  /// Riverpod observer. Add it to your `ProviderScope(observers: [...])` to
  /// see every provider's lifecycle and state changes in the Instances tab —
  /// the Riverpod counterpart of [blocObserver]. A no-op observer is returned
  /// when the runtime isn't ready, so it's safe to wire unconditionally.
  ///
  /// ```dart
  /// ProviderScope(
  ///   observers: [Watchdog.providerObserver],
  ///   child: const MyApp(),
  /// );
  /// ```
  static WatchdogProviderObserver get providerObserver =>
      _runtime?.providerObserver ?? _fallbackProviderObserver;

  /// Navigator observer. Safe to attach to your router regardless of whether
  /// Watchdog has been initialized.
  static WatchdogRouteObserver get routeObserver =>
      _runtime?.routeObserver ?? _fallbackRouteObserver;

  /// Socket tracker for manually reporting WebSocket traffic. Calls to the
  /// returned tracker are silently discarded when Watchdog is inactive.
  static WatchdogSocketTracker get socketTracker =>
      _runtime?.socketTracker ?? _fallbackSocketTracker;

  /// Location tracker for reporting device location fixes. Streamed to the
  /// DevTools **Location** tab, which plots them live on a map. Calls to the
  /// returned tracker are silently discarded when Watchdog is inactive.
  ///
  /// ```dart
  /// Geolocator.getPositionStream().listen((p) {
  ///   Watchdog.locationTracker.track(
  ///     latitude: p.latitude,
  ///     longitude: p.longitude,
  ///     accuracy: p.accuracy,
  ///     speed: p.speed,
  ///     heading: p.heading,
  ///   );
  /// });
  /// ```
  static WatchdogLocationTracker get locationTracker =>
      _runtime?.locationTracker ?? _fallbackLocationTracker;

  /// Permission tracker for reporting device permission status. Streamed to
  /// the DevTools **Permissions** tab. Calls to the returned tracker are
  /// silently discarded when Watchdog is inactive.
  ///
  /// ```dart
  /// await Watchdog.permissionTracker.checkAndReportCommon();
  /// ```
  static WatchdogPermissionTracker get permissionTracker =>
      _runtime?.permissionTracker ?? _fallbackPermissionTracker;

  /// Updates (or adds) user-identity fields — `username`, `phoneNumber`,
  /// `email` — on the already-running session. Use this when the signed-in
  /// user isn't known yet at [initialize]/[start] time (the common case:
  /// Watchdog starts at app boot, login happens later). Merges into
  /// whatever [WatchdogConfig.device] info was set at startup and
  /// re-broadcasts the full snapshot to the local DevTools page and the
  /// cloud dashboard alike. No-op when Watchdog is inactive.
  ///
  /// ```dart
  /// // e.g. in a BlocListener once the user's profile loads:
  /// Watchdog.updateUser(username: profile.fullName, phoneNumber: profile.phoneNumber);
  /// ```
  static void updateUser({String? username, String? phoneNumber, String? email}) {
    final runtime = _runtime;
    if (runtime == null) return;
    runtime.broadcaster.updateDeviceInfo({
      if (username != null && username.isNotEmpty) 'username': username,
      if (phoneNumber != null && phoneNumber.isNotEmpty) 'phoneNumber': phoneNumber,
      if (email != null && email.isNotEmpty) 'email': email,
    });
  }

  /// Chopper interceptor to add to your `ChopperClient.interceptors`. A
  /// pass-through interceptor is returned when Watchdog is inactive, so it's
  /// safe to register during DI setup even before `initialize()` is awaited.
  static WatchdogChopperInterceptor get chopperInterceptor =>
      _runtime?.chopperInterceptor ?? _fallbackChopperInterceptor;

  /// Dio interceptor to add to your `Dio.interceptors`. Mirrors
  /// [chopperInterceptor] — captured Dio calls appear in the Network tab
  /// identically to Chopper calls. A no-op interceptor is returned when
  /// Watchdog is inactive, so it's safe to register during DI setup even
  /// before `start()` is awaited.
  ///
  /// ```dart
  /// final dio = Dio()..interceptors.add(Watchdog.dioInterceptor);
  /// ```
  static WatchdogDioInterceptor get dioInterceptor =>
      _runtime?.dioInterceptor ?? _fallbackDioInterceptor;

  // ── GetIt tracking ────────────────────────────────────────────────────────

  /// Scans a [GetIt] container and broadcasts every registration as an
  /// [InstanceEvent] so it appears in the DevTools Instances tab.
  ///
  /// Call **after** your DI configuration is complete:
  ///
  /// ```dart
  /// await configureDependencies();
  /// Watchdog.trackGetIt(getIt);
  /// ```
  static void trackGetIt(
    GetIt getIt, {
    bool instantiateLazy = true,
    bool callFactories = false,
  }) {
    final runtime = _runtime;
    if (runtime == null) return;
    WatchdogGetItTracker.trackAll(
      getIt,
      broadcaster: runtime.broadcaster,
      instantiateLazy: instantiateLazy,
      callFactories: callFactories,
    );
  }

  // ── Convenience log methods ───────────────────────────────────────────────

  static void debug(String message, {Object? error, StackTrace? stackTrace}) =>
      _runtime?.logger
          .debug(message, error: error, stackTrace: stackTrace);

  static void info(String message, {Object? error, StackTrace? stackTrace}) =>
      _runtime?.logger
          .info(message, error: error, stackTrace: stackTrace);

  static void warning(String message, {Object? error, StackTrace? stackTrace}) =>
      _runtime?.logger
          .warning(message, error: error, stackTrace: stackTrace);

  static void error(String message, {Object? error, StackTrace? stackTrace}) =>
      _runtime?.logger
          .error(message, error: error, stackTrace: stackTrace);

  static void critical(String message, {Object? error, StackTrace? stackTrace}) =>
      _runtime?.logger
          .critical(message, error: error, stackTrace: stackTrace);

  // ── Private fallbacks (lazily created when runtime is absent) ─────────────

  static NoopBroadcaster? _noopBroadcaster;
  static NoopBroadcaster get _broadcasterFallback =>
      _noopBroadcaster ??= NoopBroadcaster();

  static const WatchdogLogger _fallbackLogger = NoopLogger();

  static WatchdogLoggerBridge? _fallbackBridgeInstance;
  static WatchdogLoggerBridge get _fallbackBridge =>
      _fallbackBridgeInstance ??= WatchdogLoggerBridge(logger: _fallbackLogger);

  static WatchdogBlocObserver? _fallbackBlocObserverInstance;
  static WatchdogBlocObserver get _fallbackBlocObserver =>
      _fallbackBlocObserverInstance ??=
          WatchdogBlocObserver(broadcaster: _broadcasterFallback);

  static WatchdogProviderObserver? _fallbackProviderObserverInstance;
  static WatchdogProviderObserver get _fallbackProviderObserver =>
      _fallbackProviderObserverInstance ??=
          WatchdogProviderObserver(broadcaster: _broadcasterFallback);

  static WatchdogRouteObserver? _fallbackRouteObserverInstance;
  static WatchdogRouteObserver get _fallbackRouteObserver =>
      _fallbackRouteObserverInstance ??=
          WatchdogRouteObserver(broadcaster: _broadcasterFallback);

  static WatchdogSocketTracker? _fallbackSocketTrackerInstance;
  static WatchdogSocketTracker get _fallbackSocketTracker =>
      _fallbackSocketTrackerInstance ??=
          WatchdogSocketTracker(broadcaster: _broadcasterFallback);

  static WatchdogLocationTracker? _fallbackLocationTrackerInstance;
  static WatchdogLocationTracker get _fallbackLocationTracker =>
      _fallbackLocationTrackerInstance ??=
          WatchdogLocationTracker(broadcaster: _broadcasterFallback);

  static WatchdogPermissionTracker? _fallbackPermissionTrackerInstance;
  static WatchdogPermissionTracker get _fallbackPermissionTracker =>
      _fallbackPermissionTrackerInstance ??=
          WatchdogPermissionTracker(broadcaster: _broadcasterFallback);

  static WatchdogChopperInterceptor? _fallbackChopperInterceptorInstance;
  static WatchdogChopperInterceptor get _fallbackChopperInterceptor =>
      _fallbackChopperInterceptorInstance ??=
          WatchdogChopperInterceptor(broadcaster: _broadcasterFallback);

  static WatchdogDioInterceptor? _fallbackDioInterceptorInstance;
  static WatchdogDioInterceptor get _fallbackDioInterceptor =>
      _fallbackDioInterceptorInstance ??=
          WatchdogDioInterceptor(broadcaster: _broadcasterFallback);
}
