import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// HTTP网络客户端（单例）
/// 封装Dio，统一请求/响应处理
class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  late final Dio _dio;
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.xxblqaq.cn/api',
  );
  static String get socketBaseUrl =>
      baseUrl.replaceFirst(RegExp(r'/api/?$'), '');

  static bool get hasValidBaseUrl => isAllowedBaseUrl(baseUrl);

  static bool isAllowedBaseUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return false;
    if (uri.scheme == 'https') return true;
    return uri.scheme == 'http' &&
        (uri.host == 'localhost' ||
            uri.host == '127.0.0.1' ||
            uri.host == '10.0.2.2');
  }

  String? _token;

  void setToken(String? token) => _token = token;

  factory ApiClient() => _instance;

  ApiClient._internal() {
    if (!hasValidBaseUrl) {
      throw StateError(
        'API_BASE_URL 必须使用 HTTPS；本地调试仅允许 localhost、127.0.0.1 或 10.0.2.2 的 HTTP 地址。',
      );
    }
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      },
    ));
    _dio.interceptors.add(_logInterceptor());
  }

  InterceptorsWrapper _logInterceptor() => InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.extra['authenticated'] != false &&
              _token != null &&
              _token!.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $_token';
          }
          debugPrint('[API] → ${options.method} ${options.path}');
          handler.next(options);
        },
        onResponse: (response, handler) {
          handler.next(response);
        },
        onError: (err, handler) {
          debugPrint('[API] ✗ ${err.type}');
          handler.next(err);
        },
      );

  Future<Response> get(String path,
          {Map<String, dynamic>? params, bool authenticated = true}) =>
      _dio.get(path,
          queryParameters: params,
          options: Options(extra: {'authenticated': authenticated}));

  Future<Response> post(String path,
          {dynamic data, bool authenticated = true}) =>
      _dio.post(path,
          data: data,
          options: Options(extra: {'authenticated': authenticated}));

  Future<Response> put(String path,
          {dynamic data, bool authenticated = true}) =>
      _dio.put(path,
          data: data,
          options: Options(extra: {'authenticated': authenticated}));

  Future<Response> patch(String path,
          {dynamic data, bool authenticated = true}) =>
      _dio.patch(path,
          data: data,
          options: Options(extra: {'authenticated': authenticated}));

  Future<Response> delete(String path, {bool authenticated = true}) => _dio
      .delete(path, options: Options(extra: {'authenticated': authenticated}));
}
