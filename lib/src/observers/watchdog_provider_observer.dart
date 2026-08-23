import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/instance_event.dart';
import '../server/watchdog_broadcaster.dart';

/// A Riverpod [ProviderObserver] that broadcasts provider lifecycle events
/// (initialization, updates, disposal) to the Watchdog HTML DevTools page.
///
/// It is the Riverpod counterpart of `WatchdogBlocObserver` — both feed the
/// same **Instances** tab, so a project can use BLoC/Cubit, Riverpod, or both
/// and see every state container in one place.
///
/// Wire it into your `ProviderScope`:
///
/// ```dart
/// runApp(
///   ProviderScope(
///     observers: [Watchdog.providerObserver],
///     child: const MyApp(),
///   ),
/// );
/// ```
class WatchdogProviderObserver extends ProviderObserver {
  WatchdogProviderObserver({required this.broadcaster});

  final WatchdogBroadcaster broadcaster;

  static const _uuid = Uuid();

  /// Maps a provider (by identity) → its stable instanceId across events.
  final Map<ProviderBase<Object?>, String> _instanceIds = {};

  /// Maps a provider → creation timestamp, to compute lifetime on disposal.
  final Map<ProviderBase<Object?>, DateTime> _createdAt = {};

  // ── ProviderObserver overrides ────────────────────────────────────────────

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    final instanceId = _uuid.v4();
    _instanceIds[provider] = instanceId;
    _createdAt[provider] = DateTime.now();

    final stateStr = _safeStringify(value);

    broadcaster.broadcastInstance(
      InstanceEvent(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        category: InstanceCategory.provider,
        typeName: _providerName(provider),
        action: InstanceAction.created,
        currentState: stateStr,
        estimatedSizeBytes: _estimateSize(stateStr),
        instanceId: instanceId,
        registrationType: _providerKind(provider),
        details: _details(provider),
      ),
    );
  }

  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    final stateStr = _safeStringify(newValue);

    broadcaster.broadcastInstance(
      InstanceEvent(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        category: InstanceCategory.provider,
        typeName: _providerName(provider),
        action: InstanceAction.stateChange,
        currentState: stateStr,
        estimatedSizeBytes: _estimateSize(stateStr),
        instanceId: _instanceIds[provider],
        registrationType: _providerKind(provider),
        details: 'from: ${_safeStringify(previousValue)}',
      ),
    );
  }

  @override
  void didDisposeProvider(
    ProviderBase<Object?> provider,
    ProviderContainer container,
  ) {
    final instanceId = _instanceIds.remove(provider);
    final createdAt = _createdAt.remove(provider);
    final lifetime = createdAt != null
        ? DateTime.now().difference(createdAt).inMilliseconds
        : null;

    broadcaster.broadcastInstance(
      InstanceEvent(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        category: InstanceCategory.provider,
        typeName: _providerName(provider),
        action: InstanceAction.closed,
        instanceId: instanceId,
        registrationType: _providerKind(provider),
        details: lifetime != null ? 'alive for ${lifetime}ms' : null,
      ),
    );
  }

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    if (kDebugMode) {
      debugPrint(
        'Watchdog ProviderObserver: ${_providerName(provider)} failed: $error',
      );
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// A human-friendly name for the provider — prefers the explicit `name:`
  /// (set directly or by riverpod_generator), falls back to the runtime type.
  static String _providerName(ProviderBase<Object?> provider) {
    final name = provider.name;
    if (name != null && name.isNotEmpty) return name;
    return provider.runtimeType.toString();
  }

  /// Short label describing the kind of provider, e.g. "Provider",
  /// "StateNotifierProvider", "NotifierProvider" — derived from the runtime
  /// type and shown as the registration-type badge.
  static String _providerKind(ProviderBase<Object?> provider) {
    var type = provider.runtimeType.toString();
    final generic = type.indexOf('<');
    if (generic != -1) type = type.substring(0, generic);
    // Strip riverpod's private impl prefixes/suffixes for readability.
    type = type.replaceAll('_', '').replaceAll('Impl', '');
    final auto = type.contains('AutoDispose');
    type = type.replaceAll('AutoDispose', '');
    return auto ? '$type · autoDispose' : type;
  }

  static String _details(ProviderBase<Object?> provider) {
    final arg = provider.argument;
    return arg != null ? 'Riverpod · arg: $arg' : 'Riverpod';
  }

  static String _safeStringify(Object? value) {
    try {
      return value.toString();
    } catch (_) {
      return '<unable to stringify>';
    }
  }

  static int _estimateSize(String? s) {
    if (s == null) return 0;
    return s.length * 2; // ~2 bytes per char (UTF-16 in Dart)
  }
}
