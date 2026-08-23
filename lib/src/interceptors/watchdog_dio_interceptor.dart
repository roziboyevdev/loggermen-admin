import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../models/network_event.dart';
import '../server/watchdog_broadcaster.dart';
import '../utils/body_parser.dart';
import '../utils/header_masker.dart';

/// A Dio [Interceptor] that captures every HTTP request and response and
/// broadcasts them as [NetworkEvent]s to the Watchdog HTML DevTools page.
///
/// It mirrors [WatchdogChopperInterceptor] one-to-one, so a Dio-based project
/// gets exactly the same network view a Chopper-based project does — method,
/// URL, headers, body, query params, status code, duration, and errors.
///
/// Add it to your [Dio] interceptors list:
///
/// ```dart
/// final dio = Dio();
/// dio.interceptors.add(Watchdog.dioInterceptor); // ← just add this
/// ```
///
/// By default the [Authorization] and similar headers are masked in the HTML
/// page. Set [maskSensitiveHeaders] to false to see raw header values.
///
/// ## How error status codes are reported
///
/// Dio throws a [DioException] for non-2xx responses by default. To match
/// Chopper — where a 4xx/5xx arrives as a normal (colour-coded) row — those
/// are reported as **completed** events carrying their status code. Only
/// responseless failures (connection refused, timeouts, cancellations) are
/// reported as **failed** events.
class WatchdogDioInterceptor extends Interceptor {
  WatchdogDioInterceptor({
    required this.broadcaster,
    this.maskSensitiveHeaders = true,
  });

  final WatchdogBroadcaster broadcaster;

  /// When true (default) the [Authorization] and similar headers are masked
  /// in the HTML DevTools page, so Bearer tokens never appear on screen.
  final bool maskSensitiveHeaders;

  static const _uuid = Uuid();

  // Keys used to thread per-request state through Dio's `extra` map so the
  // response/error callbacks can recover the id and start time.
  static const _idKey = 'watchdog.id';
  static const _startKey = 'watchdog.start';
  static const _stopwatchKey = 'watchdog.stopwatch';

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    options.extra[_idKey] = _uuid.v4();
    options.extra[_startKey] = DateTime.now();
    options.extra[_stopwatchKey] = Stopwatch()..start();
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _broadcastCompleted(response.requestOptions, response);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    if (response != null) {
      // Server responded (4xx/5xx) — show it like Chopper: a completed call
      // with its status code, plus the error body for context.
      _broadcastCompleted(err.requestOptions, response, error: err);
    } else {
      // No response — connection refused, timeout, cancellation, etc.
      _broadcastFailed(err.requestOptions, err);
    }
    handler.next(err);
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _broadcastCompleted(
    RequestOptions request,
    Response<dynamic> response, {
    DioException? error,
  }) {
    broadcaster.broadcastNetwork(
      NetworkEvent.completed(
        id: _id(request),
        timestamp: _startTime(request),
        method: request.method,
        url: request.uri.toString(),
        requestHeaders: HeaderMasker.mask(
          BodyParser.headers(request.headers),
          mask: maskSensitiveHeaders,
        ),
        requestBody: BodyParser.parse(request.data),
        queryParams: _queryParams(request),
        statusCode: response.statusCode ?? 0,
        responseHeaders: BodyParser.headers(response.headers.map),
        responseBody: BodyParser.parse(response.data ?? error?.message),
        durationMs: _elapsedMs(request),
      ),
    );
  }

  void _broadcastFailed(RequestOptions request, DioException err) {
    broadcaster.broadcastNetwork(
      NetworkEvent.failed(
        id: _id(request),
        timestamp: _startTime(request),
        method: request.method,
        url: request.uri.toString(),
        requestHeaders: HeaderMasker.mask(
          BodyParser.headers(request.headers),
          mask: maskSensitiveHeaders,
        ),
        requestBody: BodyParser.parse(request.data),
        queryParams: _queryParams(request),
        errorMessage: err.message ?? err.toString(),
        stackTrace: err.stackTrace.toString(),
        durationMs: _elapsedMs(request),
      ),
    );
  }

  String _id(RequestOptions request) {
    final existing = request.extra[_idKey];
    return existing is String ? existing : _uuid.v4();
  }

  DateTime _startTime(RequestOptions request) {
    final start = request.extra[_startKey];
    return start is DateTime ? start : DateTime.now();
  }

  int _elapsedMs(RequestOptions request) {
    final sw = request.extra[_stopwatchKey];
    if (sw is Stopwatch) {
      sw.stop();
      return sw.elapsedMilliseconds;
    }
    return 0;
  }

  /// Dio keeps query parameters as `Map<String, dynamic>`; flatten to strings.
  Map<String, String> _queryParams(RequestOptions request) {
    if (request.queryParameters.isNotEmpty) {
      return request.queryParameters.map(
        (k, v) => MapEntry(k, v?.toString() ?? ''),
      );
    }
    return request.uri.queryParameters;
  }
}
