import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../bridge/watchdog_logger_bridge.dart';
import '../cloud/watchdog_cloud_client.dart';
import '../config/watchdog_cloud_config.dart';
import '../config/watchdog_config.dart';
import '../config/watchdog_dependencies.dart';
import '../interceptors/watchdog_chopper_interceptor.dart';
import '../interceptors/watchdog_dio_interceptor.dart';
import '../logging/default_logger.dart';
import '../logging/watchdog_logger.dart';
import '../observers/watchdog_bloc_observer.dart';
import '../observers/watchdog_provider_observer.dart';
import '../observers/watchdog_route_observer.dart';
import '../server/watchdog_broadcaster.dart';
import '../server/watchdog_server.dart';
import '../trackers/watchdog_location_tracker.dart';
import '../trackers/watchdog_permission_tracker.dart';
import '../trackers/watchdog_socket_tracker.dart';

/// Internal orchestrator that owns every moving part of Watchdog.
///
/// Lifecycle:
///
///  1. [WatchdogRuntime.new] — wires dependencies, constructs collaborators.
///  2. [boot]                 — prepares the runtime; safe to await.
///  3. [start]                — opens the local server and optional cloud
///                              connection. Idempotent.
///  4. [stop]                 — closes network resources but keeps the
///                              runtime reusable. Idempotent.
///  5. [shutdown]             — tears the runtime down for good; used by
///                              hot-restart handling and tests.
///
/// Not exported from the package. Consumers interact with [Watchdog] only.
class WatchdogRuntime {
  WatchdogRuntime({
    required this.config,
    WatchdogDependencies dependencies = const WatchdogDependencies(),
  }) : _dependencies = dependencies;

  final WatchdogConfig config;
  final WatchdogDependencies _dependencies;

  static const _uuid = Uuid();

  late final DateTime Function() clock;
  late final String Function() idGenerator;
  late final WatchdogBroadcaster broadcaster;
  late final WatchdogLogger logger;
  late final WatchdogLoggerBridge bridge;
  late final WatchdogServer server;
  late final WatchdogBlocObserver blocObserver;
  late final WatchdogProviderObserver providerObserver;
  late final WatchdogRouteObserver routeObserver;
  late final WatchdogSocketTracker socketTracker;
  late final WatchdogLocationTracker locationTracker;
  late final WatchdogPermissionTracker permissionTracker;
  late final WatchdogChopperInterceptor chopperInterceptor;
  late final WatchdogDioInterceptor dioInterceptor;

  WatchdogCloudClient? _cloudClient;
  AppLifecycleListener? _lifecycleListener;
  bool _booted = false;
  bool _running = false;

  bool get isRunning => _running;

  /// Constructs and wires every collaborator. Safe to call once.
  Future<void> boot() async {
    if (_booted) return;

    clock = _dependencies.clock ?? DateTime.now;
    idGenerator = _dependencies.idGenerator ?? () => _uuid.v4();

    broadcaster = WatchdogBroadcaster(
      replayBufferSize: config.replayBufferSize,
    );

    logger = _dependencies.logger ??
        DefaultLogger(
          broadcaster: broadcaster,
          idGenerator: idGenerator,
          clock: clock,
        );

    bridge = WatchdogLoggerBridge(logger: logger);

    locationTracker = WatchdogLocationTracker(broadcaster: broadcaster);
    permissionTracker = WatchdogPermissionTracker(broadcaster: broadcaster);

    server = WatchdogServer(
      broadcaster: broadcaster,
      port: config.port,
      host: config.host,
      onLocationRefreshRequested: () => locationTracker.refreshLocation(),
    );

    blocObserver = WatchdogBlocObserver(broadcaster: broadcaster);
    providerObserver = WatchdogProviderObserver(broadcaster: broadcaster);
    routeObserver = WatchdogRouteObserver(broadcaster: broadcaster);
    socketTracker = WatchdogSocketTracker(broadcaster: broadcaster);
    chopperInterceptor = WatchdogChopperInterceptor(
      broadcaster: broadcaster,
      maskSensitiveHeaders: config.maskSensitiveHeaders,
    );
    dioInterceptor = WatchdogDioInterceptor(
      broadcaster: broadcaster,
      maskSensitiveHeaders: config.maskSensitiveHeaders,
    );

    _booted = true;
  }

