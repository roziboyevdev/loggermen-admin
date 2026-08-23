import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../models/instance_event.dart';
import '../server/watchdog_broadcaster.dart';

/// A [BlocObserver] that broadcasts BLoC lifecycle events (creation, state
/// changes, closure) to the Watchdog HTML DevTools page.
///
/// Usage:
/// ```dart
/// Bloc.observer = WatchdogBlocObserver();
/// ```
class WatchdogBlocObserver extends BlocObserver {
  WatchdogBlocObserver({required this.broadcaster});

  final WatchdogBroadcaster broadcaster;

  static const _uuid = Uuid();

  /// Maps a BLoC instance hashCode → its stable instanceId for tracking.
  final Map<int, String> _instanceIds = {};

  /// Maps a BLoC hashCode → creation timestamp.
  final Map<int, DateTime> _createdAt = {};

  // ── Lifecycle ───────────────────────────────────────────────────────────

  @override
  void onCreate(BlocBase<dynamic> bloc) {
    super.onCreate(bloc);
    final instanceId = _uuid.v4();
    _instanceIds[bloc.hashCode] = instanceId;
    _createdAt[bloc.hashCode] = DateTime.now();

    final stateStr = _safeState(bloc);
    final sizeEstimate = _estimateSize(stateStr);

    // Capture creation stack — trim watchdog internals, keep the useful frames.
    final rawStack = StackTrace.current.toString();
    final creationStack = _trimStack(rawStack);

    broadcaster.broadcastInstance(
      InstanceEvent(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        category: InstanceCategory.fromTypeName(bloc.runtimeType.toString()),
        typeName: bloc.runtimeType.toString(),
        action: InstanceAction.created,
        currentState: stateStr,
        estimatedSizeBytes: sizeEstimate,
        instanceId: instanceId,
        details: bloc is Bloc ? 'Bloc' : 'Cubit',
        creationStack: creationStack,
      ),
    );
  }

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);

    final instanceId = _instanceIds[bloc.hashCode];
    final stateStr = _safeStringify(change.nextState);
    final sizeEstimate = _estimateSize(stateStr);

    broadcaster.broadcastInstance(
      InstanceEvent(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        category: InstanceCategory.fromTypeName(bloc.runtimeType.toString()),
        typeName: bloc.runtimeType.toString(),
        action: InstanceAction.stateChange,
        currentState: stateStr,
        estimatedSizeBytes: sizeEstimate,
        instanceId: instanceId,
        details: 'from: ${_safeStringify(change.currentState)}',
      ),
    );
  }

  @override
  void onClose(BlocBase<dynamic> bloc) {
    super.onClose(bloc);

    final instanceId = _instanceIds.remove(bloc.hashCode);
    final createdAt = _createdAt.remove(bloc.hashCode);
    final lifetime = createdAt != null
        ? DateTime.now().difference(createdAt).inMilliseconds
        : null;

    broadcaster.broadcastInstance(
      InstanceEvent(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        category: InstanceCategory.fromTypeName(bloc.runtimeType.toString()),
        typeName: bloc.runtimeType.toString(),
        action: InstanceAction.closed,
        instanceId: instanceId,
        details: lifetime != null ? 'alive for ${lifetime}ms' : null,
      ),
    );
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    if (kDebugMode) {
      debugPrint('Watchdog BlocObserver error in ${bloc.runtimeType}: $error');
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  static String _safeState(BlocBase<dynamic> bloc) {
    try {
      return bloc.state.toString();
    } catch (_) {
      return '<unable to read state>';
    }
  }

  static String _safeStringify(dynamic value) {
    try {
      return value.toString();
    } catch (_) {
      return '<unable to stringify>';
    }
  }

  static int _estimateSize(String? s) {
    if (s == null) return 0;
    // Rough estimate: 2 bytes per char (UTF-16 in Dart).
    return s.length * 2;
  }

  /// Trims internal watchdog/bloc frames from the stack, keeping only
  /// the caller's frames so the developer sees WHERE in their project
  /// the instance was created.
  static String _trimStack(String stack) {
    final lines = stack.split('\n');
    final filtered = <String>[];
    for (final line in lines) {
      // Skip watchdog internals and bloc package frames
      if (line.contains('watchdog_bloc_observer') ||
          line.contains('package:bloc/') ||
          line.contains('package:flutter_bloc/')) {
        continue;
      }
      filtered.add(line);
      // Keep max 15 useful frames
      if (filtered.length >= 15) break;
    }
    return filtered.join('\n').trim();
  }
}
