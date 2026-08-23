import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/watchdog_cloud_config.dart';
import '../config/watchdog_config.dart';
import '../config/watchdog_dependencies.dart';
import '../config/watchdog_device.dart';
import 'watchdog.dart';

/// Which state-management observer(s) `runWatchLocalApp` / `runWatchGlobalApp`
/// should wire up automatically.
enum StateManagement {
  /// Don't wire any state-management observer.
  none,

  /// Set `Bloc.observer` so BLoC/Cubit lifecycle appears in the Instances tab.
  bloc,

  /// Wrap the app in a `ProviderScope` with Watchdog's Riverpod observer.
  riverpod,

  /// Wire both BLoC and Riverpod.
  both,
}

/// Boots Watchdog in **local** mode (localhost DevTools) and runs [app].
///
/// One call replaces the usual `ensureInitialized` + `Watchdog.start` +
/// observer wiring + `runApp` boilerplate:
///
/// ```dart
/// void main() => runWatchLocalApp(
///   const MyApp(),
///   stateManagement: StateManagement.riverpod,
/// );
/// ```
///
/// All defaults are production-safe (no-op in release unless
/// `WatchdogConfig.enabled` is `true`). Pass [config] to override anything.
Future<void> runWatchLocalApp(
  Widget app, {
  WatchdogConfig config = const WatchdogConfig(),
  StateManagement stateManagement = StateManagement.none,
  List<ProviderObserver> observers = const [],
  WatchdogDependencies dependencies = const WatchdogDependencies(),
}) {
  return _runWatchApp(
    app,
    config.copyWith(global: false),
    stateManagement,
    observers,
    dependencies,
  );
}

/// Boots Watchdog in **global** (cloud-only) mode and runs [app].
///
/// The local localhost server is not started — every event is streamed to the
/// [cloud] server instead, so the app can be observed remotely from the cloud
/// dashboard. Provide a [device] so each running instance is distinguishable.
///
/// ```dart
/// void main() => runWatchGlobalApp(
///   const MyApp(),
///   cloud: const WatchdogCloudConfig(
///     serverUrl: 'ws://10.30.15.180:8080',
///     apiKey: 'wdg_dev_test_key_12345',
///     appName: 'pdaftar',
///   ),
///   device: WatchdogDevice(deviceName: deviceName, appVersion: '1.4.2'),
///   stateManagement: StateManagement.both,
/// );
/// ```
///
/// Note: global mode only actually streams when Watchdog is enabled
/// (`kDebugMode`, or `WatchdogConfig.enabled == true` for release devices).
Future<void> runWatchGlobalApp(
  Widget app, {
  required WatchdogCloudConfig cloud,
  WatchdogDevice? device,
  WatchdogConfig config = const WatchdogConfig(),
  StateManagement stateManagement = StateManagement.none,
  List<ProviderObserver> observers = const [],
  WatchdogDependencies dependencies = const WatchdogDependencies(),
}) {
  return _runWatchApp(
    app,
    config.copyWith(global: true, cloud: cloud, device: device ?? config.device),
    stateManagement,
    observers,
    dependencies,
  );
}

Future<void> _runWatchApp(
  Widget app,
  WatchdogConfig config,
  StateManagement stateManagement,
  List<ProviderObserver> observers,
  WatchdogDependencies dependencies,
) async {
  WidgetsFlutterBinding.ensureInitialized();

  await Watchdog.start(config: config, dependencies: dependencies);

  final wantsBloc = stateManagement == StateManagement.bloc ||
      stateManagement == StateManagement.both;
  final wantsRiverpod = stateManagement == StateManagement.riverpod ||
      stateManagement == StateManagement.both;

  if (wantsBloc) {
    Bloc.observer = Watchdog.blocObserver;
  }

  Widget root = app;
  if (wantsRiverpod) {
    root = ProviderScope(
      observers: [Watchdog.providerObserver, ...observers],
      child: app,
    );
  }

  runApp(root);
}
