/// Watchdog — Flutter developer toolkit.
///
/// Streams HTTP requests, responses, BLoC lifecycle events, navigation, and
/// app logs from your Flutter app to a browser-based DevTools page in
/// real-time.
///
/// ## Quick start
///
/// **Option A — one-liner (recommended):**
///
/// ```dart
/// import 'package:watchdog/watchdog.dart';
///
/// void main() => runWatchLocalApp(
///   const MyApp(),
///   stateManagement: StateManagement.bloc, // or .riverpod / .both / .none
/// );
/// ```
///
/// **Option B — manual:**
///
/// ```dart
/// import 'package:flutter/widgets.dart';
/// import 'package:watchdog/watchdog.dart';
///
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await Watchdog.start();
///   runApp(const MyApp());
/// }
/// ```
///
/// Wire interceptors/observers where you set up your HTTP client / router:
///
/// ```dart
/// ChopperClient(interceptors: [Watchdog.chopperInterceptor]);
/// final dio = Dio()..interceptors.add(Watchdog.dioInterceptor);
/// MaterialApp(navigatorObservers: [Watchdog.routeObserver]);
/// ```
///
/// Then run `watchdog open` to launch the browser DevTools page.
library watchdog;

// ── Public entry point ──────────────────────────────────────────────────────
export 'src/core/watchdog.dart' show Watchdog;
export 'src/core/watchdog_run.dart'
    show runWatchLocalApp, runWatchGlobalApp, StateManagement;

// ── Configuration ───────────────────────────────────────────────────────────
export 'src/config/watchdog_config.dart' show WatchdogConfig;
export 'src/config/watchdog_cloud_config.dart' show WatchdogCloudConfig;
export 'src/config/watchdog_dependencies.dart' show WatchdogDependencies;
export 'src/config/watchdog_device.dart' show WatchdogDevice;

// ── Logging abstraction ─────────────────────────────────────────────────────
export 'src/logging/watchdog_logger.dart' show WatchdogLogger, WatchdogLogLevel;
export 'src/bridge/watchdog_logger_bridge.dart' show WatchdogLoggerBridge;

// ── Event models (read-only data types surfaced by listeners) ───────────────
export 'src/models/location_event.dart' show LocationEvent;
export 'src/models/permission_event.dart' show PermissionEvent;
export 'src/models/log_event.dart' show LogEvent;
export 'src/models/network_event.dart' show NetworkEvent, NetworkEventStatus;
export 'src/models/route_event.dart' show RouteEvent, RouteAction;
export 'src/models/socket_event.dart' show SocketEvent, SocketDirection;
export 'src/models/instance_event.dart'
    show InstanceEvent, InstanceCategory, InstanceAction;

// ── Integrations — constructed by the runtime, exposed for typing only ──────
export 'src/observers/watchdog_bloc_observer.dart' show WatchdogBlocObserver;
export 'src/observers/watchdog_provider_observer.dart'
    show WatchdogProviderObserver;
export 'src/observers/watchdog_route_observer.dart' show WatchdogRouteObserver;
export 'src/interceptors/watchdog_chopper_interceptor.dart'
    show WatchdogChopperInterceptor;
export 'src/interceptors/watchdog_dio_interceptor.dart'
    show WatchdogDioInterceptor;
export 'src/trackers/watchdog_socket_tracker.dart' show WatchdogSocketTracker;
export 'src/trackers/watchdog_location_tracker.dart'
    show WatchdogLocationTracker;
export 'src/trackers/watchdog_permission_tracker.dart'
    show WatchdogPermissionTracker;

// Re-exported so apps don't need a direct `permission_handler` dependency
// just to call `Watchdog.permissionTracker.checkAndReport` for a permission
// beyond the built-in location/notification pair.
export 'package:permission_handler/permission_handler.dart'
    show Permission, PermissionStatus;
export 'src/trackers/watchdog_location_options.dart'
    show WatchdogAutoTrackingOptions, WatchdogAndroidForegroundNotification;
export 'src/trackers/watchdog_location_exceptions.dart'
    show
        WatchdogLocationException,
        WatchdogLocationServiceDisabledException,
        WatchdogLocationPermissionDeniedException,
        WatchdogLocationPermissionDeniedForeverException;

// ── Re-exported so apps don't need a direct `geolocator` dependency just to
//    consume Watchdog's built-in location fetch/stream API. ─────────────────
export 'package:geolocator/geolocator.dart'
    show Position, LocationAccuracy, LocationPermission;
