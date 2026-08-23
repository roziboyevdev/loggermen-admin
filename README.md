# Watchdog

A Flutter developer toolkit that streams HTTP requests, responses, BLoC
lifecycle events, navigation, and app logs to a browser-based DevTools
page in real-time. No IDE plugins, no native tooling, no account.

```
flutter run                watchdog open
   │                           │
   ▼                           ▼
┌───────────────┐         ┌───────────────┐
│ your app      │◀────────│ browser tab   │
│  Watchdog     │   :8888 │  localhost    │
└───────────────┘         └───────────────┘
```

---

## 2-minute quickstart

Five steps. Copy-paste each block as you go.

### 1. Add the dependency

`pubspec.yaml`:

```yaml
dependencies:
  watchdog: ^0.2.0
```

```bash
flutter pub get
```

### 2. Start before `runApp`

`main.dart` — pick the pattern that fits your project:

**Option A — one-liner (recommended)**

```dart
import 'package:watchdog/watchdog.dart';

// Replaces ensureInitialized + Watchdog.start + runApp in one call.
void main() => runWatchLocalApp(
  const MyApp(),
  stateManagement: StateManagement.bloc, // or .riverpod / .both / .none
);
```

`runWatchLocalApp` handles `WidgetsFlutterBinding.ensureInitialized()`,
`Watchdog.start()`, BLoC/Riverpod observer wiring, and `runApp` for you.

**Option B — manual (more control)**

```dart
import 'package:flutter/widgets.dart';
import 'package:watchdog/watchdog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Watchdog.start(); // one call — initializes on first use

  runApp(const MyApp());
}
```

Either way, Watchdog only runs in debug builds — release builds are a
no-op, so it's safe to leave in production code.

### 3. Wire the observers where you already use your HTTP client / Navigator

Only add the lines you need. Skip the ones that don't apply.

```dart
// HTTP inspection — Chopper:
ChopperClient(interceptors: [Watchdog.chopperInterceptor]);

// HTTP inspection — Dio (same Network tab, identical view):
final dio = Dio()..interceptors.add(Watchdog.dioInterceptor);

// State management — Riverpod (Instances tab):
ProviderScope(observers: [Watchdog.providerObserver], child: const MyApp());

// Navigation events:
MaterialApp(navigatorObservers: [Watchdog.routeObserver]);

// DI registrations (GetIt) — after configureDependencies():
Watchdog.trackGetIt(getIt);
```

State management is optional and pluggable — use **BLoC/Cubit**, **Riverpod**,
or both. BLoC/Cubit lifecycle is wired automatically by `Watchdog.start()`;
for Riverpod, add `Watchdog.providerObserver` to your `ProviderScope`. Both
feed the same Instances tab.

### 4. Install the CLI (once per machine)

```bash
dart pub global activate watchdog
```

