import 'dart:async';

import 'package:dio/dio.dart';

import '../storage/token_storage.dart';
import '../utils/app_constants.dart';
import 'api_config.dart';
import 'api_exception.dart';

/// Thin wrapper around [Dio] that:
///  - attaches the JWT access token to every request
///  - transparently refreshes the access token on a 401 and retries once
///  - converts errors into [ApiException]
class ApiClient {
  ApiClient(this._tokenStorage) {
    dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.apiBase,
        connectTimeout: AppConstants.connectTimeout,
        receiveTimeout: AppConstants.receiveTimeout,
        headers: const {'Accept': 'application/json'},
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final isPublic = _publicPaths.any((p) => options.path.contains(p));
          if (!isPublic) {
            final token = await _tokenStorage.getAccessToken();
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final requestOptions = error.requestOptions;
          final alreadyRetried = requestOptions.extra['retried'] == true;

          if (error.response?.statusCode == 401 && !alreadyRetried) {
            final newToken = await _refreshAccessToken();
            if (newToken != null) {
              requestOptions.headers['Authorization'] = 'Bearer $newToken';
              requestOptions.extra['retried'] = true;
              try {
                final response = await dio.fetch(requestOptions);
                return handler.resolve(response);
              } on DioException catch (retryError) {
                return handler.next(retryError);
              }
            } else {
              await _tokenStorage.clear();
              onSessionExpired?.call();
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  static const _publicPaths = [
    ApiConfig.login,
    ApiConfig.refresh,
    ApiConfig.register,
  ];

  final TokenStorage _tokenStorage;
  late final Dio dio;

  /// Called when the refresh token is invalid/expired and the user must
  /// log in again. Wired up by the auth provider.
  void Function()? onSessionExpired;

  bool _isRefreshing = false;
  Completer<String?>? _refreshCompleter;

  Future<String?> _refreshAccessToken() async {
    if (_isRefreshing) {
      return _refreshCompleter?.future;
    }
    _isRefreshing = true;
    _refreshCompleter = Completer<String?>();

    try {
      final refreshToken = await _tokenStorage.getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        throw Exception('No refresh token available');
      }

      // Use a bare Dio instance so this call doesn't recurse through
      // the interceptor above.
      final plainDio = Dio(BaseOptions(baseUrl: ApiConfig.apiBase));
      final response = await plainDio.post(
        ApiConfig.refresh,
        data: {'refresh': refreshToken},
      );
      final newAccess = response.data['access'] as String;
      await _tokenStorage.saveAccessToken(newAccess);
      _refreshCompleter!.complete(newAccess);
      return newAccess;
    } catch (_) {
      _refreshCompleter!.complete(null);
      return null;
    } finally {
      _isRefreshing = false;
    }
  }

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      return await dio.get(path, queryParameters: queryParameters);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Response<dynamic>> post(String path, {dynamic data}) async {
    try {
      return await dio.post(path, data: data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Response<dynamic>> put(String path, {dynamic data}) async {
    try {
      return await dio.put(path, data: data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Response<dynamic>> patch(String path, {dynamic data}) async {
    try {
      return await dio.patch(path, data: data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Response<dynamic>> delete(String path) async {
    try {
      return await dio.delete(path);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST with multipart/form-data — used for endpoints that may include
  /// a file (profile picture, course thumbnail, resource upload).
  Future<Response<dynamic>> postMultipart(
    String path,
    Map<String, dynamic> fields,
  ) async {
    try {
      final formData = FormData.fromMap(fields);
      return await dio.post(path, data: formData);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// PUT/PATCH with multipart/form-data.
  Future<Response<dynamic>> patchMultipart(
    String path,
    Map<String, dynamic> fields,
  ) async {
    try {
      final formData = FormData.fromMap(fields);
      return await dio.patch(path, data: formData);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
