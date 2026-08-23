import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Identity of a single running app instance — used to distinguish devices in
/// the Watchdog **cloud** dashboard (and shown in the local DevTools header).
///
/// Every field is optional. Provide what you can — for richer values feed them
/// from `device_info_plus` on the app side (the package itself stays
/// dependency-light and only auto-fills basic values from `dart:io`):
///
/// ```dart
/// final info = await DeviceInfoPlugin().iosInfo;
/// final device = WatchdogDevice(
///   deviceName: info.name,          // "Akmal's iPhone"
///   model: info.utsname.machine,    // "iPhone16,1"
///   osVersion: info.systemVersion,  // "18.5"
///   appVersion: '1.4.2',
/// );
/// ```
class WatchdogDevice {
  const WatchdogDevice({
    this.sessionId,
    this.deviceId,
    this.deviceName,
    this.model,
    this.platform,
    this.osVersion,
    this.appName,
    this.appVersion,
    this.username,
    this.phoneNumber,
    this.email,
    this.extra = const <String, String>{},
  });

  /// Unique id for this app *run*. Defaults to a generated UUID when null.
  final String? sessionId;

  /// Stable id for the *device/install* (survives across runs). Optional.
  final String? deviceId;

  /// Human-friendly device name, e.g. "Akmal's iPhone".
  final String? deviceName;

  /// Hardware model, e.g. "iPhone16,1" / "SM-A405FN".
  final String? model;

  /// Platform, e.g. "ios" / "android". Auto-filled from `dart:io` when null.
  final String? platform;

  /// OS version, e.g. "18.5". Auto-filled from `dart:io` when null.
  final String? osVersion;

  /// App display name shown in the cloud session list.
  final String? appName;

  /// App version, e.g. "1.4.2".
  final String? appVersion;

  /// Optional identity of the person using this device — not every project
  /// has a signed-in user model, so leave these null when there's nothing to
  /// show. When provided, the cloud dashboard's device list/map surfaces them
  /// next to the device (e.g. a driver's name and phone number), so you can
  /// tell *who* a pin belongs to, not just *which phone*.
  ///
  /// Feed these from wherever your app already keeps the signed-in user —
  /// this is deliberately just three plain strings rather than a project
  /// -specific user model, since every app's `User`/`Driver`/`Account` class
  /// looks different.
  final String? username;

  /// E.g. "+998901234567". Optional.
  final String? phoneNumber;

  /// Optional.
  final String? email;

  /// Any extra labels you want surfaced (userId, env, flavor, …).
  final Map<String, String> extra;

  /// A display name, falling back to the host name / platform when not given.
  String resolvedDeviceName() {
    final n = deviceName;
    if (n != null && n.isNotEmpty) return n;
    if (!kIsWeb) {
      try {
        final host = Platform.localHostname;
        if (host.isNotEmpty) return host;
      } catch (_) {}
    }
    return resolvedPlatform();
  }

  String resolvedPlatform() {
    final p = platform;
    if (p != null && p.isNotEmpty) return p;
    if (kIsWeb) return 'web';
    try {
      return Platform.operatingSystem;
    } catch (_) {
      return 'unknown';
    }
  }

  String? _resolvedOsVersion() {
    if (osVersion != null && osVersion!.isNotEmpty) return osVersion;
    if (kIsWeb) return null;
    try {
      return Platform.operatingSystemVersion;
    } catch (_) {
      return null;
    }
  }

  /// JSON payload broadcast as a `device_info` event so clients (local HTML
  /// header and cloud dashboard) can label this session.
  Map<String, dynamic> toInfoJson() {
    final os = _resolvedOsVersion();
    return {
      'deviceName': resolvedDeviceName(),
      'platform': resolvedPlatform(),
      if (model != null && model!.isNotEmpty) 'model': model,
      if (deviceId != null && deviceId!.isNotEmpty) 'deviceId': deviceId,
      if (os != null) 'osVersion': os,
      if (appName != null && appName!.isNotEmpty) 'appName': appName,
      if (appVersion != null && appVersion!.isNotEmpty) 'appVersion': appVersion,
      if (username != null && username!.isNotEmpty) 'username': username,
      if (phoneNumber != null && phoneNumber!.isNotEmpty) 'phoneNumber': phoneNumber,
      if (email != null && email!.isNotEmpty) 'email': email,
      ...extra,
    };
  }
}
