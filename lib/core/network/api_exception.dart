import 'package:dio/dio.dart';

/// A normalized exception thrown by [ApiClient] so the UI layer never has
/// to deal with raw [DioException]s.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.fieldErrors});

  final String message;
  final int? statusCode;

  /// Field-level validation errors, e.g. {"email": ["already exists"]}.
  final Map<String, dynamic>? fieldErrors;

  factory ApiException.fromDioException(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return ApiException(
        'The connection timed out. Check that the backend server is '
        'running and reachable.',
      );
    }
    if (e.type == DioExceptionType.connectionError) {
      return ApiException(
        'Could not reach the server. Check your network connection and '
        'the API host configured in ApiConfig.',
      );
    }

    final response = e.response;
    if (response != null) {
      final data = response.data;
      String message = 'Something went wrong (${response.statusCode}).';
      Map<String, dynamic>? fieldErrors;

      if (data is Map<String, dynamic>) {
        fieldErrors = data;
        if (data['detail'] is String) {
          message = data['detail'] as String;
        } else {
          // DRF validation errors look like {"field": ["msg", ...]}
          final firstEntry = data.entries.firstWhere(
            (entry) => entry.value is List && (entry.value as List).isNotEmpty,
            orElse: () => const MapEntry('', []),
          );
          if (firstEntry.key.isNotEmpty) {
            final firstMsg = (firstEntry.value as List).first.toString();
            message = '${_humanizeField(firstEntry.key)}: $firstMsg';
          }
        }
      } else if (data is String && data.isNotEmpty) {
        message = data;
      }

      return ApiException(
        message,
        statusCode: response.statusCode,
        fieldErrors: fieldErrors,
      );
    }

    return ApiException(e.message ?? 'Unexpected network error.');
  }

  static String _humanizeField(String field) {
    return field.replaceAll('_', ' ');
  }

  @override
  String toString() => message;
}