  /// Starts event capture. In normal mode the local server runs (plus the
  /// cloud as an extra sink when configured); in [WatchdogConfig.global] mode
  /// only the cloud connection is opened. Idempotent.
  Future<void> start() async {
    if (!_booted) await boot();
    if (_running) return;

    final cloud = config.cloud;
    final deviceInfo = config.device?.toInfoJson();
    if (deviceInfo != null) broadcaster.setDeviceInfo(deviceInfo);

    if (config.global) {
      // ── Cloud-only mode ──────────────────────────────────────────────────
      if (cloud == null) {
        debugPrint(
          'Watchdog: global mode requires a cloud config — nothing started.',
        );
        return;
      }
      _connectCloud(cloud, deviceInfo);
      await _cloudClient!.connect();
      // ignore: avoid_print
      print(
        '\n🐕 Watchdog GLOBAL mode → streaming to ${cloud.serverUrl}\n'
        '   session: ${config.device?.sessionId ?? cloud.sessionId ?? '(generated)'}\n',
      );
    } else {
      // ── Local mode (+ optional cloud) ────────────────────────────────────
      await server.start();
      if (cloud != null) {
        _connectCloud(cloud, deviceInfo);
        await _cloudClient!.connect();
      }
    }

    // Force an immediate cloud reconnect every time the app returns to the
    // foreground (mobile OSes drop the socket while backgrounded), and
    // re-check permissions on the same trigger — the most common time their
    // status actually changes is the user coming back from Settings.
    try {
      _lifecycleListener = AppLifecycleListener(
        onResume: () {
          _cloudClient?.reconnectNow();
          unawaited(permissionTracker.checkAndReportCommon());
        },
      );
    } catch (_) {
      // WidgetsBinding not ready (e.g. unit tests) — skip lifecycle hook;
      // the reconnect backoff timer still covers the cloud side.
    }

    // Automatic baseline permission report — no app code required. Safe to
    // fire immediately even before the cloud socket finishes connecting;
    // WatchdogCloudClient queues events until it's actually open instead of
    // dropping them. Apps that want snappier feedback right after a
    // permission *request* (rather than waiting for this or the next
    // resume) can still call `Watchdog.permissionTracker.checkAndReport(...)`
    // directly — both are safe to call any number of times.
    unawaited(permissionTracker.checkAndReportCommon());

    Bloc.observer = blocObserver;

    _running = true;
  }

  void _connectCloud(WatchdogCloudConfig cloud, Map<String, dynamic>? info) {
    _cloudClient = WatchdogCloudClient(
      serverUrl: cloud.serverUrl,
      apiKey: cloud.apiKey,
      // Prefer a STABLE id (explicit sessionId → deviceId) so re-running the
      // app reuses the same cloud session instead of piling up new ones. Only
      // falls back to a random id when no device identity is available.
      sessionId: config.device?.sessionId ??
          config.device?.deviceId ??
          cloud.sessionId ??
          idGenerator(),
      appName: _composeAppName(cloud.appName),
      deviceInfo: info,
      onLocationRefreshRequested: () => locationTracker.refreshLocation(),
    );
    broadcaster.attachCloud(_cloudClient!);
  }

  /// Folds the device name into the cloud session label so the dashboard can
  /// distinguish multiple devices, e.g. "move_green · Akmal's iPhone".
  String _composeAppName(String baseAppName) {
    final device = config.device;
    if (device == null) return baseAppName;
    final name = device.resolvedDeviceName();
    if (name.isEmpty || name == baseAppName) return baseAppName;
    return '$baseAppName · $name';
  }

  /// Closes network resources but keeps the runtime reusable (e.g. for a
  /// subsequent [start] call). Idempotent.
  Future<void> stop() async {
    if (!_running) return;
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    await broadcaster.detachCloud();
    _cloudClient = null;
    await server.stop();
    _running = false;
  }

  /// Tears the runtime down completely. Used by hot-restart handling.
  Future<void> shutdown() async {
    await locationTracker.stopAutoTracking();
    await stop();
    await broadcaster.dispose();
  }
}
