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
    String? lessonId,
  }) async {
    final response = await _api.postMultipart(ApiConfig.resourceUpload, {
      'title': title,
      if (description != null) 'description': description,
        'resource_type': resourceType,
        'is_downloadable': isDownloadable,
        if (lessonId != null) 'lesson': lessonId,
          'file': await MultipartFile.fromFile(filePath),
    });
    return Resource.fromJson(response.data as Map<String, dynamic>);
  }
  
  Future<PaginatedResponse<OfflineDownload>> myDownloads({int page = 1}) async {
    final response = await _api.get(
      ApiConfig.myDownloads,
      queryParameters: {'page': page},
    );
    return PaginatedResponse.fromDynamic(response.data, OfflineDownload.fromJson);
  }
}
