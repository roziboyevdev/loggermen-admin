/// Base type for errors raised by [WatchdogLocationTracker]'s built-in
/// permission + fetch flow (`getCurrentLocation` / `startAutoTracking`).
sealed class WatchdogLocationException implements Exception {
  const WatchdogLocationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The device's location service (GPS/network location) is turned off.
class WatchdogLocationServiceDisabledException extends WatchdogLocationException {
  const WatchdogLocationServiceDisabledException()
      : super('Location services are disabled on this device.');
}

/// Permission was denied. The caller may prompt again.
class WatchdogLocationPermissionDeniedException extends WatchdogLocationException {
  const WatchdogLocationPermissionDeniedException()
      : super('Location permission was denied.');
}

/// Permission was permanently denied — the OS will not show the system
/// prompt again; the app must send the user to settings.
class WatchdogLocationPermissionDeniedForeverException extends WatchdogLocationException {
  const WatchdogLocationPermissionDeniedForeverException()
      : super('Location permission was permanently denied. Open app settings to grant it.');
}
