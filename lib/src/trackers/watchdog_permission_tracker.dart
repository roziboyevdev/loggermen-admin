import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../core/watchdog.dart';
import '../models/permission_event.dart';
import '../server/watchdog_broadcaster.dart';

/// Reports permission status to the DevTools **Permissions** tab, which
/// shows each one as a card — green border when it's granted, red when it
/// needs attention — so you can tell at a glance whether a device actually
/// has the location/notification access your app needs, without asking.
///
/// **You don't need to call anything for location + notification.**
/// [WatchdogRuntime] calls [checkAndReportCommon] automatically once at
/// `Watchdog.start()` and again every time the app returns to the
/// foreground (the most common moment a status actually changes — the user
/// coming back from Settings). This is intentional: the whole point of
/// putting permission tracking in the package is that it works the same way
/// for every project without each one having to remember to wire it up.
///
/// Two things you can still do explicitly:
///
/// **1. Call [checkAndReportCommon] yourself** right after requesting a
/// permission, for feedback faster than waiting for the next auto-check
/// (requesting a permission doesn't reliably trigger a resume event, so the
/// automatic check won't necessarily catch it right away):
///
/// ```dart
/// await Permission.locationWhenInUse.request();
/// await Watchdog.permissionTracker.checkAndReportCommon();
/// ```
///
/// **2. Manual [report]** — for permissions this package doesn't check
/// itself, or a status that came from somewhere other than
/// `permission_handler`:
///
/// ```dart
/// Watchdog.permissionTracker.report(type: 'camera', status: 'granted');
/// ```
///
/// Both are safe to call any number of times — every call just re-reports
/// current status, and the dashboard always shows the latest one.
class WatchdogPermissionTracker {
  WatchdogPermissionTracker({required this.broadcaster});

  final WatchdogBroadcaster broadcaster;

  static const _uuid = Uuid();

  /// Reports a single permission's status.
  ///
  /// [type] and [status] are free-form strings — see [PermissionEvent] for
  /// the values the dashboard specifically recognizes for coloring.
  void report({
    required String type,
    required String status,
    String? label,
    DateTime? timestamp,
  }) {
    final event = PermissionEvent(
      id: _uuid.v4(),
      timestamp: timestamp ?? DateTime.now(),
      type: type,
      status: status,
      label: label,
    );
    broadcaster.broadcastPermission(event);
  }

  /// Checks and reports location + notification permission via
  /// `permission_handler`. Safe to call repeatedly (e.g. on every app
  /// resume) — each call just re-reports the current status.
  ///
  /// Never throws. If `permission_handler` isn't set up for a permission on
  /// this platform (e.g. missing Info.plist/manifest entries) or the check
  /// fails for any other reason, that failure is reported as an
  /// `'unavailable'` status (shown as a red card in the dashboard, same as
  /// `denied`) *and* logged to the Logs tab — so a permission that never
  /// shows up is visible as a loud failure, not silence.
  Future<void> checkAndReportCommon() async {
    await checkAndReport('location', Permission.locationWhenInUse);
    await checkAndReport('notification', Permission.notification);
  }

  /// Checks and reports a single `permission_handler` [Permission] under
  /// [type]. Use this directly (instead of [checkAndReportCommon]) for
  /// permissions beyond location/notification — camera, microphone,
  /// bluetooth, etc:
  ///
  /// ```dart
  /// await Watchdog.permissionTracker.checkAndReport('camera', Permission.camera);
  /// ```
  Future<void> checkAndReport(String type, Permission permission) async {
    try {
      final status = await permission.status;
      report(type: type, status: _mapStatus(status));
    } catch (e, st) {
      // Most common cause: permission_handler's native side isn't linked yet
      // because a *new* native dependency was added but the app was only
      // hot-reloaded/hot-restarted, not fully stopped and rebuilt. Report it
      // loudly instead of vanishing — an empty Permissions tab with no
      // explanation is much harder to debug than a red "unavailable" card
      // plus a warning in Logs.
      Watchdog.warning(
        'Permission check failed for "$type" — do a full rebuild (not hot '
        'reload/restart) after adding permission_handler, and make sure '
        'Info.plist / AndroidManifest.xml declare it.',
        error: e,
        stackTrace: st,
      );
      report(type: type, status: 'unavailable');
    }
  }

  String _mapStatus(PermissionStatus status) {
    switch (status) {
      case PermissionStatus.granted:
        return 'granted';
      case PermissionStatus.provisional:
        return 'provisional';
      case PermissionStatus.limited:
        return 'limited';
      case PermissionStatus.denied:
        return 'denied';
      case PermissionStatus.restricted:
        return 'restricted';
      case PermissionStatus.permanentlyDenied:
        return 'deniedForever';
    }
  }
}
