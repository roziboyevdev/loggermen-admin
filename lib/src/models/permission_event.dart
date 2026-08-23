/// A single permission's current status, broadcast to the DevTools page's
/// **Permissions** tab.
///
/// Constructed by [WatchdogPermissionTracker] and sent through
/// [WatchdogBroadcaster] like every other event type — the local server and
/// the cloud relay treat it as an opaque JSON payload, so no server-side
/// changes are needed to support it.
class PermissionEvent {
  const PermissionEvent({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.status,
    this.label,
  });

  /// Unique ID for this report (UUID v4).
  final String id;

  /// When this status was checked.
  final DateTime timestamp;

  /// Free-form permission name, e.g. `'location'`, `'notification'`,
  /// `'camera'`, `'microphone'`, `'bluetooth'` — whatever your app checks.
  /// Shown as-is in the dashboard, so use a short lowercase word.
  final String type;

  /// Free-form status string. [WatchdogPermissionTracker]'s built-in checks
  /// use `'granted'`, `'denied'`, `'deniedForever'`, `'restricted'`,
  /// `'limited'`, `'provisional'` (matching `permission_handler`'s
  /// `PermissionStatus`) — but any string works if you're reporting from
  /// somewhere else. The dashboard treats `'granted'`/`'provisional'`/
  /// `'limited'` as "OK" (green) and everything else as "needs attention"
  /// (red).
  final String status;

  /// Optional free-form label, e.g. a driver name — handy when a session
  /// aggregates permissions for more than one identity.
  final String? label;

  Map<String, dynamic> toJson() {
    return {
      'type': 'permission',
      'id': id,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'permissionType': type,
      'status': status,
      'label': label,
    };
  }
}
