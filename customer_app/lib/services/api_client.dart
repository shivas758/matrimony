import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';

/// Error surfaced to the UI. `code` is the server's stable machine code
/// (see SPEC §4), `message` is already human-readable.
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.status, this.fieldErrors});

  final String code;
  final String message;
  final int? status;
  final Map<String, String>? fieldErrors;

  bool get isPendingAccount => code == 'account_pending';
  bool get isRejectedAccount => code == 'account_rejected';
  bool get isSuspendedAccount => code == 'account_suspended';

  /// 403 because the customer is not `active` yet (SPEC §9.2) — the token is
  /// fine, the account is not. Never log out for these.
  bool get isAccountBlocked => isPendingAccount || isRejectedAccount || isSuspendedAccount;

  /// 403 `unlock_required`: guest access — register, pay and get approved
  /// first (SPEC §9.12). Never log out for it.
  bool get isUnlockRequired => code == 'unlock_required';

  /// The server no longer accepts our token — the app must log out.
  bool get isAuthProblem =>
      status == 401 ||
      code == 'invalid_token' ||
      code == 'missing_token' ||
      code == 'unknown_customer';

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

  /// Separate key from Mediator's `auth_token` — a customer token never
  /// works on agent routes and vice versa (SPEC §9.2).
  static const _tokenKey = 'customer_token';

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

  /// Absolute URL for a server-relative path like `/api/customer/photos/12`.
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

  /// Multipart (profile create + photo uploads). [receiveTimeout] overrides
  /// the default for slow endpoints.
  Future<Map<String, dynamic>> postForm(String path, FormData form, {Duration? receiveTimeout}) =>
      _send(() => _dio.post(
            path,
            data: form,
            options: receiveTimeout == null ? null : Options(receiveTimeout: receiveTimeout),
          ));

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
      return ApiException(
        '${data['error'] ?? 'server_error'}',
        '${data['message'] ?? 'Something went wrong'}',
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
