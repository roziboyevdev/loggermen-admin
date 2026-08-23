## 0.6.2

- **Fixed the real reason the Permissions tab could stay empty even with
  everything wired correctly.** `WatchdogCloudClient.send()` silently
  dropped any event broadcast before the WebSocket handshake finished —
  `connect()` doesn't wait for that handshake before returning, so there's
  a real (if short) window between `Watchdog.start()` returning and the
  socket actually being open. A one-shot report fired in that window (like
  a permission check right after startup) was gone for good; nothing
  re-sends a one-shot report the way continuous location/network traffic
  eventually gets through once the socket is up. Fixed with a pending
  buffer: events sent while disconnected are now queued in order and
  flushed the moment the socket opens (on first connect *and* every
  reconnect), instead of dropped.
- **Permission checks are now automatic — no app code required.**
  `Watchdog.start()` now calls `permissionTracker.checkAndReportCommon()`
  once on its own, and again every time the app returns to the foreground
  (reusing the existing resume hook that already reconnects the cloud
  socket). This is the point of putting permission tracking in the package
  in the first place: every project gets location + notification status in
  the Permissions tab automatically, with zero setup, not just the ones
  that remembered to call `checkAndReportCommon()` themselves. Calling it
  yourself right after requesting a permission is still worthwhile for
  faster feedback than waiting for the next resume — both are safe to call
  any number of times.

## 0.6.1

- **Permission check failures are no longer silent.** If
  `checkAndReport`/`checkAndReportCommon` can't read a permission's status
  (most commonly: `permission_handler`'s native side isn't linked yet
  because the app was hot-reloaded/restarted instead of fully rebuilt after
  adding the dependency, or the platform manifest/Info.plist entry is
  missing), it now reports an `'unavailable'` status — shown as a red card
  in the Permissions tab, same as `denied` — and logs a warning to the Logs
  tab explaining the likely cause. Previously the failure was swallowed
  entirely, so a misconfigured permission just never appeared, with no way
  to tell why.

## 0.6.0

- **Permission tracking.** New `Watchdog.permissionTracker` reports device
  permission status to a new **Permissions** tab in the cloud dashboard
  (watchdog-cloud 0.4.0+), shown as a card per permission — green border
  when it's granted, red when it needs attention.
  - `Watchdog.permissionTracker.checkAndReportCommon()` — built-in check for
    location + notification via `permission_handler` (now a dependency of
    this package), reporting both with no per-permission code in your app.
    Call once at startup, and again any time permission might have changed
    (e.g. after the user acts on a system prompt, or returns from Settings).
  - `Watchdog.permissionTracker.checkAndReport(type, permission)` — same
    built-in check for any other `permission_handler` `Permission` (camera,
    microphone, bluetooth, ...).
  - `Watchdog.permissionTracker.report(type:, status:)` — manual API for
    statuses that come from somewhere other than `permission_handler`.
  - **New dependency:** `permission_handler: '>=11.0.0 <13.0.0'`.
    `Permission`/`PermissionStatus` are re-exported from
    `package:watchdog/watchdog.dart` so apps using only the built-in checks
    don't need a direct `permission_handler` dependency.
- **`Watchdog.updateUser(...)`.** Merges `username`/`phoneNumber`/`email`
  into the device info set at startup and re-broadcasts it — for the common
  case where Watchdog starts before login, so there's no user identity yet
  at `initialize()` time. Call it once the signed-in user becomes known
  (e.g. from a BlocListener on your profile/auth state). Survives cloud
  reconnects — the merged snapshot is resent, not just the original.

## 0.5.1

- **Optional user identity on `WatchdogDevice`.** New `username`,
  `phoneNumber`, and `email` fields — all optional, since not every project
  has a signed-in user model. When provided, they flow through the existing
  `device_info` event and are surfaced by the cloud dashboard's device list
  and multi-device map (watchdog-cloud 0.3.0+), so a pin/list entry can show
  *who* a device belongs to, not just *which phone*. Nothing changes for
  projects that don't set them.

## 0.5.0

- Version bump only — no functional changes from 0.4.1.

## 0.4.1

- **On-demand location refresh.** The dashboard's Location tab (watchdog-cloud
  0.2.0+) now has a refresh button that asks the connected device for a fresh
  fix right now, instead of waiting for the next auto-tracked update.
  `WatchdogLocationTracker.refreshLocation()` handles the request — a
  fire-and-forget one-shot fetch with permission escalation disabled (a
  remote command should never pop a permission dialog on the device). No app
  code needs to call this directly; it's wired automatically for both the
  local DevTools server and the cloud connection.

## 0.4.0

- **Built-in location fetch/tracking.** `WatchdogLocationTracker` now owns
  permission handling and the `geolocator` calls itself, so consuming apps no
  longer need to write that boilerplate per project:
  - `Watchdog.locationTracker.getCurrentLocation()` — one-shot fetch with
    permission check/request, returns a `Position` and reports it to the
    dashboard automatically.
  - `Watchdog.locationTracker.startAutoTracking(WatchdogAutoTrackingOptions(...))`
    — continuous, self-healing stream (auto-restarts on platform-stream death
    or staleness) with optional Android foreground-service notification and
    iOS background-update settings. Every fix is reported to the dashboard
    and also emitted on `Watchdog.locationTracker.stream` for your own app
    logic (route drawing, map centering, etc).
  - `Watchdog.locationTracker.stopAutoTracking()`.
  - New typed errors — `WatchdogLocationServiceDisabledException`,
    `WatchdogLocationPermissionDeniedException`,
    `WatchdogLocationPermissionDeniedForeverException`.
  - `Position`, `LocationAccuracy`, and `LocationPermission` are re-exported
    from `package:watchdog/watchdog.dart` so apps using only this API don't
    need a direct `geolocator` dependency.
  - The manual `track()` API is unchanged — still the right call for fixes
    that come from something other than `geolocator`.
  - **New dependency:** the package now depends on `geolocator: '>=13.0.0
    <15.0.0'`. Apps must still declare the platform location permissions
    (`AndroidManifest.xml` / `Info.plist`) themselves — see README.