Then add pub's `bin` directory to your PATH. Pick the block for **your
shell** (see [PATH setup details](#path-setup-details) if unsure):

<details>
<summary><b>macOS / Linux</b> (zsh or bash)</summary>

```bash
echo 'export PATH="$PATH:$HOME/.pub-cache/bin"' >> ~/.zshrc
source ~/.zshrc
```

Use `~/.bashrc` instead of `~/.zshrc` if you're on bash.
</details>

<details>
<summary><b>Windows — Git Bash</b></summary>

```bash
echo 'watchdog() { "$(cygpath "$LOCALAPPDATA/Pub/Cache/bin/watchdog.bat")" "$@"; }' >> ~/.bashrc
source ~/.bashrc
```
</details>

<details>
<summary><b>Windows — PowerShell</b></summary>

```powershell
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";$env:LOCALAPPDATA\Pub\Cache\bin", "User")
```

Close and reopen the terminal afterwards.
</details>

Verify:

```bash
watchdog version
```

### 5. Open DevTools

With the app running on a device or emulator:

```bash
watchdog open
```

Your browser opens `http://localhost:8888`. You're done.

---

## What you get

- **Network inspector** — every Chopper *or* Dio HTTP request/response with
  headers, body, status, timing, and cURL export.
- **BLoC lifecycle** — creation, state changes, and closure of every Bloc
  and Cubit, with creation stack traces.
- **Riverpod lifecycle** — provider init, updates, and disposal in the same
  Instances tab (optional; wire `Watchdog.providerObserver`).
- **Navigation** — push, pop, replace, remove events with a live route stack.
- **Structured logging** — debug / info / warning / error / critical levels.
- **WebSocket tracker** — send, receive, and connection state events.
- **Location tracking** — live device position on a map (accuracy circle +
  recent-fixes trail), optionally with speed, heading, and a custom label.
- **GetIt scanner** — broadcasts every DI registration.
- **Cloud streaming** — optionally mirror events to a remote server.
- **Replay buffer** — late-connecting browsers receive full event history.

---

## Daily usage

```bash
watchdog open               # the one you'll use 99% of the time
watchdog open --port 9000   # custom port
watchdog open --no-adb      # iOS-only / real-WiFi (skip adb)
watchdog forward            # set up port forwarding, no browser
watchdog devices            # list adb devices
watchdog version            # print CLI version
```

### Convenience logging

```dart
Watchdog.debug('Cache miss for key=$key');
Watchdog.info('Driver connected');
Watchdog.warning('GPS accuracy degraded: ${accuracy}m');
Watchdog.error('Sync failed', error: e, stackTrace: st);
```

### WebSocket tracking

```dart
Watchdog.socketTracker.trackSend(channel: 'wss://api.example.com/ws', data: payload);
Watchdog.socketTracker.trackReceive(channel: 'wss://api.example.com/ws', data: decoded);
```

### Location tracking

**Recommended — let Watchdog fetch the location itself.** No `geolocator`
glue code in your app; permission handling, the platform calls, and
reporting to the dashboard are all built in.

One-shot fetch (e.g. a "use my current location" button):

```dart
try {
  final position = await Watchdog.locationTracker.getCurrentLocation();
  // use position.latitude / position.longitude as usual
} on WatchdogLocationPermissionDeniedException {
  // show your own "location needed" UI
} on WatchdogLocationPermissionDeniedForeverException {
  // send the user to app settings
} on WatchdogLocationServiceDisabledException {
  // prompt to turn on GPS
}
```

Continuous tracking (e.g. a driver during a trip):

```dart
await Watchdog.locationTracker.startAutoTracking(
  const WatchdogAutoTrackingOptions(
    distanceFilter: 10,
    interval: Duration(seconds: 5),
    // Omit this to track foreground-only. Include it to survive the app
    // being backgrounded on Android (requires a foreground-service).
    androidForegroundNotification: WatchdogAndroidForegroundNotification(
      title: 'Trip active',
      text: 'Sharing your location',
    ),
  ),
);

// Your app still gets every fix for its own logic (route drawing, map
// centering, pushing over your own socket) — it's already been reported
// to the dashboard, so you don't call track() yourself:
Watchdog.locationTracker.stream.listen((position) { ... });

// Later, e.g. when the trip ends:
await Watchdog.locationTracker.stopAutoTracking();
```

The stream auto-restarts itself if the platform stream dies or goes stale
(no fix for `staleFixTimeout`, default 2 minutes) — configure per-call via
`WatchdogAutoTrackingOptions`. `Position`, `LocationAccuracy`, and
`LocationPermission` are re-exported from `package:watchdog/watchdog.dart`,
so this API works without adding `geolocator` as a direct dependency.

You still need to declare platform permissions yourself (Watchdog can't do
this for you — it's app-specific):

- **Android** (`android/app/src/main/AndroidManifest.xml`):
  ```xml
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
  <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
  <!-- Only if you pass androidForegroundNotification: -->
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
  ```
- **iOS** (`ios/Runner/Info.plist`):
  ```xml
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>Used to show your position on the map.</string>
  <!-- Only if you set iosAllowBackgroundLocationUpdates: true, plus the
       "Background Modes > Location updates" capability in Xcode: -->
  <key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
  <string>Used to keep tracking your trip while the app is in the background.</string>
  ```

**Manual `track()`** — still available for fixes that come from something
other than `geolocator` (a platform channel, an ELD SDK's own GPS module):

```dart
Watchdog.locationTracker.track(
  latitude: position.latitude,
  longitude: position.longitude,
  accuracy: position.accuracy,
  speed: position.speed,
  heading: position.heading,
  altitude: position.altitude,
);
```

`label` is optional and shown next to the pin — handy for a driver name or
current duty status. The dashboard's **Location** tab plots fixes live on a
map with an accuracy circle and a trail of recent points, and has a refresh
button that asks the device for a fresh fix on demand — no app code needed,
`Watchdog.locationTracker` answers that automatically (fetches once with
permission escalation disabled, so a remote click never pops a permission
dialog on someone else's device).

---

## Configuration

Pass a `WatchdogConfig` to `initialize()` to override defaults:

```dart
await Watchdog.initialize(
  config: const WatchdogConfig(
    apiBaseUrl: 'https://api.example.com',
    enableLogging: true,
  ),
);
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `apiBaseUrl` | `null` | Shown in the DevTools header for environment ID |
| `port` | `8888` | Local server port |
| `host` | `0.0.0.0` | Bind address |
| `enableLogging` | `true` | Enable log events in the Logs tab |
| `maskSensitiveHeaders` | `true` | Mask `Authorization` headers in the UI |
| `replayBufferSize` | `10000` | Max events retained for late clients |
| `enabled` | `null` | `null` = `kDebugMode`; `true` forces enable |
| `global` | `false` | When `true`, skips local server — streams to cloud only |
| `cloud` | `null` | `WatchdogCloudConfig` for remote streaming |
| `device` | `null` | `WatchdogDevice` — identifies this instance in the cloud dashboard |

---

## Running the example against the cloud server

`example/` is a small app wired for **local + cloud mirror** mode: every event
lands both on the on-device DevTools page and in the watchdog-nest dashboard.
Handy for checking a deployment without touching a real app.

```bash
cd example
cp build.example.json build.json     # then fill in the values
flutter run --dart-define-from-file=build.json
```

| Key | Meaning |
|-----|---------|
| `WATCHDOG_SERVER_URL` | Server **origin**, no path — `wss://your-domain`. The package appends `/ws/app` itself, so `wss://host/watchdog` would become `wss://host/watchdog/ws/app` |
| `WATCHDOG_CLIENT_API_KEY` | Must match `WATCHDOG_CLIENT_API_KEY` in the server's `.env` |
| `WATCHDOG_DEVICE_ID` | Optional. Fixed so re-running reuses one session instead of creating a row per launch |

`build.json` is gitignored — it holds the client key. `build.example.json` is
the committed template.

Without the flag the example still runs, local-only; the screen says which mode
it is in. On a real device use the machine's LAN address (`ws://192.168.1.50:8080`),
not `localhost`, which is the phone itself.

---

## Advanced

<details>
<summary><b>Custom logger</b> — integrate your own logging backend</summary>

```dart
class MyLogger implements WatchdogLogger {
  @override
  void log(WatchdogLogLevel level, String message,
      {String? title, Object? error, StackTrace? stackTrace}) {
    // your implementation
  }
}

await Watchdog.initialize(
  dependencies: WatchdogDependencies(logger: MyLogger()),
);
```

</details>

<details>
<summary><b>Cloud streaming (local + cloud)</b> — mirror events to a remote server alongside local DevTools</summary>

```dart
await Watchdog.initialize(
  config: const WatchdogConfig(
    cloud: WatchdogCloudConfig(
      serverUrl: 'wss://watchdog-cloud.example.com',
      apiKey: 'your-api-key',
      appName: 'my-app',
    ),
  ),
);
```

</details>

<details>
<summary><b>Global (cloud-only) mode</b> — stream remotely, skip localhost server</summary>

Use `runWatchGlobalApp` to disable the local server and stream only to the cloud.
Useful for observing devices that aren't physically connected to your machine.

```dart
import 'package:watchdog/watchdog.dart';

void main() => runWatchGlobalApp(
  const MyApp(),
  cloud: const WatchdogCloudConfig(
    serverUrl: 'wss://watchdog-cloud.example.com',
    apiKey: 'your-api-key',
    appName: 'my-app',
  ),
  device: WatchdogDevice(deviceName: 'Pixel 7', appVersion: '1.0.0'),
  stateManagement: StateManagement.both,
);
```

Or manually with `WatchdogConfig(global: true, cloud: ...)`.

</details>

<details>
<summary><b>WatchdogDevice</b> — identify instances in the cloud dashboard</summary>

```dart
WatchdogDevice(
  deviceName: 'Samsung Galaxy S24',
  appVersion: '2.1.0',
  // optional: platform, osVersion, etc. auto-detected when omitted
)
```

Pass this to `runWatchGlobalApp(device: ...)` or `WatchdogConfig(device: ...)`.

</details>

<details>
<summary><b>Bridge an existing project logger</b></summary>

```dart
AppLogger.attachBridge(Watchdog.bridge);
```

</details>

---

## Troubleshooting

**`watchdog: command not found`**
The pub cache `bin` directory isn't on your `PATH`. Redo step 4.

**Browser shows "This site can't be reached" / ERR_CONNECTION_REFUSED**
Three things to check, in order:
1. The Flutter app is running on a device/emulator (not just built).
2. You're on a debug build (`flutter run` without `--release`).
3. `adb devices` lists your device. If `adb` isn't on PATH, install
   Android platform-tools or use `watchdog open --no-adb` for iOS.

**`adb forward failed: cannot bind listener`**
A previous forwarding is stuck. Run:
```bash
adb forward --remove-all && watchdog open
```

---

## PATH setup details

`dart pub global activate` installs the `watchdog` executable into the
Dart pub cache, but **does not** add that directory to your `PATH`. Until
you do it yourself, typing `watchdog` won't find the binary.

The pub cache lives at:
- macOS / Linux: `~/.pub-cache/bin`
- Windows: `%LOCALAPPDATA%\Pub\Cache\bin`

On **Windows + Git Bash**, simply adding that directory to `PATH` isn't
enough because pub installs the executable as `watchdog.bat` and Git Bash
doesn't auto-append `.bat` when resolving commands. That's why step 4's
Git Bash block defines a shell function that invokes the `.bat` file
directly — it works regardless of extension handling.

---

## Public API summary

### Top-level helpers

| Function | Description |
|----------|-------------|
| `runWatchLocalApp(app, ...)` | One-liner boot: local DevTools + optional BLoC/Riverpod wiring |
| `runWatchGlobalApp(app, cloud:, ...)` | One-liner boot: cloud-only mode (no localhost server) |

`StateManagement` enum values: `none` · `bloc` · `riverpod` · `both`

### Watchdog class

| Accessor | Type | Description |
|----------|------|-------------|
| `Watchdog.initialize()` | `Future<void>` | One-time setup (optional — `start()` does it) |
| `Watchdog.start()` | `Future<void>` | Initializes if needed + opens server + cloud |
| `Watchdog.stop()` | `Future<void>` | Pauses capture |
| `Watchdog.dispose()` | `Future<void>` | Full teardown |
| `Watchdog.logger` | `WatchdogLogger` | Active logger instance |
| `Watchdog.bridge` | `WatchdogLoggerBridge` | Legacy logger adapter |
| `Watchdog.blocObserver` | `WatchdogBlocObserver` | BLoC/Cubit lifecycle observer |
| `Watchdog.providerObserver` | `WatchdogProviderObserver` | Riverpod lifecycle observer |
| `Watchdog.routeObserver` | `WatchdogRouteObserver` | Navigation observer |
| `Watchdog.chopperInterceptor` | `WatchdogChopperInterceptor` | Chopper HTTP interceptor |
| `Watchdog.dioInterceptor` | `WatchdogDioInterceptor` | Dio HTTP interceptor |
| `Watchdog.socketTracker` | `WatchdogSocketTracker` | WebSocket tracker |
| `Watchdog.locationTracker` | `WatchdogLocationTracker` | Location tracker |
| `Watchdog.trackGetIt()` | `void` | Scans GetIt container |
| `Watchdog.isInitialized` | `bool` | Init state |
| `Watchdog.isRunning` | `bool` | Server state |

---

## License

MIT — see [LICENSE](LICENSE).
