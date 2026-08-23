/// Masks sensitive values in HTTP headers before broadcasting to the HTML page.
///
/// This prevents Bearer tokens, API keys, and cookies from being visible
/// in the developer tools HTML page (which could be a security concern on
/// shared screens or recordings).
///
/// Masking can be toggled via [WatchdogConfig.maskSensitiveHeaders].
class HeaderMasker {
  HeaderMasker._();

  /// Header names whose values will be replaced with [_maskedValue].
  static const List<String> _sensitiveHeaders = [
    'authorization',
    'x-api-key',
    'api-key',
    'x-auth-token',
    'cookie',
    'set-cookie',
    'x-csrf-token',
    'proxy-authorization',
  ];

  static const String _maskedValue = '••••••••••••••••';

  /// Returns a copy of [headers] with sensitive values replaced.
  ///
  /// If [mask] is false the original map is returned unchanged.
  static Map<String, String> mask(
      Map<String, String> headers, {
        bool mask = true,
      }) {
    if (!mask) return headers;

    return headers.map((key, value) {
      final isSecret = _sensitiveHeaders.contains(key.toLowerCase());
      return MapEntry(key, isSecret ? _maskedValue : value);
    });
  }
}