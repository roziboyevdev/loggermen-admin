import 'dart:async';
import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../models/location_event.dart';
import '../server/watchdog_broadcaster.dart';
import 'watchdog_location_exceptions.dart';
import 'watchdog_location_options.dart';

/// Reports device location fixes to the DevTools **Location** tab, which
/// plots them live on a map — useful for seeing where a teammate's device
/// (or a driver's, when streaming through the cloud) actually is without
/// asking them.
///
/// Two ways to use it:
///
/// **1. Built-in fetch (recommended)** — the tracker owns permission
/// handling and the `geolocator` calls, so your app never writes that
/// boilerplate itself:
///
/// ```dart
/// // One-shot, e.g. "use my current location" button:
/// final position = await Watchdog.locationTracker.getCurrentLocation();
///
/// // Continuous, e.g. driver trip tracking:
/// Watchdog.locationTracker.startAutoTracking(
///   const WatchdogAutoTrackingOptions(
///     distanceFilter: 10,
///     interval: Duration(seconds: 5),
///     androidForegroundNotification: WatchdogAndroidForegroundNotification(
///       title: 'Trip active',
///       text: 'Sharing your location',
///     ),
///   ),
/// );
///
/// // Your app still gets every fix — for map centering, route drawing, etc:
/// Watchdog.locationTracker.stream.listen((position) { ... });
///
/// // Later:
/// await Watchdog.locationTracker.stopAutoTracking();
/// ```
///
/// Every fix produced this way is reported to the dashboard automatically —
/// you don't call [track] yourself.
///
/// **2. Manual [track]** — for fixes that come from somewhere other than
/// `geolocator` (a platform channel, an ELD SDK's own GPS module, a fix you
/// already fetched for other reasons):
///
/// ```dart
/// tracker.track(
///   latitude: position.latitude,
///   longitude: position.longitude,
///   accuracy: position.accuracy,
/// );
/// ```
class WatchdogLocationTracker {
  WatchdogLocationTracker({required this.broadcaster});

  final WatchdogBroadcaster broadcaster;

  static const _uuid = Uuid();

  /// Reports a single location fix.
  ///
  /// [latitude]/[longitude] are required; everything else is optional and
  /// simply omitted from the dashboard when not provided.
  void track({
    required double latitude,
    required double longitude,
    double? accuracy,
    double? altitude,
    double? speed,
    double? speedAccuracy,
    double? heading,
    String? provider,
    String? label,
    DateTime? timestamp,
  }) {
    final event = LocationEvent(
      id: _uuid.v4(),
      timestamp: timestamp ?? DateTime.now(),
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      altitude: altitude,
      speed: speed,
      speedAccuracy: speedAccuracy,
      heading: heading,
      provider: provider,
      label: label,
    );
    broadcaster.broadcastLocation(event);
  }

  // ── Built-in fetch — the package owns permissions + geolocator calls ────

  StreamSubscription<Position>? _autoSub;
  StreamController<Position>? _autoController;
  Timer? _staleTimer;
  DateTime? _lastFixAt;
  WatchdogAutoTrackingOptions? _autoOptions;

  /// Whether [startAutoTracking] is currently active.
  bool get isAutoTracking => _autoOptions != null;

  /// Broadcast stream of fixes produced while [startAutoTracking] is active.
  /// Every fix on this stream has already been reported to the dashboard —
  /// listen here only if your app also needs the raw [Position] (route
  /// drawing, map centering, pushing over your own socket, etc.).
  Stream<Position> get stream =>
      (_autoController ??= StreamController<Position>.broadcast()).stream;

  /// One-shot fetch: checks (and, by default, requests) location permission,
  /// then returns a single [Position] — reporting it to the dashboard
  /// automatically. No `geolocator` calls needed in your app.
  ///
  /// Throws a [WatchdogLocationException] subtype on failure —
  /// [WatchdogLocationServiceDisabledException],
  /// [WatchdogLocationPermissionDeniedException], or
  /// [WatchdogLocationPermissionDeniedForeverException] — so callers can
  /// branch without depending on `geolocator`'s own exception shape.
  Future<Position> getCurrentLocation({
    LocationAccuracy accuracy = LocationAccuracy.high,
    bool requestPermissionIfDenied = true,
    String? provider,
    String? label,
  }) async {
    await _ensurePermission(requestIfDenied: requestPermissionIfDenied);

    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(accuracy: accuracy),
    );

