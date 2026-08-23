import 'package:geolocator/geolocator.dart';

/// Android-only: configures the foreground-service notification that keeps
/// location updates alive while the app is backgrounded. Required on
/// Android 14+ if you want fixes to keep arriving after the user leaves the
/// app (e.g. a driver app tracking a trip).
///
/// Leave [WatchdogAutoTrackingOptions.androidForegroundNotification] null to
/// track only while the app is foregrounded — no notification is shown and
/// the OS is free to suspend the stream in the background.
class WatchdogAndroidForegroundNotification {
  const WatchdogAndroidForegroundNotification({
    required this.title,
    required this.text,
    this.enableWakeLock = true,
    this.setOngoing = true,
  });

  final String title;
  final String text;
  final bool enableWakeLock;
  final bool setOngoing;
}

/// Configuration for [WatchdogLocationTracker.startAutoTracking].
///
/// Every fix produced under these settings is automatically forwarded to
/// the DevTools **Location** tab (equivalent to calling
/// [WatchdogLocationTracker.track] yourself) *and* emitted on
/// [WatchdogLocationTracker.stream] so your app can still react to it (draw a
/// route, recenter a map, push it over your own socket, etc.) without
/// touching `geolocator` directly.
class WatchdogAutoTrackingOptions {
  const WatchdogAutoTrackingOptions({
    this.accuracy = LocationAccuracy.high,
    this.distanceFilter = 10,
    this.interval = const Duration(seconds: 5),
    this.androidForegroundNotification,
    this.requestPermissionIfDenied = true,
    this.label,
    this.staleFixTimeout = const Duration(minutes: 2),
    this.iosActivityType = ActivityType.automotiveNavigation,
    this.iosAllowBackgroundLocationUpdates = false,
    this.iosShowBackgroundLocationIndicator = false,
  });

  /// Desired accuracy. Default: [LocationAccuracy.high].
  final LocationAccuracy accuracy;

  /// Minimum distance (meters) the device must move before a new fix is
  /// delivered. Default: 10.
  final int distanceFilter;

  /// Android only — minimum time between fixes. Default: 5 seconds.
  final Duration interval;

  /// When set, Android runs the location stream inside a foreground service
  /// with this notification, so tracking survives the app being backgrounded.
  /// When null, tracking is foreground-only (no notification).
  final WatchdogAndroidForegroundNotification? androidForegroundNotification;

  /// If permission is denied (not "denied forever"), automatically request
  /// it once before giving up. Default: true.
  final bool requestPermissionIfDenied;

  /// Optional label attached to every fix reported to the dashboard — handy
  /// for telling multiple tracked entities apart (e.g. `'driver-trip'` vs
  /// `'driver-idle'`).
  final String? label;

  /// If no fix arrives within this window, the underlying platform stream is
  /// assumed dead and restarted automatically. Set to [Duration.zero] to
  /// disable. Default: 2 minutes.
  final Duration staleFixTimeout;

  /// iOS only — passed through to [AppleSettings.activityType].
  final ActivityType iosActivityType;

  /// iOS only — passed through to
  /// [AppleSettings.allowBackgroundLocationUpdates]. Requires the
  /// "Background Modes > Location updates" capability to be enabled in
  /// Xcode; leave false unless you've done that.
  final bool iosAllowBackgroundLocationUpdates;

  /// iOS only — passed through to
  /// [AppleSettings.showBackgroundLocationIndicator].
  final bool iosShowBackgroundLocationIndicator;
}
