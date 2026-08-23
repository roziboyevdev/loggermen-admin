import 'dart:convert';

/// Shared request/response body normaliser used by the HTTP interceptors
/// (Chopper and Dio) before an event is broadcast to the DevTools page.
///
/// Produces a JSON-safe representation:
///   * `Map` / non-byte `List` → returned as-is (rendered as a JSON tree)
///   * `String`               → decoded to JSON when possible, else raw text
///   * `List<int>` (bytes)    → replaced with a `<binary N bytes>` placeholder
///   * anything else          → `toString()`
///   * `null`                 → `null`
class BodyParser {
  BodyParser._();

  static dynamic parse(dynamic body) {
    if (body == null) return null;

    if (body is Map) return body;
    if (body is List && body is! List<int>) return body;

    if (body is String) {
      if (body.isEmpty) return body;
      try {
        return jsonDecode(body);
      } catch (_) {
        return body;
      }
    }

    if (body is List<int>) {
      // Binary data — show size only.
      return '<binary ${body.length} bytes>';
    }

    return body.toString();
  }

  /// Converts a raw header map of any value type to `Map<String, String>`.
  static Map<String, String> headers(dynamic raw) {
    if (raw == null) return {};
    if (raw is Map<String, String>) return Map<String, String>.from(raw);
    if (raw is Map) {
      return raw.map(
        (k, v) => MapEntry(
          k.toString(),
          v is Iterable ? v.join(', ') : v.toString(),
        ),
      );
    }
    return {};
  }
}
