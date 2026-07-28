import '../core/network/api_client.dart';
import '../core/network/api_config.dart';
import '../models/notification_model.dart';
import '../models/paginated_response.dart';

class NotificationRepository {
  NotificationRepository(this._api);

  final ApiClient _api;

  Future<PaginatedResponse<AppNotification>> myNotifications({
    int page = 1,
  }) async {
    final response = await _api.get(
      ApiConfig.notifications,
      queryParameters: {'page': page},
    );
    return PaginatedResponse.fromDynamic(response.data, AppNotification.fromJson);
  }

  Future<AppNotification> markAsRead(String id) async {
    final response = await _api.patch(ApiConfig.notificationRead(id), data: {});
    return AppNotification.fromJson(response.data as Map<String, dynamic>);
  }
}
