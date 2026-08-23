/// Action that triggered the route event.
enum RouteAction {
  push,
  pop,
  replace,
  remove,
}

/// A single navigation event captured by [WatchdogRouteObserver].
class RouteEvent {
  const RouteEvent({
    required this.id,
    required this.timestamp,
    required this.action,
    required this.routeName,
    required this.fullStack,
    this.routeType,
    this.previousRouteName,
    this.arguments,
    this.isModal = false,
  });

  /// Unique ID for this event (UUID v4).
  final String id;

  /// When the navigation event occurred.
  final DateTime timestamp;

  /// The navigation action (push, pop, replace, remove).
  final RouteAction action;

  /// Name of the route from [RouteSettings.name], or the runtime type if unnamed.
  final String routeName;

  /// Runtime type of the route (e.g. "MaterialPageRoute<dynamic>").
  final String? routeType;

  /// The full navigator stack after this action, from bottom to top.
  final List<String> fullStack;

  /// Name of the previous/other route involved in this action.
  final String? previousRouteName;

  /// Stringified route arguments, if any.
  final String? arguments;

  /// Whether this route was presented as a modal.
  final bool isModal;

  /// Current depth of the navigation stack.
  int get depth => fullStack.length;

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'type': 'route',
        'id': id,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'action': action.name,
        'routeName': routeName,
        'routeType': routeType,
        'fullStack': fullStack,
        'depth': depth,
        'previousRouteName': previousRouteName,
        'arguments': arguments,
        'isModal': isModal,
      };
}
