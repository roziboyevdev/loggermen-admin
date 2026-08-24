// Minimal integration example for the Watchdog package.
//
// Runs in local + cloud mirror mode: events show up both on the on-device
// DevTools page and in the watchdog-nest dashboard.
//
//   flutter run --dart-define-from-file=build.json
//
// See example/build.example.json for the values it expects.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:watchdog/watchdog.dart';

/// Base URL of the watchdog-nest server — **origin only, no path**. The package
/// appends `/ws/app` itself, so `wss://host/watchdog` would end up requesting
/// `wss://host/watchdog/ws/app`.
const String kServerUrl = String.fromEnvironment(
  'WATCHDOG_SERVER_URL',
  defaultValue: '',
);

/// Must match `WATCHDOG_CLIENT_API_KEY` in the server's `.env`.
const String kClientApiKey = String.fromEnvironment(
  'WATCHDOG_CLIENT_API_KEY',
  defaultValue: '',
);

/// Fixed so re-running the example reuses one session in the dashboard instead
/// of creating a new row per launch (the package falls back to a random UUID
/// when no device id is given).
const String kDeviceId = String.fromEnvironment(
  'WATCHDOG_DEVICE_ID',
  defaultValue: 'watchdog-example',
);

/// Cloud is wired only when both values were supplied at build time; without
/// them the example still works as a purely local demo.
const bool kCloudEnabled = kServerUrl != '' && kClientApiKey != '';

/// True when [url] is something `WatchdogCloudClient` can actually dial.
///
/// Without this a bad `--dart-define` (an empty string, a pasted Dart VM
/// service URL, a plain host with no scheme) is only discovered as an endless
/// "Connection refused" retry loop against an address nobody intended.
bool isValidWatchdogServerUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return false;
  if (uri.scheme != 'ws' && uri.scheme != 'wss') return false;
  if (uri.host.isEmpty) return false;
  // The package appends "/ws/app" itself; a path here produces
  // ".../whatever/ws/app" and silently never connects.
  if (uri.path.isNotEmpty && uri.path != '/') return false;
  return true;
}

// A Dio client wired with Watchdog — every request now shows up in the
// Network tab exactly like a Chopper one would.
final dio = Dio(BaseOptions(baseUrl: 'https://jsonplaceholder.typicode.com'))
  ..interceptors.add(Watchdog.dioInterceptor);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final cloudReady = kCloudEnabled && isValidWatchdogServerUrl(kServerUrl);
  if (kCloudEnabled && !cloudReady) {
    debugPrint(
      '[Watchdog] Ignoring WATCHDOG_SERVER_URL="$kServerUrl" - it must be an '
      'origin such as wss://host (no path). Running local-only.',
    );
  } else if (!kCloudEnabled) {
    debugPrint(
      '[Watchdog] Local-only: pass --dart-define-from-file=build.json to '
      'mirror events to the cloud dashboard.',
    );
  }

  // Single-call start — no separate initialize() needed.
  await Watchdog.start(
    config: WatchdogConfig(
      enabled: true,
      cloud: cloudReady
          ? const WatchdogCloudConfig(
              serverUrl: kServerUrl,
              apiKey: kClientApiKey,
              appName: 'watchdog-example',
            )
          : null,
      device: const WatchdogDevice(
        deviceId: kDeviceId,
        appName: 'watchdog-example',
      ),
    ),
  );

  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Watchdog Example',
      debugShowCheckedModeBanner: false,
      home: ExamplePage(),
    );
  }
}

class ExamplePage extends StatelessWidget {
  const ExamplePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🐕 Watchdog Example')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Open http://localhost:8888 in Chrome\n'
              'to see live logs and network events.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                kCloudEnabled && isValidWatchdogServerUrl(kServerUrl)
                    ? 'Mirroring to $kServerUrl\nsession: $kDeviceId'
                    : 'Local only — pass --dart-define-from-file=build.json\n'
                        'to mirror events to the cloud dashboard.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                // Both a successful and a failing Dio call — watch them land
                // in the Network tab.
                await dio.get<dynamic>('/todos/1');
                try {
                  await dio.get<dynamic>('/this-route-does-not-exist');
                } on DioException {
                  // 404 still shows up as a (red) row in the Network tab.
                }
              },
              child: const Text('Fire Dio requests'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                Watchdog.info('Button tapped', stackTrace: StackTrace.current);
              },
              child: const Text('Log an INFO event'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () {
                Watchdog.warning('This is a warning');
              },
              child: const Text('Log a WARNING'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                Watchdog.error(
                  'Simulated error',
                  error: Exception('Something went wrong'),
                  stackTrace: StackTrace.current,
                );
              },
              child: const Text('Log an ERROR'),
            ),
          ],
        ),
      ),
    );
  }
}