## 0.3.0

- **Location tracking.** New `Watchdog.locationTracker` reports device
  location fixes (`latitude`/`longitude` plus optional accuracy, altitude,
  speed, heading, provider, and a free-form label) to a new **Location** tab
  in DevTools/the cloud dashboard, which plots the device live on a map with
  an accuracy circle and a recent-fixes trail. Decoupled from any specific
  location package — map whatever position object you already have (e.g. a
  `geolocator` `Position`) onto `track()`'s named parameters. No server-side
  changes required; it rides the existing generic event relay.

## 0.2.0

- **One-liner startup.** New top-level `runWatchLocalApp` and
  `runWatchGlobalApp` functions replace the
  `ensureInitialized + Watchdog.start + Bloc.observer + runApp` boilerplate
  with a single call. The `StateManagement` enum controls which observer(s)
  are wired automatically (`none` · `bloc` · `riverpod` · `both`).
- **Global (cloud-only) mode.** Set `WatchdogConfig(global: true, cloud: ...)` 
  or use `runWatchGlobalApp` to skip the local localhost server entirely and
  stream events only to the remote cloud dashboard — ideal for observing
  devices that aren't physically reachable from your machine.
- **Device identity.** New `WatchdogDevice` lets each running app instance
  declare its device name, app version, platform, and OS version so the cloud
  dashboard can tell instances apart.
- **Riverpod support.** New `Watchdog.providerObserver` is a Riverpod
  `ProviderObserver` that streams provider lifecycle and state changes into the
  same **Instances** tab as BLoC/Cubit. State management is now optional and
  pluggable — use BLoC/Cubit, Riverpod, or both. Wire it with
  `ProviderScope(observers: [Watchdog.providerObserver], child: ...)`. Providers
  get their own colour-coded "Riverpod" category and filter chip.
- **Dio support.** New `Watchdog.dioInterceptor` captures every Dio request and
  response and shows it in the Network tab exactly like Chopper — method, URL,
  headers, body, query params, status code, duration, and errors. Add it with
  `dio.interceptors.add(Watchdog.dioInterceptor)`. Non-2xx responses are
  reported with their status code (mirroring Chopper); responseless failures
  (timeouts, connection refused, cancellation) appear as failed calls.
- **Simpler startup.** `Watchdog.start()` now initializes on first use, so a
  single `await Watchdog.start(config: ...)` call is enough. Calling
  `Watchdog.initialize()` separately still works and is fully backward
  compatible.
- Internal: request/response body normalisation is now shared between the
  Chopper and Dio interceptors (`BodyParser`).

## 0.1.3

- **Fix:** the CLI was running `adb reverse` but should have been running
  `adb forward`. `adb reverse` exposes host ports *on the device*, which
  caused a port collision with the Watchdog server and a
  `cannot bind listener: Address already in use` error. `adb forward` is the
  correct direction for reaching a device-side server from the host browser.
  After upgrading, `watchdog open` works end-to-end for Android devices and
  emulators.

## 0.1.2

- Added a CLI executable (`watchdog`) so teammates can open DevTools with a
  single command. Install once with `dart pub global activate watchdog`, then
  run `watchdog open` to auto-run `adb reverse tcp:8888 tcp:8888` (when adb is
  available) and launch `http://localhost:8888` in the default browser. No
  more chasing device IPs.
- New subcommands: `watchdog forward` (port-forward only), `watchdog devices`
  (list adb devices), `watchdog help`, `watchdog version`. Supports `--port`
  and `--no-adb` flags.

## 0.1.1

- Wiring-time accessors (`chopperInterceptor`, `routeObserver`, `blocObserver`,
  `socketTracker`, `logger`, `bridge`) now return safe no-op fallbacks when
  `Watchdog.initialize()` hasn't been awaited yet or when Watchdog is disabled
  in release builds. Host apps can wire these unconditionally during DI/router
  setup without worrying about initialization order.
- Removed the assertion that previously crashed host apps on misuse.

## 0.1.0

- Initial public release.
- Local DevTools server with HTTP request/response inspection, BLoC lifecycle
  tracking, navigation observer, WebSocket tracker, and structured logging.
- Single entry point via `Watchdog.initialize()` / `Watchdog.start()`.
- `WatchdogLogger` abstraction for pluggable logging backends.
- `WatchdogDependencies` for optional dependency injection (logger, clock, id
  generator).
- Optional cloud streaming via `WatchdogCloudConfig`.
- Init-once safety guard — concurrent `initialize()` calls are coalesced.
- Replay buffer for late-connecting HTML clients.
- GetIt container scanning via `Watchdog.trackGetIt()`.
- Auto-wired `Bloc.observer` on `start()`.