    _report(position, provider: provider ?? 'geolocator', label: label);
    return position;
  }

  /// Starts a continuous, self-healing location stream: handles permission,
  /// restarts itself if the platform stream dies or goes stale, and reports
  /// every fix to the dashboard — all without your app touching `geolocator`
  /// directly.
  ///
  /// Returns [stream] for convenience, so
  /// `(await Watchdog.locationTracker.startAutoTracking()).listen(...)`
  /// works in one line. Safe to call again with new [options] — it restarts
  /// the underlying stream with the new settings.
  Future<Stream<Position>> startAutoTracking([
    WatchdogAutoTrackingOptions options = const WatchdogAutoTrackingOptions(),
  ]) async {
    await _ensurePermission(requestIfDenied: options.requestPermissionIfDenied);

    _autoOptions = options;
    _restartAutoStream();
    return stream;
  }

  /// Stops [startAutoTracking] and releases the underlying platform stream
  /// (and, on Android, the foreground-service notification if one was
  /// configured). Safe to call even when not tracking.
  Future<void> stopAutoTracking() async {
    _autoOptions = null;
    _staleTimer?.cancel();
    _staleTimer = null;
    _lastFixAt = null;
    await _autoSub?.cancel();
    _autoSub = null;
  }

  /// Fetches one fresh fix right now and reports it — used to answer a
  /// remote "refresh" request from the dashboard (e.g. the Location tab's
  /// refresh button), so you don't need to wire that yourself.
  ///
  /// Deliberately fire-and-forget with permission escalation disabled: a
  /// command triggered from a browser on someone else's screen should never
  /// pop a permission dialog on the device. If permission isn't already
  /// granted, or the fetch fails for any other reason, this is a silent
  /// no-op — the dashboard just won't see a new fix and the developer can
  /// press refresh again once the app has permission.
  Future<void> refreshLocation() async {
    try {
      await getCurrentLocation(
        requestPermissionIfDenied: false,
        provider: 'geolocator-refresh',
      );
    } on WatchdogLocationException {
      // No permission / service disabled — nothing to surface it to.
    } catch (_) {
      // Swallow platform errors for the same reason.
    }
  }

  // ── internals ─────────────────────────────────────────────────────────

  void _restartAutoStream() {
    final options = _autoOptions;
    if (options == null) return;

    final previousSub = _autoSub;
    if (previousSub != null) unawaited(previousSub.cancel());
    _lastFixAt = DateTime.now();

    _autoSub = Geolocator.getPositionStream(
      locationSettings: _buildSettings(options),
    ).listen(
      (position) {
        _lastFixAt = DateTime.now();
        _report(position, provider: 'geolocator-stream', label: options.label);
        (_autoController ??= StreamController<Position>.broadcast()).add(position);
      },
      onError: (Object _, StackTrace __) {
        // Platform hiccup — the stale-fix watchdog below restarts the stream
        // if it doesn't recover on its own.
      },
      onDone: () {
        // Distinguishes "the platform stream ended on its own" (restart)
        // from "stopAutoTracking() was called" (do nothing).
        if (_autoOptions == null) return;
        _restartAutoStream();
      },
      cancelOnError: false,
    );

    _staleTimer?.cancel();
    if (options.staleFixTimeout > Duration.zero) {
      _staleTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        final lastFixAt = _lastFixAt;
        if (lastFixAt == null) return;
        if (DateTime.now().difference(lastFixAt) < options.staleFixTimeout) {
          return;
        }
        _restartAutoStream();
      });
    }
  }

  LocationSettings _buildSettings(WatchdogAutoTrackingOptions options) {
    if (Platform.isAndroid) {
      final notification = options.androidForegroundNotification;
      return AndroidSettings(
        accuracy: options.accuracy,
        distanceFilter: options.distanceFilter,
        intervalDuration: options.interval,
        foregroundNotificationConfig: notification == null
            ? null
            : ForegroundNotificationConfig(
                notificationTitle: notification.title,
                notificationText: notification.text,
                enableWakeLock: notification.enableWakeLock,
                setOngoing: notification.setOngoing,
              ),
      );
    }

    if (Platform.isIOS || Platform.isMacOS) {
      return AppleSettings(
        accuracy: options.accuracy,
        activityType: options.iosActivityType,
        distanceFilter: options.distanceFilter,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: options.iosAllowBackgroundLocationUpdates,
        showBackgroundLocationIndicator: options.iosShowBackgroundLocationIndicator,
      );
    }

    return LocationSettings(
      accuracy: options.accuracy,
      distanceFilter: options.distanceFilter,
    );
  }

  Future<void> _ensurePermission({required bool requestIfDenied}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw const WatchdogLocationServiceDisabledException();

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestIfDenied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const WatchdogLocationPermissionDeniedException();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const WatchdogLocationPermissionDeniedForeverException();
    }
  }

  void _report(Position position, {String? provider, String? label}) {
    track(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      altitude: position.altitude,
      speed: position.speed,
      speedAccuracy: position.speedAccuracy,
      heading: position.heading,
      provider: provider,
      label: label,
    );
  }
}
