import '../core/network/api_config.dart';
import 'parsing_utils.dart';

class Resource {
  Resource({
    required this.id,
    required this.uploadedById,
    this.lessonId,
    required this.title,
    this.description,
    required this.resourceType,
    required this.file,
    this.isDownloadable = true,
    this.createdAt,
  });
  
  final String id;
  final String uploadedById;
  final String? lessonId;
  final String title;
  final String? description;
  final String resourceType; // video | pdf | document
  final String file;
  final bool isDownloadable;
  final DateTime? createdAt;
  
  String get fileUrl => ApiConfig.resolveMediaUrl(file);
  
  factory Resource.fromJson(Map<String, dynamic> json) {
    return Resource(
      id: parseString(json['id']),
      uploadedById: parseString(json['uploaded_by']),
      lessonId: json['lesson'] as String?,
      title: parseString(json['title']),
      description: json['description'] as String?,
      resourceType: parseString(json['resource_type'], fallback: 'document'),
      file: parseString(json['file']),
      isDownloadable: parseBool(json['is_downloadable'], fallback: true),
      createdAt: parseDate(json['created_at']),
    );
  }
}

class OfflineDownload {
  OfflineDownload({
    required this.id,
    required this.userId,
    required this.resourceId,
    this.status = 'pending',
    this.progress = 0,
    this.createdAt,
  });
  
  final String id;
  final String userId;
  final String resourceId;
  final String status;
  final int progress;
  final DateTime? createdAt;
  
  factory OfflineDownload.fromJson(Map<String, dynamic> json) {
    return OfflineDownload(
      id: parseString(json['id']),
      userId: parseString(json['user']),
      resourceId: parseString(json['resource']),
      status: parseString(json['status'], fallback: 'pending'),
      progress: parseInt(json['progress']),
      createdAt: parseDate(json['created_at']),
    );
  }
}
