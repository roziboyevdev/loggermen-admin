import 'dart:async';

import 'package:chopper/chopper.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/network_event.dart';
import '../server/watchdog_broadcaster.dart';
import '../utils/body_parser.dart';
import '../utils/header_masker.dart';

/// A Chopper [Interceptor] that captures every HTTP request and response and
/// broadcasts them as [NetworkEvent]s to the Watchdog HTML DevTools page.
///
/// Add it to your [ChopperClient] interceptors list:
///
/// ```dart
/// ChopperClient(
///   interceptors: [
///     ErrorInterceptor(),
///     AuthInterceptor(getIt<SecureStorageService>()),
///     LoggingInterceptor(),
///     WatchdogChopperInterceptor(), // ← just add this
///   ],
/// )
/// ```
///
/// By default the [Authorization] header value is masked in the HTML page.
/// Set [maskSensitiveHeaders] to false to see raw header values.
class WatchdogChopperInterceptor implements Interceptor {
  WatchdogChopperInterceptor({
    required this.broadcaster,
    this.maskSensitiveHeaders = true,
  });

  final WatchdogBroadcaster broadcaster;

  /// When true (default) the [Authorization] and similar headers are masked
  /// in the HTML DevTools page, so Bearer tokens never appear on screen.
  final bool maskSensitiveHeaders;

  static const _uuid = Uuid();

  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(
      Chain<BodyType> chain,
      ) async {
    final request = chain.request;
    final id = _uuid.v4();
    final startTime = DateTime.now();
    final stopwatch = Stopwatch()..start();

    try {
      final response = await chain.proceed(request);
      stopwatch.stop();

      broadcaster.broadcastNetwork(
        NetworkEvent.completed(
          id: id,
          timestamp: startTime,
          method: request.method,
          url: request.url.toString(),
          requestHeaders: HeaderMasker.mask(
            BodyParser.headers(request.headers),
            mask: maskSensitiveHeaders,
          ),
          requestBody: BodyParser.parse(request.body),
          queryParams: _extractQueryParams(request.url),
          statusCode: response.statusCode,
          responseHeaders: BodyParser.headers(response.headers),
          responseBody: BodyParser.parse(
            response.body ??
            response.error ??
            _rawBody(response.base),
          ),
          durationMs: stopwatch.elapsedMilliseconds,
        ),
      );

      return response;
    } catch (e, st) {
      stopwatch.stop();

      broadcaster.broadcastNetwork(
        NetworkEvent.failed(
          id: id,
          timestamp: startTime,
          method: request.method,
          url: request.url.toString(),
          requestHeaders: HeaderMasker.mask(
            BodyParser.headers(request.headers),
            mask: maskSensitiveHeaders,
          ),
          requestBody: BodyParser.parse(request.body),
          queryParams: _extractQueryParams(request.url),
          errorMessage: e.toString(),
          stackTrace: st.toString(),    // mapped to errorStackTrace in NetworkEvent
          durationMs: stopwatch.elapsedMilliseconds,
        ),
      );

      rethrow;
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Extracts the raw body string from [base] for non-2xx responses.
  /// Chopper types [base] as [http.BaseResponse] which has no body getter,
  /// but at runtime it is always an [http.Response] that does.
  static String? _rawBody(http.BaseResponse base) {
    if (base is http.Response && base.body.isNotEmpty) return base.body;
    return null;
  }

  /// Extracts URL query parameters into a [Map<String, String>].
  Map<String, String> _extractQueryParams(Uri url) {
    return url.queryParameters;
  }
}