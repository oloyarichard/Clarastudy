import 'package:dio/dio.dart';

import '../core/network/api_client.dart';
import '../core/network/api_config.dart';
import '../models/paginated_response.dart';
import '../models/resource_models.dart';

class ResourceRepository {
  ResourceRepository(this._api);

  final ApiClient _api;

  Future<PaginatedResponse<Resource>> listResources({int page = 1}) async {
    final response = await _api.get(
      ApiConfig.resources,
      queryParameters: {'page': page},
    );
    return PaginatedResponse.fromDynamic(response.data, Resource.fromJson);
  }

  Future<Resource> uploadResource({
    required String title,
    String? description,
    required String resourceType,
    required String filePath,
    bool isDownloadable = true,
    required String courseId,
    String? lessonId,
    void Function(double progress)? onProgress,
  }) async {
    final response = await _api.postMultipart(
      ApiConfig.resourceUpload,
      {
        'title': title,
        if (description != null) 'description': description,
        'resource_type': resourceType,
        'is_downloadable': isDownloadable,
        'course': courseId,
        if (lessonId != null) 'lesson': lessonId,
        'file': await MultipartFile.fromFile(filePath),
      },
      onSendProgress: onProgress == null
          ? null
          : (sent, total) {
              if (total > 0) onProgress(sent / total);
            },
    );
    return Resource.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PaginatedResponse<OfflineDownload>> myDownloads({int page = 1}) async {
    final response = await _api.get(
      ApiConfig.myDownloads,
      queryParameters: {'page': page},
    );
    return PaginatedResponse.fromDynamic(response.data, OfflineDownload.fromJson);
  }

  /// Checked before ever opening a resource's file. Throws an
  /// ApiException with statusCode 403 (and course_id/course_title/price
  /// in fieldErrors) if the resource is tied to a course the caller
  /// isn't enrolled in — the UI uses that to prompt payment/enrollment
  /// instead of just failing silently.
  Future<String> checkResourceAccess(String resourceId) async {
    final response = await _api.get(ApiConfig.resourceAccess(resourceId));
    return (response.data as Map<String, dynamic>)['file_url'] as String;
  }
}
