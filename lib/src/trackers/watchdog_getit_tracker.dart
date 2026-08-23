import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import '../models/instance_event.dart';
import '../server/watchdog_broadcaster.dart';

/// Scans a [GetIt] container and broadcasts [InstanceEvent]s for every
/// registration it finds — singletons, lazy singletons, and (optionally)
/// factories.
///
/// This bridges the gap between [WatchdogBlocObserver] (which only sees
/// BLoC/Cubit instances) and the rest of your DI graph.
class WatchdogGetItTracker {
  WatchdogGetItTracker._();

  static const _uuid = Uuid();

  /// Discovers all registrations in [getIt] and broadcasts an
  /// [InstanceEvent] for each one.
  ///
  /// * [instantiateLazy] — when `true` (default), forces lazy singletons to
  ///   be created so they appear in the Instances tab immediately.  Set to
  ///   `false` if you only want to see eagerly-resolved instances.
  /// * [callFactories] — when `true`, factory registrations are also invoked
  ///   once to discover their type.  Defaults to `false` because factory
  ///   calls may have side effects.
  static void trackAll(
    GetIt getIt, {
    required WatchdogBroadcaster broadcaster,
    bool instantiateLazy = true,
    bool callFactories = false,
  }) {
    try {
      final instances = getIt.findAll<Object>(
        inAllScopes: true,
        includeSubtypes: true,
        instantiateLazySingletons: instantiateLazy,
        callFactories: callFactories,
      );

      final now = DateTime.now();
      var order = 0;

      for (final instance in instances) {
        // Skip BLoC/Cubit instances — they are already tracked by
        // WatchdogBlocObserver via Bloc.observer, so reporting them
        // here would cause false "2x created" duplicate warnings.
        if (instance is BlocBase) continue;

        order++;
        final typeName = instance.runtimeType.toString();

        // Try to get registration metadata (type, name, etc.)
        String? registrationType;
        String? instanceName;
        try {
          final reg = getIt.findFirstObjectRegistration<Object>(
            instance: instance,
          );
          if (reg != null) {
            registrationType = _mapRegistrationType(reg.registrationType);
            instanceName = reg.instanceName;
          }
        } catch (_) {
          // Metadata lookup failed — proceed without it.
        }

        final stateStr = _safeToString(instance);
        final sizeEstimate = _estimateSize(stateStr);

        broadcaster.broadcastInstance(
          InstanceEvent(
            id: _uuid.v4(),
            timestamp: now.add(Duration(microseconds: order)),
            category: InstanceCategory.fromTypeName(typeName),
            typeName: typeName,
            action: InstanceAction.created,
            instanceId: _uuid.v4(),
            registrationType: registrationType,
            currentState: stateStr,
            estimatedSizeBytes: sizeEstimate,
            details: _buildDetails(registrationType, instanceName),
          ),
        );
      }

      if (kDebugMode) {
        debugPrint(
          'Watchdog: tracked $order GetIt registration(s)',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Watchdog: GetIt tracking failed — $e');
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _mapRegistrationType(ObjectRegistrationType type) {
    switch (type) {
      case ObjectRegistrationType.constant:
        return 'singleton';
      case ObjectRegistrationType.lazy:
        return 'lazySingleton';
      case ObjectRegistrationType.alwaysNew:
        return 'factory';
      case ObjectRegistrationType.cachedFactory:
        return 'cachedFactory';
    }
  }

  static String _buildDetails(String? regType, String? name) {
    final parts = <String>[];
    if (regType != null) parts.add('GetIt ($regType)');
    if (name != null && name.isNotEmpty) parts.add('name: $name');
    return parts.isEmpty ? 'GetIt registration' : parts.join(' · ');
  }

  static String _safeToString(Object instance) {
    try {
      final s = instance.toString();
      // Clamp very long toString output.
      return s.length > 2000 ? '${s.substring(0, 2000)}…' : s;
    } catch (_) {
      return '<unable to stringify>';
    }
  }

  static int _estimateSize(String s) => s.length * 2;
}
