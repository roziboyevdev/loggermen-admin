/// A single device location fix, broadcast to the DevTools page's
/// **Location** tab.
///
/// Constructed by [WatchdogLocationTracker] and sent through
/// [WatchdogBroadcaster] like every other event type — the local server and
/// the cloud relay treat it as an opaque JSON payload, so no server-side
/// changes are needed to support it.
class LocationEvent {
  const LocationEvent({
    required this.id,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.altitude,
    this.speed,
    this.speedAccuracy,
    this.heading,
    this.provider,
    this.label,
  });

  /// Unique ID for this fix (UUID v4).
  final String id;

  /// When this fix was recorded.
  final DateTime timestamp;

  final double latitude;
  final double longitude;

  /// Horizontal accuracy in meters, when known (e.g. `Position.accuracy`
  /// from `geolocator`).
  final double? accuracy;

  /// Altitude in meters, when known.
  final double? altitude;

  /// Ground speed in m/s, when known.
  final double? speed;

  /// Speed accuracy in m/s, when known.
  final double? speedAccuracy;

  /// Heading in degrees (0-360, 0 = north), when known.
  final double? heading;

  /// Source of the fix, e.g. `'gps'`, `'network'`, `'eld'`, `'fused'`.
  /// Free-form — shown as-is in the dashboard.
  final String? provider;

  /// Optional free-form label shown next to the pin, e.g. a driver name or
  /// duty status (`'Driving'`, `'On Duty'`) — handy for telling sessions
  /// apart on the map at a glance.
  final String? label;

  Map<String, dynamic> toJson() {
    return {
      'type': 'location',
      'id': id,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'altitude': altitude,
      'speed': speed,
      'speedAccuracy': speedAccuracy,
      'heading': heading,
      'provider': provider,
      'label': label,
    };
  }
}
