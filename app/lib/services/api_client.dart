import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';
import '../ui/strings.dart';

/// Error surfaced to the UI. `code` is the server's stable machine code
/// (see SPEC §4), `message` is already human-readable.
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.status, this.fieldErrors});

  final String code;
  final String message;
  final int? status;
  final Map<String, String>? fieldErrors;

  bool get isPendingAccount => code == 'account_pending';
  bool get isSuspendedAccount => code == 'account_suspended';
  bool get isAuthProblem =>
      status == 401 || code == 'invalid_token' || code == 'missing_token' || code == 'unknown_agent';

  @override
  String toString() => message;
}

/// Single Dio instance with the bearer token attached and server errors
/// normalised into [ApiException].
class ApiClient {
  ApiClient({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiRoot,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 60), // photo uploads
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await readToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (e, handler) {
        if (_toApiException(e).isAuthProblem) {
          for (final cb in _onUnauthorized) {
            cb();
          }
        }
        handler.next(e);
      },
    ));
  }

  static const _tokenKey = 'auth_token';

  late final Dio _dio;
  final FlutterSecureStorage _storage;
  final List<void Function()> _onUnauthorized = [];
  String? _cachedToken;

  Dio get dio => _dio;

  /// Called when the server rejects our token, so the app can log out.
  void addUnauthorizedListener(void Function() cb) => _onUnauthorized.add(cb);

  /// Last known token, without touching secure storage. Photo widgets read this
  /// on every rebuild, so it must not be an async round trip.
  String? get tokenSync => _cachedToken;

  Future<String?> readToken() async => _cachedToken ??= await _storage.read(key: _tokenKey);

  Future<void> saveToken(String token) async {
    _cachedToken = token;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> clearToken() async {
    _cachedToken = null;
    await _storage.delete(key: _tokenKey);
  }

  /// Absolute URL for a server-relative path like `/api/photos/12`.
  static String absoluteUrl(String path) {
    if (path.startsWith('http')) return path;
    return '${AppConfig.apiBaseUrl}$path';
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get(path, queryParameters: query));

  Future<Map<String, dynamic>> post(String path, {Object? body}) =>
      _send(() => _dio.post(path, data: body));

  Future<Map<String, dynamic>> patch(String path, {Object? body}) =>
      _send(() => _dio.patch(path, data: body));

  Future<Map<String, dynamic>> put(String path, {Object? body}) =>
      _send(() => _dio.put(path, data: body));

  Future<Map<String, dynamic>> delete(String path) => _send(() => _dio.delete(path));

  /// [receiveTimeout] overrides the default for slow endpoints (AI import
  /// can take 30–60 s on a large PDF).
  Future<Map<String, dynamic>> postForm(String path, FormData form, {Duration? receiveTimeout}) =>
      _send(() => _dio.post(
            path,
            data: form,
            options: receiveTimeout == null ? null : Options(receiveTimeout: receiveTimeout),
          ));

  /// Raw bytes — used for the downloadable masked profile card.
  Future<List<int>> postBytes(String path, {Object? body}) async {
    try {
      final res = await _dio.post<List<int>>(
        path,
        data: body,
        options: Options(responseType: ResponseType.bytes),
      );
      return res.data ?? const [];
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<Map<String, dynamic>> _send(Future<Response> Function() call) async {
    try {
      final res = await call();
      final data = res.data;
      if (data is Map<String, dynamic>) return data;
      return {'data': data};
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  /// Server codes whose message we word for agents ourselves.
  static const _friendlyMessages = {
    // SPEC §9.12: an unpaid customer profile stays hidden.
    'payment_required': S.paymentRequired,
  };

  ApiException _toApiException(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;

    if (data is Map) {
      final details = data['details'];
      Map<String, String>? fieldErrors;
      if (details is List) {
        fieldErrors = {
          for (final d in details)
            if (d is Map && d['field'] != null) '${d['field']}': '${d['message']}',
        };
      }
      final code = '${data['error'] ?? 'server_error'}';
      return ApiException(
        code,
        _friendlyMessages[code] ?? '${data['message'] ?? 'Something went wrong'}',
        status: status,
        fieldErrors: fieldErrors,
      );
    }

    final offline = e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout;
    return ApiException(
      offline ? 'network_error' : 'server_error',
      offline
          ? 'Cannot reach the server. Check your internet connection.'
          : 'Something went wrong. Please try again.',
      status: status,
    );
  }
}
