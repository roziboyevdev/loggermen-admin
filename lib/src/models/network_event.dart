import 'dart:convert';

/// Status of a network call at any point in time.
enum NetworkEventStatus { pending, completed, failed }

/// A complete snapshot of a single HTTP call — request + response (or error).
///
/// Constructed by [WatchdogChopperInterceptor] and broadcast to the HTML page
/// via [WatchdogBroadcaster].
class NetworkEvent {
  const NetworkEvent({
    required this.id,
    required this.timestamp,
    required this.method,
    required this.url,
    required this.requestHeaders,
    required this.requestBody,
    required this.queryParams,
    required this.status,
    this.statusCode,
    this.responseHeaders,
    this.responseBody,
    this.errorMessage,
    this.errorStackTrace,
    this.durationMs,
  });

  /// Unique ID for this call (UUID v4).
  final String id;

  /// When the request was initiated.
  final DateTime timestamp;

  /// HTTP method — GET, POST, PUT, DELETE, PATCH, etc.
  final String method;

  /// Full URL including scheme, host, path.
  final String url;

  /// Request headers (Authorization header value is masked by [HeaderMasker]).
  final Map<String, String> requestHeaders;

  /// Request body — null for GET/HEAD requests.
  final dynamic requestBody;

  /// URL query parameters, parsed from the URL.
  final Map<String, String> queryParams;

  /// Current lifecycle status of the call.
  final NetworkEventStatus status;

  /// HTTP status code — null while the request is still [pending].
  final int? statusCode;

  /// Response headers — null while the request is still [pending].
  final Map<String, String>? responseHeaders;

  /// Response body — null while the request is still [pending].
  final dynamic responseBody;

  /// Error message — non-null only when [status] is [failed].
  final String? errorMessage;

  /// Stack trace string — non-null only when [status] is [failed].
  final String? errorStackTrace;

  /// Total round-trip duration in milliseconds — null while [pending].
  final int? durationMs;

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Returns a short path label, e.g. "/v1/trips" from the full URL.
  String get path {
    try {
      return Uri.parse(url).path;
    } catch (_) {
      return url;
    }
  }

  /// Returns true when the status code is in the 2xx success range.
  bool get isSuccess => statusCode != null && statusCode! >= 200 && statusCode! < 300;

  /// Returns true when the status code is in the 4xx or 5xx error range.
  bool get isError => statusCode != null && statusCode! >= 400;

  /// Builds a cURL command string from the request data.
  String get curlCommand {
    final buffer = StringBuffer('curl -X $method \\\n');
    buffer.write("  '$url' \\\n");
    requestHeaders.forEach((key, value) {
      buffer.write("  -H '$key: $value' \\\n");
    });
    if (requestBody != null) {
      final bodyStr = _bodyToString(requestBody);
      buffer.write("  -d '$bodyStr'");
    }
    return buffer.toString();
  }

  // ── Factory constructors ──────────────────────────────────────────────────

  /// Creates a [NetworkEvent] marking the start of a request (before response).
  factory NetworkEvent.request({
    required String id,
    required String method,
    required String url,
    required Map<String, String> requestHeaders,
    required dynamic requestBody,
    required Map<String, String> queryParams,
  }) {
    return NetworkEvent(
      id: id,
      timestamp: DateTime.now(),
      method: method,
      url: url,
      requestHeaders: requestHeaders,
      requestBody: requestBody,
      queryParams: queryParams,
      status: NetworkEventStatus.pending,
    );
  }

  /// Creates a completed [NetworkEvent] with full request + response data.
  factory NetworkEvent.completed({
    required String id,
    required DateTime timestamp,
    required String method,
    required String url,
    required Map<String, String> requestHeaders,
    required dynamic requestBody,
    required Map<String, String> queryParams,
    required int statusCode,
    required Map<String, String> responseHeaders,
    required dynamic responseBody,
    required int durationMs,
  }) {
    return NetworkEvent(
      id: id,
      timestamp: timestamp,
      method: method,
      url: url,
      requestHeaders: requestHeaders,
      requestBody: requestBody,
      queryParams: queryParams,
      status: NetworkEventStatus.completed,
      statusCode: statusCode,
      responseHeaders: responseHeaders,
      responseBody: responseBody,
      durationMs: durationMs,
    );
  }

  /// Creates a failed [NetworkEvent] with error details.
  factory NetworkEvent.failed({
    required String id,
    required DateTime timestamp,
    required String method,
    required String url,
    required Map<String, String> requestHeaders,
    required dynamic requestBody,
    required Map<String, String> queryParams,
    required String errorMessage,
    required int durationMs,
    String? stackTrace,
    int? statusCode,
  }) {
    return NetworkEvent(
      id: id,
      timestamp: timestamp,
      method: method,
      url: url,
      requestHeaders: requestHeaders,
      requestBody: requestBody,
      queryParams: queryParams,
      status: NetworkEventStatus.failed,
      statusCode: statusCode,
      errorMessage: errorMessage,
      errorStackTrace: stackTrace,
      durationMs: durationMs,
    );
  }

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() {
    return {
      'type': 'network',
      'id': id,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'method': method,
      'url': url,
      'path': path,
      'status': status.name,
      'requestHeaders': requestHeaders,
      'requestBody': _bodyToJsonSafe(requestBody),
      'queryParams': queryParams,
      'statusCode': statusCode,
      'responseHeaders': responseHeaders,
      'responseBody': _bodyToJsonSafe(responseBody),
      'errorMessage': errorMessage,
      'errorStackTrace': errorStackTrace,
      'durationMs': durationMs,
    };
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  static String _bodyToString(dynamic body) {
    if (body == null) return '';
    if (body is String) return body;
    if (body is Map || body is List) return jsonEncode(body);
    return body.toString();
  }

  static dynamic _bodyToJsonSafe(dynamic body) {
    if (body == null) return null;
    if (body is String) {
      // Try to parse as JSON for pretty rendering in HTML
      try {
        return jsonDecode(body);
      } catch (_) {
        return body;
      }
    }
    if (body is Map || body is List) return body;
    return body.toString();
  }
}