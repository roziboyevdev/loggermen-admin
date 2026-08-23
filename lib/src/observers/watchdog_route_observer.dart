import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../models/route_event.dart';
import '../server/watchdog_broadcaster.dart';

/// A [NavigatorObserver] that broadcasts every navigation event to the
/// Watchdog HTML DevTools page.
///
/// Works with any router (auto_route, go_router, vanilla Navigator).
///
/// Usage with auto_route:
/// ```dart
/// MaterialApp.router(
///   routerConfig: appRouter.config(
///     navigatorObservers: () => [Watchdog.routeObserver],
///   ),
/// )
/// ```
///
/// Usage with vanilla Navigator:
/// ```dart
/// MaterialApp(
///   navigatorObservers: [Watchdog.routeObserver],
/// )
/// ```
class WatchdogRouteObserver extends NavigatorObserver {
  WatchdogRouteObserver({required this.broadcaster});

  final WatchdogBroadcaster broadcaster;

  static const _uuid = Uuid();

  /// Internal route stack — mirrors the navigator's stack.
  final List<String> _stack = [];

  /// Returns the current route stack (bottom to top).
  List<String> get currentStack => List.unmodifiable(_stack);

  // ── NavigatorObserver overrides ──────────────────────────────────────────

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    final name = _routeName(route);
    _stack.add(name);

    _broadcast(
      action: RouteAction.push,
      route: route,
      previousRoute: previousRoute,
    );
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    final name = _routeName(route);
    // Remove from top — find last occurrence
    final idx = _stack.lastIndexOf(name);
    if (idx >= 0) _stack.removeAt(idx);

    _broadcast(
      action: RouteAction.pop,
      route: route,
      previousRoute: previousRoute,
    );
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    final oldName = oldRoute != null ? _routeName(oldRoute) : null;
    final newName = newRoute != null ? _routeName(newRoute) : 'unknown';

    // Replace in stack
    if (oldName != null) {
      final idx = _stack.lastIndexOf(oldName);
      if (idx >= 0) {
        _stack[idx] = newName;
      } else {
        _stack.add(newName);
      }
    } else {
      _stack.add(newName);
    }

    _broadcast(
      action: RouteAction.replace,
      route: newRoute,
      previousRoute: oldRoute,
    );
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    final name = _routeName(route);
    final idx = _stack.lastIndexOf(name);
    if (idx >= 0) _stack.removeAt(idx);

    _broadcast(
      action: RouteAction.remove,
      route: route,
      previousRoute: previousRoute,
    );
  }

  // ── Private ────────────────────────────────────────────────────────────────

  void _broadcast({
    required RouteAction action,
    Route<dynamic>? route,
    Route<dynamic>? previousRoute,
  }) {
    final event = RouteEvent(
      id: _uuid.v4(),
      timestamp: DateTime.now(),
      action: action,
      routeName: route != null ? _routeName(route) : 'unknown',
      routeType: route?.runtimeType.toString(),
      fullStack: List<String>.from(_stack),
      previousRouteName:
          previousRoute != null ? _routeName(previousRoute) : null,
      arguments: route?.settings.arguments?.toString(),
      isModal: route is ModalRoute && route.barrierDismissible,
    );

    broadcaster.broadcastRoute(event);
  }

  /// Extracts a display name from a route.
  /// Prefers [RouteSettings.name], falls back to the runtime type.
  static String _routeName(Route<dynamic> route) {
    final name = route.settings.name;
    if (name != null && name.isNotEmpty) return name;
    return route.runtimeType.toString();
  }
}
