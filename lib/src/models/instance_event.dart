/// Category of a tracked instance.
enum InstanceCategory {
  bloc,
  provider,
  repository,
  service,
  network,
  other;

  /// Automatically classify by type name conventions.
  static InstanceCategory fromTypeName(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('bloc') || lower.contains('cubit')) return bloc;
    if (lower.contains('repository') || lower.contains('repo')) return repository;
    if (lower.contains('service') || lower.contains('provider')) return service;
    if (lower.contains('client') ||
        lower.contains('interceptor') ||
        lower.contains('chopper') ||
        lower.contains('http') ||
        lower.contains('dio') ||
        lower.contains('socket')) {
      return network;
    }
    return other;
  }
}

/// Lifecycle action of an instance.
enum InstanceAction {
  created,
  closed,
  stateChange,
}

/// A single instance lifecycle event broadcast to the HTML DevTools page.
class InstanceEvent {
  const InstanceEvent({
    required this.id,
    required this.timestamp,
    required this.category,
    required this.typeName,
    required this.action,
    this.registrationType,
    this.currentState,
    this.details,
    this.estimatedSizeBytes,
    this.instanceId,
    this.creationStack,
  });

  final String id;
  final DateTime timestamp;
  final InstanceCategory category;
  final String typeName;
  final InstanceAction action;

  /// e.g. "singleton", "lazySingleton", "factory"
  final String? registrationType;

  /// Current state representation (for BLoCs).
  final String? currentState;

  /// Extra details (e.g. creation context, parameter info).
  final String? details;

  /// Estimated size in bytes (from toString/JSON serialisation length).
  final int? estimatedSizeBytes;

  /// Stable identifier for the instance across lifecycle events.
  final String? instanceId;

  /// Stack trace captured at creation time — shows where the instance was
  /// created from (which file/line triggered it).
  final String? creationStack;

  Map<String, dynamic> toJson() => {
        'type': 'instance',
        'id': id,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'category': category.name,
        'typeName': typeName,
        'action': action.name,
        'registrationType': registrationType,
        'currentState': currentState,
        'details': details,
        'estimatedSizeBytes': estimatedSizeBytes,
        'instanceId': instanceId,
        'creationStack': creationStack,
      };
}
